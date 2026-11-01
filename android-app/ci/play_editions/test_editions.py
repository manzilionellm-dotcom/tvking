"""Contrats d'installation et détection d'un mélange entre les deux produits."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

from prepare import (A, APP, CAST_KEY, CAST_SERVICE, EDITION_KEY, PACKAGES, T,
                     edition_manifest, load_module, version_for)
from verify import verify_manifest


class EditionTests(unittest.TestCase):
    def source(self, edition):
        patcher = load_module('manifest_test', APP / 'ci/tv/patch_manifest.py')
        original = (APP / 'android/app/src/main/AndroidManifest.xml').read_text()
        return edition_manifest(patcher.patch(original), edition)

    def merged(self, edition):
        # Le vrai manifeste fusionné sera ensuite contrôlé dans chaque AAB.
        root = ET.fromstring(self.source(edition))
        for parent in root.iter():
            for child in list(parent):
                if child.get(T + 'node') == 'remove':
                    parent.remove(child)
        root.set('package', PACKAGES[edition])
        code, name = version_for(edition)
        root.set(A + 'versionCode', str(code))
        root.set(A + 'versionName', name)
        sdk = root.find('uses-sdk')
        sdk.set(A + 'minSdkVersion', '24')
        sdk.set(A + 'targetSdkVersion', '36')
        if edition == 'mobile':
            app = root.find('application')
            ET.SubElement(app, 'meta-data', {A + 'name': CAST_KEY, A + 'value': 'provider'})
            ET.SubElement(app, 'service', {A + 'name': CAST_SERVICE})
        return root

    def test_distinct_packages_and_version_sequences(self):
        self.assertNotEqual(PACKAGES['tv'], PACKAGES['mobile'])
        self.assertEqual(PACKAGES['tv'], 'com.sevenmotion.tv.seven_tv')
        self.assertEqual(version_for('mobile'), (1, '1.0.0'))
        self.assertGreater(version_for('tv')[0], 1)

    def test_launcher_and_pip_are_specific_to_each_edition(self):
        for edition in PACKAGES:
            root = self.merged(edition)
            report = verify_manifest(ET.tostring(root), edition)
            self.assertEqual(report['cast_sender'], edition == 'mobile')
            self.assertEqual(report['picture_in_picture'], edition == 'mobile')

    def test_mobile_has_no_tv_launcher(self):
        self.assertNotIn('LEANBACK_LAUNCHER', self.source('mobile'))
        self.assertIn('LEANBACK_LAUNCHER', self.source('tv'))

    def test_package_collision_is_rejected(self):
        root = self.merged('mobile')
        root.set('package', PACKAGES['tv'])
        with self.assertRaisesRegex(AssertionError, 'package'):
            verify_manifest(ET.tostring(root), 'mobile')

    def test_tv_with_cast_configuration_is_rejected(self):
        root = self.merged('tv')
        ET.SubElement(root.find('application'), 'meta-data', {A + 'name': CAST_KEY})
        with self.assertRaisesRegex(AssertionError, 'Cast'):
            verify_manifest(ET.tostring(root), 'tv')

    def test_mobile_without_sender_service_is_rejected(self):
        root = self.merged('mobile')
        app = root.find('application')
        app.remove(app.find('service'))
        with self.assertRaisesRegex(AssertionError, 'Cast'):
            verify_manifest(ET.tostring(root), 'mobile')

    def test_mismatched_native_edition_is_rejected(self):
        root = self.merged('tv')
        for item in root.find('application').findall('meta-data'):
            if item.get(A + 'name') == EDITION_KEY:
                item.set(A + 'value', 'mobile')
        with self.assertRaisesRegex(AssertionError, 'Édition'):
            verify_manifest(ET.tostring(root), 'tv')

    def test_unknown_edition_is_rejected(self):
        with self.assertRaises(ValueError):
            edition_manifest('<manifest/>', 'typo')


if __name__ == '__main__':
    unittest.main()
