"""Les ZIP de fixture vérifient l'inspection d'assets, pas un démarrage Android."""

import json
from pathlib import Path
import tempfile
import unittest
from zipfile import ZipFile

from verify_bundled_fonts import APP_ROOT, MANIFEST, checked_records, verify


class BundledFontEvidenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.manifest = json.loads((APP_ROOT / MANIFEST).read_bytes())

    def archive(self, *, missing=None, corrupted=None, duplicate=None):
        path = self.folder / "assets-fixture.zip"
        assets = [MANIFEST] + [record["asset"] for record in checked_records(self.manifest)]
        with ZipFile(path, "w") as archive:
            for asset in assets:
                if asset == missing:
                    continue
                data = (APP_ROOT / asset).read_bytes()
                if asset == corrupted:
                    data = data[:-1] + bytes([data[-1] ^ 1])
                archive.writestr(f"assets/flutter_assets/{asset}", data)
                if asset == duplicate:
                    # Un ZIP ambigu ne doit pas être accepté sous prétexte
                    # qu'une des deux entrées contient les bons octets.
                    archive.writestr(f"assets/flutter_assets/{asset}", data)
        return path

    def test_repository_bytes_and_inventory(self):
        result = verify()
        self.assertEqual(result["fonts"], 14)
        self.assertEqual(result["font_bytes"], 2388328)
        self.assertFalse(result["apk_assets_verified"])

    def test_archive_preserves_exact_font_and_license_bytes(self):
        result = verify(apk=self.archive())
        self.assertTrue(result["apk_assets_verified"])

    def test_missing_inter_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "APK absent"):
            verify(apk=self.archive(missing="assets/fonts/Inter-Regular.ttf"))

    def test_same_length_corruption_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "SHA-256 différent"):
            verify(apk=self.archive(corrupted="assets/fonts/Inter-Regular.ttf"))

    def test_missing_license_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "APK absent"):
            verify(apk=self.archive(missing="assets/fonts/licenses/Manrope-OFL.txt"))

    def test_duplicate_font_entry_is_rejected(self):
        with self.assertWarns(UserWarning):
            archive = self.archive(duplicate="assets/fonts/Inter-Regular.ttf")
        with self.assertRaisesRegex(ValueError, "APK absent ou dupliqué"):
            verify(apk=archive)

    def test_manifest_cannot_drop_a_variant(self):
        self.manifest["fonts"].pop()
        with self.assertRaisesRegex(ValueError, "14 variantes incomplet"):
            checked_records(self.manifest)


if __name__ == "__main__":
    unittest.main()
