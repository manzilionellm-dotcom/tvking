#!/usr/bin/env python3
"""Contrat des rapports Android : vrai échec des pixels, jamais un autre échec."""

import base64
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import runpy
import tempfile
import unittest
import xml.etree.ElementTree as ET


verifier = runpy.run_path(str(Path(__file__).with_name("verify-contrast-results.py")))
verify = verifier["verify"]
PIXEL_METHOD = verifier["PIXEL_METHOD"]
MUTATION_MARKER = verifier["MUTATION_MARKER"]
RECOVERY_METHODS = verifier["RECOVERY_METHODS"]
RECOVERY_PROOFS = verifier["RECOVERY_PROOFS"]


class ContrastResultsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        (self.output / "junit").mkdir()
        captures = self.output / "contrast-pixels"
        captures.mkdir()
        # Le test Python vérifie le contrat du rapport et la présence des pièces.
        # Seul le test instrumenté Android mesure les pixels de la vraie vidéo.
        png = base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
            "+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
        for name in ("01-default-on", "02-off", "03-on-again", "04-off-again"):
            (captures / f"{name}.png").write_bytes(png)
        (captures / "measurements.json").write_text(json.dumps({"passed": True}))
        recovery = captures / "recovery"
        recovery.mkdir()
        for name in RECOVERY_PROOFS:
            (recovery / f"{name}.json").write_text(json.dumps({"passed": True}))

    def report(self, failure_type=None, failure_text=None, failure_message=None, status=None):
        suite = ET.Element("testsuite")
        case = ET.SubElement(suite, "testcase", {
            "name": PIXEL_METHOD,
            "classname": "com.manzilionellm.native_video_player.NativeContrastPixelTest",
        })
        if failure_text is not None or failure_type is not None or failure_message is not None:
            failure = ET.SubElement(case, "failure")
            if failure_type is not None:
                failure.set("type", failure_type)
            if failure_message is not None:
                failure.set("message", failure_message)
            failure.text = failure_text
        if status is not None:
            ET.SubElement(case, status)
        for method in RECOVERY_METHODS:
            ET.SubElement(suite, "testcase", {
                "name": method,
                "classname": "com.manzilionellm.native_video_player.NativeRecoveryPlaybackTest",
            })
        ET.ElementTree(suite).write(self.output / "junit" / "TEST-render.xml")

    def check(self, mode):
        with redirect_stdout(io.StringIO()):
            verify(self.output, mode)

    def test_agp_failure_without_type_keeps_the_expected_pixel_assertion(self):
        # Forme réellement produite par AGP dans le run 41551529426, API 29/35.
        self.report(failure_text=(
            "java.lang.AssertionError: Délai dépassé : PIXEL_CONTRAST_NOT_APPLIED\n"
            "at com.manzilionellm.native_video_player.NativeContrastPixelTest.await"
            "(NativeContrastPixelTest.kt:198)\n"
        ))
        self.check("mutation")

    def test_typed_junit_failure_remains_accepted(self):
        self.report(failure_type="java.lang.AssertionError", failure_message=MUTATION_MARKER)
        self.check("mutation")

    def test_successful_baseline_remains_accepted(self):
        self.report()
        self.check("baseline")

    def test_mutation_without_failure_is_rejected(self):
        self.report()
        with self.assertRaisesRegex(SystemExit, "assertion des pixels"):
            self.check("mutation")

    def test_assertion_without_pixel_marker_is_rejected(self):
        self.report(failure_text="java.lang.AssertionError: Délai dépassé : première image native")
        with self.assertRaisesRegex(SystemExit, "régression de contraste"):
            self.check("mutation")

    def test_different_exception_with_pixel_marker_is_rejected(self):
        self.report(failure_text=f"java.lang.IllegalStateException: {MUTATION_MARKER}")
        with self.assertRaisesRegex(SystemExit, "assertion des pixels"):
            self.check("mutation")

    def test_nested_assertion_does_not_hide_an_unrelated_exception(self):
        self.report(failure_text=(
            "java.lang.RuntimeException: instrumentation failed\n"
            f"Caused by: java.lang.AssertionError: {MUTATION_MARKER}"
        ))
        with self.assertRaisesRegex(SystemExit, "assertion des pixels"):
            self.check("mutation")

    def test_explicit_nonassertion_type_is_not_overridden_by_text(self):
        self.report(failure_type="java.lang.RuntimeException", failure_text=(
            f"java.lang.AssertionError: {MUTATION_MARKER}"
        ))
        with self.assertRaisesRegex(SystemExit, "assertion des pixels"):
            self.check("mutation")

    def test_skipped_or_error_result_cannot_validate_the_mutation(self):
        for status in ("skipped", "error"):
            with self.subTest(status=status):
                self.report(failure_type="java.lang.AssertionError",
                            failure_message=MUTATION_MARKER, status=status)
                with self.assertRaisesRegex(SystemExit, "interrompu/ignoré"):
                    self.check("mutation")

    def test_missing_capture_cannot_validate_the_mutation(self):
        self.report(failure_type="java.lang.AssertionError", failure_message=MUTATION_MARKER)
        (self.output / "contrast-pixels" / "02-off.png").unlink()
        with self.assertRaisesRegex(SystemExit, "Capture du test absente"):
            self.check("mutation")

    def test_failed_baseline_cannot_validate_the_render(self):
        self.report(failure_type="java.lang.AssertionError", failure_message=MUTATION_MARKER)
        with self.assertRaisesRegex(SystemExit, "non réussi"):
            self.check("baseline")

    def test_baseline_requires_actual_recovery_test_execution(self):
        self.report()
        report = self.output / "junit" / "TEST-render.xml"
        tree = ET.parse(report)
        for case in list(tree.getroot()):
            if case.get("name") in RECOVERY_METHODS:
                tree.getroot().remove(case)
        tree.write(report)
        with self.assertRaisesRegex(SystemExit, "reprise non exécutées"):
            self.check("baseline")

    def test_failed_or_skipped_recovery_is_not_green(self):
        for status in ("failure", "skipped", "error"):
            self.report()
            report = self.output / "junit" / "TEST-render.xml"
            tree = ET.parse(report)
            case = next(case for case in tree.getroot() if case.get("name") in RECOVERY_METHODS)
            ET.SubElement(case, status)
            tree.write(report)
            with self.assertRaisesRegex(SystemExit, "reprise échouée ou ignorée"):
                self.check("baseline")

    def test_successful_junit_without_recovery_evidence_is_not_green(self):
        self.report()
        (self.output / "contrast-pixels" / "recovery" / "pause-502.json").write_text('{"passed": false}')
        with self.assertRaisesRegex(SystemExit, "Preuve de reprise absente ou échouée"):
            self.check("baseline")


if __name__ == "__main__":
    unittest.main()
