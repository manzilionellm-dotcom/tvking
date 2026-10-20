"""Régression : apkanalyzer encode mediaPlayback en 0x2 dans le vrai APK."""
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

from prepare_android import ANDROID, PERMISSIONS, TEST_LABEL, TEST_PACKAGE
from verify_android import verify


class VerifyForegroundTypeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.apk = directory / "fixture.apk"
        self.manifest = directory / "manifest.xml"
        # Conteneur synthétique limité au contrat du vérificateur ; il ne
        # remplace pas la vérification d'un APK compilé/signé dans le workflow.
        with zipfile.ZipFile(self.apk, "w") as archive:
            archive.writestr("classes.dex", b"\0".join((
                b"Lcom/example/tv_king/ZunoCastActivity;",
                b"Lcom/example/tv_king/GoogleCastApi;",
                b"Lcom/example/tv_king/MulticastLockBridge;",
                b"Lcom/google/android/gms/cast/framework/CastContext;",
            )))

    def root(self):
        root = ET.Element("manifest", {"package": TEST_PACKAGE})
        ET.SubElement(root, "uses-sdk", {
            ANDROID + "minSdkVersion": "24", ANDROID + "targetSdkVersion": "35",
        })
        for permission in PERMISSIONS:
            ET.SubElement(root, "uses-permission", {
                ANDROID + "name": "android.permission." + permission,
            })
        app = ET.SubElement(root, "application", {ANDROID + "label": TEST_LABEL})
        activity = ET.SubElement(app, "activity", {
            ANDROID + "name": "com.example.tv_king.ZunoCastActivity",
        })
        intent = ET.SubElement(activity, "intent-filter")
        ET.SubElement(intent, "category", {
            ANDROID + "name": "android.intent.category.LAUNCHER",
        })
        ET.SubElement(app, "meta-data", {
            ANDROID + "name": "com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME",
            ANDROID + "value": "com.example.tv_king.CastOptionsProviderImpl",
        })
        for name in ("RecordingForegroundService", "PlaybackForegroundService"):
            ET.SubElement(app, "service", {
                ANDROID + "name": "com.example.tv_king." + name,
                ANDROID + "foregroundServiceType": "mediaPlayback",
            })
        return root

    def check(self, root):
        ET.ElementTree(root).write(self.manifest, encoding="utf-8")
        return verify(self.apk, self.manifest)

    def test_symbolic_decimal_and_hexadecimal_formats_are_equivalent(self):
        for value in ("mediaPlayback", "2", "0x2", "0x00000002", "0X02", "0002"):
            with self.subTest(value=value):
                root = self.root()
                for service in root.findall("application/service"):
                    service.set(ANDROID + "foregroundServiceType", value)
                self.assertEqual(self.check(root)["edition"], "touch")

    def test_missing_type_is_rejected_for_each_service(self):
        for index in (0, 1):
            with self.subTest(service=index):
                root = self.root()
                service = root.findall("application/service")[index]
                del service.attrib[ANDROID + "foregroundServiceType"]
                with self.assertRaisesRegex(AssertionError, "type foreground incorrect"):
                    self.check(root)

    def test_other_types_and_combinations_are_rejected_for_each_service(self):
        for index in (0, 1):
            for value in ("", "0", "1", "3", "6", "0x1", "0x3", "0x6",
                          "dataSync", "mediaPlayback|dataSync", "dataSync|mediaPlayback",
                          "0x2|0x1", "0b10", "0x", "2.0", "mediaPlayback "):
                with self.subTest(service=index, value=value):
                    root = self.root()
                    root.findall("application/service")[index].set(
                        ANDROID + "foregroundServiceType", value)
                    with self.assertRaisesRegex(AssertionError, "type foreground incorrect"):
                        self.check(root)

    def test_missing_service_is_still_rejected(self):
        for index in (0, 1):
            with self.subTest(service=index):
                root = self.root()
                app = root.find("application")
                app.remove(app.findall("service")[index])
                with self.assertRaisesRegex(AssertionError, "Service absent"):
                    self.check(root)


if __name__ == "__main__":
    unittest.main()
