#!/usr/bin/env python3
"""Isolated Linux/Docker integration using ONLY already installed images.

No production mounts/config writes, no image pulls, no installed binary changes.
Run on the authorized test VPS, from a temporary checkout. Never pass secrets
as arguments. Temporary credentials/configs have root-only permissions.
"""
import argparse
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import json
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import sys
import tarfile
import tempfile
import time
import threading
import uuid
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tests'))
from test_xhttp import LIB


def run(args, *, check=True, timeout=45, **kw):
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout, **kw)
    if check and r.returncode:
        # Never reproduce arguments/config/env or unsanitized logs containing secrets.
        raise RuntimeError(f'{args[0]} failed, exit={r.returncode}: '+r.stderr[-400:])
    return r


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0));return s.getsockname()[1]


def wait_for(predicate, seconds=20):
    until=time.monotonic()+seconds
    while time.monotonic()<until:
        if predicate():return
        time.sleep(.1)
    raise RuntimeError('Readiness deadline exceeded')


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--node-container', default='remnanode')
    ap.add_argument('--nginx-container', default='remnanode-nuvrion-xhttp-nginx-1')
    ap.add_argument('--domain', required=True)
    args=ap.parse_args()
    if os.geteuid()!=0:raise SystemExit('Requires root on the authorized test system')
    old=json.loads(run(['docker','inspect',args.node_container,args.nginx_container]).stdout)
    baseline=[(c['Id'],c['Image'],c['State']['StartedAt']) for c in old]
    binary_hash=run(['docker','exec',args.node_container,'sha256sum','/usr/local/bin/rw-core']).stdout.split()[0]
    results=[];containers=[];clients=[]
    def record(name, ok, evidence=''):
        results.append({'test':name,'status':'PASS' if ok else 'FAIL','evidence':evidence})
        print(f'[{results[-1]["status"]}] {name} {evidence}',flush=True)
        if not ok:raise AssertionError(name)
    def write(path,data):
        path.write_text(json.dumps(data) if isinstance(data,dict) else data);path.chmod(0o600)
    with tempfile.TemporaryDirectory(prefix='nuvrion-security-isolated.') as td:
        work=Path(td);shm=work/'shm';shm.mkdir();shm.chmod(0o1777)
        private=shm/'nuvrion-xhttp';LIB['secure_directory'](private,33)
        source=(ROOT/'nuvrion-xhttp-install.sh').read_text()
        raw=source.split("<<'NUVRION_XHTTP_ARCHIVE'\n",1)[1].split('\nNUVRION_XHTTP_ARCHIVE',1)[0]
        site=work/'site';site.mkdir();site.chmod(0o755)
        with tarfile.open(fileobj=io.BytesIO(base64.b64decode(raw)),mode='r:gz') as archive:
            for member in archive.getmembers():
                if not member.name.startswith('pokehabitat/public/'):continue
                relative=Path(member.name.removeprefix('pokehabitat/public/'))
                if relative.is_absolute() or '..' in relative.parts:raise ValueError('Unsafe archive')
                dest=site/relative;dest.parent.mkdir(parents=True,exist_ok=True)
                for p in [dest.parent,*dest.parent.parents]:
                    if p==work:break
                    p.chmod(0o755)
                dest.write_bytes(archive.extractfile(member).read());dest.chmod(0o644)
        token=uuid.uuid4().hex[:12]
        node_image,nginx_image=[c['Image'] for c in old]
        state={'domain':args.domain,'node_tag':'Isolated','xhttp_path':'/api/v3/sync/',
               'trusted_xff':True,'secure_sockets':True,'padding_supported':True,
               'docker_hardening':True,'node_service':'node','nginx_service':'nginx',
               'nginx_kind':'docker','nginx_new':True,'node_image_id':node_image,
               'nginx_image_id':nginx_image,'nginx_config':str(work/'nginx.conf'),'site_root':str(site)}
        lineage='/etc/letsencrypt/live/'+args.domain
        ng_text=LIB['nginx_template'](state,lineage)
        ng_text,_=LIB['nginx_patch'](ng_text,args.domain,state['xhttp_path'],lineage,state=state)
        write(work/'nginx.conf',ng_text)
        overlay=LIB['compose_override'](state,{'services':{'node':{'image':node_image,'network_mode':'host'}}},{})
        ng=overlay['services']['nginx'];ng_name='nuvrion-isolated-nginx-'+token
        server_name='nuvrion-isolated-xray-'+token
        ngsock=private/'nginx.sock';xhsock=private/'xrxh.socket'
        # Compose config deliberately retains escaped dollars. Check the actual
        # container command after create, then start ONLY this isolated service.
        ng.update({'container_name':ng_name,'network_mode':'none','volumes':[]})
        for src,dest,ro in [(work/'nginx.conf','/etc/nginx/nginx.conf',True),(site,'/var/www/decoy',True),
                            (shm,'/dev/shm',False),('/etc/letsencrypt','/etc/letsencrypt',True),
                            ('/run/nuvrion-pokehabitat','/run/nuvrion-pokehabitat',True)]:
            ng['volumes'].append({'type':'bind','source':str(src),'target':dest,'read_only':ro})
        write(work/'compose.json',{'services':{'nginx':ng}})
        compose=['docker','compose','-p','nuvrion-isolated-'+token,'-f',str(work/'compose.json')]
        try:
            containers.append(ng_name);run(compose+['create','--pull','never','nginx'])
            actual=json.loads(run(['docker','inspect',ng_name]).stdout)[0]['Config']['Cmd'][2]
            record('Compose shell variable preservation','$p' in actual and '$$p' not in actual)
            run(['docker','start',ng_name])
            wait_for(lambda:ngsock.is_socket())
            wait_for(lambda:ngsock.stat().st_mode & 0o777 == 0o600)
            record('nginx config',run(['docker','exec',ng_name,'nginx','-t']).returncode==0)
            key_output=run(['docker','run','--rm','--pull','never','--network','none','--entrypoint','/usr/local/bin/rw-core',node_image,'x25519']).stdout
            private_key=re.search(r'Private\s*Key:\s*(\S+)',key_output,re.I)[1]
            public_key=re.search(r'(?:Public\s*Key|Password(?: \(PublicKey\))?):\s*(\S+)',key_output,re.I)[1]
            profile,extra,_=LIB['profile'](state,private_key,public_key)
            user_id=str(uuid.uuid4());port=free_port()
            for inbound in profile['inbounds']:inbound['settings']['clients']=[{'id':user_id,**({'flow':'xtls-rprx-vision'} if inbound['tag']=='Isolated' else {})}]
            profile['inbounds'][0].update({'port':port,'listen':'127.0.0.1'})
            profile['log']={'loglevel':'info','access':'/work/access.log'}
            write(work/'server.json',profile)
            server_cmd=['docker','run','-d','--pull','never','--name',server_name,'--network','host',
                        '--entrypoint','/usr/local/bin/rw-core','--security-opt','no-new-privileges:true',
                        '--cap-drop','ALL','--pids-limit','1024','--read-only','-v',str(work)+':/work:rw',
                        '-v',str(shm)+':/dev/shm:rw',node_image,'run','-format','json','-config','/work/server.json']
            containers.append(server_name);run(server_cmd)
            wait_for(lambda:xhsock.is_socket())
            record('socket permissions', ngsock.stat().st_mode & 0o777==0o600 and xhsock.stat().st_mode & 0o777==0o660,
                   'nginx 0600; XHTTP 0660')
            record('socket GID',ngsock.stat().st_gid==33 and xhsock.stat().st_gid==33,'shared GID 33 via setgid directory')

            def request(sni,host,path='/',version=None,method='GET',through_xray=False):
                context=ssl.create_default_context();context.check_hostname=False
                if version:context.minimum_version=context.maximum_version=version
                if through_xray:sock=socket.create_connection(('127.0.0.1',port),timeout=10)
                else:
                    sock=socket.socket(socket.AF_UNIX);sock.settimeout(10);sock.connect(str(ngsock))
                    sock.sendall(b'PROXY TCP4 203.0.113.9 127.0.0.1 50000 443\r\n')
                with context.wrap_socket(sock,server_hostname=sni) as conn:
                    # Inspect wrong/no SNI, but still require a trusted chain and
                    # verify this is the existing DOMAIN certificate, never claim
                    # the SAN validates the intentionally wrong hostname.
                    names=[name.lower() for kind,name in conn.getpeercert().get('subjectAltName',[]) if kind=='DNS']
                    assert any(name==args.domain or name.startswith('*.') and args.domain.partition('.')[2]==name[2:] for name in names)
                    conn.sendall((f'{method} {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n').encode())
                    response=b''
                    while True:
                        chunk=conn.recv(65536)
                        if not chunk:break
                        response+=chunk
                    return response.decode(errors='replace')
            for name,sni,host in [('correct SNI',args.domain,args.domain),('wrong SNI','wrong.invalid','wrong.invalid'),
                                  ('no SNI',None,args.domain),('direct IP',None,'45.198.0.253')]:
                response=request(sni,host)
                record(name,' 200 ' in response.splitlines()[0] and '<!doctype html' in response.lower())
                response=request(sni,host,through_xray=True)
                record(name+' through Reality fallback',' 200 ' in response.splitlines()[0] and '<!doctype html' in response.lower())
            for version in [ssl.TLSVersion.TLSv1_2,ssl.TLSVersion.TLSv1_3]:
                record(version.name,' 200 ' in request(args.domain,args.domain,version=version).splitlines()[0])
            for sni,host in [('wrong.invalid',args.domain),(None,args.domain),(args.domain,'wrong.invalid')]:
                for path in ['/api/v3/sync/','/api/game/me','/api/nodes']:
                    record('unknown/mismatched SNI API '+path,' 404 ' in request(sni,host,path).splitlines()[0])
            for method in ['GET','POST','OPTIONS']:
                response=request(args.domain,args.domain,'/api/v3/sync/',method=method)
                record(method+' cookie padding','set-cookie: site_session=' in response.lower() and 'x-padding:' not in response.lower()
                       and not any(' '+str(code)+' ' in response.splitlines()[0] for code in (502,504)))
            h2=run(['curl','--noproxy','*','--http2','--haproxy-protocol','--unix-socket',str(ngsock),
                    '--max-time','15','-sS','-o','/dev/null','-w','%{http_code} %{http_version}','https://'+args.domain+'/']).stdout
            record('HTTP/2',h2=='200 2',h2)
            h2_full=run(['curl','--noproxy','*','--http2','--resolve',args.domain+':'+str(port)+':127.0.0.1',
                        '--max-time','15','-sS','-o','/dev/null','-w','%{http_code} %{http_version}',
                        'https://'+args.domain+':'+str(port)+'/']).stdout
            record('HTTP/2 through Reality fallback',h2_full=='200 2',h2_full)
            denied_code='import socket,sys;s=socket.socket(socket.AF_UNIX);s.connect(sys.argv[1])'
            for sock in [ngsock,xhsock]:
                denied=run(['setpriv','--reuid=65534','--regid=65534','--clear-groups','python3','-c',denied_code,str(sock)],check=False)
                record('foreign local UID denied '+sock.name,denied.returncode!=0 and 'PermissionError' in denied.stderr)
            record('Game API',' 200 ' in request(args.domain,args.domain,'/api/game/me').splitlines()[0])

            # Exercise the actual Node/s6 entrypoint, not just the Xray binary.
            # Same secret is read in memory and written only to a temporary 0600
            # env file; it never enters command arguments/logs/reports. Network
            # none prevents any contact with the panel or other containers.
            secret=next(v.split('=',1)[1] for v in old[0]['Config']['Env'] if v.startswith('SECRET_KEY='))
            write(work/'node.env','SECRET_KEY='+secret+'\nNODE_PORT=2222\n');del secret
            full_node='nuvrion-isolated-node-'+token;containers.append(full_node)
            run(['docker','run','-d','--pull','never','--network','none','--name',full_node,
                 '--security-opt','no-new-privileges:true','--pids-limit','1024',
                 '--env-file',str(work/'node.env'),node_image])
            def api_ready():
                probe=run(['docker','exec',full_node,'sh','-c',"grep -q ':08AE ' /proc/net/tcp /proc/net/tcp6"],check=False)
                return probe.returncode==0
            wait_for(api_ready,30)
            record('Remnanode/s6 NNP compatibility',api_ready(),'isolated Node API :2222')
            (work/'node.env').unlink()

            # Real DoH responses, not availability of a TCP socket alone.
            dns_query=bytes.fromhex('6e7501000001000000000000')+b'\x07example\x03com\x00'+bytes.fromhex('00010001')
            for provider in ('dns.adguard-dns.com','dns.comss.one'):
                req=urllib.request.Request('https://'+provider+'/dns-query',data=dns_query,
                        headers={'Content-Type':'application/dns-message','Accept':'application/dns-message'})
                with urllib.request.urlopen(req,timeout=15) as response:answer=response.read()
                record(provider+' DoH',len(answer)>12 and answer[3] & 15==0 and int.from_bytes(answer[6:8],'big')>0)

            # Two real Xray clients, simultaneously, with both flows preserved.
            socks_ports={}
            for transport in ['reality','xhttp']:
                cname='nuvrion-isolated-client-'+transport+'-'+token;socks_ports[transport]=free_port()
                stream=({'network':'raw','security':'reality','realitySettings':{'serverName':args.domain,'fingerprint':'firefox','publicKey':public_key,'shortId':''}}
                        if transport=='reality' else {'network':'xhttp','security':'tls','tlsSettings':{'serverName':args.domain,'fingerprint':'firefox','alpn':['h2','http/1.1']},
                                                     'xhttpSettings':{'mode':'auto','path':'/api/v3/sync/','extra':extra}})
                config={'log':{'loglevel':'warning'},'inbounds':[{'listen':'127.0.0.1','port':socks_ports[transport],'protocol':'socks','settings':{'auth':'noauth','udp':True}}],
                        'outbounds':[{'protocol':'vless','settings':{'vnext':[{'address':'127.0.0.1','port':port,'users':[{'id':user_id,'encryption':'none',**({'flow':'xtls-rprx-vision'} if transport=='reality' else {})}]}]},'streamSettings':stream}]}
                write(work/(transport+'.json'),config)
                containers.append(cname);clients.append(cname)
                run(['docker','run','-d','--pull','never','--name',cname,'--network','host','--entrypoint','/usr/local/bin/rw-core',
                     '--security-opt','no-new-privileges:true','--cap-drop','ALL','--read-only','--pids-limit','512',
                     '-v',str(work)+':/work:ro',node_image,'run','-format','json','-config','/work/'+transport+'.json'])
            time.sleep(1)
            for attempt in range(3):
                for transport,socks_port in socks_ports.items():
                    r=run(['curl','--proxy','socks5h://127.0.0.1:'+str(socks_port),'--max-time','30','-sS',
                           '-o',str(work/'body.txt'),'-w','%{http_code} %{size_download} %{time_total}','https://'+args.domain+'/'])
                    record(transport+' authorized connection '+str(attempt+1),r.stdout.startswith('200 '),r.stdout)
                    record(transport+' HTML','<!doctype html' in (work/'body.txt').read_text().lower())
                    dns=run(['curl','--proxy','socks5h://127.0.0.1:'+str(socks_port),'--max-time','30','-sS','-o','/dev/null','-w','%{http_code}','https://example.com/']).stdout
                    record(transport+' remote DNS/data',dns=='200')
            access=(work/'access.log').read_text()
            record('XHTTP real IP forwarded',any('Isolated XHTTP' in line and '127.0.0.1' in line for line in access.splitlines()),'backend access log: original client IP, not Unix placeholder')
            # A private IP behind an otherwise public-looking DNS name must
            # not bypass geoip:private at the outbound resolution stage.
            class PrivateProbe(BaseHTTPRequestHandler):
                count=0
                def do_GET(self):
                    type(self).count+=1;self.send_response(200);self.end_headers();self.wfile.write(b'isolated-private-probe')
                def log_message(self,*_):pass
            probe=HTTPServer(('127.0.0.1',0),PrivateProbe)
            threading.Thread(target=probe.serve_forever,daemon=True).start()
            dns_socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);dns_socket.bind(('127.0.0.1',0));dns_socket.settimeout(.2)
            dns_stopped=threading.Event()
            dns_replies=[]
            def private_dns():
                while not dns_stopped.is_set():
                    try:query,peer=dns_socket.recvfrom(4096)
                    except TimeoutError:continue
                    except OSError:return
                    # Echo the question; compressed answer name points to QNAME.
                    end=12
                    while query[end]:end+=1+query[end]
                    end+=5  # QNAME terminator + QTYPE + QCLASS; exclude EDNS OPT.
                    answer=query[:2]+bytes.fromhex('81800001000100000000')+query[12:end]+bytes.fromhex('c00c000100010000001e0004')+socket.inet_aton('127.0.0.1')
                    dns_socket.sendto(answer,peer)
                    dns_replies.append(1)
            threading.Thread(target=private_dns,daemon=True).start()
            saved_dns=json.loads(json.dumps(profile['dns']));saved_routing=json.loads(json.dumps(profile['routing']))
            saved_freedom=json.loads(json.dumps(profile['outbounds'][0]['settings']))
            try:
                profile['dns']['servers'].insert(0,{'address':'127.0.0.1','port':dns_socket.getsockname()[1],
                    'domains':['full:nuvrion-private-probe.cloudflare.com'],'queryStrategy':'UseIPv4','skipFallback':True})
                profile['routing']['domainStrategy']='AsIs'
                write(work/'server.json',profile);run(['docker','restart',server_name]);wait_for(lambda:xhsock.is_socket());time.sleep(.5)
                probe_url='http://nuvrion-private-probe.cloudflare.com:'+str(probe.server_port)+'/'
                direct_probe=run(['curl','--noproxy','*','--max-time','5','-sS','-o','/dev/null','-w','%{http_code}',
                                  'http://127.0.0.1:'+str(probe.server_port)+'/'])
                record('private probe control',direct_probe.stdout=='200')
                baseline_count=PrivateProbe.count
                baseline_probe=run(['curl','--proxy','socks5h://127.0.0.1:'+str(socks_ports['reality']),'--max-time','10',
                                    '-sS','-o','/dev/null','-w','%{http_code}',probe_url],check=False)
                print('[AUDIT] routing AsIs private DNS probe HTTP='+baseline_probe.stdout+' DNS replies='+str(len(dns_replies))+' '+baseline_probe.stderr[:160],flush=True)
                baseline_blocked=baseline_probe.returncode!=0 and PrivateProbe.count==baseline_count
                profile['routing']['rules']=[]
                # Xray 26.7.28 freedom has a built-in final private-IP block for
                # VLESS, even without routing rules. Permit ONLY the local probe
                # IP/port in this isolated control, then remove the exception.
                profile['outbounds'][0]['settings']['finalRules']=[{'action':'allow','network':'tcp',
                    'ip':['127.0.0.1/32'],'port':str(probe.server_port)}]
                write(work/'server.json',profile);run(['docker','restart',server_name]);wait_for(lambda:xhsock.is_socket());time.sleep(.5)
                control=run(['curl','--proxy','socks5h://127.0.0.1:'+str(socks_ports['reality']),'--max-time','10',
                             '-sS','-o','/dev/null','-w','%{http_code}',probe_url],check=False)
                record('private DNS control with isolated finalRules exception',control.stdout=='200')
                record('AsIs private DNS destination blocked by current Xray final guard',baseline_blocked,
                       'default VLESS freedom final private block; control HTTP=200; no production exception')
                profile['outbounds'][0]['settings']=json.loads(json.dumps(saved_freedom))
                profile['routing']=json.loads(json.dumps(saved_routing))
                profile['routing']['domainStrategy']='IPIfNonMatch'
                write(work/'server.json',profile);run(['docker','restart',server_name]);wait_for(lambda:xhsock.is_socket());time.sleep(.5)
                count=PrivateProbe.count
                blocked=run(['curl','--proxy','socks5h://127.0.0.1:'+str(socks_ports['reality']),'--max-time','10',
                            '-sS','-o','/dev/null','-w','%{http_code}',probe_url],check=False)
                if control.stdout=='200':
                    record('private IP via DNS blocked in isolated IPIfNonMatch candidate',blocked.returncode!=0 and PrivateProbe.count==count,
                           'AsIs HTTP='+baseline_probe.stdout+'; no-rules control HTTP=200')
            finally:
                profile['dns']=saved_dns;profile['routing']=saved_routing
                profile['outbounds'][0]['settings']=saved_freedom
                probe.shutdown();probe.server_close();dns_stopped.set();dns_socket.close()
            # Fault injection: an unreachable primary DoH, fresh Xray DNS cache.
            original_dns=json.loads(json.dumps(profile['dns']))
            profile['dns']['servers'][0]['address']='https+local://127.0.0.1:'+str(free_port())+'/dns-query'
            write(work/'server.json',profile);run(['docker','restart',server_name]);wait_for(lambda:xhsock.is_socket());time.sleep(.5)
            fallback=run(['curl','--proxy','socks5h://127.0.0.1:'+str(socks_ports['xhttp']),'--max-time','30',
                          '-sS','-L','-o','/dev/null','-w','%{http_code}','https://www.iana.org/']).stdout
            record('real DNS fallback to COMSS',fallback=='200')
            profile['dns']=original_dns;write(work/'server.json',profile)
            for cname in [server_name,ng_name]:
                run(['docker','restart',cname])  # ONLY these newly created isolated resources
                wait_for(lambda:(xhsock if cname==server_name else ngsock).is_socket())
            wait_for(lambda:ngsock.stat().st_mode & 0o777==0o600)
            record('socket recreation permissions',ngsock.stat().st_mode & 0o777==0o600 and xhsock.stat().st_mode & 0o777==0o660)
            record('site after restart',' 200 ' in request(args.domain,args.domain).splitlines()[0])
            # Invalid configuration must never be reloaded. Restore original
            # inode, validate, then reload the isolated Nginx alone.
            saved=(work/'nginx.conf').read_text()
            (work/'nginx.conf').write_text(saved+'\ninvalid_directive;\n')
            record('invalid nginx config rejected',run(['docker','exec',ng_name,'nginx','-t'],check=False).returncode!=0)
            record('old nginx config remains running',' 200 ' in request(args.domain,args.domain).splitlines()[0])
            (work/'nginx.conf').write_text(saved)
            run(['docker','exec',ng_name,'nginx','-t']);run(['docker','exec',ng_name,'nginx','-s','reload'])
            record('nginx backup rollback',' 200 ' in request(args.domain,args.domain).splitlines()[0])
            inspection=json.loads(run(['docker','inspect',ng_name,server_name]).stdout)
            for c in inspection:
                h=c['HostConfig'];name=c['Name']
                record(name+' hardening',not h['Privileged'] and h['ReadonlyRootfs'] and h['PidsLimit']>0
                       and any('no-new-privileges' in v for v in h['SecurityOpt']) and h['CapDrop']==['ALL'] and c['AppArmorProfile']=='docker-default')
            logs=run(['docker','logs',ng_name]).stderr+run(['docker','logs',server_name]).stderr
            record('no socket/502/504 errors',not re.search(r'permission denied|failed to listen|address already in use|connect\(\).*failed|invalid config',logs,re.I))
        finally:
            for cname in reversed(containers):
                run(['docker','stop','-t','5',cname],check=False)
                run(['docker','rm',cname],check=False)
            now=json.loads(run(['docker','inspect',args.node_container,args.nginx_container]).stdout)
            record('existing containers untouched',baseline==[(c['Id'],c['Image'],c['State']['StartedAt']) for c in now])
            record('Xray binary unchanged',binary_hash==run(['docker','exec',args.node_container,'sha256sum','/usr/local/bin/rw-core']).stdout.split()[0])
    print(json.dumps({'results':results,'temporary_resources_removed':True},ensure_ascii=False),flush=True)


if __name__=='__main__':main()
