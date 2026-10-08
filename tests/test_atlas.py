"""Atlas packaging and upgrade/rollback regressions; temporary files only."""
import base64
import hashlib
import io
import json
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch

import test_xhttp as xhttp
from test_xhttp import LIB, ROOT, SOURCE


class AtlasTests(unittest.TestCase):
    def test_embedded_site_matches_every_distributable_file(self):
        raw=SOURCE.split("<<'NUVRION_XHTTP_ARCHIVE'\n",1)[1].split('\nNUVRION_XHTTP_ARCHIVE',1)[0]
        with tarfile.open(fileobj=io.BytesIO(base64.b64decode(raw)),mode='r:gz') as tar:
            prefix='beer-atlas/public/'
            embedded={m.name[len(prefix):]:tar.extractfile(m).read() for m in tar if m.name.startswith(prefix)}
        files={p.relative_to(ROOT/'site/dist').as_posix():p.read_bytes()
               for p in (ROOT/'site/dist').rglob('*') if p.is_file()}
        self.assertEqual(embedded,files)
        self.assertIn('Атлас пива',embedded['index.html'].decode())
        self.assertEqual(len(json.loads(embedded['beers.json'])),96)
        self.assertFalse(any('pokemon' in name or 'habitat' in name for name in embedded))

    def test_upgrade_removes_obsolete_owned_files_and_rollback_restores_them(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);dest=root/'public';dest.mkdir();source=root/'new';source.mkdir()
            old={'index.html':b'old index','assets/old.js':b'old bundle'}
            for name,data in old.items():
                p=dest/name;p.parent.mkdir(exist_ok=True);p.write_bytes(data)
            foreign=dest/'foreign.txt';foreign.write_text('untouched')
            manifest=root/'manifest.json'
            manifest.write_text(json.dumps({name:hashlib.sha256(data).hexdigest() for name,data in old.items()}))
            folder=root/'backup';journal=root/'journal.json';selected=[str(dest),str(manifest)]
            with patch.dict(LIB,safe_backup=lambda p:Path(p)):
                LIB['snapshot'](folder,selected)
                (source/'index.html').write_text('Atlas index');(source/'beers.json').write_text('[]')
                xhttp.XhttpTests().invoke('assets',[str(source),str(dest),str(manifest)])
                self.assertFalse((dest/'assets/old.js').exists())
                self.assertEqual(foreign.read_text(),'untouched')
                LIB['snapshot_delta'](folder,journal)
                LIB['restore'](folder,selected,journal)
                for name,data in old.items():self.assertEqual((dest/name).read_bytes(),data)
                self.assertFalse((dest/'beers.json').exists())
                self.assertEqual(foreign.read_text(),'untouched')

    def test_modified_obsolete_asset_refuses_upgrade_before_writes(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);dest=root/'public';dest.mkdir();source=root/'new';source.mkdir()
            (dest/'index.html').write_text('old');(dest/'obsolete.js').write_text('user edit')
            manifest=root/'manifest.json';manifest.write_text(json.dumps({
                'index.html':hashlib.sha256(b'old').hexdigest(),
                'obsolete.js':hashlib.sha256(b'original').hexdigest()}))
            (source/'index.html').write_text('new')
            with self.assertRaises(ValueError):xhttp.XhttpTests().invoke('assets',[str(source),str(dest),str(manifest)])
            self.assertEqual((dest/'index.html').read_text(),'old')
            self.assertEqual((dest/'obsolete.js').read_text(),'user edit')

    def test_manifest_cannot_escape_the_public_root(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);manifest=root/'manifest.json';other=root/'other';other.write_text('untouched')
            for name in ['../other',str(other)]:
                manifest.write_text(json.dumps({name:hashlib.sha256(b'untouched').hexdigest()}))
                with self.assertRaises(ValueError):LIB['asset_collisions']([],root/'public',manifest)
            self.assertEqual(other.read_text(),'untouched')

    def test_repatching_old_managed_default_server_is_reversible(self):
        state={'domain':'node.example.org','xhttp_path':'/api/v3/sync/'}
        lineage='/cert';old=LIB['nginx_template'](state,lineage)
        # Simulate the former PokéHabitat default vhost without Atlas locations.
        start=old.index('    server {\n        listen unix:')
        before=old[:start]+'''    server {
        listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
        server_name _;
        ssl_certificate /cert/fullchain.pem;
        ssl_certificate_key /cert/privkey.pem;
        root /var/www/decoy;
        location / { try_files $uri $uri/ /index.html; }
    }
}
'''
        after,meta=LIB['nginx_patch'](before,state['domain'],state['xhttp_path'],lineage,state=state)
        again,_=LIB['nginx_patch'](after,state['domain'],state['xhttp_path'],lineage,meta,state)
        self.assertEqual(after,again)
        self.assertEqual(after.count('location = /app.mjs'),2)
        self.assertNotIn('proxy_pass http://unix:/run/nuvrion-pokehabitat',after)
        restored=LIB['strip_marked'](after)
        for old,new in meta['replacements']:restored=restored.replace(new,old,1)
        self.assertEqual([v for v,_,_ in LIB['tokens'](restored)],[v for v,_,_ in LIB['tokens'](before)])

    def test_new_compose_has_no_game_mount_and_legacy_mount_is_preserved(self):
        state=xhttp.XhttpTests().state()
        config={'services':{'remnanode':{'image':'node','network_mode':'host'},'nginx':{'image':'nginx','network_mode':'host'}}}
        overlay=LIB['compose_override'](state,config,{})
        self.assertNotIn('/run/nuvrion-pokehabitat',LIB['mounts'](overlay['services']['nginx']))
        old={'services':{'nginx':{'volumes':['/run/nuvrion-pokehabitat:/run/nuvrion-pokehabitat:ro']}}}
        overlay=LIB['compose_override'](state,config,old)
        self.assertIn('/run/nuvrion-pokehabitat',LIB['mounts'](overlay['services']['nginx']))

    def test_new_site_does_not_install_node_runtime_or_game_server(self):
        body=SOURCE.split('configure_site() {',1)[1].split('\ngame_socket() {',1)[0]
        self.assertNotIn('curl ',body)
        self.assertNotIn('useradd',body)
        self.assertNotIn('enable --now',body)
        self.assertIn('systemctl disable --now nuvrion-pokehabitat.service',body)
        self.assertNotIn('nodejs.org',SOURCE)

    def test_site_paths_are_reserved_for_xhttp(self):
        for path in ['/assets/product/','/vendor/engine/','/api/game/','/api/']:
            with self.assertRaises(ValueError):LIB['validate']('node.example.org','192.0.2.1','a@example.org','Node',path,'')
