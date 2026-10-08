#!/usr/bin/env python3
"""Complète le projet Android généré, sans modifier la box ni ses sources."""
import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)
ET.register_namespace("tools", "http://schemas.android.com/tools")
name = "{" + ANDROID + "}name"
exported = "{" + ANDROID + "}exported"
manifest = Path("android/app/src/main/AndroidManifest.xml")
tree = ET.parse(manifest)
application = tree.getroot().find("application")
if application is None:
    raise SystemExit("Manifeste Android sans application")
for receiver_name, actions in [
    ("com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver", []),
    ("com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver", [
        "android.intent.action.BOOT_COMPLETED", "android.intent.action.MY_PACKAGE_REPLACED",
        "android.intent.action.QUICKBOOT_POWERON", "com.htc.intent.action.QUICKBOOT_POWERON",
    ]),
]:
    found = [r for r in application.findall("receiver") if r.get(name) == receiver_name]
    if len(found) > 1:
        raise SystemExit("Récepteur Android déclaré plusieurs fois")
    receiver = found[0] if found else ET.SubElement(application, "receiver", {
        name: receiver_name, exported: "false",
    })
    if receiver.get(exported) != "false":
        raise SystemExit("Le récepteur des notifications doit rester privé")
    if actions and not receiver.findall("intent-filter"):
        intent = ET.SubElement(receiver, "intent-filter")
        for action in actions:
            ET.SubElement(intent, "action", {name: action})
tree.write(manifest, encoding="unicode")
# Le son est synthétisé par le script existant, pas récupéré chez un tiers.
subprocess.run([sys.executable, "tools/make_goal_sound.py"], check=True)
raw = Path("android/app/src/main/res/raw")
raw.mkdir(parents=True, exist_ok=True)
# Ces ressources sont recherchées par leur nom à l'exécution ; R8 ne
# doit pas les supprimer lorsque le lien vient d'un appel Flutter.
(raw / "keep_notifications.xml").write_text(
    '<resources xmlns:tools="http://schemas.android.com/tools" '
    'tools:keep="@mipmap/ic_launcher,@raw/goal_roar"/>\n')
print("Notifications Android : son généré, ressources conservées, récepteurs privés")
