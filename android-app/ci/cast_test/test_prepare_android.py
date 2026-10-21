"""Vérifie le packaging sur une copie temporaire des vrais fichiers Android."""
from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

from prepare_android import ANDROID, NATIVE_FILES, PERMISSIONS, TEST_PACKAGE, prepare, touch_activity

APP = Path(__file__).resolve().parents[2]


class PrepareAndroidTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name)
        shutil.copytree(APP / "android/app", self.app / "android/app")
        shutil.copytree(APP / "android_overlay/google_cast", self.app / "android_overlay/google_cast")
        self.kotlin = self.app / "android/app/src/main/kotlin/com/example/tv_king"
        self.tv_before = (self.kotlin / "MainActivity.kt").read_bytes()

    def test_mobile_launcher_sdk_and_foreground_keep_tv_activity_intact(self):
        prepare(self.app)
        self.assertEqual((self.kotlin / "MainActivity.kt").read_bytes(), self.tv_before)
        root = ET.parse(self.app / "android/app/src/main/AndroidManifest.xml").getroot()
        app = root.find("application")
        activity = app.find("activity")
        self.assertEqual(app.get(ANDROID + "label"), "Zuno Cast test")
        self.assertEqual(activity.get(ANDROID + "name"), "com.example.tv_king.ZunoCastActivity")
        self.assertIsNone(activity.get(ANDROID + "screenOrientation"))
        categories = {c.get(ANDROID + "name") for c in activity.findall("intent-filter/category")}
        self.assertEqual(categories, {"android.intent.category.LAUNCHER"})
        self.assertFalse(any("leanback" in f.get(ANDROID + "name", "") for f in root.findall("uses-feature")))
        permissions = {p.get(ANDROID + "name") for p in root.findall("uses-permission")}
        self.assertTrue({"android.permission." + p for p in PERMISSIONS} <= permissions)
        services = app.findall("service")
        self.assertEqual(len(services), 2)
        self.assertTrue(all(s.get(ANDROID + "foregroundServiceType") == "mediaPlayback" for s in services))
        activity_source = (self.kotlin / "ZunoCastActivity.kt").read_text()
        self.assertIn("class ZunoCastActivity : FlutterFragmentActivity()", activity_source)
        self.assertIn("GoogleCastApi(messenger = messenger, activity = this)", activity_source)
        for method in ("onUserLeaveHint()", "onPause()", "onStop()", "onResume()", "onWindowFocus(hasFocus)"):
            self.assertEqual(activity_source.count("AppForeground." + method), 1)
        for name in NATIVE_FILES:
            self.assertTrue((self.kotlin / name).is_file(), name)
        gradle = (self.app / "android/app/build.gradle.kts").read_text()
        self.assertIn(f'applicationId = "{TEST_PACKAGE}"', gradle)
        self.assertIn("minSdk = 24", gradle)
        self.assertIn('signingConfig = signingConfigs.getByName("debug")', gradle)
        self.assertIn("play-services-cast-framework:", gradle)

    def test_second_preparation_is_identical(self):
        prepare(self.app)
        files = [p for p in (self.app / "android/app").rglob("*") if p.is_file()]
        before = {p: p.read_bytes() for p in files}
        prepare(self.app)
        self.assertEqual(before, {p: p.read_bytes() for p in files})

    def test_client_signing_input_stops_before_any_write(self):
        manifest = self.app / "android/app/src/main/AndroidManifest.xml"
        before = manifest.read_bytes()
        (self.app / "android/key.properties").write_text("# sentinelle synthétique, aucune clé\n")
        with self.assertRaisesRegex(ValueError, "key.properties"):
            prepare(self.app)
        self.assertEqual(manifest.read_bytes(), before)
        self.assertFalse((self.kotlin / "ZunoCastActivity.kt").exists())

    def test_future_overlay_lifecycle_change_requires_review(self):
        source = (APP / "android_overlay/google_cast/MainActivity.kt").read_text()
        source = source.replace("class MainActivity : FlutterFragmentActivity() {",
                                "class MainActivity : FlutterFragmentActivity() {\n    override fun onStop() {}")
        with self.assertRaisesRegex(ValueError, "onStop"):
            touch_activity(source, "com.example.tv_king")


if __name__ == "__main__":
    unittest.main()
