#!/usr/bin/env python3
"""Refuser les mauvaises provenances et les écrans non chargés, sans appareil.

Ces tests vérifient les barrières du banc. Ils ne prétendent pas qu'une
capture Android ou une vidéo de service a été exécutée localement.
"""

import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET

from common import BUNDLETOOL_SHA256, BUNDLETOOL_VERSION, ENTRYPOINT, LABEL, PACKAGE, VERSION_CODE, VERSION_NAME, expected_certificate
from run_play_evidence import (
    BRANCH, HOME_KEYS, REPOSITORY, SOURCE_KEYS, png_dimensions, recognized_screen,
    runner_context, tap_target, validate_artifact,
)


class PlayEvidenceTest(unittest.TestCase):
    def setUp(self):
        owner = REPOSITORY.split("/", 1)[0]
        self.env = {
            "GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_REPOSITORY_OWNER": owner,
            "GITHUB_REF": "refs/heads/" + BRANCH, "GITHUB_ACTOR": owner,
            "GITHUB_TRIGGERING_ACTOR": owner, "GITHUB_SHA": "a" * 40,
            "REVIEWED_COMMIT": "a" * 40, "GITHUB_RUN_ID": "123456",
            "GITHUB_RUN_ATTEMPT": "2", "NOVATUBE_CAPTURE_CONFIRMATION": "COMPILER_NOVATUBE",
        }
        self.translations = {"en": {
            "tvNavLive": "Live", "tvNavFilms": "Movies", "tvNavSeries": "Series",
            "tvNavServer": "Server", "tvMySources": "My sources", "tvAddXtream": "Add Xtream",
            "tvAddM3u": "Add M3U", "tvSourcesEmpty": "No sources yet.\nAdd an M3U link.",
        }}

    def hierarchy(self, keys, package=PACKAGE):
        root = ET.Element("hierarchy")
        for key in keys:
            ET.SubElement(root, "node", {"package": package, "content-desc": self.translations["en"][key],
                          "bounds": "[20,30][200,130]", "enabled": "true"})
        return ET.tostring(root, encoding="unicode")

    def artifact(self, folder):
        filename = f"NOVATUBE-{VERSION_NAME}-{VERSION_CODE}.aab"
        data = b"fixture-for-metadata-guards-not-an-executable-app"
        (folder / filename).write_bytes(data)
        source = {"status": "passed", "sourceCommit": "a" * 40,
                  "buildTargets": {"play-aab": {"versionName": VERSION_NAME, "versionCode": int(VERSION_CODE)}}}
        context = runner_context(self.env)
        provenance = {
            "status": "verified", "package": PACKAGE, "label": LABEL,
            "versionName": VERSION_NAME, "versionCode": int(VERSION_CODE), "entrypoint": ENTRYPOINT,
            "testBuild": False, "source": source, "uploadCertificateSha256": expected_certificate()[1],
            "signing": "dedicated-novatube-upload-key", "bundletoolVersion": BUNDLETOOL_VERSION,
            "bundletoolSha256": BUNDLETOOL_SHA256, "sha256": hashlib.sha256(data).hexdigest(),
            "sizeBytes": len(data), "abis": ["armeabi-v7a", "arm64-v8a", "x86_64"],
            **{key: context[key] for key in ("runId", "runAttempt", "runUrl")},
        }
        (folder / "source-verification.json").write_text(json.dumps(source))
        (folder / "build-provenance.json").write_text(json.dumps(provenance))
        (folder / "SHA256SUMS.txt").write_text(provenance["sha256"] + "  " + filename + "\n")
        return provenance, context

    def test_runtime_guards_match_the_manual_play_job(self):
        self.assertEqual(runner_context(self.env)["sourceCommit"], "a" * 40)
        mutations = {
            "GITHUB_EVENT_NAME": "push", "GITHUB_REPOSITORY": "other/repo",
            "GITHUB_REF": "refs/heads/main", "GITHUB_ACTOR": "other",
            "GITHUB_TRIGGERING_ACTOR": "other", "REVIEWED_COMMIT": "b" * 40,
            "NOVATUBE_CAPTURE_CONFIRMATION": "PUBLIER_NOVATUBE_APK_PRIVE",
            "GITHUB_RUN_ATTEMPT": "", "NOVATUBE_UPLOAD_KEYSTORE_BASE64": "not-needed",
        }
        for name, value in mutations.items():
            with self.subTest(name=name), self.assertRaises(ValueError):
                runner_context({**self.env, name: value})

    def test_artifact_must_match_source_run_version_and_public_certificate(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            original, context = self.artifact(folder)
            validate_artifact(folder, context)
            mutations = {"runId": "999", "runAttempt": "1", "runUrl": "https://example.invalid/run",
                         "package": "com.other.app", "versionCode": 5, "versionName": "0.1.5",
                         "sha256": "0" * 64, "uploadCertificateSha256": "0" * 64,
                         "bundletoolSha256": "1" * 64, "testBuild": True}
            for name, value in mutations.items():
                with self.subTest(name=name), self.assertRaises(ValueError):
                    (folder / "build-provenance.json").write_text(json.dumps({**original, name: value}))
                    validate_artifact(folder, context)
            changed = copy.deepcopy(original)
            changed["source"]["sourceCommit"] = "b" * 40
            (folder / "build-provenance.json").write_text(json.dumps(changed))
            (folder / "source-verification.json").write_text(json.dumps(changed["source"]))
            with self.assertRaises(ValueError):
                validate_artifact(folder, context)

    def test_modified_aab_or_wrong_checksum_filename_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            _, context = self.artifact(folder)
            aab = folder / f"NOVATUBE-{VERSION_NAME}-{VERSION_CODE}.aab"
            aab.write_bytes(aab.read_bytes() + b"tampered")
            with self.assertRaises(ValueError):
                validate_artifact(folder, context)
            self.artifact(folder)
            checksum = folder / "SHA256SUMS.txt"
            checksum.write_text(checksum.read_text().replace(aab.name, "another.aab"))
            with self.assertRaises(ValueError):
                validate_artifact(folder, context)

    def test_loaded_home_and_sources_require_app_specific_labels(self):
        self.assertEqual(recognized_screen(self.hierarchy(HOME_KEYS), self.translations, "home"), "en")
        self.assertEqual(recognized_screen(self.hierarchy(SOURCE_KEYS), self.translations, "sources"), "en")
        self.assertIsNone(recognized_screen(self.hierarchy(HOME_KEYS[:2]), self.translations, "home"))
        self.assertIsNone(recognized_screen(self.hierarchy(HOME_KEYS, "com.other.app"), self.translations, "home"))
        self.assertIsNone(recognized_screen(self.hierarchy(HOME_KEYS), self.translations, "sources"))
        self.assertIsNone(recognized_screen('<hierarchy><node text="NOVATUBE"/></hierarchy>', self.translations, "home"))

    def test_navigation_uses_observed_visible_app_bounds(self):
        xml = self.hierarchy(HOME_KEYS)
        self.assertEqual(tap_target(xml, "Server", 1080, 1920), (110, 80))
        for bad in (xml.replace(PACKAGE, "com.other.app"), xml.replace('[20,30][200,130]', '[20,30][1200,130]'),
                    xml.replace('enabled="true"', 'enabled="false"')):
            with self.subTest(xml=bad), self.assertRaises(ValueError):
                tap_target(bad, "Server", 1080, 1920)

    def test_source_empty_label_accepts_literal_or_actual_newline(self):
        actual = self.hierarchy(SOURCE_KEYS)
        self.translations["en"]["tvSourcesEmpty"] = self.translations["en"]["tvSourcesEmpty"].replace("\n", "\\n")
        self.assertEqual(recognized_screen(actual, self.translations, "sources"), "en")
        literal = self.hierarchy(SOURCE_KEYS)
        self.translations["en"]["tvSourcesEmpty"] = self.translations["en"]["tvSourcesEmpty"].replace("\\n", "\n")
        self.assertEqual(recognized_screen(literal, self.translations, "sources"), "en")

    def test_screenshot_header_must_be_png_and_keep_device_dimensions(self):
        data = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 1080, 1920) + b"\x08\x06\0\0\0" + b"\0" * 4
        self.assertEqual(png_dimensions(data), (1080, 1920))
        with self.assertRaises(ValueError):
            png_dimensions(b"adb: device unavailable")


if __name__ == "__main__":
    unittest.main()
