"""Rebuild the runtime payload for an emulator with temporary test signing."""
import hashlib
import re
import sys
from zipfile import ZipFile

source, replacements, output, expected = sys.argv[1:]
reference = "b6ef0db61ecd97c4a6a84714483a4041f9f591e6b382193335a95f0f3a015591"
with open(source, "rb") as stream:
    assert hashlib.file_digest(stream, "sha256").hexdigest() == reference

def signature_entry(name):
    return re.fullmatch(r"META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))", name, re.I)

with ZipFile(source) as ref, ZipFile(replacements) as patch, ZipFile(output, "w") as dst:
    assert set(patch.namelist()) == {"AndroidManifest.xml", "resources.arsc", "res/xml/splits0.xml"}
    for item in ref.infolist():
        name = item.filename
        if signature_entry(name):
            continue
        data = patch.read(name) if name in patch.NameToInfo else ref.read(name)
        dst.writestr(item, data)
    for name in sorted(set(patch.namelist()) - set(ref.namelist())):
        dst.writestr(name, patch.read(name))

with ZipFile(output) as apk:
    inventory = hashlib.sha256()
    for name in sorted(apk.namelist()):
        inventory.update(name.encode() + bytes(1) + hashlib.sha256(apk.read(name)).digest())
    assert inventory.hexdigest() == expected
    print("Compiled runtime verified against the universal APK from the Play AAB:", expected)
