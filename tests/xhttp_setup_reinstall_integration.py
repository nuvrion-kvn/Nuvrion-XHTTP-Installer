#!/usr/bin/env python3
"""Explicitly authorized reinstall of an ALREADY managed Linux test node.

Unlike isolated fixtures this test applies the installer to the selected node.
Requires --allow-test-reinstall and a matching saved domain. Never run from CI.
No panel access, new users, credential rotation, image changes or reboot.
"""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile

ROOT=Path(__file__).resolve().parents[1]
OWN=Path('/opt/remnanode/nuvrion-xhttp')


def command(args,timeout=30):
    result=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
    if result.returncode:raise RuntimeError(args[0]+' failed: exit='+str(result.returncode))
    return result.stdout


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--domain',required=True)
    parser.add_argument('--allow-test-reinstall',action='store_true')
    args=parser.parse_args()
    if not args.allow_test_reinstall or os.geteuid()!=0:
        raise SystemExit('Requires root and explicit --allow-test-reinstall')
    state=json.loads((OWN/'state.json').read_text())
    assert state['domain']==args.domain and not state.get('removed')
    node=state['node_container'];nginx=state['nginx_container']
    info=json.loads(command(['docker','inspect',node]))[0]
    secret=next(v.split('=',1)[1] for v in info['Config']['Env'] if v.startswith('SECRET_KEY='))
    api_port=next(v.split('=',1)[1] for v in info['Config']['Env'] if v.startswith('NODE_PORT='))
    paths=[Path('/root/nuvrion-xhttp-profile.json'),
           *[Path(p) for p in state['compose_files'] if p!='/opt/remnanode/docker-compose.nuvrion-xhttp.json'],
           *[p for p in Path('/etc/ssh').rglob('*') if p.is_file() and not p.is_symlink()]]
    def baseline():
        containers=json.loads(command(['docker','inspect',node,nginx]))
        return ([tuple(c[k] for k in ('Id','Image'))+(c['State']['StartedAt'],) for c in containers],
                command(['docker','exec',node,'sha256sum','/usr/local/bin/rw-core']).split()[0],
                {str(p):digest(p) for p in paths})
    before=baseline();state_before=digest(OWN/'state.json')
    installer=ROOT/'nuvrion-xhttp-install.sh'
    rejected=subprocess.run(['bash',str(installer),'--reinstall','--yes','--no-updates',
                             '--domain','dns.google'],capture_output=True,text=True,timeout=180)
    assert rejected.returncode==4,'DNS mismatch must abort'
    assert 'Установка отменена' in rejected.stderr
    assert secret not in rejected.stdout+rejected.stderr,'Secret disclosure'
    assert before==baseline() and state_before==digest(OWN/'state.json')
    print('[PASS] real DNS mismatch aborted before changes; existing node/SSH/profile preserved',flush=True)
    installed=subprocess.run(['bash',str(installer),'--reinstall','--yes','--no-updates'],
                             capture_output=True,text=True,timeout=900)
    assert secret not in installed.stdout+installed.stderr,'Secret disclosure'
    if installed.returncode:
        # Do not reproduce full diagnostics or environment on failure.
        raise RuntimeError('Reinstall failed: exit='+str(installed.returncode)+'; inspect root-only installer log')
    assert 'Статус: RUNNING' in installed.stdout
    assert 'ошибок: 0; ожидают профиля: 0' in installed.stdout
    assert 'Decoy: HTTP 200' in installed.stdout and 'XHTTP route: HTTP 400' in installed.stdout
    assert before==baseline(),'Container/image/SSH/profile changed'
    state=json.loads((OWN/'state.json').read_text())
    assert state['node_port']==api_port and state['panel_ip']
    source=installer.read_text()
    encoded=source.split("<<'NUVRION_XHTTP_ARCHIVE'\n",1)[1].split('\nNUVRION_XHTTP_ARCHIVE',1)[0]
    with tarfile.open(fileobj=io.BytesIO(base64.b64decode(encoded)),mode='r:gz') as archive:
        assert archive.extractfile('installer-manager.sh').read()==(OWN/'installer.sh').read_bytes()
    report={'status':'RUNNING','decoy':200,'xhttp_backend':400,'api_port':api_port,
            'backup':state['last_backup'],'manager_matches_release':True,
            'containers_images_xray_ssh_profile_preserved':True}
    print('[PASS] complete reinstall: '+json.dumps(report,ensure_ascii=False),flush=True)


if __name__=='__main__':main()
