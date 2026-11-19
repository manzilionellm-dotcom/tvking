"""Cas négatifs du contrôle ; ces fixtures ne simulent jamais un succès Android."""

import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from zipfile import ZipFile

from PIL import Image, ImageDraw
from verify_apk_startup import (
    CLIENT_CERT, PACKAGE, expected_identity, verify_archive, verify_background,
    verify_bytes, verify_crashes, verify_evidence, verify_metadata, verify_quit_dialog,
    verify_samples, verify_screen, verify_signature,
)


class ApkStartupEvidenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.apk = self.folder / "zuno-tv.apk"
        with ZipFile(self.apk, "w") as archive:
            archive.writestr("lib/x86_64/libapp.so", b"fixture, pas du code Android")
            archive.writestr("lib/x86_64/libflutter.so", b"fixture du moteur")
        self.environment = {
            "SOURCE_SHA": "a" * 40, "STARTUP_SOURCE_SHA": "a" * 40,
            "STARTUP_APK_SHA256": hashlib.sha256(self.apk.read_bytes()).hexdigest(),
            "STARTUP_APK_SIZE": str(self.apk.stat().st_size),
            "STARTUP_VERSION_NAME": "116", "STARTUP_VERSION_CODE": "1793700001",
            "STARTUP_APK_CERT": CLIENT_CERT,
            "GITHUB_RUN_ID": "41000000001", "STARTUP_BUILD_ATTEMPT": "1",
            "STARTUP_ARTIFACT_ID": "900000001", "STARTUP_ARTIFACT_DIGEST": "b" * 64,
        }
        self.expected = expected_identity(self.environment)
        self.badging = (
            f"package: name='{PACKAGE}' versionCode='1793700001' versionName='116'\n"
            "sdkVersion:'21'\nleanback-launchable-activity: name='example.MainActivity'\n"
        )
        self.signature = f"Verifies\nSigner #1 certificate SHA-256 digest: {CLIENT_CERT}\n"
        self.samples = "\n".join(f"{index}\t1234\tforeground" for index in range(15))
        self.screen = self.content_screen()
        self.xml = self.ui("Ajouter une playlist")
        self.dialog = self.ui("Stay", "Restart", "Exit")
        self.background = "mResumedActivity: ActivityRecord{abc u0 com.android.launcher/.Home t4}"

    @staticmethod
    def ui(*labels, package=PACKAGE, bounds="[0,0][160,100]"):
        return f'<hierarchy><node package="{package}" bounds="{bounds}">' + "".join(
            f'<node package="{package}" text="{label}" />' for label in labels) + '</node></hierarchy>'

    @staticmethod
    def encode(image):
        output = BytesIO()
        image.save(output, format="PNG")
        return output.getvalue()

    @classmethod
    def content_screen(cls):
        # Petite interface de fixture : fond sombre, titre et action dorée.
        # Elle teste le critère visuel, pas le rendu réel de l'APK Android.
        image = Image.new("RGB", (160, 100), (8, 10, 14))
        draw = ImageDraw.Draw(image)
        draw.text((28, 24), "ZUNO", fill=(240, 240, 240))
        draw.rectangle((22, 46, 138, 74), fill=(190, 150, 45))
        draw.text((30, 54), "ACTIVER", fill=(8, 10, 14))
        return cls.encode(image)

    def save_evidence(self):
        files = {
            "apk-identity.json": json.dumps(self.expected),
            "checker-sha.txt": self.expected["buildCommit"] + "\n",
            "apk-badging.txt": self.badging,
            "signature.txt": self.signature,
            "installed-package.txt": " versionCode=1793700001 minSdk=21\n versionName=116\n",
            "api.txt": "35\n", "connectivity.txt": "Active default network: none\n",
            "final-connectivity.txt": "Active default network: none\n",
            "crash.txt": "", "logcat.txt": "ActivityManager: Displayed " + PACKAGE,
            "quit-dialog.xml": self.dialog, "after-back.txt": self.background,
        }
        for name, value in files.items():
            (self.folder / name).write_text(value)
        (self.folder / "after-back.png").write_bytes(self.screen)
        (self.folder / "quit-dialog.png").write_bytes(self.screen)
        for phase in ("cold", "reopen"):
            directory = self.folder / phase
            directory.mkdir(exist_ok=True)
            (directory / "samples.tsv").write_text(self.samples)
            (directory / "ui.xml").write_text(self.xml)
            (directory / "screen.png").write_bytes(self.screen)

    def test_build_identity_requires_every_output_and_the_same_source(self):
        self.assertEqual(self.expected["artifactId"], 900000001)
        for key in self.environment:
            with self.subTest(absent=key), self.assertRaises(ValueError):
                expected_identity({k: value for k, value in self.environment.items() if k != key})
        invalid = {
            "SOURCE_SHA": "c" * 40, "STARTUP_SOURCE_SHA": "short",
            "STARTUP_ARTIFACT_ID": "0", "STARTUP_ARTIFACT_DIGEST": "inconnu",
            "STARTUP_APK_SHA256": "115", "STARTUP_APK_SIZE": "-1",
            "STARTUP_APK_CERT": "d" * 64, "STARTUP_VERSION_CODE": "0",
        }
        for key, value in invalid.items():
            with self.subTest(invalid=key), self.assertRaises(ValueError):
                expected_identity(dict(self.environment, **{key: value}))

    def test_the_accepted_archive_is_pinned_to_the_build_bytes(self):
        self.assertEqual(verify_archive(self.apk, self.expected), self.expected)
        original = self.apk.read_bytes()
        for changed in (original + b"extra", bytes([original[0] ^ 1]) + original[1:]):
            self.apk.write_bytes(changed)
            with self.assertRaises(ValueError):
                verify_archive(self.apk, self.expected)

    def test_rerun_of_only_startup_does_not_change_the_build_attempt(self):
        retried = expected_identity(dict(self.environment, GITHUB_RUN_ATTEMPT="2"))
        self.assertEqual(retried["buildAttempt"], 1)
        self.assertEqual(retried, self.expected)

    def test_a_missing_emulator_abi_is_rejected_even_with_the_correct_digest(self):
        with ZipFile(self.apk, "w") as archive:
            archive.writestr("lib/arm64-v8a/libapp.so", b"fixture")
        self.expected.update(size=self.apk.stat().st_size,
                             sha256=hashlib.sha256(self.apk.read_bytes()).hexdigest())
        with self.assertRaises(ValueError):
            verify_archive(self.apk, self.expected)

    def test_wrong_package_version_min_sdk_or_launcher_is_rejected(self):
        verify_metadata(self.badging, self.expected)
        for original, replacement in (
            (PACKAGE, PACKAGE + ".essai"), ("1793700001", "1793700002"),
            ("versionName='116'", "versionName='115'"), ("sdkVersion:'21'", "sdkVersion:'24'"),
            ("leanback-launchable-activity:", "launchable-activity:"),
        ):
            with self.subTest(field=original), self.assertRaises(ValueError):
                verify_metadata(self.badging.replace(original, replacement), self.expected)

    def test_only_a_verified_client_signature_is_accepted(self):
        verify_signature(self.signature, self.expected)
        for changed in (
            self.signature.replace(CLIENT_CERT, "e" * 64),
            self.signature.replace("Verifies", "DOES NOT VERIFY"),
            "Verifies\n", self.signature + f"Signer #2 certificate SHA-256 digest: {CLIENT_CERT}\n",
        ):
            with self.subTest(signature=changed), self.assertRaises(ValueError):
                verify_signature(changed, self.expected)

    def test_publisher_byte_check_also_accepts_the_exact_phone_file(self):
        phone = self.folder / "zuno-essai.apk"
        phone.write_bytes(b"fixture du binaire telephone, aucun scenario box")
        digest = hashlib.sha256(phone.read_bytes()).hexdigest()
        verify_bytes(phone, digest, phone.stat().st_size)
        with self.assertRaises(ValueError):
            verify_bytes(phone, self.expected["sha256"], phone.stat().st_size)

    def test_missing_samples_or_a_restarted_process_are_rejected(self):
        verify_samples(self.samples)
        for changed in (self.samples.split("\n", 1)[1], self.samples.replace("7\t1234", "7\t9876"),
                        self.samples.replace("foreground", "background", 1)):
            with self.assertRaises(ValueError):
                verify_samples(changed)

    def test_splash_version_label_or_other_app_are_not_an_open_zuno_screen(self):
        verify_screen(self.xml, self.screen, self.expected)
        for xml in (self.ui("Zuno", "116"), self.ui("Accueil", package="com.android.launcher")):
            with self.assertRaises(ValueError):
                verify_screen(xml, self.screen, self.expected)

    def test_truncated_or_corrupted_png_does_not_prove_a_visible_screen(self):
        for image in (self.screen[:40], self.screen[:-1], self.screen[:-1] + b"\1"):
            with self.assertRaises(ValueError):
                verify_screen(self.xml, image, self.expected)

    def test_accessible_labels_do_not_validate_black_or_other_uniform_surfaces(self):
        for color in ((0, 0, 0), (255, 255, 255), (30, 55, 90)):
            image = self.encode(Image.new("RGB", (160, 100), color))
            with self.subTest(color=color), self.assertRaisesRegex(ValueError, "noire ou uniforme"):
                verify_screen(self.xml, image, self.expected)
        proof = verify_screen(self.xml, self.screen, self.expected)
        self.assertGreaterEqual(proof["pixels"]["peakRange"], 16)
        self.assertGreaterEqual(proof["pixels"]["maximumStandardDeviation"], 2)

    def test_system_bars_cannot_make_a_black_application_look_open(self):
        image = Image.new("RGB", (160, 100), (0, 0, 0))
        draw = ImageDraw.Draw(image)
        # Ces barres empiètent volontairement sur la marge : les rectangles
        # com.android.systemui doivent être exclus, pas seulement l'écran rogné.
        draw.rectangle((0, 0, 159, 24), fill=(70, 70, 70))
        draw.text((4, 6), "12:00  WiFi", fill=(255, 255, 255))
        draw.rectangle((0, 70, 159, 99), fill=(55, 55, 55))
        draw.rectangle((55, 80, 105, 83), fill=(255, 255, 255))
        system = ('<node package="com.android.systemui" bounds="[0,0][160,25]" />'
                  '<node package="com.android.systemui" bounds="[0,70][160,100]" />')
        xml = self.xml.replace("</hierarchy>", system + "</hierarchy>")
        with self.assertRaisesRegex(ValueError, "noire ou uniforme"):
            verify_screen(xml, self.encode(image), self.expected)

    def test_missing_app_bounds_or_a_transparent_surface_is_not_visible_content(self):
        with self.assertRaisesRegex(ValueError, "Limites"):
            verify_screen(self.ui("Activation", bounds=""), self.screen, self.expected)
        image = Image.open(BytesIO(self.screen)).convert("RGBA")
        image.putalpha(0)
        with self.assertRaisesRegex(ValueError, "noire ou uniforme"):
            verify_screen(self.xml, self.encode(image), self.expected)

    def test_quit_requires_the_real_dialog_then_leaving_the_foreground(self):
        verify_quit_dialog(self.dialog)
        verify_quit_dialog(self.ui("Continuer", "Redémarrer", "Quitter"))
        verify_background(self.background)
        for xml in (self.ui("Stay", "Restart"), self.ui("Stay", "Restart", "Exit", package="other")):
            with self.assertRaises(ValueError):
                verify_quit_dialog(xml)
        for text in ("", "mResumedActivity: " + PACKAGE + "/.MainActivity",
                     "mResumedActivity: null", "topResumedActivity=null"):
            with self.assertRaises(ValueError):
                verify_background(text)
        # Le processus et une entrée non reprise de l'activité peuvent subsister.
        verify_background(self.background + "\nHist #0: " + PACKAGE + "/.MainActivity")

    def test_app_crash_or_anr_is_rejected(self):
        verify_crashes("", "ActivityManager: Displayed " + PACKAGE + "/.MainActivity")
        with self.assertRaises(ValueError):
            verify_crashes("FATAL EXCEPTION: main\nProcess: " + PACKAGE, "")
        with self.assertRaises(ValueError):
            verify_crashes("", "ActivityManager: ANR in " + PACKAGE)

    def test_complete_evidence_contract_has_both_phases_and_exact_identity(self):
        self.save_evidence()
        proof = verify_evidence(self.folder, self.expected)
        self.assertTrue(proof["leftForegroundBeforeReopen"])
        self.assertEqual(set(proof["phases"]), {"cold", "reopen"})
        self.assertEqual(proof["apk"], self.expected)

    def test_stale_identity_connected_network_or_missing_reopen_cannot_pass(self):
        self.save_evidence()
        changes = {
            "apk-identity.json": json.dumps(dict(self.expected, artifactId=1)),
            "checker-sha.txt": "c" * 40,
            "installed-package.txt": "versionCode=1793700000\nversionName=115\n",
            "final-connectivity.txt": "Active default network: 100",
            "after-back.txt": "mResumedActivity: " + PACKAGE + "/.MainActivity",
            "reopen/samples.tsv": self.samples.split("\n", 1)[1],
        }
        for name, value in changes.items():
            file = self.folder / name
            original = file.read_text()
            file.write_text(value)
            with self.subTest(evidence=name), self.assertRaises(ValueError):
                verify_evidence(self.folder, self.expected)
            file.write_text(original)
        (self.folder / "reopen" / "screen.png").unlink()
        with self.assertRaises(FileNotFoundError):
            verify_evidence(self.folder, self.expected)

    def bash_function(self, name, commands, mocks):
        script = Path(__file__).with_name("run-apk-startup.sh").read_text()
        definition = re.search(rf"^{name}\(\) \{{\n.*?^\}}", script, re.M | re.S).group()
        return subprocess.run(
            ["bash", "-c", 'set -Eeuo pipefail\nstartup_serial=fixture\n'
             'startup_out="$TEST_OUTPUT"\n' + mocks + "\n" + definition + "\n" + commands],
            env=dict(os.environ, TEST_OUTPUT=str(self.folder)), text=True, capture_output=True)

    def test_uiautomator_success_without_a_new_file_cannot_reuse_stale_labels(self):
        # Le vrai DumpCommand Android peut sortir 0 sans écrire de fichier.
        # L'ancienne version du helper aurait récupéré le XML précédent.
        result = self.bash_function("startup_dump_ui", 'startup_dump_ui "$startup_out/ui.xml"', r'''
startup_fake_xml_present=true
timeout() { shift; "$@"; }
adb() {
  case "$3 $4" in
    "shell rm") startup_fake_xml_present=false ;;
    "shell uiautomator") return 0 ;;
    "shell test") test "$startup_fake_xml_present" = true ;;
    "pull /sdcard/zuno-startup.xml") printf 'stale' > "$startup_out/stale-pulled" ;;
    *) return 1 ;;
  esac
}
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.folder / "stale-pulled").exists())

    def test_failed_log_collection_stops_before_a_pass_can_be_written(self):
        result = self.bash_function(
            "startup_collect", 'startup_collect\nprintf passed > "$startup_out/false-pass"', r'''
adb() {
  if [[ "$3" == get-state ]]; then return 0; fi
  if [[ "$3" == logcat ]]; then printf 'adb: device offline\n'; return 1; fi
  return 0
}
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.folder / "false-pass").exists())


if __name__ == "__main__":
    unittest.main()
