"""Isolated stopped-node recovery regressions; never start real Docker/services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'nuvrion-xhttp-install.sh').read_text().split('# BEGIN EMBEDDED NUVRION XHTTP')[0]

FIXTURE = r'''
mkdir -p "$OWN"
printf '{"services":{"remnanode":{"image":"sha256:fixture"}}}\n' > "$BASE/docker-compose.yml"
python3 - "$STATE" "$OWN/owned-delta.json" "$BASE" <<'FIXTURE_PY'
import hashlib,json,pathlib,sys
state,delta,base=map(pathlib.Path,sys.argv[1:])
compose=base/'docker-compose.yml'
state.write_text(json.dumps({'node_container':'fixture','node_service':'remnanode','project':'fixture',
    'workdir':str(base),'node_image_id':'sha256:fixture','node_new':True,'removed':False}))
delta.write_text(json.dumps({str(compose):{'before':None,'after':hashlib.sha256(compose.read_bytes()).hexdigest()}}))
state.chmod(0o600);delta.chmod(0o600)
FIXTURE_PY
printf true > "$BASE/label"
NODE_CONTAINER=fixture
# All command traces remain inside this temporary fixture.
docker(){
 printf '%s\n' "$*" >> "$BASE/docker-calls"
 case $1 in
  info) return 0;;
  compose) [[ $2 == version ]] && return 0;echo UNEXPECTED_COMPOSE_MUTATION;return 1;;
  ps) echo fixture;;
  inspect)
   if [[ ${2:-} == -f ]];then
    case $3 in
     *io.nuvrion.xhttp.installed*) cat "$BASE/label";;
     *Config.User*) printf root;;
     *Mounts*) :;;
     *) echo UNEXPECTED_INSPECT;return 1;;
    esac
   else
    python3 - "$BASE" <<'INSPECT_PY'
import json,pathlib,sys
base=pathlib.Path(sys.argv[1])
print(json.dumps([{'Name':'/fixture','Image':'sha256:fixture','State':{'Running':(base/'started').exists()},
 'Mounts':[],'Config':{'Image':'remnawave/node:3.4.2','Env':['NODE_PORT=3222'],
 'Labels':{'com.docker.compose.service':'remnanode','com.docker.compose.project':'fixture',
 'com.docker.compose.project.working_dir':str(base),'com.docker.compose.project.config_files':str(base/'docker-compose.yml')}},
 'HostConfig':{'NetworkMode':'host'}}]))
INSPECT_PY
   fi;;
  run)
   python3 - "$BASE/run-args" "${@:2}" <<'ARGS_PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);p.write_text(p.read_text()+'\n'+json.dumps(sys.argv[2:]) if p.exists() else json.dumps(sys.argv[2:]))
ARGS_PY
   [[ ${*: -1} != -u ]] || { echo 0;return 0; }
   echo 'Xray 26.7.28';;
  start) [[ $2 == fixture ]] || return 1;touch "$BASE/started";;
  exec) [[ -f $BASE/started ]] || return 1;echo 'Xray 26.7.28';;
  *) echo UNEXPECTED_DOCKER;return 1;;
 esac
}
ss(){ printf '%s' "${TEST_LISTENERS:-}"; }
'''


class StoppedNodeAuditTests(unittest.TestCase):
    def run_shell(self, code, **env):
        with tempfile.TemporaryDirectory() as temp:
            source = SOURCE.replace('readonly BASE=/opt/remnanode', 'readonly BASE=' + temp + '/remnanode')
            source = source.replace('readonly LOG=/var/log/nuvrion-xhttp-installer.log', 'readonly LOG=' + temp + '/installer.log')
            return subprocess.run(['bash'], input=source+'\n'+FIXTURE+'\n'+code,
                                  env={**os.environ, **env}, text=True, capture_output=True, timeout=20)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertNotIn('UNEXPECTED_', result.stdout + result.stderr)

    def test_stopped_owned_discovery_probes_exact_image_without_start(self):
        result = self.run_shell(r'''
detect_remnanode allow-stopped
[[ $NODE_STOPPED == 1 && $NODE_NEW == 0 && $XRAY_VERSION == 'Xray 26.7.28' && $NODE_PORT == 3222 ]]
[[ ! -e $BASE/started ]]
! grep -Eq '^(start|exec|pull) ' "$BASE/docker-calls"
python3 - "$BASE/run-args" <<'CHECK_PY'
import json,sys
args=json.loads(open(sys.argv[1]).read())
for pair in (['--network','none'],['--cap-drop','ALL'],['--security-opt','no-new-privileges:true'],['--pull','never']):
 assert any(args[i:i+2]==pair for i in range(len(args)))
assert '--read-only' in args and '--rm' in args
assert args[-2:]==['sha256:fixture','version']
assert '--volume' not in args and '-v' not in args and '--env' not in args
CHECK_PY
''')
        self.assert_ok(result)

    def test_diagnostics_default_does_not_call_stopped_node_running(self):
        result = self.run_shell(r'''
if detect_remnanode;then exit 90;else [[ $? == 3 ]];fi
[[ ! -e $BASE/started && ! -e $BASE/run-args ]]
''')
        self.assert_ok(result)

    def test_metadata_restore_discovery_does_not_require_any_core_probe(self):
        result = self.run_shell(r'''
detect_remnanode metadata
[[ $NODE_STOPPED == 1 && $NODE_NEW == 0 && $XRAY_VERSION == unknown ]]
[[ ! -e $BASE/started && ! -e $BASE/run-args ]]
! grep -Eq '^(start|exec|pull) ' "$BASE/docker-calls"
''')
        self.assert_ok(result)

    def test_restore_reaches_saved_service_recovery_without_core_execution(self):
        result = self.run_shell(r'''
BACKUP_INPUT=$BASE/backup;mkdir "$BACKUP_INPUT";printf '[]' > "$BACKUP_INPUT/files.json"
printf 'fixture backup\n' > "$BACKUP_INPUT/manifest.txt"
YES=1
detect_nginx(){ :; };detect_firewall(){ :; }
rollback(){
 [[ $1 == "$BACKUP_INPUT" && $SERVICES_APPLIED == 1 && $NODE_RECREATE == 1 && $NGINX_RECREATE == 1 ]]
 [[ ! -e $BASE/run-args && ! -e $BASE/started ]]
 echo RESTORE_REACHED
}
restore_backup
''')
        self.assertEqual(result.returncode, 8, result.stdout + result.stderr)
        self.assertIn('RESTORE_REACHED', result.stdout)

    def test_foreign_or_tampered_stopped_node_is_never_probed_or_started(self):
        changes = [
            'rm "$STATE"',
            'printf false > "$BASE/label"',
            'helper set "$STATE" node_new false',
            'helper set "$STATE" project \'"other"\'',
            'helper set "$STATE" node_container \'"other"\'',
            'helper set "$STATE" node_service \'"other"\'',
            'helper set "$STATE" workdir \'"/other"\'',
            'helper set "$STATE" node_image_id \'"sha256:other"\'',
            'helper set "$STATE" removed true',
            'chmod 644 "$STATE"',
            'rm "$OWN/owned-delta.json"',
            'printf "changed\\n" >> "$BASE/docker-compose.yml"',
        ]
        for change in changes:
            with self.subTest(change=change):
                result = self.run_shell(change + r'''
if detect_remnanode allow-stopped;then exit 90;else [[ $? == 3 ]];fi
[[ ! -e $BASE/started && ! -e $BASE/run-args ]]
''')
                self.assert_ok(result)

    def test_uid_probe_uses_same_isolation_and_actual_container_user(self):
        result = self.run_shell(r'''
detect_remnanode allow-stopped
[[ $(node_probe id -u) == 0 ]]
python3 - "$BASE/run-args" <<'CHECK_PY'
import json,sys
args=json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert args[-4:]==['--entrypoint','id','sha256:fixture','-u']
assert args[args.index('--user')+1]=='root'
assert args[args.index('--network')+1]=='none'
CHECK_PY
[[ ! -e $BASE/started ]]
''')
        self.assert_ok(result)

    def test_prepare_requires_completed_backup_and_transaction_before_start(self):
        for setup in ('TRANSACTION=0', 'TRANSACTION=1;BACKUP=$BASE/no-backup',
                      'TRANSACTION=1;BACKUP=$BASE/backup;mkdir "$BACKUP"'):
            with self.subTest(setup=setup):
                result = self.run_shell('detect_remnanode allow-stopped\n'+setup+r'''
(prepare_node);rc=$?
[[ $rc == 3 && ! -e $BASE/started ]]
'''.replace('(prepare_node);rc=$?', 'set +e\n(prepare_node);rc=$?\nset -e'))
                self.assert_ok(result)

    def test_prepare_starts_same_node_after_backup_and_port_check(self):
        result = self.run_shell(r'''
detect_remnanode allow-stopped
BACKUP=$BASE/backup;mkdir "$BACKUP";printf '[]' > "$BACKUP/files.json";TRANSACTION=1
save_state(){ :; }
prepare_node
[[ -e $BASE/started && $NODE_NEW == 0 && $NODE_STOPPED == 0 && $SERVICES_APPLIED == 1 && $NODE_RECREATE == 1 ]]
[[ $(grep -c '^start fixture$' "$BASE/docker-calls") == 1 ]]
! grep -Eq '^(compose up|pull) ' "$BASE/docker-calls"
''')
        self.assert_ok(result)

    def test_prepare_refuses_occupied_ports_or_changed_ownership(self):
        for change, listeners in [('','LISTEN 0 128 0.0.0.0:443'),
                                  ('helper set "$STATE" project \'"other"\'','')]:
            with self.subTest(change=change, listeners=listeners):
                result = self.run_shell(r'''
detect_remnanode allow-stopped
BACKUP=$BASE/backup;mkdir "$BACKUP";printf '[]' > "$BACKUP/files.json";TRANSACTION=1
''' + change + r'''
set +e
(prepare_node);rc=$?
set -e
[[ $rc == 3 && ! -e $BASE/started ]]
''', TEST_LISTENERS=listeners)
                self.assert_ok(result)

    def test_install_uses_stopped_aware_discovery_and_restore_requests_metadata(self):
        # Guard callers too: regressions otherwise silently restore the old
        # default-running discovery and again reject stopped-node recovery.
        install_plan = SOURCE.split('plan_install() {',1)[1].split('\n}\n',1)[0]
        restore = SOURCE.split('restore_backup() {',1)[1].split('\n}\n',1)[0]
        self.assertIn('detect_remnanode allow-stopped', install_plan)
        self.assertIn('node_probe id -u', install_plan)
        self.assertIn('detect_remnanode metadata', restore)
        self.assertIn('assert_stopped_node_ports_free', restore)


if __name__ == '__main__':
    unittest.main()
