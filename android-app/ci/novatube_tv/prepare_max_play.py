"""Prépare exclusivement le manifeste du nouveau package NovaTube MAX Play."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

APP = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(APP))
from ci.play_editions.prepare import A, T, ANDROID, TOOLS, set_named

def prepare(path):
    ET.register_namespace('android', ANDROID)
    ET.register_namespace('tools', TOOLS)
    root = ET.parse(path).getroot()
    app = root.find('application')
    activity = app.find('activity')
    if app.get(A + 'label') != 'NovaTube MAX':
        raise ValueError('Ce manifeste ne correspond pas à NovaTube MAX')
    names = {node.get(A + 'name') for node in activity.findall('intent-filter/category')}
    for name in ('LAUNCHER', 'LEANBACK_LAUNCHER'):
        category = 'android.intent.category.' + name
        if category not in names:
            intent = ET.SubElement(activity, 'intent-filter')
            ET.SubElement(intent, 'action', {A + 'name': 'android.intent.action.MAIN'})
            ET.SubElement(intent, 'category', {A + 'name': category})
    for feature in ('android.software.leanback', 'android.hardware.touchscreen',
                    'android.hardware.faketouch', 'android.hardware.screen.landscape'):
        set_named(root, 'uses-feature', feature, **{A + 'required': 'false'})
    set_named(root, 'uses-permission', 'android.permission.REQUEST_INSTALL_PACKAGES',
              **{T + 'node': 'remove'})
    ET.ElementTree(root).write(path, encoding='utf-8', xml_declaration=True)

if __name__ == '__main__':
    prepare(APP / 'android/app/src/main/AndroidManifest.xml')
