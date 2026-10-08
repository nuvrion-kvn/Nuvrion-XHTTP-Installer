"""Exercise ZRAM repair and boot preparation in temporary files, without APT/systemd."""
import os
from pathlib import Path
import tempfile
import unittest

import test_xhttp_shell


@unittest.skipUnless(os.name != 'nt', 'Requires Linux Bash')
class ZramRepairTests(unittest.TestCase):
    def execute(self, script, root, **env):
        return test_xhttp_shell.XhttpShellTests().run_shell(
            'modinfo(){ return 1; }\n'+script, TEST_KERNEL_ROOT=str(root), **env)

    def boot_files(self, root, kernel='6.8.0-146-generic', *, module=True, initrd=True):
        for name in ('boot', 'state', 'bin', 'modules/'+kernel+'/kernel/drivers/block/zram'):
            (root/name).mkdir(parents=True, exist_ok=True)
        (root/'boot'/('vmlinuz-'+kernel)).write_text('kernel fixture')
        if initrd:
            (root/'boot'/('initrd.img-'+kernel)).write_text('initrd fixture')
        if module:
            (root/'modules'/kernel/'kernel/drivers/block/zram/zram.ko.zst').write_text('module fixture')

    def test_active_swap_does_not_probe_or_install_modules(self):
        with tempfile.TemporaryDirectory() as td:
            result=self.execute('''
swapon(){ echo /dev/zram0; }
zram_module_ready(){ echo MUST_NOT_PROBE;return 1; }
apt_apply_checked(){ echo MUST_NOT_INSTALL;return 1; }
prepare_zram_kernel
[[ -z $ZRAM_PENDING_KERNEL ]]
''',Path(td))
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertNotIn('MUST_NOT',result.stdout)

    def test_current_kernel_modules_use_checked_apt_then_reprobe(self):
        with tempfile.TemporaryDirectory() as td:
            result=self.execute('''
swapon(){ :; };uname(){ echo 6.8.0-88-generic; }
zram_module_ready(){ [[ -f $TEST_KERNEL_ROOT/installed ]]; }
zram_package_available(){ [[ $1 == linux-modules-extra-6.8.0-88-generic ]]; }
apt_apply_checked(){ printf '%s\\n' "$*";touch "$TEST_KERNEL_ROOT/installed"; }
prepare_zram_kernel
[[ -z $ZRAM_PENDING_KERNEL ]]
''',Path(td))
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('install --no-install-recommends linux-modules-extra-6.8.0-88-generic',result.stdout)

    def test_removed_old_abi_prepares_only_complete_installed_new_kernel(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);self.boot_files(root)
            result=self.execute('''
swapon(){ :; };uname(){ echo 6.8.0-88-generic; }
zram_module_ready(){ return 1; };zram_package_available(){ return 1; }
apt_apply_checked(){ echo MUST_NOT_INSTALL;return 1; }
prepare_zram_kernel
[[ $ZRAM_PENDING_KERNEL == 6.8.0-146-generic ]]
''',root)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertNotIn('MUST_NOT',result.stdout)
            self.assertFalse((root/'state/zram-pending-kernel').exists())

    def test_new_kernel_extra_modules_installed_and_verified_before_selection(self):
        for produces_module in ('0','1'):
            with self.subTest(produces_module=produces_module),tempfile.TemporaryDirectory() as td:
                root=Path(td);self.boot_files(root,module=False)
                result=self.execute('''
swapon(){ :; };uname(){ echo 6.8.0-88-generic; }
zram_module_ready(){ return 1; }
zram_package_available(){ [[ $1 == linux-modules-extra-6.8.0-146-generic ]]; }
apt_apply_checked(){
 printf '%s\\n' "$*"
 if [[ $TEST_PRODUCES == 1 ]];then printf fixture > "$TEST_KERNEL_ROOT/modules/6.8.0-146-generic/kernel/drivers/block/zram/zram.ko.zst";fi
}
prepare_zram_kernel
[[ $ZRAM_PENDING_KERNEL == 6.8.0-146-generic ]]
''',root,TEST_PRODUCES=produces_module)
                self.assertEqual(result.returncode,0 if produces_module=='1' else 1,result.stderr)
                self.assertIn('install --no-install-recommends linux-modules-extra-6.8.0-146-generic',result.stdout)

    def test_wrong_flavour_missing_initrd_and_same_kernel_never_become_pending(self):
        for kernel,initrd in [('6.8.0-146-azure',True),('6.8.0-146-generic',False),('6.8.0-88-generic',True)]:
            with self.subTest(kernel=kernel,initrd=initrd),tempfile.TemporaryDirectory() as td:
                root=Path(td);self.boot_files(root,kernel,initrd=initrd)
                result=self.execute('''
swapon(){ :; };uname(){ echo 6.8.0-88-generic; }
zram_module_ready(){ return 1; };zram_package_available(){ return 1; }
apt_apply_checked(){ echo MUST_NOT_INSTALL;return 1; }
prepare_zram_kernel
echo MUST_NOT_SUCCEED
''',root)
                self.assertEqual(result.returncode,1,result.stderr)
                self.assertNotIn('MUST_NOT',result.stdout)
                self.assertFalse((root/'state/zram-pending-kernel').exists())

    def test_present_but_unloadable_module_is_not_hidden_as_a_reboot_wait(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);self.boot_files(root)
            result=self.execute('''
swapon(){ :; };uname(){ echo 6.8.0-88-generic; }
zram_module_ready(){ return 1; };zram_package_available(){ return 1; }
modinfo(){ return 0; }
prepare_zram_kernel
echo MUST_NOT_SUCCEED
''',root)
            self.assertEqual(result.returncode,1,result.stderr)
            self.assertIn('существует, но не загружается',result.stderr)
            self.assertNotIn('MUST_NOT',result.stdout)

    def test_pending_boot_writes_helper_unit_and_marker_without_starting_service(self):
        for failure in ('','enable','helper','foreign','module'):
            with self.subTest(failure=failure),tempfile.TemporaryDirectory() as td:
                root=Path(td);self.boot_files(root,module=failure!='module')
                result=self.execute('''
uname(){ echo 6.8.0-88-generic; }
get_active_zram(){ :; };warn(){ printf '%s\\n' "$*"; };info(){ :; }
has_external_zram_manager(){ [[ $TEST_FAILURE == foreign ]]; }
ensure_zram_userspace_tools(){ :; }
atomic_write_file(){ cat > "$1";chmod "$2" "$1"; }
write_nuvrion_zram_helper(){
 [[ $TEST_FAILURE != helper ]] || return 1
 printf '#!/bin/sh\\nexit 0\\n' > "$ZRAM_SETUP";chmod 755 "$ZRAM_SETUP"
}
systemctl(){
 printf '%s\\n' "$*" >> "$TEST_KERNEL_ROOT/systemctl-calls"
 case $1 in start|restart) echo MUST_NOT_START;return 1;;enable|is-enabled) [[ $TEST_FAILURE != enable ]];;*) :;;esac
}
RAM_MB=4096
ZRAM_SERVICE=$TEST_KERNEL_ROOT/zram.service;ZRAM_SETUP=$TEST_KERNEL_ROOT/bin/nuvrion-zram-setup.sh
NUVRION_ZRAM_PENDING_KERNEL=6.8.0-146-generic
complete_zram_setup
zram_pending_ready
''',root,TEST_FAILURE=failure)
                self.assertEqual(result.returncode,0 if failure=='' else 1,result.stderr)
                self.assertNotIn('MUST_NOT_START',result.stdout)
                marker=root/'state/zram-pending-kernel'
                self.assertEqual(marker.exists(),failure=='')
                if failure=='':
                    self.assertEqual(marker.read_text(),'6.8.0-146-generic\n')
                    self.assertIn('ExecStart='+str(root/'bin/nuvrion-zram-setup.sh'),(root/'zram.service').read_text())
                    self.assertEqual(marker.stat().st_mode & 0o777,0o600)

    def test_tuner_without_active_swap_or_prepared_kernel_is_a_failure(self):
        with tempfile.TemporaryDirectory() as td:
            result=self.execute('''
get_active_zram(){ :; };warn(){ printf '%s\\n' "$*"; }
NUVRION_ZRAM_PENDING_KERNEL=''
complete_zram_setup
echo MUST_NOT_SUCCEED
''',Path(td))
            self.assertEqual(result.returncode,1,result.stderr)
            self.assertNotIn('MUST_NOT',result.stdout)


if __name__=='__main__':
    unittest.main()
