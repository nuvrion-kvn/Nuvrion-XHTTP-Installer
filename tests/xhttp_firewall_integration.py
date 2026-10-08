#!/usr/bin/env python3
"""Real nft/iptables regression in a NEW network namespace only.

Run: unshare --net python3 tests/xhttp_firewall_integration.py
Must never be invoked in the host namespace; fail closed if it is unchanged.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import threading
from test_xhttp import LIB


def run(args,check=True,**kw):
    r=subprocess.run(args,capture_output=True,text=True,timeout=15,**kw)
    if check and r.returncode:raise RuntimeError(r.stderr)
    return r


def main():
    if os.readlink('/proc/self/ns/net')==os.readlink('/proc/1/ns/net'):
        raise SystemExit('REFUSED: create a new network namespace with unshare --net')
    run(['ip','link','set','lo','up'])
    seed='''table inet foreign {
 chain input { type filter hook input priority 0; policy drop; ct state established,related accept; }
}
table inet nuvrion_tc {
 chain input { type filter hook input priority -200; policy accept; ip saddr 127.0.0.2 tcp dport 443 drop; }
}
table inet nuvrion_privacy {
 chain input { type filter hook input priority -190; policy accept; }
}
'''
    run(['nft','-f','-'],input=seed)
    for iteration in range(2):
        before=json.loads(run(['nft','-a','-j','list','ruleset']).stdout)
        batch=LIB['nft_security_rules']('127.0.0.1',False,before)
        run(['nft','-c','-f','-'],input=batch);run(['nft','-f','-'],input=batch)
        state=json.loads(run(['nft','-a','-j','list','ruleset']).stdout)
        rules=[r['rule'] for r in state['nftables'] if 'rule' in r]
        assert len([r for r in rules if r.get('comment')=='Nuvrion-XHTTP'])==4
        assert len([r for r in rules if r['table']=='nuvrion_tc'])==1
        assert not any(r.get('comment')=='Nuvrion-XHTTP' and r['table'] in ('nuvrion_tc','nuvrion_privacy') for r in rules)
        print('[PASS] nft atomic repeat '+str(iteration+1)+'; no duplicates/foreign TC bypass',flush=True)
    servers=[]
    for family,address,port in [(socket.AF_INET,'127.0.0.1',2222),(socket.AF_INET6,'::1',2222),(socket.AF_INET,'127.0.0.1',443)]:
        server=socket.socket(family);server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        server.bind((address,port));server.listen(4);servers.append(server)
    def connect(family,source,dest,port):
        with socket.socket(family) as client:
            client.settimeout(.3);client.bind((source,0))
            try:client.connect((dest,port));return True
            except (TimeoutError,ConnectionError,OSError):return False
    assert connect(socket.AF_INET,'127.0.0.1','127.0.0.1',2222)
    assert not connect(socket.AF_INET,'127.0.0.2','127.0.0.1',2222)
    assert not connect(socket.AF_INET6,'::1','::1',2222)
    assert connect(socket.AF_INET,'127.0.0.1','127.0.0.1',443)
    assert not connect(socket.AF_INET,'127.0.0.2','127.0.0.1',443)
    print('[PASS] panel API allowed; foreign IPv4/IPv6 API blocked; HTTPS respects TC',flush=True)
    previous=run(['nft','-j','list','ruleset']).stdout
    assert run(['nft','-f','-'],input=batch+'invalid-command\n',check=False).returncode!=0
    assert previous==run(['nft','-j','list','ruleset']).stdout
    print('[PASS] injected invalid nft transaction leaves all old rules intact',flush=True)
    # iptables-restore --noflush must accept deletes in a batch. Each legacy
    # backend is checked here without touching any host table or policy.
    for binary in ('iptables','ip6tables'):
        restore=binary+'-restore'
        run([restore,'--noflush'],input='*filter\n:NUVRION_TEST - [0:0]\n-A NUVRION_TEST -p tcp --dport 2222 -j DROP\nCOMMIT\n')
        old=run([binary,'-S','NUVRION_TEST']).stdout
        delete='\n'.join('-D '+line[3:] for line in old.splitlines() if line.startswith('-A '))
        body='*filter\n'+delete+'\n-A NUVRION_TEST -p tcp --dport 2222 -j DROP\nCOMMIT\n'
        run([restore,'--test','--noflush'],input=body);run([restore,'--noflush'],input=body)
        assert run([binary,'-S','NUVRION_TEST']).stdout==old
        print('[PASS] '+restore+' atomic replacement without flush',flush=True)
    for server in servers:server.close()


if __name__=='__main__':main()
