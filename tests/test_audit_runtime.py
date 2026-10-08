"""Runtime regressions use temporary files and mocked host operations only."""
import copy
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'nuvrion-xhttp-install.sh').read_text().split('# BEGIN EMBEDDED NUVRION XHTTP')[0]
PYTHON=SOURCE.split("<<'NUVRION_PY'\n",1)[1].split('\nNUVRION_PY',1)[0]
LIB={'__name__':'audit_runtime'}
exec(compile(PYTHON,'embedded-runtime-helper','exec'),LIB)


class AuditRuntimeTests(unittest.TestCase):
    def shell(self,body):
        with tempfile.TemporaryDirectory(prefix='nuvrion-audit-') as td:
            source=SOURCE.replace('/opt/remnanode',td+'/remnanode').replace('/run/nuvrion-xhttp',td+'/run-nuvrion-xhttp')
            Path(td,'definitions.sh').write_text(source)
            return subprocess.run(['bash'],input='source "$FIXTURE/definitions.sh"\n'+body,
                                  env={**os.environ,'FIXTURE':td},capture_output=True,text=True,timeout=20)

    def test_host_nginx_does_not_require_docker_nginx_image(self):
        result=self.shell(r'''
NODE_CONTAINER=node;NGINX_KIND=host;NGINX_CONTAINER=''
docker(){ if [[ $1 == image ]];then echo MUST_NOT_INSPECT_IMAGE >&2;return 1;else echo sha256:node;fi; }
helper(){ [[ $1 != xff-version ]] || echo 1; }
save_state
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('MUST_NOT_INSPECT_IMAGE',result.stderr)

    def test_host_nginx_is_not_a_compose_service(self):
        config={'services':{'node':{'image':'sha256:node','network_mode':'host'}}}
        LIB['verify_compose'](config,copy.deepcopy(config),{'node_service':'node','nginx_service':'','nginx_new':False,'nginx_kind':'host'})

    def test_failed_acme_pre_restores_stopped_services(self):
        result=self.shell(r'''
require_root(){ :; };load_settings(){ :; };state_value(){ printf nft; }
port80_plan(){ printf '{"units":["nginx.service"],"containers":[]}'; }
systemctl(){ echo "SERVICE_$*"; }
acme_firewall(){ [[ $1 == close ]] || return 7; }
main --acme-pre
''')
        self.assertEqual(result.returncode,7,result.stderr)
        self.assertIn('SERVICE_stop nginx.service',result.stdout)
        self.assertIn('SERVICE_start nginx.service',result.stdout)
        self.assertIn('восстанавливаю',result.stderr)

    def test_game_socket_helper_does_not_lock_waiting_install(self):
        result=self.shell(r'''
require_root(){ :; };load_settings(){ :; };state_value(){ echo 33; }
lock_changes(){ echo MUST_NOT_LOCK;return 1; };game_socket(){ echo SOCKET_HELPER; }
main --game-socket
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('SOCKET_HELPER',result.stdout)
        self.assertNotIn('MUST_NOT_LOCK',result.stdout)

    def test_rejected_second_acme_pre_does_not_clean_first_lease(self):
        result=self.shell(r'''
require_root(){ :; };load_settings(){ :; };state_value(){ echo nft; }
printf '{"units":["first-renewal.service"],"containers":[]}' > "$FIXTURE/run-nuvrion-xhttp-acme.json"
systemctl(){ echo MUST_NOT_RESTART_FIRST_RENEWAL; }
acme_firewall(){ echo MUST_NOT_CLOSE_FIRST_RENEWAL; }
main --acme-pre
''')
        self.assertEqual(result.returncode,4,result.stderr)
        self.assertNotIn('MUST_NOT',result.stdout)

    def test_certbot_close_fds_hook_can_use_verified_parent_lock(self):
        result=self.shell(r'''
lock_changes
python3 - "$FIXTURE" <<'PY'
import os,subprocess,sys
result=subprocess.run(['bash','-c','source "$FIXTURE/definitions.sh"; test ! -e /proc/$$/fd/9; lock_changes; echo HOOK_OK'],capture_output=True,text=True,close_fds=True,env=os.environ)
print(result.stdout,end='');print(result.stderr,end='',file=sys.stderr)
assert result.returncode==0
PY
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('HOOK_OK',result.stdout)

    def test_unrelated_process_cannot_bypass_lock_using_owner_pid(self):
        result=self.shell(r'''
lock_changes
python3 - "$FIXTURE" <<'PY'
import os,subprocess,sys
env=dict(os.environ);env['NUVRION_LOCK_OWNER_PID']='1'
result=subprocess.run(['bash','-c','source "$FIXTURE/definitions.sh"; lock_changes; echo MUST_NOT_PASS'],capture_output=True,text=True,close_fds=True,env=env)
assert result.returncode==1
assert 'MUST_NOT_PASS' not in result.stdout
print('UNVERIFIED_OWNER_REJECTED')
PY
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('UNVERIFIED_OWNER_REJECTED',result.stdout)

    def test_acme_post_preserves_lease_on_firewall_cleanup_failure(self):
        result=self.shell(r'''
printf '{"units":[],"containers":[]}' > "$FIXTURE/run-nuvrion-xhttp-acme.json"
acme_firewall(){ return 1; }
trap 'test -f "$FIXTURE/run-nuvrion-xhttp-acme.json" && echo LEASE_PRESERVED' EXIT
acme_post
''')
        self.assertEqual(result.returncode,4,result.stderr)
        self.assertIn('LEASE_PRESERVED',result.stdout)

    def test_cleanup_captures_runtime_before_rollback(self):
        result=self.shell(r'''
TRANSACTION=1;YES=1;BACKUP=fixture
end_package_maintenance(){ :; }
capture_runtime_after(){ echo LIVE_SNAPSHOT; }
capture_transaction(){ echo OWNERSHIP_JOURNAL; }
rollback(){ echo ROLLBACK; }
trap cleanup EXIT
exit 2
''')
        self.assertEqual(result.returncode,8,result.stderr)
        self.assertLess(result.stdout.index('LIVE_SNAPSHOT'),result.stdout.index('ROLLBACK'))
        self.assertLess(result.stdout.index('OWNERSHIP_JOURNAL'),result.stdout.index('ROLLBACK'))

    def test_partial_first_tuning_keys_are_captured_before_conf_publication(self):
        result=self.shell(r'''
mkdir -p "$OWN" "$FIXTURE/bin"
printf 'net.ipv4.tcp_mtu_probing = 1\n' > "$FIXTURE/tuner.sh"
printf '#!/bin/sh\nprintf "21\\n"\n' > "$FIXTURE/bin/sysctl"
chmod +x "$FIXTURE/bin/sysctl"
export PATH="$FIXTURE/bin:$PATH"
helper runtime-keys "$FIXTURE/tuner.sh" "$OWN/runtime-keys.json"
helper runtime-after "$OWN/sysctl-after.json"
python3 - "$OWN/sysctl-after.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['net.ipv4.tcp_mtu_probing']=='21'
PY
''')
        self.assertEqual(result.returncode,0,result.stderr)

    def test_runtime_snapshot_failure_prevents_unverified_rollback(self):
        result=self.shell(r'''
TRANSACTION=1;YES=1;BACKUP=fixture
end_package_maintenance(){ :; };capture_runtime_after(){ :; }
capture_transaction(){ return 1; };rollback(){ echo MUST_NOT_ROLLBACK; }
trap cleanup EXIT
exit 2
''')
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertNotIn('MUST_NOT_ROLLBACK',result.stdout)

    def test_rollback_ownership_preflight_runs_before_firewall_or_service_mutations(self):
        result=self.shell(r'''
mkdir -p "$FIXTURE/backup"
printf '[]' > "$FIXTURE/backup/files.json"
printf '{}' > "$FIXTURE/backup/after-delta.json"
helper(){ case $1 in rollback-selection) echo '[]';;restore-check) return 1;;*) echo MUST_NOT_MUTATE;return 1;;esac; }
firewall_remove(){ echo MUST_NOT_REMOVE_FIREWALL; }
security_stop(){ echo MUST_NOT_STOP_SERVICES; }
rollback "$FIXTURE/backup"
''')
        self.assertEqual(result.returncode,1,result.stderr)
        self.assertNotIn('MUST_NOT',result.stdout)

    def test_directory_restore_preserves_new_unknown_files(self):
        with tempfile.TemporaryDirectory() as td:
            folder=Path(td,'backup');folder.mkdir()
            directory=Path(td,'config');directory.mkdir()
            owned=directory/'nuvrion.conf';owned.write_text('before')
            original=LIB['safe_backup'];LIB['safe_backup']=lambda p:Path(p)
            try:
                LIB['snapshot'](folder/'snapshot',[str(directory)])
                backup=folder/'snapshot'
                owned.write_text('after')
                journal=folder/'journal.json';LIB['snapshot_delta'](backup,journal,True)
                foreign=directory/'other-service.conf';foreign.write_text('external')
                LIB['restore'](backup,[str(directory)],journal)
                self.assertEqual(owned.read_text(),'before')
                self.assertEqual(foreign.read_text(),'external')
            finally:LIB['safe_backup']=original

    def test_directory_restore_refuses_later_edits_before_any_writes(self):
        with tempfile.TemporaryDirectory() as td:
            directory=Path(td,'config');directory.mkdir()
            first=directory/'nuvrion-first.conf';second=directory/'nuvrion-second.conf'
            first.write_text('first before');second.write_text('second before')
            original=LIB['safe_backup'];LIB['safe_backup']=lambda p:Path(p)
            try:
                backup=Path(td,'snapshot');LIB['snapshot'](backup,[str(directory)])
                first.write_text('first after');second.write_text('second after')
                journal=Path(td,'journal.json');LIB['snapshot_delta'](backup,journal,True)
                second.write_text('external edit')
                with self.assertRaisesRegex(ValueError,'после снимка'):LIB['restore'](backup,[str(directory)],journal)
                self.assertEqual(first.read_text(),'first after')
                self.assertEqual(second.read_text(),'external edit')
            finally:LIB['safe_backup']=original

    def test_shared_sysctl_journal_recognizes_only_exact_marker_edits(self):
        with tempfile.TemporaryDirectory() as td:
            # Substitute shared roots in the function's global definition to
            # exercise the same logic without writing into host /etc.
            shared=Path(td,'sysctl.d');shared.mkdir()
            code=PYTHON.replace("'/etc/sysctl.d'",repr(str(shared))).replace("'/etc/sysctl'",repr(str(shared)))
            lib={'__name__':'runtime_fixture'};exec(code,lib);lib['safe_backup']=lambda p:Path(p)
            file=shared/'zz-admin.conf';file.write_text('net.core.somaxconn = 128\n')
            backup=Path(td,'snapshot');lib['snapshot'](backup,[str(shared)])
            file.write_text('# [Nuvrion v1.0.0] отключено: net.core.somaxconn = 128\n')
            journal=Path(td,'journal.json');lib['snapshot_delta'](backup,journal,True)
            expected=lib['read'](journal)[str(file)]['after']
            file.write_text(file.read_text()+'# independent external edit\n')
            lib['snapshot_delta'](backup,journal,True)
            self.assertEqual(lib['read'](journal)[str(file)]['after'],expected)
            new=shared/'foreign.conf';new.write_text('external')
            lib['snapshot_delta'](backup,journal,True)
            self.assertNotIn(str(new),lib['read'](journal))
            with self.assertRaises(ValueError):lib['restore'](backup,[str(shared)],journal)


if __name__=='__main__':unittest.main()
