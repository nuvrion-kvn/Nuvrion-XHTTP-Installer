"""Regression cases from the independent audit; never modify host services."""
import hashlib
import contextlib
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
import types
import sys
from unittest.mock import patch

import test_xhttp
import test_xhttp_shell

LIB = test_xhttp.LIB


class SecurityAuditTests(unittest.TestCase):
    def test_iptables_reapply_promotes_existing_jump_without_deleting_foreign_accept(self):
        result=test_xhttp_shell.XhttpShellTests().run_shell(r'''
FW=iptables;PANEL_IP=192.0.2.10;NODE_PORT=3222
state_value(){ :; }
iptables(){
 case " $* " in
  *' -S INPUT '*) printf '%s\n' '-P INPUT ACCEPT' '-A INPUT -p tcp --dport 3222 -j ACCEPT' '-A INPUT -j NUVRION_XHTTP';;
  *' -S NUVRION_XHTTP '*) printf '%s\n' '-N NUVRION_XHTTP' '-A NUVRION_XHTTP -p tcp --dport 3222 -j DROP';;
  *) return 1;;
 esac
}
ip6tables(){ iptables "$@"; }
iptables-restore(){ cat; };ip6tables-restore(){ cat; }
configure_firewall
''')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.count('-D INPUT -j NUVRION_XHTTP'),4)
        self.assertEqual(result.stdout.count('-I INPUT 1 -j NUVRION_XHTTP'),4)
        self.assertNotIn('-D INPUT -p tcp --dport 3222 -j ACCEPT',result.stdout)

    def test_inactive_ufw_fails_before_any_rule_changes(self):
        result=test_xhttp_shell.XhttpShellTests().run_shell(r'''
FW=ufw;PANEL_IP=192.0.2.10;NODE_PORT=3222
state_value(){ :; }
ufw(){ if [[ $1 == status ]];then printf 'Status: inactive\n';else echo MUST_NOT_CHANGE;fi; }
configure_firewall
''')
        self.assertEqual(result.returncode,7,result.stderr)
        self.assertNotIn('MUST_NOT_CHANGE',result.stdout)
        self.assertIn('UFW выключен',result.stderr)

    def test_iptables_checker_rejects_unhooked_late_duplicate_and_modified_chain(self):
        good='''-P INPUT ACCEPT
-A INPUT -j NUVRION_XHTTP
-A INPUT -p tcp -m tcp --dport 3222 -j ACCEPT
-A NUVRION_XHTTP -s 192.0.2.10/32 -p tcp -m tcp --dport 3222 -j ACCEPT
-A NUVRION_XHTTP -p tcp -m tcp --dport 3222 -j DROP
-A NUVRION_XHTTP -p tcp -m tcp --dport 443 -j ACCEPT
'''
        # iptables -S reorders -s ahead of -p; compare option semantics.
        LIB['check_iptables_guard']('192.0.2.10',3222,4,False,good)
        bad=[good.replace('-A INPUT -j NUVRION_XHTTP\n',''),
             good.replace('-P INPUT ACCEPT\n','-P INPUT ACCEPT\n-A INPUT -j ACCEPT\n'),
             good.replace('-P INPUT ACCEPT\n','-P INPUT ACCEPT\n-A INPUT -j NUVRION_XHTTP\n'),
             good.replace('-A NUVRION_XHTTP -p tcp -m tcp --dport 3222 -j DROP',
                          '-A NUVRION_XHTTP -j ACCEPT\n-A NUVRION_XHTTP -p tcp -m tcp --dport 3222 -j DROP')]
        for text in bad:
            with self.assertRaises(ValueError):LIB['check_iptables_guard']('192.0.2.10',3222,4,False,text)

    def nft_fixture(self):
        def match(protocol,field,value):return {'match':{'op':'==','left':{'payload':{'protocol':protocol,'field':field}},'right':value}}
        chain={'family':'inet','table':'nuvrion_xhttp','name':'api_guard','type':'filter','hook':'input','prio':-250,'policy':'accept'}
        rules=[{'family':'inet','table':'nuvrion_xhttp','chain':'api_guard','handle':i+1,'comment':'Nuvrion-XHTTP','expr':expr}
               for i,expr in enumerate([[match('ip','saddr','192.0.2.10'),match('tcp','dport',3222),{'accept':None}],
                                        [match('tcp','dport',3222),{'drop':None}]])]
        return {'nftables':[{'chain':chain},*[{'rule':r} for r in rules]]}

    def test_nft_checker_rejects_reordered_guard_and_conflicting_chain(self):
        good=self.nft_fixture();LIB['check_nft_guard']('192.0.2.10',3222,good)
        reversed_rules={'nftables':[good['nftables'][0],*reversed(good['nftables'][1:])]}
        with self.assertRaises(ValueError):LIB['check_nft_guard']('192.0.2.10',3222,reversed_rules)
        for field,value in [('policy','drop'),('type','nat'),('hook','forward'),('prio',0)]:
            bad=json.loads(json.dumps(good));bad['nftables'][0]['chain'][field]=value
            with self.assertRaises(ValueError):LIB['check_nft_guard']('192.0.2.10',3222,bad)
            with self.assertRaises(ValueError):LIB['nft_security_rules']('192.0.2.10',False,bad,3222)
        foreign=json.loads(json.dumps(good));foreign['nftables'][1]['rule']['comment']='foreign'
        with self.assertRaises(ValueError):LIB['nft_security_rules']('192.0.2.10',False,foreign,3222)

    def test_ufw_checker_requires_active_both_families_and_allow_before_deny(self):
        good='''Status: active
[ 1] 443/tcp                    ALLOW IN    Anywhere                   # Nuvrion-XHTTP HTTPS
[ 2] 3222/tcp                   ALLOW IN    192.0.2.10                 # Nuvrion-XHTTP panel
[ 3] 3222/tcp                   DENY IN     Anywhere                   # Nuvrion-XHTTP API guard
[ 4] 443/tcp (v6)               ALLOW IN    Anywhere (v6)              # Nuvrion-XHTTP HTTPS
[ 5] 3222/tcp (v6)              DENY IN     Anywhere (v6)              # Nuvrion-XHTTP API guard
'''
        LIB['check_ufw_guard']('192.0.2.10',3222,False,good)
        for bad in [good.replace('Status: active','Status: inactive'),
                    good.replace('[ 5] 3222/tcp (v6)','[ 5] 2222/tcp (v6)'),
                    good.replace('[ 1]', '[ 0] Anywhere ALLOW IN Anywhere\n[ 1]'),
                    good.replace('[ 1]', '[ 0] 3222 ALLOW IN Anywhere\n[ 1]'),
                    good.replace('[ 1]', '[ 0] 3222 LIMIT IN Anywhere\n[ 1]'),
                    good.replace('[ 1]', '[ 0] 3000:4000/tcp ALLOW IN Anywhere\n[ 1]'),
                    good.replace('192.0.2.10','192.0.2.100'),
                    good.replace('192.0.2.10','192.0.2.11')]:
            with self.assertRaises(ValueError):LIB['check_ufw_guard']('192.0.2.10',3222,False,bad)

    @unittest.skipIf(os.name=='nt' or os.geteuid()!=0,'Root-owned unit fixture')
    def test_units_are_not_taken_over_by_merely_creating_state_and_owned_edits_are_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);own=root/'own';own.mkdir();state=own/'state.json';state.write_text('{}')
            unit=root/'game.service';marker='# BEGIN NUVRION XHTTP GAME'
            unit.write_text('foreign app\n');unit.chmod(0o644)
            with patch.dict(LIB,OWN=own,STATE=state):
                with self.assertRaises(ValueError):LIB['write_owned_unit'](unit,marker,marker+'\nnew\n')
                self.assertEqual(unit.read_text(),'foreign app\n')
                unit.unlink();LIB['write_owned_unit'](unit,marker,marker+'\nnew\n')
                LIB['check_owned_unit'](unit,marker)
                unit.write_text(marker+'\nmanual change\n')
                with self.assertRaises(ValueError):LIB['write_owned_unit'](unit,marker,marker+'\nnew\n')
                self.assertIn('manual change',unit.read_text())

    @unittest.skipIf(os.name=='nt' or os.geteuid()!=0,'Root-owned unit fixture')
    def test_unit_legacy_delta_allows_unchanged_own_unit(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);own=root/'own';own.mkdir();state=own/'state.json';state.write_text('{}')
            unit=root/'firewall.service';marker='# BEGIN NUVRION XHTTP FIREWALL';unit.write_text(marker+'\nlegacy\n');unit.chmod(0o644)
            (own/'owned-delta.json').write_text(json.dumps({str(unit):{'after':hashlib.sha256(unit.read_bytes()).hexdigest()}}))
            with patch.dict(LIB,OWN=own,STATE=state):LIB['check_owned_unit'](unit,marker)

    def test_first_deploy_reports_existing_assets_and_never_follows_nested_symlink(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);dest=root/'public';dest.mkdir();(dest/'index.html').write_text('existing');manifest=root/'assets.json'
            self.assertEqual(LIB['asset_collisions'](['index.html'],dest,manifest),['index.html'])
            self.assertEqual((dest/'index.html').read_text(),'existing')
            elsewhere=root/'elsewhere';elsewhere.mkdir();(dest/'assets').symlink_to(elsewhere,target_is_directory=True)
            with self.assertRaises(ValueError):LIB['asset_collisions'](['assets/new.js'],dest,manifest)
            self.assertFalse((elsewhere/'new.js').exists())

    def test_existing_assets_require_confirmation_and_new_foreign_assets_are_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);source=root/'source';source.mkdir();(source/'index.html').write_text('new')
            dest=root/'public';dest.mkdir();(dest/'index.html').write_text('existing');manifest=root/'assets.json'
            def invoke(flag=''):
                return test_xhttp.XhttpTests().invoke('assets',[str(source),str(dest),str(manifest),flag])
            with self.assertRaises(ValueError):invoke()
            self.assertEqual((dest/'index.html').read_text(),'existing')
            invoke('1');self.assertEqual((dest/'index.html').read_text(),'new')
            (source/'new.js').write_text('owned');(dest/'new.js').write_text('foreign')
            with self.assertRaises(ValueError):invoke('1')
            self.assertEqual((dest/'new.js').read_text(),'foreign')

    def test_bundle_preflight_is_read_only_and_requires_complete_atlas(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);own=root/'own';public=root/'public';public.mkdir()
            (public/'index.html').write_text('existing site')
            def invoke(files):
                archive=io.BytesIO()
                with tarfile.open(fileobj=archive,mode='w:gz') as tar:
                    for name,data in files:
                        info=tarfile.TarInfo(name);info.size=len(data);tar.addfile(info,io.BytesIO(data))
                output=io.StringIO()
                with patch.dict(LIB,OWN=own),patch.object(sys,'argv',['helper','bundle-assets-preflight',str(public)]),\
                        patch.object(sys,'stdin',types.SimpleNamespace(buffer=io.BytesIO(archive.getvalue()))),contextlib.redirect_stdout(output):
                    LIB['run']()
                return json.loads(output.getvalue())
            files=[('beer-atlas/public/index.html',b'new'),('beer-atlas/public/beers.json',b'[]')]
            self.assertEqual(invoke(files),['index.html'])
            self.assertFalse(own.exists())
            self.assertEqual((public/'index.html').read_text(),'existing site')
            for invalid in [files[:1],files+[files[0]],files+[('../escape',b'x')]]:
                with self.assertRaises(ValueError):invoke(invalid)
            self.assertEqual((public/'index.html').read_text(),'existing site')

    def test_confirmed_public_replacement_does_not_mutate_other_hardlinks(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);source=root/'source';source.mkdir();(source/'index.html').write_text('new site')
            dest=root/'public';dest.mkdir();outside=root/'outside';outside.write_text('keep outside')
            os.link(outside,dest/'index.html')
            test_xhttp.XhttpTests().invoke('assets',[str(source),str(dest),str(root/'assets.json'),'1'])
            self.assertEqual((dest/'index.html').read_text(),'new site')
            self.assertEqual(outside.read_text(),'keep outside')


if __name__=='__main__':unittest.main()
