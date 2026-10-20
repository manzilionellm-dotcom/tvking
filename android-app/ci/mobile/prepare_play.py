#!/usr/bin/env python3
"""Applique les restrictions déjà utilisées par le constructeur Play.

La signature et le namespace Kotlin restent identiques. Seul le bundle
du Store porte son applicationId et retire les permissions du sideload.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID = "http://schemas.android.com/apk/res/android"
TOOLS = "http://schemas.android.com/tools"
ET.register_namespace("android", ANDROID)
ET.register_namespace("tools", TOOLS)
name = "{" + ANDROID + "}name"
node = "{" + TOOLS + "}node"
manifest = Path("android/app/src/main/AndroidManifest.xml")
tree = ET.parse(manifest)
root = tree.getroot()
removed = ["REQUEST_INSTALL_PACKAGES", "READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO",
           "READ_MEDIA_AUDIO", "USE_EXACT_ALARM", "FOREGROUND_SERVICE_MEDIA_PROJECTION",
           "RECEIVE_BOOT_COMPLETED"]
for permission in removed + ["SCHEDULE_EXACT_ALARM"]:
    full = "android.permission." + permission
    for element in list(root.findall("uses-permission")):
        if element.get(name) == full:
            root.remove(element)
    ET.SubElement(root, "uses-permission", {
        name: full, node: "replace" if permission == "SCHEDULE_EXACT_ALARM" else "remove",
    })
application = root.find("application")
if application is None:
    raise SystemExit("Manifeste Android sans application")
service_name = "com.manzilionellm.tvking_miroir.MiroirService"
for service in list(application.findall("service")):
    if service.get(name) == service_name:
        application.remove(service)
ET.SubElement(application, "service", {name: service_name, node: "remove"})
tree.write(manifest, encoding="unicode")
gradle = Path("android/app/build.gradle.kts")
text = gradle.read_text()
text, changed = re.subn(r'applicationId\s*=\s*"com\.manzilionellm\.tvking\.tv_king"',
                       'applicationId = "com.manzilionellm.tvking"', text)
if changed != 1:
    raise SystemExit("applicationId mobile attendu introuvable ou ambigu")
gradle.write_text(text)
print("Bundle Play : identifiant de la fiche existante et permissions contrôlées")
