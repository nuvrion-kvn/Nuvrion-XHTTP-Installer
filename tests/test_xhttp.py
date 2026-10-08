"""Exercise config transformations; never run an installer on the test host."""
import base64
import copy
import hashlib
import io
from pathlib import Path
import re
import tarfile
import contextlib
import json
import os
import sys
import time
import types
import tempfile
from unittest.mock import patch
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT/'nuvrion-xhttp-install.sh').read_text(encoding='utf-8')
HELPER = SOURCE.split("<<'NUVRION_PY'\n", 1)[1].split('\nNUVRION_PY\n', 1)[0]
LIB = {'__name__': 'test'}
exec(compile(HELPER, 'embedded-xhttp-helper', 'exec'), LIB)


class XhttpTests(unittest.TestCase):
    @unittest.skipIf(os.name=='nt', 'Unix symlink ownership test')
    def test_backup_preserves_owned_ntc_link_without_following_target(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);binary=root/'binary';shortcut=root/'ntc';folder=root/'backup'
            binary.write_text('binary unchanged');shortcut.symlink_to(binary)
            with patch.dict(LIB, safe_backup=lambda p:Path(p), SAFE_SNAPSHOT_LINKS={str(shortcut):str(binary)}):
                LIB['snapshot'](folder,[str(shortcut)])
                saved=folder/'files'/shortcut.relative_to('/')
                self.assertTrue(saved.is_symlink())
                shortcut.unlink();shortcut.write_text('replacement')
                LIB['restore'](folder,[str(shortcut)])
                self.assertTrue(shortcut.is_symlink())
                self.assertEqual(binary.read_text(),'binary unchanged')
                saved.unlink();saved.symlink_to(root/'foreign')
                with self.assertRaises(ValueError):LIB['restore'](folder,[str(shortcut)])
                self.assertEqual(os.readlink(shortcut),str(binary))

    @unittest.skipIf(os.name=='nt', 'Unix symlink ownership test')
    def test_backup_rejects_unrecognized_links_and_accepts_owned_dangling_link(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);shortcut=root/'ntc';target=root/'missing';folder=root/'backup'
            shortcut.symlink_to(target)
            with patch.dict(LIB,safe_backup=lambda p:Path(p)):
                with self.assertRaises(ValueError):LIB['snapshot'](folder,[str(shortcut)])
            folder.rmdir()
            with patch.dict(LIB,safe_backup=lambda p:Path(p),SAFE_SNAPSHOT_LINKS={str(shortcut):str(target)}):
                LIB['snapshot'](folder,[str(shortcut)])
                self.assertTrue(json.loads((folder/'files.json').read_text())[0]['exists'])
                shortcut.unlink();LIB['restore'](folder,[str(shortcut)])
                self.assertEqual(os.readlink(shortcut),str(target))

    def test_uninstall_preserves_mutable_boot_state_and_user_outputs(self):
        paths=['/var/lib/nuvrion-tuning','/var/lib/nuvrion-tuning/post-reboot-check.pending',
               '/etc/sysctl.d/99-nuvrion.conf','/usr/local/sbin/nuvrion-zram-setup.sh',
               '/root/nuvrion-xhttp-profile.json','/etc/letsencrypt',
               '/opt/remnanode/docker-compose.yml','/opt/remnanode/nuvrion-xhttp/state.json']
        selected=LIB['uninstall_selection']([{'path':p} for p in paths],
            '/opt/remnanode/nuvrion-xhttp','/opt/remnanode/docker-compose.yml','/opt/remnanode/nginx.conf')
        self.assertEqual(selected,['/etc/sysctl.d/99-nuvrion.conf','/usr/local/sbin/nuvrion-zram-setup.sh'])

    def state(self):
        return dict(domain='node.example.org', node_tag='Test Node', xhttp_path='/api/v3/sync/',
                    trusted_xff=True, node_service='remnanode', nginx_service='nginx',
                    nginx_kind='docker', nginx_new=False, node_image_id='sha256:node',
                    nginx_image_id='sha256:nginx', nginx_config='/opt/remnanode/nginx.conf',
                    site_root='/var/www/html')

    def test_profile_contains_both_transports_and_combined_extra(self):
        p, extra, hosts = LIB['profile'](self.state(), 'A'*43, 'B'*43)
        r, x = p['inbounds']
        self.assertEqual(r['streamSettings']['realitySettings']['target'], '/dev/shm/nginx.sock')
        self.assertEqual(r['streamSettings']['realitySettings']['xver'], 1)
        self.assertEqual(x['listen'], '/dev/shm/xrxh.socket,0666')
        settings = x['streamSettings']['xhttpSettings']
        self.assertEqual(set(settings), {'mode','path','extra'})
        self.assertEqual(settings['extra']['scMaxBufferedPosts'], 30)
        self.assertEqual(settings['extra']['scStreamUpServerSecs'], '20-80')
        self.assertEqual(settings['extra']['xmux'], extra['xmux'])
        self.assertEqual(x['streamSettings']['sockopt']['trustedXForwardedFor'], ['X-Forwarded-For'])
        self.assertEqual(len(p['routing']['rules']), 6)
        self.assertNotIn('A'*43, hosts)

    def test_profile_reinstall_preserves_keys_clients_and_foreign_routing(self):
        original, _, _ = LIB['profile'](self.state(), 'A'*43, 'B'*43)
        original['inbounds'][0]['settings']['clients'] = [{'id':'existing-reality-user'}]
        original['inbounds'][1]['settings']['clients'] = [{'id':'existing-xhttp-user'}]
        original['inbounds'].append({'tag':'foreign','port':1234,'protocol':'socks'})
        original['outbounds'].append({'tag':'foreign-out','protocol':'freedom'})
        updated, _, _ = LIB['profile'](self.state(), 'A'*43, 'B'*43, original)
        self.assertEqual(updated, original)
        with self.assertRaises(ValueError):
            LIB['profile'](self.state(), 'C'*43, 'B'*43, original)

    def test_nginx_patch_idempotent_preserves_decoy_and_unix_http(self):
        before = '''map $http_upgrade $connection_upgrade { default upgrade; "" close; }
server {
    server_name node.example.org;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;
    ssl_certificate /etc/nginx/ssl/old/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/old/privkey.pem;
    root /var/www/html;
    location / { try_files $uri $uri/ /index.html; }
}
'''
        first, meta = LIB['nginx_patch'](before, 'node.example.org', '/api/v3/sync/', '/etc/letsencrypt/live/node.example.org')
        second, _ = LIB['nginx_patch'](first, 'node.example.org', '/api/v3/sync/', '/etc/letsencrypt/live/node.example.org', meta)
        self.assertEqual(first, second)
        self.assertEqual(first.count('location ^~ /api/v3/sync/'), 1)
        self.assertIn('proxy_pass http://unix:/dev/shm/xrxh.socket;', first)
        self.assertIn('proxy_buffering off;', first)
        self.assertNotIn('grpc_pass', first)
        self.assertIn('location / { try_files $uri $uri/ /index.html; }', first)
        clean = LIB['strip_marked'](first)
        for old, new in meta['replacements']:
            clean = clean.replace(new, old, 1)
        self.assertEqual(LIB['tokens'](before), LIB['tokens'](clean)) if before == clean else self.assertEqual(
            [v for v,_,_ in LIB['tokens'](before)], [v for v,_,_ in LIB['tokens'](clean)])

    def test_nginx_new_map_and_conflict_rejection(self):
        before = 'http { server { server_name node.example.org; listen unix:/dev/shm/nginx.sock ssl proxy_protocol; root /web; } }\n'
        first, meta = LIB['nginx_patch'](before, 'node.example.org', '/api/v3/sync/', '/cert')
        second, _ = LIB['nginx_patch'](first, 'node.example.org', '/api/v3/sync/', '/cert', meta)
        self.assertEqual(first, second)
        self.assertEqual(first.count('map $http_upgrade'), 1)
        with self.assertRaises(ValueError):
            LIB['nginx_patch'](before.replace('root /web;', 'root /web; location /api/v3/sync/ { return 200; }'), 'node.example.org', '/api/v3/sync/', '/cert')

    def test_compose_existing_shm_options_and_other_fields_preserved(self):
        state = self.state()
        node = dict(image='remnawave/node:2.9.0',network_mode='host',
                    environment={'SECRET_KEY':'fixture-secret'},labels={'owner':'user'},
                    cap_add=['NET_ADMIN'],security_opt=['no-new-privileges:true'],
                    restart='always',healthcheck={'test':['CMD','true']},
                    logging={'driver':'json-file','options':{'max-size':'17m'}},
                    volumes=[{'type':'bind','source':'/dev/shm','target':'/dev/shm','bind':{'propagation':'rshared'}}])
        config = {'services':{'remnanode':node,'nginx':{'image':'nginx:1.30','network_mode':'host'},'foreign':{'image':'redis:7'}},'name':'project'}
        override = LIB['compose_override'](state, config, {})
        self.assertNotIn('volumes', override['services']['remnanode'])
        after = copy.deepcopy(config)
        for name, data in override['services'].items():
            after['services'][name].update(data)
        LIB['verify_compose'](config, after, state)
        after['services']['remnanode']['environment']['SECRET_KEY'] = 'changed'
        with self.assertRaises(ValueError): LIB['verify_compose'](config, after, state)

    def test_input_rejects_nginx_shell_injection(self):
        for path in ['/api/v3/sync/;return 200;', '/api/game/', '/../../', '/api$host/']:
            with self.assertRaises(ValueError):
                LIB['validate']('node.example.org', '192.0.2.1', 'user@example.org', 'Test', path, '')

    def test_embedded_payload_hash_and_safe_complete_site(self):
        if '# BEGIN EMBEDDED NUVRION XHTTP' not in SOURCE: self.skipTest('Build first')
        encoded = SOURCE.split("<<'NUVRION_XHTTP_ARCHIVE'\n",1)[1].split('\nNUVRION_XHTTP_ARCHIVE',1)[0]
        data = base64.b64decode(encoded)
        expected = re.search(r"payload_hash\(\) \{ printf '%s\\n' '([0-9a-f]{64})'",SOURCE)[1]
        self.assertEqual(hashlib.sha256(data).hexdigest(), expected)
        with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as tar:
            names = tar.getnames()
            self.assertIn('beer-atlas/public/index.html', names)
            self.assertIn('beer-atlas/public/beers.json', names)
            self.assertFalse(any(n.startswith('pokehabitat/') for n in names))
            self.assertIn('installer-manager.sh', names)
            self.assertIn('nuvrion-auto-tuning.sh', names)
            self.assertIn('nuvrion-traffic-control.py', names)
            self.assertIn('nuvrion-two-way-ping.sh', names)
            self.assertIn('nuvrion-two-way-ping.service', names)
            self.assertTrue(all(m.isfile() and not m.name.startswith('/') and '..' not in Path(m.name).parts for m in tar.getmembers()))

    def invoke(self, action, args=(), data=''):
        out=io.StringIO()
        with patch.object(sys,'argv',['helper',action,*args]), patch.object(sys,'stdin',io.StringIO(data)), contextlib.redirect_stdout(out):
            LIB['run']()
        return out.getvalue()

    def test_https_firewall_exception_does_not_bypass_scanner_filter(self):
        nft={'nftables':[{'chain':{'hook':'input','family':'inet','table':name,'name':'input'}}
                        for name in ['nuvrion_xhttp','nuvrion_tc','nuvrion_privacy','user_firewall']]}
        ordinary=self.invoke('nft-chains',['platform'],json.dumps(nft))
        self.assertIn('user_firewall',ordinary)
        self.assertNotIn('nuvrion_tc',ordinary)
        self.assertNotIn('nuvrion_privacy',ordinary)
        acme=self.invoke('nft-chains',data=json.dumps(nft))
        self.assertIn('nuvrion_tc',acme)

    @unittest.skipIf(os.name=='nt', 'Restore ownership uses Unix path semantics')
    def test_core_uninstall_does_not_restore_security_files_twice(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);folder=root/'backup';folder.mkdir()
            protected=root/'security.conf';ordinary=root/'ordinary.conf';ordinary.write_text('created')
            delta=root/'delta.json';delta.write_text(json.dumps({str(p):{'before':None,'after':hashlib.sha256(b'created').hexdigest()} for p in (protected,ordinary)}))
            # The security manifest already removed protected; the broad parent
            # selection must still restore the ordinary file without rejecting it.
            with patch.dict(LIB,safe_backup=lambda p:Path(p),SECURITY_PATHS=[str(protected)]):
                self.invoke('restore-delta',[str(folder),str(delta),'core'],json.dumps([str(root)]))
            self.assertFalse(protected.exists());self.assertFalse(ordinary.exists())

    def test_rollback_preserves_foreign_traffic_control_and_privacy(self):
        with tempfile.TemporaryDirectory() as td:
            records=Path(td)/'records.json';owned=Path(td)/'owned.json'
            records.write_text(json.dumps([{'path':p} for p in LIB['SECURITY_PATHS']+
                ['/var/lib/nuvrion-traffic-control','/etc/letsencrypt','/etc/sysctl.d/custom.conf']]))
            owned.write_text('{"traffic_owned":false,"privacy_owned":false}')
            selected=json.loads(self.invoke('rollback-selection',[str(records),str(owned)]))
            self.assertNotIn('/var/lib/nuvrion-traffic-control',selected)
            self.assertNotIn('/usr/local/bin/ntc',selected)
            self.assertNotIn('/usr/local/sbin/nuvrion-two-way-ping.sh',selected)
            self.assertIn('/etc/sysctl.d/custom.conf',selected)


@unittest.skipIf(os.name=='nt','Traffic Control uses Linux fcntl')
class EmbeddedTrafficTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        raw=SOURCE.split("<<'NUVRION_XHTTP_ARCHIVE'\n",1)[1].split('\nNUVRION_XHTTP_ARCHIVE',1)[0]
        with tarfile.open(fileobj=io.BytesIO(base64.b64decode(raw)),mode='r:gz') as tar:
            code=tar.extractfile('nuvrion-traffic-control.py').read().decode()
        cls.module=types.ModuleType('embedded_traffic_test')
        cls.module.__file__=str(ROOT/'vendor/nuvrion-traffic-control-xhttp.py')
        exec(compile(code,'embedded-traffic-control','exec'),cls.module.__dict__)

    def state(self):
        return {'schema':1,'ssh_ports':[22],'allow':['192.0.2.1','192.0.2.2'],
                'manual':['203.0.113.4/32'],'lists':{name:['198.51.100.0/24'] for name in self.module.SOURCES},
                'updated':100,'logging':True}

    def test_ipv4_ipv6_filter_keeps_ssh_and_panel_exemptions_before_drops(self):
        text=self.module.render(self.module.validate_state(self.state()))
        self.assertLess(text.index('tcp dport { 22 } return'),text.index('saddr @block4'))
        self.assertLess(text.index('saddr @allow4 return'),text.index('saddr @block4'))
        self.assertIn('saddr @block6',text)
        self.assertNotIn('Nuvrion-XHTTP-ACME',text)

    def test_acme_lease_survives_updater_but_expired_lease_cannot_open_80(self):
        module=self.module;real_path=Path
        with tempfile.TemporaryDirectory() as td:
            lease=Path(td)/'lease';lease.write_text(str(time.time()));lease.chmod(0o600)
            def paths(name):return lease if str(name)=='/run/nuvrion-xhttp-acme-open' else real_path(name)
            rules=[]
            with patch.object(module,'Path',side_effect=paths), patch.object(module,'present',return_value=True), patch.object(module,'run',side_effect=lambda *a,**k: rules.append(k['data'])):
                module.apply(self.state())
                self.assertIn('tcp dport 80 return comment "Nuvrion-XHTTP-ACME"',rules[-1])
                lease.write_text(str(time.time()-1201));module.apply(self.state())
                self.assertNotIn('Nuvrion-XHTTP-ACME',rules[-1])
                lease.unlink();module.apply(self.state())
                self.assertNotIn('Nuvrion-XHTTP-ACME',rules[-1])

    def test_combined_manual_lists_cannot_block_entire_address_family(self):
        state=self.state();state['lists']={n:['0.0.0.0/1'] for n in self.module.SOURCES}
        state['manual']=['128.0.0.0/1']
        with self.assertRaises(ValueError):self.module.validate_state(state)


if __name__ == '__main__': unittest.main()
