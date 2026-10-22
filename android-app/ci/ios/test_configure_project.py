"""Teste les permissions réellement inscrites et l'échec fermé du générateur."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('configure', Path(__file__).with_name('configure_project.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ProjectTests(unittest.TestCase):
    def test_configuration_is_idempotent_and_no_android_cast_permission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = root / 'ios/Runner'; runner.mkdir(parents=True)
            project = root / 'ios/Runner.xcodeproj'; project.mkdir()
            info = runner / 'Info.plist'
            info.write_bytes(plistlib.dumps({'CFBundleVersion':'$(FLUTTER_BUILD_NUMBER)',
                'NSBonjourServices':['_googlecast._tcp']}))
            pbx = project / 'project.pbxproj'
            pbx.write_text(('PRODUCT_BUNDLE_IDENTIFIER = com.example.app;\n'
                            'IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n'
                            'TARGETED_DEVICE_FAMILY = "1,2";\n') * 3)
            # Cas réel Flutter 3.47 : aucun Podfile n'a encore été généré.
            module.configure(root, 'com.manzilionellm.sevenmotion')
            first = (info.read_bytes(),pbx.read_bytes())
            module.configure(root, 'com.manzilionellm.sevenmotion')
            self.assertEqual(first,(info.read_bytes(),pbx.read_bytes()))
            data=plistlib.loads(info.read_bytes())
            self.assertEqual(data['CFBundleDisplayName'],'7 MOTION')
            self.assertIn('NSFaceIDUsageDescription',data)
            self.assertNotIn('NSBonjourServices',data)
            self.assertEqual(data['UIBackgroundModes'],['audio'])
            self.assertEqual(data['CFBundleVersion'],'$(FLUTTER_BUILD_NUMBER)')
            self.assertNotIn('1,2',pbx.read_text())
            self.assertIn("platform :ios, '15.0'", (root / 'ios/Podfile').read_text())
    def test_missing_project_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError): module.configure(Path(directory),'com.example.valid')
    def test_invalid_identifier_is_an_error(self):
        with self.assertRaises(ValueError): module.configure(Path('/missing'), 'invalid;code')

if __name__ == '__main__': unittest.main()
