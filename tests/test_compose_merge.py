"""Validate actual multi-file Compose merging without pulling or starting images."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import test_xhttp
LIB=test_xhttp.LIB


def compose_command():
    binary=os.environ.get('NUVRION_TEST_COMPOSE_BIN')
    if binary:
        return [binary]
    docker=shutil.which('docker')
    if docker and subprocess.run([docker,'compose','version'],capture_output=True).returncode==0:
        return [docker,'compose']
    binary=shutil.which('docker-compose')
    return [binary] if binary else None


COMPOSE=compose_command()


@unittest.skipUnless(COMPOSE,'Requires real Docker Compose; no Docker daemon needed')
class ComposeMergeTests(unittest.TestCase):
    def config(self, paths):
        command=COMPOSE+['-p','nuvrion-merge-test']
        for path in paths:
            command+=['-f',str(path)]
        result=subprocess.run(command+['config','--format','json'],text=True,capture_output=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        return json.loads(result.stdout)

    def test_initial_install_and_repeated_overlays_preserve_inherited_options(self):
        cases=[([],None),(['no-new-privileges:true'],None),
               (['no-new-privileges=true','apparmor=docker-default'],None),
               (['apparmor=docker-default'],{
                   'image':'nginx:1.30','network_mode':'host',
                   'security_opt':['no-new-privileges:true'],'cap_drop':['ALL'],
                   'cap_add':['CHOWN'],'tmpfs':['/custom:rw,size=1m']})]
        state={**test_xhttp.XhttpTests().state(),'secure_sockets':True,'docker_hardening':True,'nginx_new':True}
        for security,nginx in cases:
            with self.subTest(security=security,nginx=bool(nginx)),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);base=root/'base.json';overlay=root/'overlay.json'
                model={'services':{'remnanode':{
                    'image':'remnawave/node:3.4.1','network_mode':'host',
                    'security_opt':security,'environment':{'KEEP':'unchanged'}}}}
                if nginx:
                    model['services']['nginx']=nginx
                base.write_text(json.dumps(model))
                baseline=self.config([base]);before=copy.deepcopy(baseline);existing={};first=None
                for iteration in range(3):
                    value=LIB['compose_override'](state,before,existing,baseline)
                    # The raw overlay must never repeat inherited sequence entries.
                    for name,service in value['services'].items():
                        for field in ('security_opt','cap_add','cap_drop','tmpfs'):
                            inherited=baseline['services'].get(name,{}).get(field,[])
                            self.assertFalse(set(inherited)&set(service.get(field,[])),(name,field))
                    overlay.write_text(json.dumps(value))
                    after=self.config([base,overlay])
                    node=after['services']['remnanode'];web=after['services']['nginx']
                    self.assertEqual(node['environment'],{'KEEP':'unchanged'})
                    self.assertEqual(node['network_mode'],'host')
                    self.assertTrue(set(node['security_opt'])&{'no-new-privileges:true','no-new-privileges=true'})
                    if 'apparmor=docker-default' in security:
                        self.assertIn('apparmor=docker-default',node['security_opt'])
                    self.assertIn('no-new-privileges:true',web['security_opt'])
                    for capability in ('CHOWN','DAC_OVERRIDE','SETUID','SETGID'):
                        self.assertIn(capability,web['cap_add'])
                    self.assertIn('ALL',web['cap_drop'])
                    if nginx:
                        self.assertIn('/custom:rw,size=1m',web['tmpfs'])
                    for service in (node,web):
                        for field in ('security_opt','cap_add','cap_drop','tmpfs'):
                            values=service.get(field,[])
                            self.assertEqual(len(values),len(set(values)),field)
                    if iteration:
                        self.assertEqual(after,first)
                    else:
                        first=copy.deepcopy(after)
                    before=after;existing=value


if __name__=='__main__':
    unittest.main()
