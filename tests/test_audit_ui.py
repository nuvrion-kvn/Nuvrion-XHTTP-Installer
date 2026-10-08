"""UI retries and honest diagnostics, using isolated files and command mocks."""
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'nuvrion-xhttp-install.sh').read_text().split('# BEGIN EMBEDDED NUVRION XHTTP')[0]
HELPER = SOURCE.split("<<'NUVRION_PY'\n", 1)[1].split('\nNUVRION_PY\n', 1)[0]
LIB = {'__name__': 'test'}
exec(compile(HELPER, 'audit-ui-helper', 'exec'), LIB)


class AuditUiTests(unittest.TestCase):
    def run_shell(self, code, assume_socket=False, **env):
        with tempfile.TemporaryDirectory() as td:
            source = SOURCE.replace('readonly BASE=/opt/remnanode', 'readonly BASE=' + td + '/node')
            source = source.replace('readonly PROFILE=/root/nuvrion-xhttp-profile.json', 'readonly PROFILE=' + td + '/profile.json')
            if assume_socket:
                source = source.replace('[[ -f $STATE && -S $XHTTP_SOCKET ]]', '[[ -f $STATE ]]')
            source = source.replace('/usr/local/bin/nuvrion-traffic-control', td + '/traffic')
            source = source.replace('/var/lib/nuvrion-traffic-control/enabled', td + '/enabled')
            script = Path(td) / 'script.sh'
            script.write_text(source + '\n' + code)
            return subprocess.run(['bash', str(script)], text=True, capture_output=True,
                                  env={**os.environ, 'TEST_ROOT': td, 'NO_COLOR': '1', **env}, timeout=15)

    def test_confirmation_retries_invalid_input_and_honors_no_color(self):
        with tempfile.TemporaryDirectory() as td:
            script = Path(td) / 'question.sh'
            script.write_text(SOURCE + '\nask_yes "Продолжить?"; printf "\\nACCEPTED\\n"')
            pid, fd = pty.fork()
            if pid == 0:
                os.environ.update(NO_COLOR='1', TERM='xterm')
                os.execvp('bash', ['bash', str(script)])
            output = b''
            answers = [b'unknown\n', b'Yes\n']
            try:
                for _ in range(20):
                    readable, _, _ = select.select([fd], [], [], 1)
                    if not readable:
                        continue
                    try:
                        chunk = os.read(fd, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                    if b'Enter' in chunk and answers:
                        os.write(fd, answers.pop(0))
                _, status = os.waitpid(pid, 0)
            finally:
                os.close(fd)
            text = output.decode()
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, text)
            self.assertIn('Введите Д', text)
            self.assertIn('ACCEPTED', text)
            self.assertNotIn('\x1b', text)

    def test_menu_and_version_retry(self):
        r = self.run_shell('''
require_root(){ :; }
i=0
prompt(){ i=$((i+1));if ((i==1));then printf -v "$1" bad;else printf -v "$1" 0;fi; }
main
[[ $i == 2 ]]
NODE_NEW=1;NODE_VERSION='';i=0
helper(){ printf '1.2.3\\n'; }
prompt(){ i=$((i+1));if ((i==1));then printf -v "$1" bad;else printf -v "$1" 2;fi; }
choose_node_version
[[ $i == 2 && $NODE_VERSION == 1.2.3 ]]
''')
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)

    def test_tuning_mismatch_fails_and_pending_boot_is_distinct(self):
        with tempfile.TemporaryDirectory() as td:
            config, tfo, modprobe, pending = [Path(td) / name for name in ('sysctl.conf', 'tfo.conf', 'modprobe.conf', 'pending')]
            config.write_text('net.ipv4.tcp_congestion_control = bbr\nnet.core.default_qdisc = fq\nnet.netfilter.nf_conntrack_buckets = 4096\n')
            modprobe.write_text('options nf_conntrack hashsize=4096\n')
            pending.touch()
            original = config.read_bytes()
            values = {'net.ipv4.tcp_congestion_control': 'cubic', 'net.core.default_qdisc': 'fq', 'net.netfilter.nf_conntrack_buckets': '8192'}

            def fake_run(cmd, **kwargs):
                return subprocess.CompletedProcess(cmd, 0, values.get(cmd[-1], '') + '\n', '')

            with patch('subprocess.run', side_effect=fake_run):
                results = list(LIB['tuning_checks'](*map(str, (config, tfo, modprobe, pending))))
                self.assertTrue(any(status == 'FAIL' and 'cubic' in name for status, name in results))
                self.assertTrue(any(status == 'WAIT' and 'nf_conntrack_buckets' in name for status, name in results))
                pending.unlink()
                results = list(LIB['tuning_checks'](*map(str, (config, tfo, modprobe, pending))))
                self.assertTrue(any(status == 'FAIL' and 'nf_conntrack_buckets' in name for status, name in results))
            self.assertEqual(config.read_bytes(), original)

    def test_zram_preparation_counts_as_wait(self):
        r = self.run_shell('''
swapon(){ :; }
zram_pending_ready(){ return 0; }
validate_zram
[[ $ZRAM_STATUS == REBOOT_REQUIRED && $WAITS == 1 && $REBOOT_WAITS == 1 && $FAILS == 0 ]]
''')
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_tls_helper_failure_cannot_pass_self_check(self):
        # Mock only the socket presence boundary; the test exercises real
        # helper exit handling without requiring socket capabilities in CI.
        r = self.run_shell('''
mkdir -p "$OWN";touch "$STATE"
run_diagnostics(){ FAILS=0;WAITS=0; }
helper(){ return 1; }
curl(){ printf '200 2'; }
if run_self_check;then echo FALSE_SUCCESS;exit 1;fi
[[ $FAILS == 1 ]]
''', assume_socket=True)
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        self.assertIn('Проверка TLS/SNI завершилась ошибкой', r.stderr)
        self.assertNotIn('FALSE_SUCCESS', r.stdout)

    def traffic_report(self, state, **env):
        import json
        return self.run_shell('''
cat > "$TEST_ROOT/traffic" <<'MOCKTC'
#!/bin/sh
printf '%s\\n' "$TEST_TC_JSON"
MOCKTC
chmod 700 "$TEST_ROOT/traffic"
docker(){ [[ $1 != inspect ]] || printf true; }
timeout(){ shift;"$@"; }
sysctl(){ case $2 in net.core.default_qdisc) printf fq;;*) printf bbr;;esac; }
systemctl(){ return 0; }
nft(){ return 0; }
[[ ${TEST_SHOW_FULL_UI:-0} == 0 ]] || { banner;installation_components;show_menu; }
final_report
''', TEST_TC_JSON=json.dumps(state), **env)

    def test_final_report_does_not_claim_disabled_foreign_filter_enabled(self):
        r = self.traffic_report(dict(enabled=False, filter_active=False, pending=False))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('установлен; фильтрация выключена', r.stdout)
        self.assertNotIn('фильтрация и автообновление активны', r.stdout)

    def test_traffic_report_requires_actual_filter_activity_not_only_marker(self):
        for state in (dict(enabled=True, filter_active=False, pending=False),
                      dict(enabled=False, filter_active=True, pending=False),
                      dict(enabled=True, filter_active=True, pending=True), {}):
            with self.subTest(state=state):
                r = self.traffic_report(state)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertNotIn('фильтрация и автообновление активны', r.stdout)
        r = self.traffic_report(dict(enabled=True, filter_active=True, pending=False))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('фильтрация и автообновление активны', r.stdout)

    def test_report_columns_align_cyrillic_and_fit_narrow_terminal(self):
        r = self.run_shell('report_row "Домен" "node.example.org";report_row "Docker" "работает"')
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0].index('node.example.org'), lines[1].index('работает'))
        r = self.run_shell('report_row "Сертификат TLS" "' + 'длинное значение ' * 6 + '"', COLUMNS='32')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(all(len(line) <= 32 for line in r.stdout.splitlines()))

    def test_full_interface_headers_components_and_menu_fit_requested_width(self):
        for width in (24, 40, 80, 160):
            with self.subTest(width=width):
                r = self.traffic_report(dict(enabled=False, filter_active=False, pending=False),
                                        COLUMNS=str(width), TEST_SHOW_FULL_UI='1', NO_COLOR='', TERM='xterm')
                self.assertEqual(r.returncode, 0, r.stderr)
                lines = r.stdout.splitlines()
                self.assertNotIn('\x1b', r.stdout)
                self.assertTrue(all(len(line) <= min(80, width) for line in lines),
                                '\n'.join(line for line in lines if len(line) > min(80, width)))
                dividers = [line for line in lines if line and set(line) == {'═'}]
                self.assertTrue(dividers)
                self.assertTrue(all(len(line) == min(80, width) for line in dividers))
                text = ' '.join(r.stdout.split())
                for label in ('Лицензия: MIT', 'Компоненты установки:', 'Traffic Control:',
                              '0. Выход', '5. Восстановить последнюю резервную копию', 'ИТОГОВЫЙ ОТЧЁТ'):
                    self.assertIn(label, text)

    def test_long_question_wraps_in_controlling_tty_and_remains_bold_yellow(self):
        import re
        with tempfile.TemporaryDirectory() as td:
            script = Path(td) / 'question.sh'
            script.write_text(SOURCE + '\nui_question "Подтвердите применение перечисленных изменений после создания резервной копии? [Д/Н; Enter — Н]:"')
            pid, fd = pty.fork()
            if pid == 0:
                os.environ.update(NO_COLOR='', TERM='xterm', COLUMNS='40')
                os.execvp('bash', ['bash', str(script)])
            output = b''
            try:
                for _ in range(5):
                    readable, _, _ = select.select([fd], [], [], 1)
                    if not readable:
                        continue
                    try:
                        chunk = os.read(fd, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                _, status = os.waitpid(pid, 0)
            finally:
                os.close(fd)
            text = output.decode()
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, text)
            self.assertIn('\x1b[1;33m', text)
            visible = re.sub(r'\x1b\[[0-9;]*m', '', text).replace('\r', '')
            self.assertTrue(all(len(line) <= 40 for line in visible.splitlines()), visible)
            self.assertIn('[Д/Н; Enter — Н]:', ' '.join(visible.split()))

    def test_messages_fit_terminal_and_piped_output_has_no_ansi(self):
        r = self.run_shell('log_info "' + 'длинное сообщение ' * 12 + '"', COLUMNS='40', NO_COLOR='', TERM='xterm')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('\x1b', r.stdout)
        self.assertTrue(all(len(line) <= 40 for line in r.stdout.splitlines()))


if __name__ == '__main__':
    unittest.main()
