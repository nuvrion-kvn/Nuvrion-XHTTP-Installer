"""Run isolated shell guards and key parsing; never run main or host changes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT/'nuvrion-xhttp-install.sh').read_text(encoding='utf-8').split('# BEGIN EMBEDDED NUVRION XHTTP')[0]


@unittest.skipUnless(os.name != 'nt' and shutil.which('bash'), 'Requires Linux Bash')
class XhttpShellTests(unittest.TestCase):
    def run_shell(self, code, **env):
        with tempfile.TemporaryDirectory() as fixture:
            source=SOURCE.replace('readonly PROFILE=/root/nuvrion-xhttp-profile.json',
                                  'readonly PROFILE='+fixture+'/profile.json')
            source=source.replace('readonly LOG=/var/log/nuvrion-xhttp-installer.log',
                                  'readonly LOG='+fixture+'/installer.log')
            source=source.replace('/usr/sbin/policy-rc.d',fixture+'/policy-rc.d')
            source=source.replace('readonly BASE=/opt/remnanode','readonly BASE='+fixture+'/remnanode')
            if 'TEST_RPS_ROOT' in env:
                source=source.replace('/usr/local/sbin/nuvrion-rps-setup.sh',env['TEST_RPS_ROOT']+'/setup.sh')
                source=source.replace('/etc/systemd/system/nuvrion-rps.service',env['TEST_RPS_ROOT']+'/rps.service')
            if 'TEST_KERNEL_ROOT' in env:
                for path, name in [('/boot/','/boot/'),('/lib/modules/','/modules/'),
                                   ('/var/lib/nuvrion-tuning/','/state/')]:
                    source=source.replace(path,env['TEST_KERNEL_ROOT']+name)
            return subprocess.run(['bash'], input=source+'\n'+code,
                                  env={**os.environ,'TEST_POLICY':fixture+'/policy-rc.d',**env},
                                  text=True,capture_output=True,timeout=20)

    def test_os_version_does_not_shadow_installer_version(self):
        r=self.run_shell('ACTION=diagnose;detect_os;printf "installer=%s" "$INSTALLER_VERSION"')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('installer=1.0.0',r.stdout)

    def test_binary_log_padding_does_not_hide_real_errors_or_warn_about_null_bytes(self):
        result=self.run_shell(r'''docker(){ printf 'padding\000invalid config\n'; }
NODE_CONTAINER=fixture;NGINX_CONTAINER=fixture
diagnostic_logs
printf 'fails=%s' "$FAILS"
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('fails=1',result.stdout)
        self.assertNotIn('ignored null byte',result.stderr)

    def test_x25519_labels_from_old_and_current_core(self):
        for label in ['PublicKey', 'Public key', 'Password', 'Password (PublicKey)']:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as td:
                code='''
WORK=$TEST_WORK;NODE_CONTAINER=fixture;XRAY_BIN=fixture
ss(){ :; }
docker(){ printf 'PrivateKey: %s\\n%s: %s\\n' "$TEST_PRIVATE" "$TEST_LABEL" "$TEST_PUBLIC"; }
generate_reality_keys
printf 'public=%s' "$PUBLIC_KEY"
'''
                r=self.run_shell(code,TEST_WORK=td,TEST_PRIVATE='A'*43,TEST_PUBLIC='B'*43,TEST_LABEL=label)
                self.assertEqual(r.returncode,0,r.stderr)
                self.assertEqual(json.loads((Path(td)/'keys.json').read_text())['private'],'A'*43)
                self.assertNotIn('A'*43,r.stdout+r.stderr)
                self.assertIn('B'*43,r.stdout)

    def test_system_install_is_not_our_install_entrypoint(self):
        with tempfile.TemporaryDirectory() as td:
            r=self.run_shell('command install -d -m 700 "$TEST_WORK/subdir";test -d "$TEST_WORK/subdir"',TEST_WORK=td)
            self.assertEqual(r.returncode,0,r.stderr)

    def test_firewall_runs_before_fresh_node_can_bind_public_api(self):
        r=self.run_shell('''
load_settings(){ :; };plan_install(){ :; };create_backup(){ :; }
unpack_bundle(){ :; };begin_package_maintenance(){ :; };install_dependencies(){ :; }
configure_firewall(){ echo API_GUARD; }
prepare_node(){ echo NODE_START;exit 0; }
command(){ [[ $1 == install ]] || builtin command "$@"; }
touch(){ :; };chmod(){ :; }
install
''')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertLess(r.stdout.index('API_GUARD'),r.stdout.index('NODE_START'))

    def apt_fixture(self, operation, plan='', changed=False):
        with tempfile.TemporaryDirectory() as td:
            return self.run_shell('''
apt_run(){
 if [[ $1 == -s ]];then
  if [[ $TEST_CHANGED == 1 && -f $TEST_WORK/seen ]];then echo 'Remv different [1]'
  else printf '%s\\n' "$TEST_PLAN";fi
  touch "$TEST_WORK/seen";return 0
 fi
 printf 'EXEC %s\\n' "$*"
}
'''+operation+'\nresult=$?;[[ ! -f $LOG ]] || cat "$LOG";exit "$result"',
                TEST_WORK=td,TEST_PLAN=plan,TEST_CHANGED='1' if changed else '0')

    def test_update_rejects_removals_and_changed_plans(self):
        for plan, changed in [('Remv libunused [1]', False),('Inst pkg [1] (2 repo)', True)]:
            r=self.apt_fixture('apt_apply_checked --with-new-pkgs upgrade',plan,changed)
            self.assertNotEqual(r.returncode,0)
            self.assertNotIn('EXEC',r.stdout)

    def test_update_applies_verified_plan_without_removals(self):
        r=self.apt_fixture('apt_apply_checked --with-new-pkgs upgrade','Inst pkg [1] (2 repo)\nConf pkg (2 repo)')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('EXEC -y --no-remove --with-new-pkgs upgrade',r.stdout)

    def test_cleanup_protects_kernel_boot_network_and_components(self):
        for package in ('linux-image-6.8.0-146-generic','grub-common','openssh-server',
                        'docker-ce','containerd.io','python3:amd64','util-linux','zram-tools','kmod'):
            with self.subTest(package=package):
                r=self.apt_fixture('cleanup_system_packages','Remv '+package+' [1]')
                self.assertEqual(r.returncode,0,r.stderr)
                self.assertNotIn('EXEC',r.stdout)

    def test_cleanup_rejects_changed_or_installation_plan(self):
        for plan,changed in [('Remv libunused [1]',True),('Inst pkg [1] (2 repo)',False)]:
            r=self.apt_fixture('cleanup_system_packages',plan,changed)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertNotIn('EXEC',r.stdout)

    def test_cleanup_removes_only_verified_orphans_and_old_cache(self):
        r=self.apt_fixture('cleanup_system_packages','Remv libunused [1]')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('-y autoremove',r.stdout)
        self.assertIn('autoclean',r.stdout)
        self.assertNotIn('--purge',r.stdout)
        self.assertNotIn(' clean',r.stdout)

    def test_empty_cleanup_only_cleans_obsolete_cache(self):
        r=self.apt_fixture('cleanup_system_packages')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertNotIn('autoremove',r.stdout)
        self.assertIn('autoclean',r.stdout)

    def test_package_policy_and_docker_version_are_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            r=self.run_shell('''
WORK=$TEST_WORK
dpkg-query(){ printf 'docker-ce\\t29.1.3\\tinstall ok installed\\n'; }
printf '#!/bin/sh\\nexit 0\\n' > "$TEST_POLICY"
chmod 751 "$TEST_POLICY"
cp -a "$TEST_POLICY" "$WORK/before"
begin_package_maintenance
grep -q 'Pin: version 29.1.3' "$APT_PREFERENCES"
"$TEST_POLICY" && exit 1 || [[ $? == 101 ]]
end_package_maintenance
cmp "$TEST_POLICY" "$WORK/before"
[[ $(stat -c %a "$TEST_POLICY") == 751 ]]
''',TEST_WORK=td)
            self.assertEqual(r.returncode,0,r.stderr)

    def test_zram_absence_is_a_failure_without_prepared_kernel(self):
        r=self.run_shell('''
swapon(){ :; };zram_pending_ready(){ return 1; }
validate_zram
[[ $ZRAM_STATUS == BROKEN && $FAILS == 1 ]]
''')
        self.assertEqual(r.returncode,0,r.stderr)

    def test_active_zram_without_autostart_is_not_reported_as_ready(self):
        r=self.run_shell('''
swapon(){ echo /dev/zram0; };zram_autostart_ready(){ return 1; }
validate_zram
[[ $ZRAM_STATUS == BROKEN && $FAILS == 1 ]]
''')
        self.assertEqual(r.returncode,0,r.stderr)

    def test_zram_reboot_wait_requires_verified_preparation(self):
        r=self.run_shell('''
swapon(){ :; };zram_pending_ready(){ return 0; }
validate_zram
[[ $ZRAM_STATUS == REBOOT_REQUIRED && $REBOOT_NEEDED == 1 && $FAILS == 0 ]]
''')
        self.assertEqual(r.returncode,0,r.stderr)

    def test_pending_zram_requires_new_kernel_image_initrd_module_and_autostart(self):
        for missing in ('', 'image', 'initrd', 'module', 'autostart', 'newer'):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as td:
                root=Path(td);kernel='6.8.0-146-generic'
                for directory in ('boot','state','modules/'+kernel+'/kernel/drivers/block/zram'):
                    (root/directory).mkdir(parents=True,exist_ok=True)
                (root/'state/zram-pending-kernel').write_text(kernel)
                for name, file in [('image','boot/vmlinuz-'+kernel),('initrd','boot/initrd.img-'+kernel),
                                  ('module','modules/'+kernel+'/kernel/drivers/block/zram/zram.ko.zst')]:
                    if missing!=name:(root/file).write_text('fixture')
                r=self.run_shell('''
uname(){ echo "$TEST_RUNNING"; }
systemctl(){ [[ $TEST_ENABLED == 1 ]]; }
zram_pending_ready
''',TEST_KERNEL_ROOT=td,TEST_ENABLED='0' if missing=='autostart' else '1',
                    TEST_RUNNING=kernel if missing=='newer' else '6.8.0-88-generic')
                self.assertEqual(r.returncode,0 if missing=='' else 1,r.stderr)

    def test_uninstall_enables_service_rollback_before_stopping_components(self):
        with tempfile.TemporaryDirectory() as td:
            r=self.run_shell('''
YES=1;mkdir -p "$OWN" "$TEST_WORK/original"
touch "$STATE" "$OWN/owned-delta.json" "$TEST_WORK/original/files.json"
load_settings(){ :; };detect_os(){ :; };detect_network(){ :; }
detect_remnanode(){ :; };detect_nginx(){ NGINX_NEW=1; };detect_firewall(){ :; }
state_value(){ echo "$TEST_WORK/original"; }
helper(){ :; };create_backup(){ :; }
restore_unit_states(){
 [[ $SERVICES_APPLIED == 1 && $NGINX_RECREATE == 1 ]] || exit 1
 echo ROLLBACK_READY;exit 0
}
uninstall
''',TEST_WORK=td)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertIn('ROLLBACK_READY',r.stdout)

    def test_unknown_noninteractive_options_rejected_before_changes(self):
        r=self.run_shell('parse_args --domain;echo MUST_NOT_RUN')
        self.assertNotEqual(r.returncode,0)
        self.assertNotIn('MUST_NOT_RUN',r.stdout)

    def test_key_only_requires_verified_login_before_security_changes(self):
        r=self.run_shell('''
ADMIN_IP=192.0.2.1;SSH_PORT=22;SSH_KEY_ONLY=1;SSH_KEY_CONFIRMED=0
security_plan
echo MUST_NOT_RUN
''')
        self.assertNotEqual(r.returncode,0)
        self.assertNotIn('MUST_NOT_RUN',r.stdout)
        self.assertIn('SSH отключены',r.stderr)

    def test_profile_test_uses_explicit_json_format(self):
        with tempfile.TemporaryDirectory() as td:
            r=self.run_shell('''
helper(){ :; };rm(){ :; }
docker(){ [[ "$*" == *"run -test -format json -config"* ]]; }
WORK=$TEST_WORK;NODE_CONTAINER=fixture;XRAY_BIN=fixture
printf '{}' > "$PROFILE"
printf '{}' > "$WORK/keys.json"
generate_remnawave_profile
''',TEST_WORK=td)
        self.assertEqual(r.returncode,0,r.stderr)

    def test_key_only_rejects_conflicting_skip_options_before_changes(self):
        for option in ('NO_TUNING','NO_SSH'):
            with self.subTest(option=option):
                r=self.run_shell('ADMIN_IP=192.0.2.1;SSH_PORT=22;SSH_KEY_ONLY=1;SSH_KEY_CONFIRMED=1;'+option+'=1;security_plan;echo MUST_NOT_RUN')
                self.assertNotEqual(r.returncode,0)
                self.assertNotIn('MUST_NOT_RUN',r.stdout)
                self.assertIn('SSH отключены',r.stderr)

    def test_legacy_ssh_flags_are_rejected_before_any_changes(self):
        for option in ('--ssh-key-only','--ssh-key-login-confirmed'):
            r=self.run_shell('parse_args '+option+';echo MUST_NOT_RUN')
            self.assertNotEqual(r.returncode,0)
            self.assertNotIn('MUST_NOT_RUN',r.stdout)

    def test_owned_rps_autostart_is_restored_after_uninstall_handoff(self):
        with tempfile.TemporaryDirectory() as td:
            r=self.run_shell('''
mkdir -p "$OWN"
printf "FLOW_GLOBAL='32768'\\n" > "$OWN/rps-managed.sh";printf unit > "$OWN/rps-managed.service"
state_value(){ echo true; }
systemctl(){ echo "SERVICE $*"; }
sysctl(){ if [[ $1 == -n ]];then echo 0;else echo "SYSCTL $*";fi; }
repair_owned_rps
cmp "$OWN/rps-managed.sh" "$TEST_RPS_ROOT/setup.sh"
cmp "$OWN/rps-managed.service" "$TEST_RPS_ROOT/rps.service"
''',TEST_RPS_ROOT=td)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertIn('enable --now nuvrion-rps.service',r.stdout)
            self.assertIn('net.core.rps_sock_flow_entries=32768',r.stdout)

    def test_rps_handoff_does_not_overwrite_later_user_edit(self):
        with tempfile.TemporaryDirectory() as td:
            r=self.run_shell('''
mkdir -p "$OWN"
printf helper > "$OWN/rps-managed.sh";printf unit > "$OWN/rps-managed.service"
printf user > "$TEST_RPS_ROOT/setup.sh"
state_value(){ echo true; }
systemctl(){ echo MUST_NOT_RUN; }
repair_owned_rps
[[ $(cat "$TEST_RPS_ROOT/setup.sh") == user ]]
[[ ! -e "$TEST_RPS_ROOT/rps.service" ]]
''',TEST_RPS_ROOT=td)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertNotIn('MUST_NOT_RUN',r.stdout)

    def test_rollback_to_removed_state_uses_preserved_node_compose(self):
        with tempfile.TemporaryDirectory() as td:
            r=self.run_shell('''
mkdir -p "$BASE"
printf '{}' > "$BASE/docker-compose.yml"
python3 -c 'import json,sys;json.dump(dict(node_service="remnanode",project="fixture",workdir=sys.argv[1],compose_files=[sys.argv[1]+"/docker-compose.yml",sys.argv[2]],removed=True,nginx_new=True),open(sys.argv[3],"w"))' "$BASE" "$OVERRIDE" "$TEST_WORK/old.json"
load_settings(){ :; }
compose_command(){ [[ ${#COMPOSE_FILES[@]} == 1 && -f ${COMPOSE_FILES[0]} ]];COMPOSE_CMD=(docker compose); }
docker(){ echo "RESTORE $*"; }
reload_nginx(){ echo MUST_NOT_RELOAD;exit 1; }
restore_services "$TEST_WORK/old.json" 1 1
''',TEST_WORK=td)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertIn('up -d --no-deps --pull never remnanode',r.stdout)
            self.assertNotIn('MUST_NOT_RELOAD',r.stdout)


if __name__ == '__main__':unittest.main()
