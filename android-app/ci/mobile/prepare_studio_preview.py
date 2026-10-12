#!/usr/bin/env python3
"""Habille le seul APK de revue. Jamais appelé par la livraison signée."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

p = Path('android/app/build.gradle.kts')
s = p.read_text()
s, count = re.subn(r'applicationId = "[^"]+"',
                   'applicationId = "com.sevenmotion.studio.preview"', s)
assert count == 1, 'Identifiant Android introuvable'
s, count = re.subn(r'minSdk = (?:flutter.minSdkVersion|\d+)', 'minSdk = 24', s)
assert count == 1, 'minSdk introuvable'
if 'isCoreLibraryDesugaringEnabled' not in s:
    s = s.replace('compileOptions {',
                  'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
if 'desugar_jdk_libs' not in s:
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
p.write_text(s)

A = '{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android', A[1:-1])
ET.register_namespace('tools', 'http://schemas.android.com/tools')
p = Path('android/app/src/main/AndroidManifest.xml')
tree = ET.parse(p)
root = tree.getroot()
app = root.find('application')
assert app is not None
app.set(A + 'label', '7MOTION Studio · test')
# Même support HTTP et PiP que le téléphone historique.
app.set(A + 'usesCleartextTraffic', 'true')
for activity in app.findall('activity'):
    if activity.get(A + 'name', '').endswith('MainActivity'):
        activity.set(A + 'supportsPictureInPicture', 'true')
        activity.set(A + 'resizeableActivity', 'true')
if not any(x.get(A + 'name') == 'android.permission.RECEIVE_BOOT_COMPLETED'
           for x in root.findall('uses-permission')):
    ET.SubElement(root, 'uses-permission', {A + 'name': 'android.permission.RECEIVE_BOOT_COMPLETED'})
tree.write(p, encoding='unicode')
