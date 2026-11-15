import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

spec = importlib.util.spec_from_file_location("video_guard", Path(__file__).parents[1] / "tools/video_guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

class VideoGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.entries = {"classes.dex": b"ORIGINAL-PLAYER", "classes2.dex": b"OLD-UI",
                        "AndroidManifest.xml": b"UNCHANGED-PERMISSIONS-IDENTITY",
                        "resources.arsc": b"ORIGINAL-RESOURCE-TABLE",
                        "lib/armeabi-v7a/libplayer.so": b"ORIGINAL-NATIVE",
                        "res/layout/player.xml": b"ORIGINAL-SURFACE",
                        "META-INF/CERT.RSA": b"SIGNATURE"}
        self.base = self.write("base.apk", self.entries)
        self.lock = guard.freeze(self.base, require_known_base=False)

    def tearDown(self): self.tmp.cleanup()

    def write(self, name, entries):
        path = self.root / name
        with zipfile.ZipFile(path, "w") as z:
            for key, value in entries.items(): z.writestr(key, value)
        return path

    def verify(self, changes=None, remove=()):
        entries = dict(self.entries)
        entries.update(changes or {})
        for name in remove: entries.pop(name)
        return guard.verify(self.lock, self.write("candidate.apk", entries))

    def test_accepts_identical_archive(self): self.assertTrue(self.verify()["ok"])
    def test_allows_secondary_dex(self): self.assertTrue(self.verify({"classes2.dex": b"REVIEWED-UI"})["ok"])
    def test_allows_signature_replacement_only(self): self.assertTrue(self.verify({"META-INF/CERT.RSA": b"NEW-SIGNATURE"})["ok"])
    def test_rejects_native_change(self): self.assertFalse(self.verify({"lib/armeabi-v7a/libplayer.so": b"CHANGED"})["ok"])
    def test_rejects_primary_dex_change(self): self.assertFalse(self.verify({"classes.dex": b"CHANGED"})["ok"])
    def test_rejects_surface_layout_change(self): self.assertFalse(self.verify({"res/layout/player.xml": b"TEXTUREVIEW"})["ok"])
    def test_rejects_manifest_change(self): self.assertFalse(self.verify({"AndroidManifest.xml": b"NEW-PACKAGE"})["ok"])
    def test_rejects_resource_table_change(self): self.assertFalse(self.verify({"resources.arsc": b"CHANGED"})["ok"])
    def test_rejects_missing_dex(self): self.assertFalse(self.verify(remove=("classes.dex",))["ok"])
    def test_rejects_missing_secondary_dex(self): self.assertFalse(self.verify(remove=("classes2.dex",))["ok"])
    def test_rejects_extra_decoder(self): self.assertFalse(self.verify({"lib/arm64-v8a/libplayer.so": b"NEW"})["ok"])
    def test_rejects_extra_dex(self): self.assertFalse(self.verify({"classes3.dex": b"NEW"})["ok"])
    def test_rejects_non_signature_meta_inf_change(self): self.assertFalse(self.verify({"META-INF/injected.dex": b"CODE"})["ok"])
    def test_rejects_duplicate_zip_names(self):
        path = self.write("duplicate.apk", self.entries)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            with zipfile.ZipFile(path, "a") as z: z.writestr("classes.dex", b"HIDDEN")
        with self.assertRaises(ValueError): guard.verify(self.lock, path)
    def test_rejects_wrong_real_base(self):
        with self.assertRaises(ValueError): guard.freeze(self.base)
    def test_rejects_weakened_lock(self):
        lock = dict(self.lock); lock["mutable_entries"] = ["classes.dex", "classes2.dex"]
        with self.assertRaises(ValueError): guard.verify(lock, self.base)

if __name__ == "__main__": unittest.main()
