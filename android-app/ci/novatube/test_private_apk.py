#!/usr/bin/env python3
"""Régressions locales : aucun appel GitHub réel, aucun téléchargement réel."""

import base64
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from common import BRANCH, PACKAGE, expected_certificate, sha256_file
from recording_device_evidence import TEST_CLASS, TEST_METHODS
from publish_private_apk import (
    API_ROOT, MANIFEST_PATH, checked_context, load_verified, publish, verify_public_download,
)
from verify_private_apk import (
    ABIS, REPOSITORY, apk_abis, apk_identity, evidence_results, verify_apk_signature, verify_sdk_versions,
)

SOURCE = "2" * 40
CERTIFICATE = expected_certificate()[1]
ENVIRONMENT = {
    "GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
    "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_REF": "refs/heads/" + BRANCH,
    "GITHUB_SHA": SOURCE, "GITHUB_RUN_ID": "200", "GITHUB_RUN_ATTEMPT": "1",
    "REVIEWED_COMMIT": SOURCE, "NOVATUBE_PUBLICATION_CONFIRMATION": "PUBLIER_NOVATUBE_APK_PRIVE",
}
BADGING = """package: name='com.sevenmotion.novatube' versionCode='5' versionName='0.1.5'
sdkVersion:'24'
targetSdkVersion:'36'
application-label:'NOVATUBE'
launchable-activity: name='com.sevenmotion.novatube.NovatubeActivity' label='NOVATUBE'
uses-permission: name='android.permission.USE_BIOMETRIC'
"""


def write_json(path, data):
    path.write_text(json.dumps(data) + "\n", encoding="utf-8")


def checksums(directory):
    (directory / "SHA256SUMS.txt").write_text("".join(
        sha256_file(path) + "  " + path.name + "\n"
        for path in sorted(directory.iterdir()) if path.name != "SHA256SUMS.txt"), encoding="ascii")


def fixture(directory):
    write_json(directory / "source-verification.json", {
        "status": "passed", "sourceCommit": SOURCE, "sourceTree": "3" * 40,
        "privateApkWorkflowVerified": True,
        "pubspecVersion": "0.1.6+6",
        "buildTargets": {
            "play-aab": {"versionName": "0.1.6", "versionCode": 6},
            "private-apk": {"versionName": "0.1.5", "versionCode": 5},
        },
    })
    write_json(directory / "flutter-toolchain.json", {"frameworkVersion": "3.47.7"})
    for name in ("flutter-tests.jsonl", "flutter-tests-private.jsonl"):
        (directory / name).write_text(
            '{"type":"testDone","result":"success","skipped":false}\n'
            '{"type":"done","success":true}\n', encoding="utf-8")
    (directory / "flutter-analyze.txt").write_text("Analyzing…\nNo issues found!\n", encoding="utf-8")
    (directory / "native-jvm-tests.txt").write_text("OK (10 tests)\n", encoding="utf-8")
    (directory / "recording-native-tests.txt").write_text("OK (2 tests)\n", encoding="utf-8")
    (directory / "static-tests.txt").write_text("Ran 2 tests in 0.001s\n\nOK\n", encoding="utf-8")
    artifact = "NOVATUBE-" + SOURCE + ".apk"
    (directory / artifact).write_bytes(b"fixture APK already verified by the preceding job")
    device_log = "".join(
        f"INSTRUMENTATION_STATUS: class={TEST_CLASS}\nINSTRUMENTATION_STATUS: test={name}\n"
        "INSTRUMENTATION_STATUS_CODE: 0\n" for name in TEST_METHODS
    ) + "OK (3 tests)\nINSTRUMENTATION_CODE: -1\n"
    (directory / "recording-device-tests.txt").write_text(device_log, encoding="utf-8")
    write_json(directory / "recording-device-tests.json", {
        "status": "passed", "platform": "Android Emulator AOSP", "apiLevel": 35,
        "physicalDevice": False, "sourceCommit": SOURCE, "passed": 3,
        "apkSha256": sha256_file(directory / artifact),
        "reportSha256": sha256_file(directory / "recording-device-tests.txt"),
    })
    proof = {
        "status": "passed", "artifact": artifact, "package": PACKAGE, "versionName": "0.1.5",
        "versionCode": 5, "distribution": "private-apk", "branch": BRANCH,
        "repository": REPOSITORY, "sourceCommit": SOURCE, "sourceTree": "3" * 40,
        "runId": "200", "runAttempt": "1", "uploadCertificateSha256": CERTIFICATE,
        "releaseSignatureVerified": True, "debuggable": False, "testOnly": False,
        "biometricPermissionVerified": True, "googleUpload": False, "publishedToGooglePlay": False,
        "sha256": sha256_file(directory / artifact), "sizeBytes": (directory / artifact).stat().st_size,
        "tests": evidence_results(directory, SOURCE)["tests"],
    }
    write_json(directory / "apk-verification.json", proof)
    write_json(directory / "build-provenance.json", {**proof, "status": "verified"})
    checksums(directory)
    return proof


class FakeGitHub:
    def __init__(self, proof):
        self.proof = proof
        self.events = []
        self.pointer = {
            "schemaVersion": 1, "status": "verified", "package": PACKAGE,
            "distribution": "private-apk", "uploadCertificateSha256": CERTIFICATE,
            "sourceCommit": "1" * 40, "sha256": "a" * 64, "runId": None,
        }
        self.original = deepcopy(self.pointer)
        self.blob = "b" * 40
        self.comparison = "ahead"
        self.asset = None
        self.fail_cas = False

    def release(self):
        return {"id": 7, "tag_name": "novatube-private-" + SOURCE, "draft": False, "prerelease": True}

    def expected_asset(self):
        name = self.proof["artifact"]
        return {"name": name, "size": self.proof["sizeBytes"], "state": "uploaded",
                "digest": "sha256:" + self.proof["sha256"],
                "browser_download_url": f"https://github.com/{REPOSITORY}/releases/download/novatube-private-{SOURCE}/{name}"}

    def request(self, method, endpoint, *, body=None, upload=None, allow_missing=False):
        self.events.append((method, endpoint, body))
        if method == "GET" and endpoint == API_ROOT:
            return {"full_name": REPOSITORY, "private": False}
        if method == "GET" and "/contents/" in endpoint:
            return {"type": "file", "encoding": "base64", "sha": self.blob,
                    "content": base64.b64encode(json.dumps(self.pointer).encode()).decode()}
        if method == "GET" and "/compare/" in endpoint:
            return {"status": self.comparison}
        if method == "GET" and "/git/ref/heads/" in endpoint:
            return {"object": {"type": "commit", "sha": SOURCE}}
        if method == "GET" and "/git/ref/tags/" in endpoint:
            return {"object": {"type": "commit", "sha": SOURCE}} if self.asset else None
        if method == "POST" and endpoint.endswith("/git/refs"):
            return {"object": {"type": "commit", "sha": body["sha"]}}
        if method == "GET" and "/releases/tags/" in endpoint:
            return self.release() if self.asset else None
        if method == "POST" and endpoint.endswith("/releases"):
            return self.release()
        if method == "GET" and "/assets?" in endpoint:
            return [self.asset] if self.asset else []
        if method == "POST" and endpoint.startswith("https://uploads.github.com/"):
            return self.expected_asset()
        if method == "PUT" and endpoint == API_ROOT + "/contents/" + MANIFEST_PATH:
            if self.fail_cas or body["sha"] != self.blob:
                raise ValueError("Conflit CAS simulé : pointeur inchangé")
            if body["branch"] != BRANCH:
                raise AssertionError("Écriture hors branche NOVATUBE")
            self.pointer = json.loads(base64.b64decode(body["content"]))
            return {"content": {"sha": "c" * 40}}
        raise AssertionError((method, endpoint))


class ApkValidationTest(unittest.TestCase):
    def test_identity_and_sdk_are_verified(self):
        self.assertEqual(apk_identity(BADGING, "N: android\n")["minSdk"], 24)

    def test_wrong_identity_or_missing_biometric_permission_is_rejected(self):
        for old, new in ((PACKAGE, "com.example.zuno"), ("versionCode='5'", "versionCode='6'"),
                         ("versionName='0.1.5'", "versionName='0.1.6'"),
                         ("application-label:'NOVATUBE'", "application-label:'ZUNO'"),
                         ("android.permission.USE_BIOMETRIC", "android.permission.INTERNET")):
            with self.subTest(old=old), self.assertRaises(ValueError):
                apk_identity(BADGING.replace(old, new), "")

    def test_sdk_missing_duplicate_or_wrong_value_is_rejected(self):
        for text in (BADGING.replace("sdkVersion:'24'\n", ""),
                     BADGING + "minSdkVersion:'24'\n", BADGING.replace("'36'", "'35'")):
            with self.assertRaises(ValueError):
                verify_sdk_versions(text)

    def test_native_debug_test_flags_are_rejected(self):
        for flag in ("debuggable", "testOnly"):
            with self.subTest(flag=flag), self.assertRaises(ValueError):
                apk_identity(BADGING, f"A: android:{flag}(0x0101000f)=(type 0x12)0xffffffff\n")

    def test_signature_must_have_exactly_the_novatube_certificate(self):
        good = "Signer #1 certificate SHA-256 digest: " + CERTIFICATE + "\n"
        verify_apk_signature(good, CERTIFICATE)
        for text in ("", good + good.replace("#1", "#2"), good.replace(CERTIFICATE, "a" * 64)):
            with self.assertRaises(ValueError):
                verify_apk_signature(text, CERTIFICATE)

    def test_all_three_flutter_abis_are_required(self):
        with tempfile.TemporaryDirectory() as name:
            apk = Path(name) / "fixture.apk"
            for abis in (ABIS, ABIS[:2]):
                with zipfile.ZipFile(apk, "w") as archive:
                    for member in ("AndroidManifest.xml", "classes.dex"):
                        archive.writestr(member, b"fixture")
                    for abi in abis:
                        for library in ("libapp.so", "libflutter.so"):
                            archive.writestr(f"lib/{abi}/{library}", b"fixture")
                if abis == ABIS:
                    self.assertEqual(apk_abis(apk), ABIS)
                else:
                    with self.assertRaises(ValueError):
                        apk_abis(apk)


class PublicationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.proof = fixture(self.directory)
        self.github = FakeGitHub(self.proof)

    def run_publish(self, download=None, environment=None):
        if download is None:
            def download(url, digest, size):
                self.github.events.append(("DOWNLOAD", url, None))
                self.assertEqual((digest, size), (self.proof["sha256"], self.proof["sizeBytes"]))
        return publish(self.directory, environment=environment or ENVIRONMENT,
                       github=self.github, download=download)

    def test_public_hash_check_precedes_atomic_pointer_update(self):
        result = self.run_publish()
        self.assertEqual(self.github.events[-2][0], "DOWNLOAD")
        self.assertEqual(self.github.events[-1][0], "PUT")
        self.assertEqual(self.github.events[-1][2]["sha"], self.github.blob)
        self.assertEqual(result, self.github.pointer)
        release = next(body for method, endpoint, body in self.github.events
                       if method == "POST" and endpoint.endswith("/releases"))
        self.assertEqual(release["make_latest"], "false")
        self.assertTrue(release["prerelease"])

    def test_modified_apk_prevents_every_network_action(self):
        (self.directory / self.proof["artifact"]).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "modifié"):
            self.run_publish()
        self.assertEqual(self.github.events, [])

    def test_play_version_cannot_replace_private_source_provenance(self):
        path = self.directory / "source-verification.json"
        source = json.loads(path.read_text())
        source["buildTargets"]["private-apk"] = {"versionName": "0.1.6", "versionCode": 6}
        write_json(path, source)
        checksums(self.directory)
        with self.assertRaisesRegex(ValueError, "Version privée"):
            self.run_publish()
        self.assertEqual(self.github.events, [])

    def test_failed_verification_cannot_be_published_even_with_valid_checksums(self):
        write_json(self.directory / "apk-verification.json", {**self.proof, "status": "failed"})
        checksums(self.directory)
        with self.assertRaisesRegex(ValueError, "non réussi"):
            self.run_publish()
        self.assertEqual(self.github.events, [])

    def test_missing_or_failed_private_tests_are_fatal(self):
        path = self.directory / "flutter-tests-private.jsonl"
        path.write_text('{"type":"done","success":false}\n', encoding="utf-8")
        checksums(self.directory)
        with self.assertRaises(ValueError):
            self.run_publish()
        self.assertEqual(self.github.events, [])

    def test_skipped_tests_are_not_a_complete_validation(self):
        path = self.directory / "flutter-tests-private.jsonl"
        path.write_text(path.read_text().replace('"skipped":false', '"skipped":true'), encoding="utf-8")
        checksums(self.directory)
        with self.assertRaisesRegex(ValueError, "ignorée"):
            self.run_publish()

    def test_failed_recording_export_rules_prevent_publication(self):
        path = self.directory / "recording-native-tests.txt"
        path.write_text("OK (2 tests)\nFAILURES!!!\n", encoding="utf-8")
        checksums(self.directory)
        with self.assertRaisesRegex(ValueError, "Échec JVM"):
            self.run_publish()
        self.assertEqual(self.github.events, [])

    def test_another_apk_cannot_reuse_successful_android_export_tests(self):
        path = self.directory / "recording-device-tests.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        report["apkSha256"] = "0" * 64
        write_json(path, report)
        checksums(self.directory)
        with self.assertRaisesRegex(ValueError, "testé sur Android"):
            self.run_publish()
        self.assertEqual(self.github.events, [])

    def test_unhashed_extra_file_is_rejected(self):
        (self.directory / "extra.txt").write_text("unreviewed", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "non couvert"):
            self.run_publish()

    def test_wrong_branch_repository_confirmation_or_run_is_rejected(self):
        for key, value in (("GITHUB_REF", "refs/heads/main"), ("GITHUB_REPOSITORY", "other/app"),
                           ("NOVATUBE_PUBLICATION_CONFIRMATION", "COMPILER_NOVATUBE"),
                           ("REVIEWED_COMMIT", "0" * 40), ("GITHUB_RUN_ID", "199")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.run_publish(environment={**ENVIRONMENT, key: value})
        self.assertEqual(self.github.events, [])

    def test_older_run_cannot_replace_a_newer_pointer(self):
        self.github.pointer["runId"] = "201"
        original = deepcopy(self.github.pointer)
        with self.assertRaisesRegex(ValueError, "ancien run"):
            self.run_publish()
        self.assertEqual(self.github.pointer, original)
        self.assertFalse(any(method != "GET" for method, _, _ in self.github.events))

    def test_older_or_diverging_source_cannot_replace_pointer(self):
        for status in ("behind", "diverged"):
            self.github.comparison = status
            with self.subTest(status=status), self.assertRaisesRegex(ValueError, "récente ou divergente"):
                self.run_publish()
        self.assertEqual(self.github.pointer, self.github.original)
        self.assertFalse(any(method != "GET" for method, _, _ in self.github.events))

    def test_same_commit_with_different_apk_is_rejected(self):
        self.github.pointer["sourceCommit"] = SOURCE
        with self.assertRaisesRegex(ValueError, "APK différent"):
            self.run_publish()
        self.assertFalse(any(method != "GET" for method, _, _ in self.github.events))

    def test_retry_reuses_identical_asset_without_overwriting(self):
        self.github.pointer.update(sourceCommit=SOURCE, sha256=self.proof["sha256"], runId="200")
        self.github.asset = self.github.expected_asset()
        self.run_publish()
        self.assertFalse(any(method == "POST" for method, _, _ in self.github.events))

    def test_existing_asset_with_different_digest_is_never_replaced(self):
        self.github.asset = {**self.github.expected_asset(), "digest": "sha256:" + "a" * 64}
        with self.assertRaisesRegex(ValueError, "Empreinte de l'asset"):
            self.run_publish()
        self.assertEqual(self.github.pointer, self.github.original)
        self.assertFalse(any(method != "GET" for method, _, _ in self.github.events))

    def test_failed_public_download_leaves_old_pointer(self):
        def refused(*_):
            raise ValueError("Hash public différent")
        with self.assertRaisesRegex(ValueError, "Hash public"):
            self.run_publish(download=refused)
        self.assertEqual(self.github.pointer, self.github.original)
        self.assertFalse(any(method == "PUT" for method, _, _ in self.github.events))

    def test_concurrent_pointer_update_is_not_forced_or_retried(self):
        self.github.fail_cas = True
        with self.assertRaisesRegex(ValueError, "Conflit CAS"):
            self.run_publish()
        self.assertEqual(self.github.pointer, self.github.original)
        self.assertEqual(sum(method == "PUT" for method, _, _ in self.github.events), 1)


class PublicDownloadTest(unittest.TestCase):
    def test_public_download_hashes_bytes_without_authorization(self):
        payload = b"public APK fixture"
        class Response(io.BytesIO):
            status = 200
            def geturl(self):
                return "https://release-assets.githubusercontent.com/fixture.apk"
        with patch("publish_private_apk.urlopen", return_value=Response(payload)) as opened:
            verify_public_download("https://github.com/fixture.apk", hashlib.sha256(payload).hexdigest(), len(payload))
            self.assertNotIn("Authorization", opened.call_args.args[0].headers)

    def test_truncated_or_wrong_public_download_is_refused(self):
        class Response(io.BytesIO):
            status = 200
            def geturl(self):
                return "https://release-assets.githubusercontent.com/fixture.apk"
        for payload in (b"short", b"wrong file of equal size!"):
            with patch("publish_private_apk.urlopen", return_value=Response(payload)), self.assertRaises(ValueError):
                verify_public_download("https://github.com/fixture.apk", "0" * 64, 24)


if __name__ == "__main__":
    unittest.main()
