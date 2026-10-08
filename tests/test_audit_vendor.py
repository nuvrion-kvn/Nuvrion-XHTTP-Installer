"""Audit regressions: pure parsing and command mocks, without host changes."""
import ast
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TUNER = (ROOT / 'vendor/nuvrion-auto-tuning-xhttp.sh').read_text()
TC_PATH = ROOT / 'vendor/nuvrion-traffic-control-xhttp.py'
spec = importlib.util.spec_from_file_location('audit_vendor_tc', TC_PATH)
TC = importlib.util.module_from_spec(spec)
spec.loader.exec_module(TC)


def shell_region(begin, end):
    start = TUNER.index(begin)
    return TUNER[start:TUNER.index(end, start)]


class VendorAuditTests(unittest.TestCase):
    def test_traffic_control_accepts_only_ubuntu_24_on_supported_architectures(self):
        for version in ('24.04', '24.04.3'):
            for machine, architecture in [('x86_64', 'amd64'), ('aarch64', 'arm64')]:
                with self.subTest(version=version, machine=machine), \
                     patch.object(TC, 'os_release', return_value={'ID': 'ubuntu', 'VERSION_ID': version}), \
                     patch.object(TC.os, 'uname', return_value=types.SimpleNamespace(machine=machine)):
                    self.assertEqual(TC.platform_details(), ('ubuntu', version, architecture))

    def test_traffic_control_rejects_other_platforms_before_package_installation(self):
        for system, version in [('ubuntu', '22.04'), ('ubuntu', '24.10'),
                                ('ubuntu', '26.04'), ('debian', '12'), ('linuxmint', '22')]:
            with self.subTest(system=system, version=version), \
                 patch.object(TC, 'os_release', return_value={'ID': system, 'VERSION_ID': version}), \
                 patch.object(TC, 'missing_packages', return_value=['nftables']), \
                 patch.object(TC, 'apt_install') as install:
                with self.assertRaisesRegex(ValueError, 'Ubuntu 24.04 LTS'):
                    TC.ensure_dependencies(auto_install=True)
                install.assert_not_called()

    def test_tuner_platform_guard_rejects_other_systems_before_changes(self):
        region = shell_region('OS_ID=""', 'SYSCTL_BIN=')
        for system, version, expected in [('ubuntu', '24.04', 0),
                                          ('ubuntu', '22.04', 1), ('ubuntu', '24.10', 1),
                                          ('ubuntu', '26.04', 1), ('debian', '12', 1),
                                          ('linuxmint', '22', 1)]:
            with self.subTest(system=system, version=version), tempfile.TemporaryDirectory() as td:
                release = Path(td) / 'os-release'
                release.write_text(f'ID={system}\nVERSION_ID="{version}"\n')
                code = '''set -Eeuo pipefail
C_BOLD=; C_RED=; C_RESET=
uname(){ printf 'x86_64\\n'; }
info(){ :; }
''' + region.replace('/etc/os-release', str(release)) + '\necho READY_TO_CHANGE\n'
                result = subprocess.run(['bash', '-c', code], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual('READY_TO_CHANGE' in result.stdout, expected == 0)
                if expected:
                    self.assertIn('Ubuntu 24.04 LTS', result.stderr)

    def test_direct_traffic_control_package_install_refuses_unsupported_system(self):
        with patch.object(TC, 'os_release', return_value={'ID': 'debian', 'VERSION_ID': '12'}), \
             patch.object(TC.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'Ubuntu 24.04 LTS'):
                TC.apt_install(['nftables'])
            run.assert_not_called()

    def test_failed_diagnostics_produce_nonzero_process_status(self):
        # Execute the real __main__ block with a failing diagnostic return.
        tree = ast.parse(TC_PATH.read_text())
        entry = next(node for node in tree.body if isinstance(node, ast.If)
                     and ast.unparse(node.test) == "__name__ == '__main__'")
        with tempfile.TemporaryDirectory() as td:
            script = Path(td) / 'entry.py'
            script.write_text('import sys, subprocess\ndef main(): return 3\n' + ast.unparse(entry) + '\n')
            result = subprocess.run(['python3', str(script)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 3)

    @staticmethod
    def table():
        table = TC.TABLE
        identity = {'family': 'inet', 'table': table}
        items = [{'table': {'family': 'inet', 'name': table}},
                 {'chain': dict(identity, name='ingress', type='filter', hook='input',
                                prio=-10, policy='accept')}]
        for version in (4, 6):
            for prefix in ('allow', 'block'):
                items.append({'set': dict(identity, name=f'{prefix}{version}',
                                          type=f'ipv{version}_addr', flags=['interval'])})
            match = {'op': '==',
                     'left': {'payload': {'protocol': 'ip' if version == 4 else 'ip6', 'field': 'saddr'}},
                     'right': f'@block{version}'}
            items.append({'rule': dict(identity, chain='ingress',
                                       expr=[{'match': match}, {'counter': {'packets': 17, 'bytes': 1024}},
                                             {'drop': None}])})
        return {'nftables': items}

    def active(self, table):
        with patch.object(TC, 'run', return_value=types.SimpleNamespace(stdout=json.dumps(table))):
            return TC.filter_active()

    def test_table_without_chains_is_not_active_filter(self):
        self.assertFalse(self.active({'nftables': [{'table': {'family': 'inet', 'name': TC.TABLE}}]}))

    def test_core_ipv4_and_ipv6_filter_is_recognized(self):
        self.assertTrue(self.active(self.table()))

    def test_missing_ipv6_drop_is_not_active_filter(self):
        table = self.table()
        table['nftables'].pop()
        self.assertFalse(self.active(table))

    def test_forward_chain_is_not_host_input_filter(self):
        table = self.table()
        table['nftables'][1]['chain']['hook'] = 'forward'
        self.assertFalse(self.active(table))

    def ceiling_plan(self, profile, current='1048576'):
        region = shell_region('profile_manages_sysctl() {',
                              '# ============================================================\n# Безопасный baseline')
        with tempfile.TemporaryDirectory() as td:
            profile_path = Path(td) / 'profile.conf'
            profile_path.write_text(profile)
            env = dict(os.environ, TEST_PROFILE=str(profile_path), CURRENT_VALUE=current)
            code = '''set -Eeuo pipefail
CONF=$TEST_PROFILE
num_or_zero() { printf '%s' "$1"; }
sysctl() { printf '%s\\n' "$CURRENT_VALUE"; }
''' + region + '\nprintf "%s/%s %s/%s\\n" "$MANAGE_NR_OPEN" "$NR_OPEN" "$MANAGE_FILE_MAX" "$FILE_MAX"\n'
            result = subprocess.run(['bash', '-c', code], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip()

    def test_repeat_run_keeps_own_persistent_kernel_ceilings(self):
        self.assertEqual(self.ceiling_plan('fs.nr_open = 1048576\nfs.file-max = 1048576\n'),
                         '1/1048576 1/1048576')

    def test_foreign_higher_kernel_ceilings_are_not_claimed(self):
        self.assertEqual(self.ceiling_plan('# no own assignments\n', current='2097152'),
                         '0/2097152 0/2097152')

    def test_existing_managed_higher_kernel_ceiling_is_not_lowered(self):
        self.assertEqual(self.ceiling_plan('fs.nr_open = 1048576\nfs.file-max = 1048576\n',
                                          current='2097152'), '1/2097152 1/2097152')

    def backend(self, *, auth_log=False, module=False, allow_package=False):
        region = shell_region('select_fail2ban_backend() {',
                              '# ------------------------------------------------------------\n# SSH: только аудит')
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            if auth_log:
                (root / 'auth.log').write_text('')
            if module:
                (root / 'module').write_text('')
            env = dict(os.environ, TEST_DIR=td, ALLOW_PACKAGE='1' if allow_package else '0')
            code = '''set -Eeuo pipefail
PYTHON3_BIN=mock_python
mock_python() { [[ -f $TEST_DIR/module ]]; }
ensure_package() {
  printf '%s\\n' "$1" >> "$TEST_DIR/packages"
  [[ $ALLOW_PACKAGE == 1 ]] || return 1
  touch "$TEST_DIR/module"
}
warn() { :; }
info() { :; }
''' + region + '''
rc=0
select_fail2ban_backend "$TEST_DIR/auth.log" || rc=$?
printf '%s/%s\\n' "$F2B_BACKEND" "$rc"
'''
            result = subprocess.run(['bash', '-c', code], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            packages = (root / 'packages').read_text() if (root / 'packages').exists() else ''
            return result.stdout.strip(), packages

    def test_existing_auth_file_uses_file_backend_without_installing(self):
        self.assertEqual(self.backend(auth_log=True), ('auto/0', ''))

    def test_journal_only_host_uses_available_python_systemd(self):
        self.assertEqual(self.backend(module=True), ('systemd/0', ''))

    def test_missing_journal_dependency_is_explicit_failure_if_install_disallowed(self):
        self.assertEqual(self.backend(), ('auto/1', 'python3-systemd\n'))

    def test_journal_dependency_can_be_installed_before_enabling_jail(self):
        self.assertEqual(self.backend(allow_package=True), ('systemd/0', 'python3-systemd\n'))


if __name__ == '__main__':
    unittest.main()
