"""Restitue les octets exacts de l’APK signé à partir du lot temporaire du même AAB."""
import base64, gzip, hashlib, json, struct, sys, zipfile
from pathlib import Path
src,template,destination=map(Path,sys.argv[1:])
plan=json.loads(gzip.decompress(template.read_bytes()))
static=base64.b64decode(plan['static'],validate=True);cur=0
with zipfile.ZipFile(src) as z,src.open('rb') as body,destination.open('wb') as dst:
    for n,name,len_apk in plan['layout']:
        dst.write(static[cur:cur+n]);cur+=n
        if not name:continue
        entry=z.getinfo(name);assert entry.compress_size==len_apk,name
        body.seek(entry.header_offset+26);nl,el=struct.unpack('<HH',body.read(4));body.seek(nl+el,1)
        dst.write(body.read(len_apk))
assert cur==len(static)
with destination.open('rb') as fd: digest=hashlib.file_digest(fd,'sha256').hexdigest()
assert digest==plan['sha']=='db585a637bb0a4672cd4019f5bd5cc178587d1f67509f9a669ec17e78e6d18df',digest
print('APK final vérifié',digest)
