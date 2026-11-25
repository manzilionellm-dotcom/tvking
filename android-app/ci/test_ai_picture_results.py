#!/usr/bin/env python3
"""Un artefact manquant ou un test ignoré ne doit jamais valider l'IA."""

import json
from pathlib import Path
import runpy
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib


module = runpy.run_path(str(Path(__file__).with_name("verify-ai-picture-results.py")))
verify = module["verify"]


def png_chunk(kind, payload):
    return (struct.pack(">I", len(payload)) + kind + payload +
            struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff))


def png(width, height, *, color=6, pixels=None, compressed=None):
    channels = 3 if color == 2 else 4
    if pixels is None:
        pixels = (b"\x00" + bytes(width * channels)) * height
    if compressed is None:
        compressed = zlib.compress(pixels)
    return (b"\x89PNG\r\n\x1a\n" +
            png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)) +
            png_chunk(b"IDAT", compressed) + png_chunk(b"IEND", b""))


class AiPictureResultsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        (self.output / "junit").mkdir()
        self.folder = self.output / "ai-picture"
        self.folder.mkdir()
        self.expected = {"modelSha256": "a" * 64, "pipelineSha256": "b" * 64}
        self.proof = dict(self.expected, schemaVersion=1,
                          performanceVerdict="NOT_MEASURED_ON_CLIENT_BOX",
                          testClockAndAdmissionInjected=True, nativeRefusalsVerified=3,
                          referenceMaximumByteError=1, referenceMeanByteError=0.124)
        self.proof.update({key: True for key in module["REQUIRED_PROOFS"]})
        self.save()
        self.report()
        # Vrais PNG consultables, même si ce test ne remesure pas les pixels
        # neuronaux : ceux-ci restent prouvés par l'instrumentation Android.
        for name, (width, height) in module["IMAGES"].items():
            (self.folder / name).write_bytes(png(width, height))

    def save(self):
        (self.folder / "measurements.json").write_text(json.dumps(self.proof))

    def report(self, result=None, name=None):
        root = ET.Element("testsuite")
        case = ET.SubElement(root, "testcase", classname="example.ai.AiPictureGpuTest",
                             name=name or module["AI_METHOD"])
        if result:
            ET.SubElement(case, result)
        ET.ElementTree(root).write(self.output / "junit" / "TEST-ai.xml")

    def test_complete_functional_evidence_is_accepted(self):
        self.assertTrue(verify(self.output, self.expected)["baselinePassed"])

    def test_missing_failed_or_skipped_method_is_rejected(self):
        for result in ("failure", "error", "skipped"):
            self.report(result)
            with self.assertRaises(ValueError):
                verify(self.output, self.expected)
        self.report(name="anotherTest")
        with self.assertRaises(ValueError):
            verify(self.output, self.expected)

    def test_every_functional_proof_is_required(self):
        for field in module["REQUIRED_PROOFS"]:
            self.proof[field] = False
            self.save()
            with self.assertRaises(ValueError):
                verify(self.output, self.expected)
            self.proof[field] = True

    def test_unrelated_model_or_claimed_box_speed_is_rejected(self):
        for field, value in (("modelSha256", "c" * 64), ("pipelineSha256", "c" * 64),
                             ("performanceVerdict", "FAST"), ("testClockAndAdmissionInjected", False)):
            previous = self.proof[field]
            self.proof[field] = value
            self.save()
            with self.assertRaises(ValueError):
                verify(self.output, self.expected)
            self.proof[field] = previous

    def test_invalid_numeric_result_or_missing_capture_is_rejected(self):
        for value in (128, -1, float("nan"), True):
            self.proof["referenceMaximumByteError"] = value
            self.save()
            with self.assertRaises(ValueError):
                verify(self.output, self.expected)
        self.proof["referenceMaximumByteError"] = 1
        self.save()
        (self.folder / "model-output.png").unlink()
        with self.assertRaises(FileNotFoundError):
            verify(self.output, self.expected)

    def test_truncated_corrupted_or_unterminated_png_is_rejected(self):
        image = self.folder / "model-output.png"
        original = image.read_bytes()
        # L'ancien contrôle acceptait le seul en-tête jusqu'à l'octet 40.
        invalid = [original[:40], original[:-1], original[:-12], original + b"extra"]
        offset = 8
        while offset < len(original):
            end = offset + struct.unpack_from(">I", original, offset)[0] + 12
            bad_crc = bytearray(original)
            bad_crc[end - 1] ^= 1
            invalid.append(bytes(bad_crc))
            offset = end
        for index, content in enumerate(invalid):
            with self.subTest(corruption=index):
                image.write_bytes(content)
                with self.assertRaises(ValueError):
                    verify(self.output, self.expected)

    def test_invalid_compressed_pixels_are_rejected_even_with_valid_chunk_crcs(self):
        image = self.folder / "model-output.png"
        pixels = (b"\x00" + bytes(32 * 4)) * 24
        compressed = zlib.compress(pixels)
        invalid = [
            png(32, 24, compressed=b"invalid zlib"),
            png(32, 24, compressed=compressed[:-1]),
            png(32, 24, compressed=compressed + zlib.compress(b"extra")),
            png(32, 24, pixels=pixels[:-1]),
            png(32, 24, pixels=pixels + b"\x00"),
            png(32, 24, pixels=b"\x05" + pixels[1:]),
        ]
        for index, content in enumerate(invalid):
            with self.subTest(pixel_data=index):
                image.write_bytes(content)
                with self.assertRaises(ValueError):
                    verify(self.output, self.expected)

    def test_required_png_chunk_order_and_dimensions_are_checked(self):
        image = self.folder / "model-output.png"
        original = image.read_bytes()
        header = original[8:33]
        compressed = zlib.compress((b"\x00" + bytes(32 * 4)) * 24)
        split = len(compressed) // 2
        invalid = [
            png(31, 24),
            original[:8] + header + header + original[33:],
            original[:8] + png_chunk(b"IDAT", compressed) + header + original[-12:],
            original[:33] + png_chunk(b"IDAT", compressed[:split]) +
            png_chunk(b"tEXt", b"note\x00fixture") +
            png_chunk(b"IDAT", compressed[split:]) + original[-12:],
        ]
        for index, content in enumerate(invalid):
            with self.subTest(structure=index):
                image.write_bytes(content)
                with self.assertRaises(ValueError):
                    verify(self.output, self.expected)

    def test_rgb_rgba_and_consecutive_idat_chunks_are_accepted(self):
        image = self.folder / "model-output.png"
        for color, channels in ((2, 3), (6, 4)):
            # Les cinq filtres légaux doivent rester consultables.
            pixels = b"".join(bytes([row % 5]) + bytes(32 * channels) for row in range(24))
            original = png(32, 24, color=color, pixels=pixels)
            compressed = zlib.compress(pixels)
            split = len(compressed) // 2
            image.write_bytes(original[:33] + png_chunk(b"IDAT", compressed[:split]) +
                              png_chunk(b"IDAT", compressed[split:]) + original[-12:])
            self.assertTrue(verify(self.output, self.expected)["baselinePassed"])


if __name__ == "__main__":
    unittest.main()
