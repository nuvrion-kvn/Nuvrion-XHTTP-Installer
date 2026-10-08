#!/usr/bin/env python3
"""Rebuild the single distributable XHTTP installer from its embedded source.

Build dependencies live in this repository; server runtime downloads none of
them. The management copy uses the same verified local archive after install.
"""
import base64
import gzip
import hashlib
import io
from pathlib import Path
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'nuvrion-xhttp-install.sh'
MARK = '# @NUVRION_XHTTP_PAYLOAD@'


def build():
    source = DEST.read_text(encoding='utf-8')
    source = re.sub(r'# BEGIN EMBEDDED NUVRION XHTTP\n.*?# END EMBEDDED NUVRION XHTTP',
                    MARK, source, flags=re.S)
    assert source.count(MARK) == 1
    manager = source.replace(MARK, 'payload() { base64 "$OWN/bundle.tar.gz"; }\n'
                                    'payload_hash() { cat "$OWN/bundle.sha256"; }')
    vendor = ROOT / 'vendor/nuvrion-auto-tuning-xhttp.sh'
    assert hashlib.sha256(vendor.read_bytes()).hexdigest() == 'cffaa9db580b06432fb4f6a8d04dadacc413a8d627032d9dfe60fc114a14c489'
    tuner = vendor.read_text(encoding='utf-8')
    # Enable the complete security/performance module. Only its firewall writer
    # delegates to the installer's existing, backed-up multi-backend firewall.
    guard = 'if [[ $SECURITY_ENABLED == 1 ]]; then\n    OTHER_FIREWALL=""'
    assert tuner.count(guard) == 1
    tuner = tuner.replace(guard, 'if [[ $SECURITY_ENABLED == 1 && ${NUVRION_MANAGED_FIREWALL:-0} != 1 ]]; then\n    OTHER_FIREWALL=""')
    traffic = ROOT / 'vendor/nuvrion-traffic-control-xhttp.py'
    assert hashlib.sha256(traffic.read_bytes()).hexdigest() == 'dc2c66855f41c0c51ce6bd0ab4c9969cc57489363eef3dd84ac3525ff9e58401'
    traffic_source = traffic.read_text(encoding='utf-8')
    # A bounded lease keeps HTTP-01 reachable even when the update timer runs
    # concurrently. Every other Traffic Control function stays upstream.
    target = 'def apply(state):\n    rules = render(state, present())'
    assert traffic_source.count(target) == 1
    traffic_source = traffic_source.replace(target, '''def apply(state):
    lease = Path("/run/nuvrion-xhttp-acme-open")
    acme = False
    if lease.exists() and not lease.is_symlink() and lease.stat().st_uid == 0:
        try:
            age = time.time() - float(lease.read_text().strip())
            acme = 0 <= age <= 1200
        except (OSError, ValueError):
            pass
    rules = render(state, present(), acme=acme)''')
    # Upstream render has no ACME switch; add only an INPUT/80 return before
    # blocklists, with the same bounded lease used by its periodic updater.
    target = 'def render(state, exists=False):'
    assert traffic_source.count(target) == 1
    traffic_source = traffic_source.replace(target, 'def render(state, exists=False, acme=False):')
    target = '    return "\\n".join(lines + [" }", "}", ""])'
    # Locate the return inside render rather than another unrelated formatter.
    start = traffic_source.index('def render(')
    end = traffic_source.index('\ndef present(', start)
    body = traffic_source[start:end]
    assert body.count(target) == 1
    body = body.replace(target, '    if acme:\n        lines.insert(next(i for i,v in enumerate(lines) if "ct state established,related return" in v), \'  tcp dport 80 return comment "Nuvrion-XHTTP-ACME"\')\n'+target)
    traffic_source = traffic_source[:start]+body+traffic_source[end:]
    files = [('installer-manager.sh', manager.encode()), ('nuvrion-auto-tuning.sh', tuner.encode()),
             ('nuvrion-traffic-control.py', traffic_source.encode())]
    for name in ('nuvrion-two-way-ping.sh', 'nuvrion-two-way-ping.service'):
        files.append((name, (ROOT/'src'/name).read_bytes()))
    for directory, name in [('site/dist', 'pokehabitat/public'), ('site/server/dist', 'pokehabitat/server')]:
        base = ROOT / directory
        assert base.is_dir()
        files.extend((name+'/'+p.relative_to(base).as_posix(), p.read_bytes())
                     for p in sorted(base.rglob('*'), key=lambda p: p.relative_to(base).as_posix()) if p.is_file())
    for name in ('site/LICENSES.md', 'THIRD_PARTY_NOTICES.md', 'LICENSE'):
        files.append(('notices/'+Path(name).name, (ROOT/name).read_bytes()))
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w', format=tarfile.USTAR_FORMAT) as tar:
        for name, data in files:
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o600, 0
            tar.addfile(info, io.BytesIO(data))
    payload = gzip.compress(buffer.getvalue(), compresslevel=9, mtime=0)
    payload = payload[:9] + b'\xff' + payload[10:]
    checksum = hashlib.sha256(payload).hexdigest()
    block = ('# BEGIN EMBEDDED NUVRION XHTTP\n'
             f"payload_hash() {{ printf '%s\\n' '{checksum}'; }}\n"
             "payload() { cat <<'NUVRION_XHTTP_ARCHIVE'\n"
             + base64.encodebytes(payload).decode('ascii')
             + 'NUVRION_XHTTP_ARCHIVE\n}\n# END EMBEDDED NUVRION XHTTP')
    DEST.write_text(source.replace(MARK, block), encoding='utf-8', newline='\n')
    DEST.chmod(0o755)
    sums = ROOT / 'SHA256SUMS'
    lines = [s for s in sums.read_text().splitlines() if not s.endswith('  '+DEST.name)]
    lines.append(hashlib.sha256(DEST.read_bytes()).hexdigest()+'  '+DEST.name)
    sums.write_text('\n'.join(lines)+'\n', encoding='utf-8', newline='\n')
    print(f'{DEST.name}: {DEST.stat().st_size} bytes; {len(files)} embedded files')


if __name__ == '__main__':
    build()
