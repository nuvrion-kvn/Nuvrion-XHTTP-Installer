"""Real isolated nginx TLS/PROXY-protocol checks. No host services or ports.

Set NUVRION_NGINX_BIN to an nginx >=1.25 binary, or NUVRION_NGINX_DOCKER
to the official image (CI uses nginx:1.30). Every socket/file is temporary.
"""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
import uuid

from test_xhttp import LIB, ROOT

BIN=os.environ.get('NUVRION_NGINX_BIN')
IMAGE=os.environ.get('NUVRION_NGINX_DOCKER')


@unittest.skipUnless(BIN or IMAGE,'Set NUVRION_NGINX_BIN or NUVRION_NGINX_DOCKER for real nginx checks')
class AtlasNginxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='atlas-nginx-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work=Path(cls.temp.name);cls.site=cls.work/'site'
        shutil.copytree(ROOT/'site/dist',cls.site)
        (cls.site/'assets/.hidden').write_text('must not be served')
        cls.domain='node.example.org';certs=cls.work/'certs';certs.mkdir()
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
                        '-keyout',str(certs/'privkey.pem'),'-out',str(certs/'fullchain.pem'),
                        '-subj','/CN='+cls.domain,'-addext','subjectAltName=DNS:'+cls.domain],
                       check=True,capture_output=True,timeout=20)
        cls.sock=cls.work/'nginx.sock';backend=cls.work/'backend.sock';cls.forwarded=[]
        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                lines=[]
                while True:
                    line=self.rfile.readline()
                    if not line or line==b'\r\n':break
                    lines.append(line)
                cls.forwarded.append(b''.join(lines).decode())
                self.wfile.write(b'HTTP/1.1 400 Bad Request\r\nSet-Cookie: site_session=test\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
        state={'domain':cls.domain,'xhttp_path':'/api/v3/sync/'}
        text=LIB['nginx_template'](state,str(certs))
        text,_=LIB['nginx_patch'](text,cls.domain,state['xhttp_path'],str(certs),state=state)
        # The empty inherited MIME table verifies compatibility with custom nginx.
        (cls.work/'mime.types').write_text('types {}\n')
        text=text.replace('user www-data;','user root;').replace('worker_processes auto;','worker_processes 1;')
        text=text.replace('/etc/nginx/mime.types',str(cls.work/'mime.types'))
        text=text.replace('/var/run/nginx.pid',str(cls.work/'nginx.pid'))
        text=text.replace('/dev/shm/nginx.sock',str(cls.sock)).replace('/dev/shm/xrxh.socket',str(backend))
        text=text.replace('/var/www/decoy',str(cls.site))
        text=text.replace('error_log /dev/stderr warn;',f'error_log {cls.work}/runtime-error.log warn;')
        temps=''.join('\n    '+kind+'_temp_path '+str(cls.work/kind)+';' for kind in ['client_body','proxy','fastcgi','uwsgi','scgi'])
        text=text.replace('access_log off;','access_log off;'+temps)
        config=cls.work/'nginx.conf';config.write_text(text)
        base=['-p',str(cls.work)+'/', '-c',str(config),'-e',str(cls.work/'error.log')]
        if IMAGE:
            cls.container='atlas-nginx-'+uuid.uuid4().hex[:12]
            docker=['docker','run','--rm','--network','none','--user',str(os.getuid())+':'+str(os.getgid()),'-v',str(cls.work)+':'+str(cls.work), '--entrypoint','nginx']
            command=docker+['--name',cls.container,IMAGE]
            validate=docker+[IMAGE]
            cls.addClassCleanup(lambda:subprocess.run(['docker','rm','-f',cls.container],capture_output=True,timeout=20))
        else:command=validate=[BIN]
        checked=subprocess.run(validate+base+['-t'],capture_output=True,text=True,timeout=30)
        if checked.returncode:
            if 'syntax is ok' in checked.stderr and 'socket()' in checked.stderr and 'Operation not permitted' in checked.stderr:
                raise unittest.SkipTest('nginx syntax is valid; current sandbox forbids socket creation')
            raise AssertionError(checked.stdout+checked.stderr)
        try:server=socketserver.UnixStreamServer(str(backend),Handler)
        except PermissionError as error:raise unittest.SkipTest('Current sandbox forbids Unix sockets; nginx -t already passed') from error
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        cls.addClassCleanup(server.server_close);cls.addClassCleanup(server.shutdown)
        cls.process=subprocess.Popen(command+base+['-g','daemon off;'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        def stop():
            if cls.process.poll() is None:cls.process.terminate()
            try:cls.process.wait(timeout=10)
            except subprocess.TimeoutExpired:cls.process.kill();cls.process.wait(timeout=5)
        cls.addClassCleanup(stop)
        deadline=time.monotonic()+20
        while time.monotonic()<deadline and not cls.sock.exists() and cls.process.poll() is None:time.sleep(.05)
        if not cls.sock.exists():raise AssertionError((cls.work/'error.log').read_text(errors='replace'))
        cls.context=ssl.create_default_context(cafile=str(certs/'fullchain.pem'));cls.context.check_hostname=False

    @classmethod
    def request(cls,path,sni='node.example.org',host='node.example.org',version=None):
        context=cls.context
        if version:
            context=ssl.create_default_context(cafile=str(cls.work/'certs/fullchain.pem'))
            context.check_hostname=False;context.minimum_version=context.maximum_version=version
        with socket.socket(socket.AF_UNIX) as sock:
            sock.settimeout(8);sock.connect(str(cls.sock))
            sock.sendall(b'PROXY TCP4 192.0.2.44 127.0.0.1 51515 443\r\n')
            with context.wrap_socket(sock,server_hostname=sni) as tls:
                tls.sendall(f'GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n'.encode())
                chunks=[]
                while True:
                    chunk=tls.recv(65536)
                    if not chunk:break
                    chunks.append(chunk)
        head,body=b''.join(chunks).split(b'\r\n\r\n',1)
        lines=head.decode().split('\r\n');status=int(lines[0].split()[1])
        headers={key.lower():value.strip() for key,value in (line.split(':',1) for line in lines[1:])}
        return status,headers,body

    def test_all_runtime_assets_are_served_intact_with_correct_mime_and_revalidation(self):
        types={'.html':'text/html','.mjs':'text/javascript','.js':'text/javascript','.css':'text/css',
               '.json':'application/json','.webp':'image/webp','.jpg':'image/jpeg','.jpeg':'image/jpeg',
               '.png':'image/png','.gif':'image/gif','.ico':'image/x-icon','.woff2':'font/woff2','.woff':'font/woff','.svg':'image/svg+xml'}
        tested=set()
        for file in sorted((ROOT/'site/dist').rglob('*')):
            if not file.is_file() or file.suffix not in types:continue
            path='/'+file.relative_to(ROOT/'site/dist').as_posix()
            with self.subTest(path=path):
                status,headers,body=self.request(path)
                self.assertEqual(status,200)
                self.assertEqual(headers['content-type'].split(';')[0],types[file.suffix])
                self.assertEqual(headers['cache-control'],'no-cache')
                self.assertEqual(headers['x-content-type-options'],'nosniff')
                self.assertEqual(hashlib.sha256(body).digest(),hashlib.sha256(file.read_bytes()).digest())
            tested.add(path)
        beers=json.loads((ROOT/'site/dist/beers.json').read_text())
        required={'/'+beer['image'].lstrip('/') for beer in beers}
        html=(ROOT/'site/dist/index.html').read_text()
        required.update(re.findall(r'(?:href|src)="(/(?!/)[^"?#]+)"',html))
        css=(ROOT/'site/dist/style.css').read_text()
        required.update('/'+match for match in re.findall(r'url\([\"\']?/?(assets/[^)\"\']+)',css))
        required.add('/vendor/topolines-0.3.0.js')
        self.assertFalse(required-tested,'Runtime references not checked: '+str(required-tested))
        print(f'Verified {len(tested)} runtime files, including every catalogue image and local HTML/CSS reference',flush=True)
        self.assertEqual(len(json.loads(self.request('/beers.json')[2])),96)

    def test_default_vhost_tls_versions_missing_assets_and_hidden_files(self):
        for sni,host in [(self.domain,self.domain),('wrong.invalid','wrong.invalid'),(None,self.domain),(None,'127.0.0.1')]:
            with self.subTest(sni=sni,host=host):
                self.assertEqual(self.request('/',sni,host)[0],200)
                self.assertIn('Атлас пива',self.request('/',sni,host)[2].decode())
                self.assertEqual(self.request('/app.mjs',sni,host)[1]['content-type'],'text/javascript')
                self.assertEqual(self.request('/api/game/me',sni,host)[0],404)
        for version in [ssl.TLSVersion.TLSv1_2,ssl.TLSVersion.TLSv1_3]:
            self.assertEqual(self.request('/',version=version)[0],200)
        for path in ['/assets/missing.webp','/vendor/missing.js','/missing.mjs','/assets/.hidden','/no-route']:
            self.assertEqual(self.request(path)[0],404,path)

    def test_xhttp_route_keeps_host_guards_and_forwarded_proxy_protocol_address(self):
        path='/api/v3/sync/'
        for sni,host in [('wrong.invalid',self.domain),(None,self.domain),(self.domain,'wrong.invalid')]:
            self.assertEqual(self.request(path,sni,host)[0],404)
        status,headers,_=self.request(path)
        self.assertEqual(status,400)
        self.assertIn('site_session=',headers['set-cookie'])
        self.assertIn('X-Real-IP: 192.0.2.44',self.forwarded[-1])
        self.assertIn('X-Forwarded-For: 192.0.2.44',self.forwarded[-1])
