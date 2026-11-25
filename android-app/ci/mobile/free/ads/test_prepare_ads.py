import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

from prepare_ads import ANDROID, PACKAGE, TEST_APP, TEST_BANNER, configured_ids, install_android


class AdMobBuildTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.project = Path(tmp.name)
        self.module = self.project / "android/app"
        self.kotlin = self.module / "src/main/kotlin/custom"
        self.kotlin.mkdir(parents=True)
        self.gradle = self.module / "build.gradle.kts"
        self.gradle.write_text(f'    applicationId = "{PACKAGE}"\n')
        self.activity = self.kotlin / "MainActivity.kt"
        self.activity.write_text("package com.generated.phone\nclass MainActivity {\n"
                                 "        super.configureFlutterEngine(flutterEngine)\n}\n")
        self.manifest = self.module / "src/main/AndroidManifest.xml"
        self.manifest.write_text('<manifest><application/></manifest>')

    def test_no_configuration_leaves_no_sdk(self):
        install_android(self.project, configured_ids({}))
        self.assertNotIn("play-services-ads", self.gradle.read_text())
        self.assertFalse((self.kotlin / "SevenMotionAds.kt").exists())

    def test_partial_mixed_and_sample_ids_cannot_leak_into_production(self):
        app = "ca-app-pub-1111111111111111~0000000000"
        for banner in ("", "ca-app-pub-2222222222222222/0000000000"):
            with self.assertRaises(ValueError):
                configured_ids({"SEVEN_ADMOB_APP_ID": app, "SEVEN_ADMOB_BANNER_ID": banner})
        with self.assertRaises(ValueError):
            configured_ids({"SEVEN_ADMOB_APP_ID": TEST_APP, "SEVEN_ADMOB_BANNER_ID": TEST_BANNER})
        with self.assertRaises(ValueError):
            configured_ids({"SEVEN_ADMOB_APP_ID": app, "SEVEN_ADMOB_TEST_ADS": "true"})

    def test_cannot_instrument_another_listing(self):
        self.gradle.write_text('applicationId = "com.sevenmotion.tv.seven_tv"')
        with self.assertRaises(ValueError):
            install_android(self.project, (TEST_APP, TEST_BANNER))
        self.assertFalse((self.kotlin / "SevenMotionAds.kt").exists())

    def test_install_identifiers_bridge_and_deps_once(self):
        ids = configured_ids({"SEVEN_ADMOB_TEST_ADS": "true"})
        self.assertEqual(ids, (TEST_APP, TEST_BANNER))
        install_android(self.project, ids)
        install_android(self.project, ids)
        self.assertEqual(self.gradle.read_text().count("play-services-ads:"), 1)
        self.assertEqual(self.activity.read_text().count("SevenMotionAds(this, flutterEngine)"), 1)
        bridge = (self.kotlin / "SevenMotionAds.kt").read_text()
        self.assertIn("package com.generated.phone", bridge)
        self.assertIn(TEST_BANNER, bridge)
        app = ET.parse(self.manifest).getroot().find("application")
        meta = {x.get(ANDROID + "name"): x.get(ANDROID + "value") for x in app}
        self.assertEqual(meta["com.google.android.gms.ads.APPLICATION_ID"], TEST_APP)
        self.assertEqual(meta["com.google.android.gms.ads.DELAY_APP_MEASUREMENT_INIT"], "true")
        with self.assertRaises(ValueError):
            install_android(self.project, None)


if __name__ == "__main__":
    unittest.main()
