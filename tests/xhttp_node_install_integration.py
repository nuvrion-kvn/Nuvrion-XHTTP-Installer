#!/usr/bin/env python3
"""Exercise first-install Node startup without touching an installed Node.

Run as root on the authorized Linux test server. Uses actual official images
and the installer's prepare_node. The generated Compose is checked first,
then its network, name and writable mounts are confined to a private fixture.
No host ports, production sockets, live config writes or panel mutations.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run(args, *, redact=(), **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, timeout=300, **kwargs)
    if result.returncode:
        # Docker inspect and env files can contain credentials: never print output.
        detail=result.stderr[-1000:]
        for value in redact:detail=detail.replace(value,'[redacted]')
        raise RuntimeError(f'{args[0]} failed, exit={result.returncode}: {detail}')
    return result.stdout


def baseline(node):
    c = json.loads(run(['docker', 'inspect', node]))[0]
    return (c['Id'], c['Image'], c['State']['StartedAt'],
            run(['docker', 'exec', node, 'sha256sum', '/usr/local/bin/rw-core']).split()[0])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--node-container', default='remnanode')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Requires root on the authorized test server')
    before = baseline(args.node_container)
    live = json.loads(run(['docker', 'inspect', args.node_container]))[0]
    secret = next(v.split('=', 1)[1] for v in live['Config']['Env'] if v.startswith('SECRET_KEY='))
    source = (ROOT / 'nuvrion-xhttp-install.sh').read_text().split('# BEGIN EMBEDDED NUVRION XHTTP')[0]
    for version,api_port in [('latest',2222),('3.4.2',3222)]:
        name = 'nuvrion-first-install-' + uuid.uuid4().hex[:12]
        with tempfile.TemporaryDirectory(prefix='nuvrion-node-first-install.') as td:
            work = Path(td)
            fixture = source.replace('/opt/remnanode', td + '/remnanode')
            fixture = fixture.replace('readonly LOG=/var/log/nuvrion-xhttp-installer.log', 'readonly LOG=' + td + '/installer.log')
            fixture = fixture.replace('command install -d -m 755 /var/log/remnanode', 'command install -d -m 755 "$BASE/logs"')
            secret_file = work / 'input-secret'
            secret_file.write_text(secret)
            secret_file.chmod(0o600)
            # Keep the helper's real implementation; confine only the Docker
            # service AFTER checking the unmodified fresh-install template.
            driver = r'''
NODE_NEW=1;YES=1;NODE_VERSION=$TEST_VERSION
NODE_PORT=$TEST_NODE_PORT;validate_node_port
NODE_CONTAINER=$TEST_CONTAINER;NODE_SERVICE=remnanode;NGINX_NEW=0
SECURE_SOCKETS=1;SECRET_FILE=$TEST_SECRET
command install -d -m 700 "$OWN" "$BASE/private-shm" "$BASE/logs"
eval "$(declare -f helper | sed '1s/helper/helper_original/')"
helper(){
    helper_original "$@" || return
    if [[ $1 == fresh-compose ]];then
        python3 - "$2" "$NODE_CONTAINER" "$BASE" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);d=json.loads(p.read_text());s=d['services']['remnanode']
assert s['network_mode']=='host' and s['container_name']=='remnanode'
assert s['image'].startswith('sha256:')
assert s['security_opt']==['no-new-privileges:true'] and s['pids_limit']==1024
assert s['labels']['io.nuvrion.xhttp.installed']=='true'
assert any(v['source']=='/dev/shm' and v['target']=='/dev/shm' for v in s['volumes'])
assert s['env_file']==[sys.argv[3]+'/nuvrion-xhttp/node.env']
s['network_mode']='none';s['container_name']=sys.argv[2]
s['volumes']=[{'type':'bind','source':sys.argv[3]+'/private-shm','target':'/dev/shm'},
              {'type':'bind','source':sys.argv[3]+'/logs','target':'/var/log/remnanode'}]
p.write_text(json.dumps(d));p.chmod(0o600)
PY
    fi
}
state_value(){ :; }
save_state(){ printf '{}' > "$STATE"; }
choose_node_version;collect_node_secret
COMPOSE_CMD=(docker compose -p "$NODE_CONTAINER" -f "$BASE/docker-compose.yml")
prepare_node
test "$(stat -c %a "$OWN/node.env")" = 600
test "$(stat -c %a "$BASE/docker-compose.yml")" = 600
docker exec "$NODE_CONTAINER" sh -c 'grep -q "NoNewPrivs:.*1" /proc/1/status'
api_ready=0
api_hex=$(printf '%04X' "$NODE_PORT")
for attempt in {1..30};do
    if docker exec "$NODE_CONTAINER" sh -c 'awk -v port="$1" '\''$2 ~ (":" port "$") && $4 == "0A" {found=1} END {exit !found}'\'' /proc/net/tcp /proc/net/tcp6' sh "$api_hex";then api_ready=1;break;fi
    sleep 1
done
[[ $api_ready == 1 ]]
grep -q "^NODE_PORT=$NODE_PORT$" "$OWN/node.env"
printf 'FIRST_INSTALL_PASS version=%s\n' "$NODE_VERSION"
'''
            try:
                output = run(['bash'], input=fixture + '\n' + driver,redact=(secret,),
                             env={**os.environ, 'TEST_VERSION': version,
                                  'TEST_CONTAINER': name, 'TEST_SECRET': str(secret_file),'TEST_NODE_PORT':str(api_port)})
                if secret in output:
                    raise AssertionError('Secret appeared in installer output')
                created = json.loads(run(['docker', 'inspect', name]))[0]
                assert created['State']['Running'] and created['HostConfig']['NetworkMode'] == 'none'
                assert created['Config']['Image'].startswith('sha256:')
                assert not created['HostConfig']['Privileged']
                assert not created['HostConfig'].get('PortBindings')
                print(f'[PASS] first-install {version}: real Node/API :{api_port}, pinned image, NNP, root-only credentials, private network', flush=True)
            finally:
                subprocess.run(['docker', 'rm', '-f', name], capture_output=True, timeout=30)
        assert before == baseline(args.node_container), 'Installed Node changed'
    print('[PASS] installed Node container/image/start time/Xray hash preserved', flush=True)


if __name__ == '__main__':
    main()
