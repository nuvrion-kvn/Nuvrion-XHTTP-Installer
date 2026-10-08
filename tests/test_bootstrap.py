"""Run the GitHub launcher with isolated downloads and package-manager mocks."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'install.sh').read_text()
REVISION = '1' * 40
INSTALLER = b'''#!/usr/bin/env bash
printf '%s\\n' "$*" > "$TEST_RUN"
IFS= read -r answer
printf '%s\\n' "$answer" >> "$TEST_RUN"
'''


class BootstrapTests(unittest.TestCase):
    def run_launcher(self, *, os_id='ubuntu', version='24.04', failure='',
                     tamper=False, revision=REVISION, quick=False, arguments=()):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            binary = root / 'bin'
            binary.mkdir()
            release = root / 'os-release'
            release.write_text(f'ID={os_id}\nVERSION_ID={version}\n')
            launcher = root / 'install.sh'
            launcher.write_text(SOURCE.replace('source /etc/os-release', f'source "{release}"')
                               .replace('/tmp/nuvrion-xhttp-launch.XXXXXXXX', str(root / 'launch.XXXXXXXX')))
            fixture = root / 'fixture.sh'
            fixture.write_bytes(INSTALLER)
            for name, text in {
                'apt-get': '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$TEST_APT"\n',
                'sudo': '#!/usr/bin/env bash\nexec "$@"\n',
                'curl': '''#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
url = next(value for value in args if value.startswith('https://'))
with open(os.environ['TEST_CURL'], 'a') as stream:
    stream.write(url + '\\n')
if url.endswith('/commits/main'):
    print(json.dumps({'sha': os.environ['TEST_REVISION']}))
    sys.exit(0)
destination = Path(args[args.index('-o') + 1])
if url.endswith('/main/install.sh'):
    destination.write_text(Path(os.environ['TEST_LAUNCHER']).read_text())
elif url.endswith('/nuvrion-xhttp-install.sh'):
    destination.write_bytes(Path(os.environ['TEST_FIXTURE']).read_bytes())
elif url.endswith('/SHA256SUMS'):
    data = Path(os.environ['TEST_FIXTURE']).read_bytes()
    digest = hashlib.sha256(b'tampered' if os.environ['TEST_TAMPER'] == '1' else data).hexdigest()
    destination.write_text(digest + '  nuvrion-xhttp-install.sh\\n')
else:
    raise SystemExit('Unexpected download: ' + url)
if url.endswith(os.environ.get('TEST_FAILURE') or '/not-a-real-download'):
    sys.exit(22)
''',
            }.items():
                script = binary / name
                script.write_text(text)
                script.chmod(0o755)
            env = {**os.environ, 'PATH': str(binary) + os.pathsep + os.environ['PATH'],
                   'TMPDIR': str(root), 'TEST_APT': str(root / 'apt.log'),
                   'TEST_CURL': str(root / 'curl.log'), 'TEST_RUN': str(root / 'run.log'),
                   'TEST_FIXTURE': str(fixture), 'TEST_LAUNCHER': str(launcher),
                   'TEST_FAILURE': failure, 'TEST_TAMPER': '1' if tamper else '0',
                   'TEST_REVISION': revision}
            if quick:
                command = (ROOT / 'README.md').read_text().split('## Быстрый запуск с GitHub', 1)[1]
                command = command.split('```bash\n', 1)[1].split('\n```', 1)[0]
                result = subprocess.run(['bash', '-c', command], env=env, input='interactive answer\n',
                                        text=True, capture_output=True, timeout=15)
            else:
                result = subprocess.run(['bash', str(launcher), *arguments], env=env,
                                        input='interactive answer\n', text=True, capture_output=True, timeout=15)
            def contents(name):
                file = root / name
                return file.read_text() if file.exists() else ''
            return result, contents('run.log'), contents('curl.log'), contents('apt.log'), list(root.glob('launch.*'))

    def test_launch_pins_both_downloads_and_preserves_interactive_input(self):
        result, run, downloads, _, leftovers = self.run_launcher(quick=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(run, '--install\ninteractive answer\n')
        self.assertEqual(downloads.splitlines()[2:], [
            f'https://raw.githubusercontent.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/{REVISION}/nuvrion-xhttp-install.sh',
            f'https://raw.githubusercontent.com/nuvrion-kvn/Nuvrion-XHTTP-Installer/{REVISION}/SHA256SUMS'])
        self.assertEqual(leftovers, [])

    def test_unsupported_os_stops_before_packages_or_downloads(self):
        for os_id, version in [('debian', '12'), ('ubuntu', '22.04'), ('ubuntu', '26.04')]:
            with self.subTest(os_id=os_id, version=version):
                result, run, downloads, packages, _ = self.run_launcher(os_id=os_id, version=version)
                self.assertEqual(result.returncode, 2)
                self.assertEqual((run, downloads, packages), ('', '', ''))

    def test_checksum_mismatch_does_not_execute_installer(self):
        result, run, _, _, leftovers = self.run_launcher(tamper=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(run, '')
        self.assertEqual(leftovers, [])

    def test_failed_partial_download_does_not_execute_installer(self):
        for stage in ['/nuvrion-xhttp-install.sh', '/SHA256SUMS']:
            with self.subTest(stage=stage):
                result, run, _, _, leftovers = self.run_launcher(failure=stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(run, '')
                self.assertEqual(leftovers, [])

    def test_failed_bootstrap_download_stops_before_packages_or_installer(self):
        result, run, _, packages, leftovers = self.run_launcher(quick=True, failure='/main/install.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((run, packages), ('', ''))
        self.assertEqual(leftovers, [])

    def test_invalid_revision_stops_before_installer_downloads(self):
        result, run, downloads, _, leftovers = self.run_launcher(revision='../main')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(run, '')
        self.assertEqual(len(downloads.splitlines()), 1)
        self.assertEqual(leftovers, [])
