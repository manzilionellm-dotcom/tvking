"""Verify a staged artifact and Android Package Manager's installed base APK."""
from hashlib import sha256
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import zipfile

out, source = map(Path, sys.argv[1:3])
package, expected = sys.argv[3:5]
adb = ['adb','-s','emulator-5554']
evidence = {}
def record():
    (out/'installed-apk-verification.json').write_text(json.dumps(evidence,indent=2)+'\n')
def call(*args, timeout=90):
    p=subprocess.run([*adb,*args], stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
    return p.returncode,p.stdout.decode(errors='replace').strip(),p.stderr.decode(errors='replace').strip()
def log(cmd,*args,timeout=90):
    rc,s,e=call(*args,timeout=timeout)
    evidence[cmd]={'rc':rc,'stdout':s[:2400],'stderr':e[:600]}
    record()
    return rc,s
def digest(path):
    with path.open('rb') as f:
        h=sha256()
        for part in iter(lambda:f.read(1024*1024), b''):
            h.update(part)
    return h.hexdigest()
def token(line):
    return line.split()[0].lower() if re.match(r'^[0-9a-fA-F]{64}\s',line) else None
def zip_info(file):
    with zipfile.ZipFile(file) as z:
        return {n:(z.getinfo(n).file_size,z.getinfo(n).CRC) for n in z.namelist()}
def verify_installed(label):
    rc,s=log(label+'_paths','shell',f'pm path {shlex.quote(package)}')
    paths=[r[8:].strip() for r in s.splitlines() if r.startswith('package:') and r.rstrip().endswith('/base.apk')]
    if rc or len(paths)!=1: raise RuntimeError('Package Manager did not return exactly one base.apk')
    remote=paths[0]
    log(label+'_stat','shell','stat -c "%s %a %n" '+shlex.quote(remote))
    rc,raw=log(label+'_sha256','shell','toybox sha256sum '+shlex.quote(remote))
    guest=token(raw) if rc==0 else None
    with tempfile.TemporaryDirectory() as td:
        f=Path(td)/'base.apk'
        success,_=log(label+'_pull','pull',remote,str(f))
        host = digest(f) if success==0 and f.exists() else None
        evidence[label+'_pulled']={'bytes':f.stat().st_size if f.exists() else None,'sha256':host}
        if host and host!=expected and f.stat().st_size>=source.stat().st_size//2:
            try:
                a,b=zip_info(source),zip_info(f)
                evidence[label+'_zip']={'missing':sorted(a.keys()-b.keys())[:15],'extra':sorted(b.keys()-a.keys())[:15],
                    'different_entries':sorted(k for k in a.keys()&b.keys() if a[k]!=b[k])[:20],
                    'source_entries':len(a),'installed_entries':len(b)}
            except zipfile.BadZipFile:
                evidence[label+'_zip']='Not an intact APK ZIP'
        record()
    # Host transport and the guest may independently verify. An affirmative discrepancy requires another installation.
    if guest != expected and host != expected:
        return False
    if guest and host and guest!=host:
        return False
    (out/'installed-apk.sha256').write_text(expected+'\n')
    return True

if digest(source)!=expected:
    raise RuntimeError('Unexpected candidate before installation')
evidence['source_expected_sha256']=expected
evidence['source_size']=source.stat().st_size
if not verify_installed('first'):
    stage='/data/local/tmp/nt-endurance-exact.apk'
    try:
        rc,_=log('staged_push','push',str(source),stage)
        if rc:raise RuntimeError('Staging transfer failed')
        rc,line=log('staged_sha256','shell','toybox sha256sum '+stage)
        if rc or token(line)!=expected:raise RuntimeError('Staged APK bytes differ')
        rc,line=log('staged_install','shell','pm install -r '+stage)
        if rc or 'Success' not in line:raise RuntimeError('Android Package Manager rejected staged candidate')
        if not verify_installed('second'):
            raise RuntimeError('Installed candidate bytes could not be authenticated by either device SHA or adb pull')
    finally:
        log('remove_staged_copy','shell','rm -f '+stage)
