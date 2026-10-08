"""Refuse UFW rules that a simple panel-port update cannot reconcile safely."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'vendor/nuvrion-auto-tuning-xhttp.sh').read_text()


def region(start, end):
    offset = SOURCE.index(start)
    return SOURCE[offset:SOURCE.index(end, offset)]


GUARD = region('ufw_panel_rules_supported() {', 'remove_broad_panel_rules() {')
WRAPPER = region('configure_panel_ufw_rule() {', 'configure_panel_ufw_rule_impl() {')
FINAL_CHECK = region('ufw_current_panel_protection_ok() {', 'final_ok() {')
ENABLE_BRANCH = region('if (( WANT_ENABLE && PANEL_NEEDED', 'if (( WANT_ENABLE )); then')


class VendorUfwGuardTests(unittest.TestCase):
    def run_guard(self, numbered, action='ufw_panel_rules_supported', *, plain=''):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'numbered').write_text(numbered)
            (root / 'status').write_text(plain)
            script = '''set -Eeuo pipefail
PANEL_PORT=2222
PANEL_IPS_NORMALIZED=203.0.113.20
UFW_BIN=mock_ufw TIMEOUT_BIN=mock_timeout
mock_timeout() { shift; "$@"; }
mock_ufw() {
  if [[ $1 == status && ${2:-} == numbered ]];then cat "$TEST_DIR/numbered"
  elif [[ $1 == status ]];then cat "$TEST_DIR/status"
  else printf 'ufw %s\\n' "$*" >> "$TEST_DIR/mutations";fi
}
warn() { printf 'WARNING: %s\\n' "$*"; }
conflict() { printf 'CONFLICT: %s\\n' "$*"; }
mktemp() { printf 'snapshot\\n' >> "$TEST_DIR/mutations";return 1; }
cp() { printf 'copy %s\\n' "$*" >> "$TEST_DIR/mutations";return 1; }
configure_panel_ufw_rule_impl() { printf 'configure\\n' >> "$TEST_DIR/mutations"; }
get_existing_ufw_panel_sources() { printf '203.0.113.20\\n'; }
ufw_has_broad_panel_rule() { return 1; }
''' + GUARD + WRAPPER + FINAL_CHECK + '\n' + action
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True,
                                    env=dict(os.environ, TEST_DIR=td))
            calls = (root / 'mutations').read_text() if (root / 'mutations').exists() else ''
            return result, calls

    def assert_refused_before_mutation(self, numbered):
        result, calls = self.run_guard(numbered, 'configure_panel_ufw_rule')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('WARNING:', result.stdout)
        self.assertEqual(calls, '')

    def test_overlapping_range_before_deny_refused_without_mutation(self):
        self.assert_refused_before_mutation('''Status: active
[ 1] 2000:3000/tcp ALLOW IN Anywhere
[ 2] 2222/tcp ALLOW IN 203.0.113.20
[ 3] 2222/tcp DENY IN Anywhere
''')

    def test_ipv6_list_containing_panel_refused(self):
        self.assert_refused_before_mutation('Status: active\n[ 1] 443,2222/tcp (v6) ALLOW IN Anywhere (v6)\n')

    def test_unknown_application_profile_refused(self):
        self.assert_refused_before_mutation('Status: active\n[ 1] Custom Panel ALLOW IN Anywhere\n')

    def test_inactive_panel_setup_refused_before_snapshot_or_reload(self):
        self.assert_refused_before_mutation('Status: inactive\n')

    def test_inactive_enable_branch_disables_request_before_mutations(self):
        action = 'WANT_ENABLE=1 PANEL_NEEDED=1 PANEL_UFW_ALLOWED=1\n' + ENABLE_BRANCH
        action += '\n[[ $WANT_ENABLE == 0 ]]\n'
        result, calls = self.run_guard('Status: inactive\n', action)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('UFW не включается', result.stdout)
        self.assertEqual(calls, '')

    def test_final_check_cannot_greenlight_overlapping_range(self):
        numbered = 'Status: active\n[ 1] 2000:3000/tcp ALLOW IN Anywhere\n[ 2] 2222/tcp DENY IN Anywhere\n'
        plain = 'Status: active\n2000:3000/tcp ALLOW Anywhere\n2222/tcp ALLOW 203.0.113.20\n2222/tcp DENY Anywhere\n'
        result, calls = self.run_guard(numbered, 'ufw_current_panel_protection_ok', plain=plain)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, '')

    def test_final_check_cannot_greenlight_unknown_profile(self):
        result, _ = self.run_guard('Status: active\n[ 1] Custom Panel ALLOW IN Anywhere\n',
                                   'ufw_current_panel_protection_ok')
        self.assertNotEqual(result.returncode, 0)

    def test_final_check_accepts_supported_source_and_deny(self):
        numbered = 'Status: active\n[ 1] 2222/tcp ALLOW IN 203.0.113.20\n[ 2] 2222/tcp DENY IN Anywhere\n'
        plain = 'Status: active\n2222/tcp ALLOW 203.0.113.20\n2222/tcp DENY Anywhere\n'
        result, calls = self.run_guard(numbered, 'ufw_current_panel_protection_ok', plain=plain)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, '')

    def test_interface_panel_allow_and_limit_refused(self):
        for target in ('2222/tcp on eth0 ALLOW IN Anywhere', '2222/tcp LIMIT IN Anywhere'):
            with self.subTest(target=target):
                self.assert_refused_before_mutation(f'Status: active\n[ 1] {target}\n')

    def test_nonoverlapping_ports_udp_outgoing_and_denies_remain_supported(self):
        numbered = '''Status: active
[ 1] 80,443,3000:4000/tcp ALLOW IN Anywhere
[ 2] 2000:3000/udp ALLOW IN Anywhere
[ 3] Custom Panel ALLOW OUT Anywhere
[ 4] Custom Panel DENY IN Anywhere
[ 5] 2222/tcp ALLOW IN 203.0.113.20
[ 6] 2222/tcp (v6) ALLOW IN 2001:db8::20
[ 7] 2222 ALLOW IN Anywhere
'''
        result, calls = self.run_guard(numbered)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, '')

    def test_numbered_inspection_failure_fails_closed(self):
        result, calls = self.run_guard('', 'mock_ufw() { return 1; }; configure_panel_ufw_rule')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, '')


if __name__ == '__main__':
    unittest.main()
