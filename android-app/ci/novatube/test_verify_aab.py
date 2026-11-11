#!/usr/bin/env python3
"""Régressions des barrières : un mauvais bundle doit être refusé."""

import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from common import ANDROID, PACKAGE
from verify_aab import flutter_test_results, manifest_identity, native_test_results


def mobile_manifest():
    root = ET.Element("manifest", {
        "package": PACKAGE, ANDROID + "versionName": "0.1.5", ANDROID + "versionCode": "5",
    })
    ET.SubElement(root, "uses-sdk", {ANDROID + "minSdkVersion": "24", ANDROID + "targetSdkVersion": "36"})
    for name in ("INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE",
                 "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_MEDIA_PLAYBACK", "POST_NOTIFICATIONS"):
        ET.SubElement(root, "uses-permission", {ANDROID + "name": "android.permission." + name})
    app = ET.SubElement(root, "application", {ANDROID + "label": "NOVATUBE", ANDROID + "icon": "@mipmap/ic_launcher"})
    activity = ET.SubElement(app, "activity", {ANDROID + "name": PACKAGE + ".MainActivity"})
    intent = ET.SubElement(activity, "intent-filter")
    ET.SubElement(intent, "action", {ANDROID + "name": "android.intent.action.MAIN"})
    ET.SubElement(intent, "category", {ANDROID + "name": "android.intent.category.LAUNCHER"})
    ET.SubElement(app, "meta-data", {
        ANDROID + "name": "com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME",
        ANDROID + "value": PACKAGE + ".CastOptionsProviderImpl",
    })
    for name in ("RecordingForegroundService", "PlaybackForegroundService"):
        ET.SubElement(app, "service", {ANDROID + "name": PACKAGE + "." + name,
                                      ANDROID + "foregroundServiceType": "mediaPlayback",
                                      ANDROID + "exported": "false"})
    return root


class ManifestRejectionTest(unittest.TestCase):
    def verify(self, root):
        return manifest_identity(ET.tostring(root, encoding="unicode"))

    def test_correct_mobile_identity_is_accepted(self):
        result = self.verify(mobile_manifest())
        self.assertEqual(result["package"], PACKAGE)
        self.assertEqual(result["versionCode"], 5)

    def test_zuno_or_7motion_package_is_rejected(self):
        for package in ("com.manzilionellm.tvking", "com.sevenmotion.tv.seven_tv", "com.example.tv_king"):
            with self.subTest(package=package):
                root = mobile_manifest()
                root.set("package", package)
                with self.assertRaisesRegex(ValueError, "Package"):
                    self.verify(root)

    def test_wrong_name_or_version_is_rejected(self):
        for attribute, value in (("versionName", "0.1.6"), ("versionCode", "116")):
            root = mobile_manifest()
            root.set(ANDROID + attribute, value)
            with self.assertRaisesRegex(ValueError, attribute):
                self.verify(root)
        root = mobile_manifest()
        root.find("application").set(ANDROID + "label", "ZUNO")
        with self.assertRaisesRegex(ValueError, "Nom affiché"):
            self.verify(root)

    def test_debug_or_test_only_bundle_is_rejected(self):
        for flag in ("debuggable", "testOnly"):
            for value in ("true", "1", "0xffffffff"):
                root = mobile_manifest()
                root.find("application").set(ANDROID + flag, value)
                with self.assertRaisesRegex(ValueError, flag):
                    self.verify(root)

    def test_google_cast_provider_from_other_app_is_rejected(self):
        root = mobile_manifest()
        root.find("application/meta-data").set(ANDROID + "value", "com.example.tv_king.CastOptionsProviderImpl")
        with self.assertRaisesRegex(ValueError, "Google Cast"):
            self.verify(root)

    def test_missing_playback_notification_service_is_rejected(self):
        root = mobile_manifest()
        app = root.find("application")
        app.remove(app.findall("service")[-1])
        with self.assertRaisesRegex(ValueError, "Service mobile absent"):
            self.verify(root)

    def test_foreground_service_cannot_gain_unrelated_types(self):
        root = mobile_manifest()
        root.find("application/service").set(ANDROID + "foregroundServiceType", "mediaPlayback|location")
        with self.assertRaisesRegex(ValueError, "Type du service"):
            self.verify(root)

    def test_tv_launcher_is_rejected(self):
        root = mobile_manifest()
        ET.SubElement(root.find("application/activity/intent-filter"), "category",
                      {ANDROID + "name": "android.intent.category.LEANBACK_LAUNCHER"})
        with self.assertRaisesRegex(ValueError, "Android TV"):
            self.verify(root)


class TestEvidenceRejectionTest(unittest.TestCase):
    def report(self, events):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "tests.jsonl"
        path.write_text("\n".join(json.dumps(event) for event in events), encoding="utf-8")
        return path

    def test_completed_tests_are_counted_without_hiding_skips(self):
        result = flutter_test_results(self.report([
            {"type": "testDone", "result": "success", "skipped": False},
            {"type": "testDone", "result": "success", "skipped": True},
            {"type": "done", "success": True},
        ]))
        self.assertEqual(result["passed"], 1)
        self.assertEqual(result["skipped"], 1)

    def test_interrupted_test_run_is_not_a_success(self):
        with self.assertRaisesRegex(ValueError, "terminée"):
            flutter_test_results(self.report([{"type": "testDone", "result": "success"}]))

    def test_empty_success_marker_is_not_a_test_result(self):
        with self.assertRaisesRegex(ValueError, "Aucun test"):
            flutter_test_results(self.report([{"type": "done", "success": True}]))

    def test_an_error_remains_fatal_even_with_success_marker(self):
        with self.assertRaisesRegex(ValueError, "Erreur de test"):
            flutter_test_results(self.report([
                {"type": "testDone", "result": "success"},
                {"type": "error", "error": "fixture failure"},
                {"type": "done", "success": True},
            ]))

    def test_jvm_failure_is_not_reported_as_passed(self):
        path = self.report([])
        path.write_text("JUnit\nFAILURES!!!\nTests run: 3, Failures: 1\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "JVM"):
            native_test_results(path)


if __name__ == "__main__":
    unittest.main()
