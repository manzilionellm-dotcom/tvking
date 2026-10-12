#!/usr/bin/env python3
"""Permissions du studio mobile, après flutter create ; jamais appliqué à la TV."""
from pathlib import Path
import xml.etree.ElementTree as ET

A = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', A)
ET.register_namespace('tools', 'http://schemas.android.com/tools')
name = '{' + A + '}name'
p = Path('android/app/src/main/AndroidManifest.xml')
tree = ET.parse(p)
root = tree.getroot()
for permission in ('INTERNET', 'ACCESS_NETWORK_STATE', 'RUN_USER_INITIATED_JOBS',
                   'POST_NOTIFICATIONS', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS'):
    value = 'android.permission.' + permission
    if not any(e.get(name) == value for e in root.findall('uses-permission')):
        ET.SubElement(root, 'uses-permission', {name: value})
# La permission micro ne doit pas exclure un appareil sans microphone.
if not any(e.get(name) == 'android.hardware.microphone' for e in root.findall('uses-feature')):
    ET.SubElement(root, 'uses-feature', {name:'android.hardware.microphone', '{'+A+'}required':'false'})
app = root.find('application')
if app is None:
    raise SystemExit('Manifeste sans application')
# Préférences privées : éviter de copier le secret du chat dans une sauvegarde.
app.set('{'+A+'}allowBackup', 'false')
tree.write(p, encoding='unicode')
