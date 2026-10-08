"""Regression tests for dormant UFW paths and narrow Russian terminal output."""
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


UFW_FUNCTIONS = region('get_existing_ufw_panel_sources() {', 'collect_public_tcp_ports() {')
UFW_IMPL = region('configure_panel_ufw_rule_impl() {', '# Возвращает source IP/CIDR')
UI_FUNCTIONS = (region('ui_width() {', 'on_error() {') + '\n'
                + region('ui_message() {', 'warn() {'))


class VendorExtraTests(unittest.TestCase):
    def ufw(self, numbered, action, *, status='', selected='203.0.113.20'):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / 'numbered').write_text(numbered)
            (root / 'status').write_text(status)
            env = dict(os.environ, TEST_DIR=td, SELECTED=selected)
            script = '''set -Eeuo pipefail
PANEL_PORT=2222
PANEL_IPS_NORMALIZED=$SELECTED
UFW_BIN=mock_ufw
mock_ufw() {
  if [[ $1 == status && ${2:-} == numbered ]];then cat "$TEST_DIR/numbered"
  elif [[ $1 == status ]];then cat "$TEST_DIR/status"
  else printf '%s\\n' "$*" >> "$TEST_DIR/calls";fi
}
warn() { printf 'WARNING: %s\\n' "$*"; }
info() { :; }
panel_port_collides_with_ssh() { return 1; }
panel_ufw_can_enforce() { return 0; }
''' + UFW_FUNCTIONS + '\n' + UFW_IMPL + '\n' + action
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True, env=env)
            calls = (root / 'calls').read_text().splitlines() if (root / 'calls').exists() else []
            return result, calls

    def test_failed_source_inspection_is_not_reported_as_empty_success(self):
        result, _ = self.ufw('', 'mock_ufw() { return 1; }; get_existing_ufw_panel_sources')
        self.assertNotEqual(result.returncode, 0)

    def test_broad_unqualified_tcp_udp_rule_is_detected(self):
        result, _ = self.ufw('', 'ufw_has_broad_panel_rule',
                             status='Status: active\n2222 ALLOW Anywhere\n2222 (v6) ALLOW Anywhere (v6)\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_removing_unqualified_allow_preserves_udp_family_and_position(self):
        status = '[ 1] 2222 ALLOW IN Anywhere\n[ 2] 2222 (v6) ALLOW IN Anywhere (v6)\n'
        result, calls = self.ufw(status, 'remove_broad_panel_rules')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [
            '--force delete 2',
            'insert 2 allow from ::/0 to any port 2222 proto udp comment Nuvrion-preserved-UDP',
            '--force delete 1',
            'insert 1 allow from 0.0.0.0/0 to any port 2222 proto udp comment Nuvrion-preserved-UDP',
        ])

    def test_removing_unqualified_deny_preserves_udp_deny(self):
        result, calls = self.ufw('[ 1] 2222 DENY IN Anywhere\n', 'remove_broad_panel_rules')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('insert 1 deny from 0.0.0.0/0 to any port 2222 proto udp comment Nuvrion-preserved-UDP', calls)

    def test_owned_cleanup_preserves_foreign_rules_and_other_ports(self):
        numbered = '''[ 1] 2222/tcp ALLOW IN 203.0.113.10 # Nuvrion-panel-access
[ 2] 2222/tcp ALLOW IN 198.51.100.5 # administrator
[ 3] 8443/tcp ALLOW IN 203.0.113.10 # Nuvrion-panel-access
[ 4] 2222/tcp ALLOW IN 198.51.100.6
[ 5] 2222/tcp ALLOW IN 198.51.100.7 # Nuvrion-panel-access-other
'''
        result, calls = self.ufw(numbered, 'remove_owned_panel_rules')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['--force delete 1'])

    def test_reconfigure_marks_new_sources_and_reports_legacy_foreign_sources(self):
        numbered = '[ 1] 2222/tcp ALLOW IN 203.0.113.10 # Nuvrion-panel-access\n'
        action = '''remove_broad_panel_rules() { return 0; }
get_existing_ufw_panel_sources() { printf '198.51.100.5\\n'; }
configure_panel_ufw_rule_impl
printf '%s\\n' "$PANEL_FIREWALL_STATUS"
'''
        result, calls = self.ufw(numbered, action)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['--force delete 1',
                                'allow from 203.0.113.20 to any port 2222 proto tcp comment Nuvrion-panel-access',
                                'deny 2222/tcp comment Nuvrion-panel-access'])
        self.assertIn('сторонние разрешения: 198.51.100.5', result.stdout)
        self.assertIn('WARNING:', result.stdout)
        self.assertNotIn('только:', result.stdout)

    def test_selected_foreign_source_is_not_adopted_by_overwriting_its_comment(self):
        action = '''remove_broad_panel_rules() { return 0; }
get_existing_ufw_panel_sources() { printf '203.0.113.20\\n'; }
configure_panel_ufw_rule_impl
'''
        result, calls = self.ufw('', action)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ['deny 2222/tcp comment Nuvrion-panel-access'])

    def ui(self, width):
        script = '''set -Eeuo pipefail
export LC_ALL=C.UTF-8
C_BOLD='' C_BLUE='' C_CYAN='' C_DIM='' C_RESET=''
''' + UI_FUNCTIONS + '''
section 'ИТОГОВЫЙ ОТЧЁТ И СОСТОЯНИЕ ВСЕХ КОМПОНЕНТОВ СЕРВЕРА'
report_row 'Конфигурация' '/etc/sysctl.d/99-zzzz-nuvrion-performance.conf'
report_row 'Предупреждения' 'нет'
report_row 'Fail2ban' 'активен, используется системный журнал'
report_row 'Отчёт после загрузки' '/var/lib/nuvrion-tuning/post-reboot-last.txt'
'''
        result = subprocess.run(['bash', '-c', script], capture_output=True, text=True,
                                env=dict(os.environ, COLUMNS=str(width)))
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_sections_and_long_cyrillic_rows_fit_40_columns(self):
        lines = self.ui(40)
        self.assertLessEqual(max(map(len, lines)), 40)
        self.assertIn('─' * 40, lines)
        warnings = next(line for line in lines if 'Предупреждения' in line)
        fail2ban = next(line for line in lines if 'Fail2ban' in line)
        self.assertEqual(warnings.index('нет'), fail2ban.index('активен'))
        start = next(i for i, line in enumerate(lines) if 'Конфигурация' in line)
        end = next(i for i, line in enumerate(lines) if 'Предупреждения' in line)
        value = lines[start][24:] + ''.join(line.strip() for line in lines[start + 1:end])
        self.assertEqual(value, '/etc/sysctl.d/99-zzzz-nuvrion-performance.conf')

    def test_sections_and_rows_clamp_wide_terminal_to_80(self):
        lines = self.ui(150)
        self.assertLessEqual(max(map(len, lines)), 80)
        self.assertIn('─' * 80, lines)

    def test_minimum_width_is_40(self):
        self.assertIn('─' * 40, self.ui(20))


if __name__ == '__main__':
    unittest.main()
