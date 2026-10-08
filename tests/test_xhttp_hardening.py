"""Security regressions for the XHTTP installer; no host configuration writes."""
import copy
import json
import os
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import test_xhttp
LIB, SOURCE = test_xhttp.LIB, test_xhttp.SOURCE


class HardeningTests(unittest.TestCase):
    def state(self):
        return {**test_xhttp.XhttpTests().state(), 'secure_sockets': True,
                'padding_supported': True, 'docker_hardening': True, 'nginx_new': True}

    def test_api_port_persists_without_secret_in_saved_state(self):
        with tempfile.TemporaryDirectory() as td:
            state=Path(td)/'state.json'
            env={'DOMAIN':'node.example.org','PANEL_IP':'192.0.2.10','NODE_PORT':'3222',
                 'NGINX_NEW':'1','FILES_JSON':'[]','NODE_IMAGE_ID':'fixed',
                 'NGINX_IMAGE_ID':'fixed-nginx','BACKUP':'/root/backup','FW':'nft',
                 'TRUSTED_XFF':'1','NODE_SECRET':'A'*80}
            with patch.dict(LIB,STATE=state),patch.dict(os.environ,env),patch.object(sys,'argv',['helper','state']):
                LIB['run']()
            saved=json.loads(state.read_text())
            self.assertEqual(saved['node_port'],'3222')
            self.assertEqual(saved['panel_ip'],'192.0.2.10')
            self.assertNotIn('A'*80,state.read_text())

    def test_nft_guard_validates_api_port_and_preserves_foreign_rules(self):
        original={'nftables':[{'rule':{'comment':'foreign','family':'inet','table':'keep','chain':'input','handle':123}}]}
        before=copy.deepcopy(original)
        for panel in ('192.0.2.10','2001:db8::10'):
            rules=LIB['nft_security_rules'](panel,False,original,3222)
            self.assertIn('tcp dport 3222 drop',rules)
            self.assertIn('saddr '+panel+' tcp dport 3222 accept',rules)
            self.assertNotIn('handle 123',rules)
            self.assertNotIn('2222',rules)
        for port in (0,80,443,65536,'invalid'):
            with self.assertRaises(ValueError):LIB['nft_security_rules']('192.0.2.10',False,original,port)
        self.assertEqual(before,original)

    def test_padding_gate_is_exact_not_a_speculative_version_comparison(self):
        for version, supported in [('Xray 26.7.28 (Xray, Penetrates Everything.)', True),
                                   ('Xray 26.3.27', False), ('Xray 26.9.1', False), ('unknown', False)]:
            self.assertEqual(LIB['padding_supported'](version), supported)

    def test_new_profile_cookie_padding_dns_and_secure_socket_paths(self):
        profile, extra, _ = LIB['profile'](self.state(), 'A'*43, 'B'*43)
        self.assertTrue(all(s == 'PASS' for s, _ in LIB['profile_checks'](profile, True)))
        reality, xhttp = profile['inbounds']
        self.assertEqual(reality['streamSettings']['realitySettings']['target'], '/dev/shm/nuvrion-xhttp/nginx.sock')
        self.assertEqual(xhttp['listen'], '/dev/shm/nuvrion-xhttp/xrxh.socket,0660')
        for key, value in LIB['padding_extra']().items():
            self.assertEqual(xhttp['streamSettings']['xhttpSettings']['extra'][key], value)
            self.assertEqual(extra[key], value)
        self.assertNotIn('nextdns', str(profile).lower())

    def test_import_preserves_custom_extra_and_existing_dns(self):
        state = test_xhttp.XhttpTests().state()
        original, _, _ = LIB['profile'](state, 'A'*43, 'B'*43)
        original['dns']['servers'] = [{'address':'https+local://dns.nextdns.io/example'}]
        original['inbounds'][1]['streamSettings']['xhttpSettings']['extra']['extension'] = {'custom':123}
        original['inbounds'][1]['streamSettings']['xhttpSettings']['extra']['xmux']['maxConcurrency'] = '8-16'
        updated, extra, _ = LIB['profile'](state, 'A'*43, 'B'*43, original)
        self.assertEqual(updated, original)
        self.assertEqual(extra['xmux']['maxConcurrency'], '8-16')

    def test_explicit_migration_keeps_keys_users_routing_and_custom_extra(self):
        original, _, _ = LIB['profile'](test_xhttp.XhttpTests().state(), 'A'*43, 'B'*43)
        original['inbounds'][0]['settings']['clients'] = [{'id':'fixture-only','flow':'xtls-rprx-vision'}]
        original['inbounds'][1]['streamSettings']['xhttpSettings']['extra']['extension'] = 'kept'
        before = copy.deepcopy(original)
        updated, _, _ = LIB['profile']({**self.state(), 'harden_profile': True}, 'A'*43, 'B'*43, original)
        self.assertEqual(original, before)
        self.assertEqual(updated['routing'], before['routing'])
        self.assertEqual(updated['inbounds'][0]['settings'], before['inbounds'][0]['settings'])
        self.assertEqual(updated['inbounds'][0]['streamSettings']['realitySettings']['privateKey'], 'A'*43)
        self.assertEqual(updated['inbounds'][1]['streamSettings']['xhttpSettings']['extra']['extension'], 'kept')
        repeated, _, _ = LIB['profile']({**self.state(), 'harden_profile': True}, 'A'*43, 'B'*43, updated)
        self.assertEqual(updated, repeated)

    def test_unsupported_padding_migration_fails_without_modifying_input(self):
        original, _, _ = LIB['profile'](test_xhttp.XhttpTests().state(), 'A'*43, 'B'*43)
        before = copy.deepcopy(original)
        with self.assertRaises(ValueError):
            LIB['profile']({**self.state(), 'harden_profile':True, 'padding_supported':False}, 'A'*43, 'B'*43, original)
        self.assertEqual(original, before)

    def test_nginx_default_and_routes_are_repeatable_with_sni_and_host_guards(self):
        state = self.state();lineage = '/etc/letsencrypt/live/node.example.org'
        template = LIB['nginx_template'](state, lineage)
        text, meta = LIB['nginx_patch'](template, state['domain'], state['xhttp_path'], lineage, state=state)
        repeated, _ = LIB['nginx_patch'](text, state['domain'], state['xhttp_path'], lineage, meta, state)
        self.assertEqual(text, repeated)
        self.assertNotIn('ssl_reject_handshake', text)
        self.assertNotIn('grpc_pass', text)
        self.assertEqual(text.count('default_server'), 1)
        self.assertEqual(text.count('if ($ssl_server_name != "node.example.org")'), 1)
        self.assertEqual(text.count('if ($host != "node.example.org")'), 1)
        self.assertNotIn('proxy_hide_header', text)

    def test_old_owned_default_vhost_migrates_idempotently(self):
        state = self.state();legacy = {**state, 'secure_sockets':False};lineage = '/etc/letsencrypt/live/node.example.org'
        template = LIB['nginx_template'](legacy, lineage)
        default = LIB['default_server'](state['domain'], lineage, '/var/www/decoy', '/dev/shm/nginx.sock')
        old = '    server {\n        listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;\n        server_name _;\n        ssl_reject_handshake on;\n        return 444;\n    }'
        template = template.replace(default, old)
        text, meta = LIB['nginx_patch'](template, state['domain'], state['xhttp_path'], lineage, state=state)
        self.assertNotIn('unix:/dev/shm/nginx.sock', text)
        repeated, _ = LIB['nginx_patch'](text, state['domain'], state['xhttp_path'], lineage, meta, state)
        self.assertEqual(text, repeated)

    def test_compose_hardening_preserves_node_image_and_environment(self):
        state = self.state()
        before = {'services':{'remnanode':{'network_mode':'host', 'image':'fixed',
                  'environment':{'KEEP':'value'},'security_opt':['apparmor=docker-default'],
                  'pids_limit':2048, 'cap_add':['NET_ADMIN']}}}
        override = LIB['compose_override'](state, before, {})
        node = override['services']['remnanode'];nginx = override['services']['nginx']
        self.assertEqual(node['pids_limit'], 2048)
        self.assertEqual(node['security_opt'], ['no-new-privileges:true'])
        self.assertNotIn('cap_drop', node)
        self.assertTrue(nginx['read_only'])
        self.assertEqual(nginx['cap_drop'], ['ALL'])
        self.assertNotIn('NET_ADMIN', nginx['cap_add'])
        after = copy.deepcopy(before)
        after['services']['remnanode'].update(node)
        after['services']['remnanode']['security_opt']=before['services']['remnanode']['security_opt']+node['security_opt']
        after['services']['nginx'] = nginx
        LIB['verify_compose'](before, after, state)
        self.assertEqual(before['services']['remnanode']['environment'], {'KEEP':'value'})

    @unittest.skipIf(os.name == 'nt' or os.geteuid() != 0, 'Linux ownership test')
    def test_protected_directory_survives_recreation_and_refuses_foreign_permissions(self):
        with tempfile.TemporaryDirectory() as td:
            # Some managed user namespaces expose UID 0 but cannot map GID 33.
            # Keep the real ownership test on normal Ubuntu/CI; do not pretend
            # a mocked chown verifies filesystem permissions.
            probe=Path(td)/'ownership-probe';probe.touch()
            try:os.chown(probe,0,33)
            except OSError as error:
                if error.errno in (1,22):self.skipTest('Current user namespace cannot map root:www-data ownership')
                raise
            p = Path(td)/'sockets';LIB['secure_directory'](p, 33)
            LIB['secure_directory'](p, 33)
            self.assertEqual(p.stat().st_mode & 0o7777, 0o2710)
            os.chmod(p, 0o777)
            with self.assertRaises(ValueError):LIB['secure_directory'](p, 33)

    @unittest.skipIf(os.name == 'nt', 'Linux restore test')
    def test_old_backup_cannot_restore_or_delete_ssh_files(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td);folder = root/'backup';target = root/'ssh-config';target.write_text('current')
            with patch.dict(LIB, safe_backup=lambda p:Path(p)):
                LIB['snapshot'](folder, [str(target)])
                target.write_text('current changed')
                with patch.dict(LIB, immutable_path=lambda p: str(p)==str(target)):
                    LIB['restore'](folder, [str(target)])
                self.assertEqual(target.read_text(), 'current changed')

    def test_entrypoints_reject_node_replacement_and_ssh_changes(self):
        self.assertIn('NUVRION_HARDEN_SSH=0', SOURCE)
        self.assertNotIn('systemctl reload ssh.service', SOURCE)
        self.assertNotIn('MaxAuthTries 3', SOURCE)
        self.assertIn('NODE_VERSION=keep;SELECTED_IMAGE=', SOURCE)
        self.assertIn('Выбор образа допустим только при первой установке', SOURCE)
        self.assertNotIn('| head -n 1', SOURCE.split('# BEGIN EMBEDDED NUVRION XHTTP')[0])

    def test_custom_nginx_capabilities_command_and_tmpfs_are_not_overwritten(self):
        state=self.state()
        for custom in [{'cap_add':['NET_ADMIN']},{'command':['my-custom-start']},
                       {'tmpfs':['/var/run:rw,size=2m']}]:
            before={'services':{'remnanode':{'network_mode':'host'},'nginx':custom}}
            preserved=copy.deepcopy(before)
            with self.assertRaises(ValueError):LIB['compose_override'](state,before,{})
            self.assertEqual(before,preserved)
        before={'services':{'remnanode':{'network_mode':'host'},'nginx':{'tmpfs':['/custom:rw,size=1m']}}}
        after=LIB['compose_override'](state,before,{})
        self.assertNotIn('/custom:rw,size=1m',after['services']['nginx']['tmpfs'])

    def test_compose_preserves_escaped_shell_variables_on_reinstall(self):
        state=self.state();before={'services':{'remnanode':{'network_mode':'host'}}}
        overlay=LIB['compose_override'](state,before,{})
        self.assertIn('$$p',overlay['services']['nginx']['command'][2])
        config=copy.deepcopy(before);config['services']['nginx']=copy.deepcopy(overlay['services']['nginx'])
        repeated=LIB['compose_override'](state,config,overlay,before)
        self.assertEqual(overlay,repeated)


if __name__ == '__main__':
    unittest.main()
