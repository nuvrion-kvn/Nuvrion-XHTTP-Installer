"""Archive security and early platform guards; never install on the host."""
import io
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import test_xhttp
import test_xhttp_shell


class CoreAuditTests(unittest.TestCase):
    def archive(self, path, entries):
        with tarfile.open(path, 'w:gz') as archive:
            for name, kind in entries:
                item = tarfile.TarInfo(name)
                item.type = kind
                data = b'verified payload'
                if kind == tarfile.REGTYPE:
                    item.size = len(data)
                    archive.addfile(item, io.BytesIO(data))
                else:
                    item.linkname = '/etc/passwd'
                    archive.addfile(item)

    def unpack(self, archive, target):
        with patch.object(sys, 'argv', ['helper', 'unpack', str(archive), str(target)]):
            test_xhttp.LIB['run']()

    def test_unpack_rejects_traversal_links_duplicates_before_writing(self):
        for entries in [[('../escape', tarfile.REGTYPE)],
                        [('/escape', tarfile.REGTYPE)],
                        [('link', tarfile.SYMTYPE)],
                        [('same', tarfile.REGTYPE), ('same', tarfile.REGTYPE)]]:
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as tmp:
                archive = Path(tmp)/'bundle.tar.gz'
                target = Path(tmp)/'bundle'
                self.archive(archive, entries)
                with self.assertRaises(ValueError):
                    self.unpack(archive, target)
                self.assertFalse(target.exists())

    def test_unpack_regular_contents_are_private_and_destination_is_exclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp)/'bundle.tar.gz'
            target = Path(tmp)/'bundle'
            self.archive(archive, [('nested/file', tarfile.REGTYPE)])
            self.unpack(archive, target)
            output = target/'nested/file'
            self.assertEqual(output.read_bytes(), b'verified payload')
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                self.unpack(archive, target)
            self.assertEqual(output.read_bytes(), b'verified payload')

    @unittest.skipUnless(os.name != 'nt', 'Linux Bash guard')
    def test_other_distributions_and_ubuntu_versions_are_rejected_before_changes(self):
        for system, version in [('ubuntu', '22.04'), ('ubuntu', '24.10'),
                                ('ubuntu', '26.04'), ('debian', '12'),
                                ('linuxmint', '22'), ('rocky', '9')]:
            with self.subTest(system=system, version=version):
                result = test_xhttp_shell.XhttpShellTests().run_shell('''
source(){ ID=$TEST_OS_ID; VERSION_ID=$TEST_OS_VERSION; PRETTY_NAME=fixture; }
ACTION=install;detect_os;echo MUST_NOT_CHANGE
''', TEST_OS_ID=system, TEST_OS_VERSION=version)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertNotIn('MUST_NOT_CHANGE', result.stdout)
                self.assertIn('Ubuntu 24.04', result.stderr)

    @unittest.skipUnless(os.name != 'nt', 'Linux Bash guard')
    def test_unsupported_architecture_is_rejected_before_changes(self):
        result = test_xhttp_shell.XhttpShellTests().run_shell('''
source(){ ID=ubuntu; VERSION_ID=24.04; PRETTY_NAME=fixture; }
uname(){ case $1 in -m) echo armv7l;;*) echo fixture;;esac; }
ACTION=install;detect_os;echo MUST_NOT_CHANGE
''')
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertNotIn('MUST_NOT_CHANGE', result.stdout)

    @unittest.skipUnless(os.name != 'nt', 'Linux Bash guard')
    def test_self_check_accepts_other_os_for_read_only_inspection(self):
        result = test_xhttp_shell.XhttpShellTests().run_shell('''
source(){ ID=debian; VERSION_ID=12; PRETTY_NAME=fixture; }
ACTION=self-check;detect_os;echo INSPECT_ONLY
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INSPECT_ONLY', result.stdout)

    @unittest.skipUnless(os.name != 'nt', 'Linux Bash guard')
    def test_rollback_returns_own_recovered_node_to_original_stopped_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, 'node-running.txt').write_text('false\n')
            result = test_xhttp_shell.XhttpShellTests().run_shell('''
NODE_CONTAINER=own-node
docker(){ case $1 in inspect) echo true;;stop) echo "$2" >> "$TEST_RUNTIME/stopped";;*) return 1;;esac; }
restore_node_running "$TEST_RUNTIME"
''', TEST_RUNTIME=tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(tmp, 'stopped').read_text(), 'own-node\n')

    @unittest.skipUnless(os.name != 'nt', 'Linux Bash callback')
    def test_active_owned_zram_is_not_repaired_again_after_tuning(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'bundle').mkdir(); (root/'bin').mkdir()
            for name in ('zram.service', 'zram-setup.sh'):
                (root/name).touch()
            systemctl = root/'bin/systemctl'
            systemctl.write_text('#!/bin/sh\nexit 0\n'); systemctl.chmod(0o700)
            (root/'bundle/nuvrion-auto-tuning.sh').write_text('''
ZRAM_SERVICE="$TEST_RUNTIME/zram.service"
ZRAM_SETUP="$TEST_RUNTIME/zram-setup.sh"
get_active_zram(){ echo /dev/zram0; }
has_external_zram_manager(){ return 1; }
create_or_repair_nuvrion_zram(){ touch "$TEST_RUNTIME/unexpected-repair"; }
''')
            result = test_xhttp_shell.XhttpShellTests().run_shell('''
WORK="$TEST_RUNTIME"; command install -d "$OWN"
PATH="$TEST_RUNTIME/bin:$PATH"; export PATH
security_baseline(){ :; }; repair_owned_rps(){ :; }; prepare_zram_kernel(){ :; }
helper(){ :; }; capture_owned_rps(){ :; }
NODE_PORT=2222; PANEL_IP=203.0.113.2
apply_tuning
cat "$OWN/tuning-report.log"
''', TEST_RUNTIME=tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root/'unexpected-repair').exists())
            self.assertNotIn('command not found', result.stdout)
