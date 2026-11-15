import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

KIT = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("patch_ui", KIT / "apply_ui_patch.py")
patch_ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch_ui)
MAINTENANCE = os.environ.get("NOVATUBE_MAINTENANCE")

@unittest.skipUnless(MAINTENANCE, "Owner maintenance archive required for source reproducibility checks")
class PatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.base = Path(MAINTENANCE)
        self.output = self.root / "patched"
    def tearDown(self): self.temp.cleanup()
    def apply(self): return patch_ui.patch_sources(self.base, self.output, KIT)
    def test_only_four_existing_sources_change(self):
        result = self.apply()
        self.assertEqual(set(result["changed_sources"]), {"AtlasAppearance.java", "DirectSources.java", "NovaTubeAtmosphere.java", "NovaTubeWelcome.java"})
    def test_authority_gateway_panel_and_catalogue_unchanged(self):
        result = self.apply()
        for name in result["immutable_sources"]:
            self.assertEqual((self.base / "src" / patch_ui.PACKAGE / name).read_bytes(),
                             (self.output / "src" / patch_ui.PACKAGE / name).read_bytes())
    def test_copies_no_signing_material(self):
        self.apply()
        self.assertEqual(set(p.name for p in self.output.iterdir()), {"src", "source-patch-report.json"})
    def test_refuses_overwrite(self):
        self.output.mkdir()
        with self.assertRaises(ValueError): self.apply()
    def test_refuses_wrong_source_version(self):
        bad = self.root / "bad"
        shutil.copytree(self.base / "src", bad / "src")
        path = bad / "src" / patch_ui.PACKAGE / "AtlasActivation.java"
        path.write_text(path.read_text() + "\n// different version\n")
        with self.assertRaises(ValueError): patch_ui.patch_sources(bad, self.output, KIT)
    def test_refuses_extra_injected_source(self):
        bad = self.root / "bad"
        shutil.copytree(self.base / "src", bad / "src")
        (bad / "src" / "Extra.java").write_text("class Extra {}")
        with self.assertRaises(ValueError): patch_ui.patch_sources(bad, self.output, KIT)
    def test_two_runs_identical(self):
        self.apply()
        other = self.root / "other"
        patch_ui.patch_sources(self.base, other, KIT)
        for path in (self.output / "src").rglob("*.java"):
            self.assertEqual(path.read_bytes(), (other / path.relative_to(self.output)).read_bytes())
    def test_welcome_has_no_player_or_network_api(self):
        self.apply()
        welcome = (self.output / "src" / patch_ui.PACKAGE / "NovaTubeWelcome.java").read_text()
        for forbidden in ("SurfaceView", "TextureView", "VideoView", "MediaCodec", "ExoPlayer", "setVideo", "getSharedPreferences", "java.net.", "setAlpha(", "setScale"):
            self.assertNotIn(forbidden, welcome)
        self.assertIn("showWelcomeEditor(activity, true)", welcome)
        self.assertIn("showWelcomeEditor(activity, false)", welcome)
        self.assertIn("AtlasActivation.openFromWelcome(activity)", welcome)
    def test_editor_persistence_and_network_tail_unchanged(self):
        self.apply()
        old = (self.base / "src" / patch_ui.PACKAGE / "DirectSources.java").read_text()
        new = (self.output / "src" / patch_ui.PACKAGE / "DirectSources.java").read_text()
        anchor = "        name.setNextFocusForwardId(url.getId());"
        self.assertEqual(old[old.index(anchor):], new[new.index(anchor):])
    def test_old_video_screen_exclusion_preserved(self):
        self.apply()
        old = (self.base / "src" / patch_ui.PACKAGE / "AtlasAppearance.java").read_text()
        new = (self.output / "src" / patch_ui.PACKAGE / "AtlasAppearance.java").read_text()
        anchor = "if (root == null || playbackActivity(activity) || containsVideo(root))"
        self.assertIn(anchor, old); self.assertIn(anchor, new)
        self.assertFalse((self.output / "source-patch-report.json").read_text().find('"compiled": false') < 0)

if __name__ == "__main__": unittest.main()
