"""Gardes hors ligne ; aucune preuve de réseau, de lecture Android ou de FGS."""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("tap_probe", Path(__file__).with_name("probe_tap_network.py"))
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class TapGuardTests(unittest.TestCase):
    def test_rejects_caller_network_before_any_subprocess(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "guard-test-only"
            # Un faux fichier adb existant et un socket hérité ne doivent pas
            # rendre le cleanup actif lorsque le namespace hôte est refusé.
            adb = Path(directory) / "platform-tools/adb"
            adb.parent.mkdir()
            adb.write_text("outil non exécuté")
            args = argparse.Namespace(output=output, sdk_root=Path(directory),
                                      parent_netns=os.readlink("/proc/self/ns/net"))
            with mock.patch.object(probe.os, "geteuid", return_value=0), \
                    mock.patch.dict(os.environ, {"ADB_SERVER_SOCKET": "tcp:127.0.0.1:12345"}), \
                    mock.patch.object(probe.subprocess, "run") as process, \
                    contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, "caller's network"):
                    probe.run_diagnostic(args)
                process.assert_not_called()
            result = json.loads((output / "network-diagnostic.json").read_text())
            self.assertEqual(result["status"], "blocked")
            for key in ("playEvidence", "foregroundServiceEvidence", "novatubeInstalled",
                        "receiverMediaPlaybackObserved", "aabModified"):
                self.assertIs(result[key], False)

    def test_process_disappearing_before_sigkill_does_not_interrupt_cleanup(self):
        child = mock.Mock(pid=12345)
        child.poll.return_value = None
        child.wait.side_effect = [probe.subprocess.TimeoutExpired("owned", 8), 0]
        with mock.patch.object(probe.os, "killpg", side_effect=[None, ProcessLookupError]) as kill:
            probe.stop_owned_process(child)
        self.assertEqual(kill.call_count, 2)
        self.assertEqual(child.wait.call_count, 2)

    def test_rejects_existing_output_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            marker = output / "keep.txt"
            marker.write_text("untouched")
            args = argparse.Namespace(output=output, sdk_root=output, parent_netns="unused")
            with self.assertRaisesRegex(RuntimeError, "must be new"):
                probe.run_diagnostic(args)
            self.assertEqual(marker.read_text(), "untouched")
            self.assertFalse((output / "network-diagnostic.json").exists())

    def test_location_accepts_only_isolated_real_receiver_endpoint(self):
        expected = "http://192.0.2.1:49494/upnp/device.xml"
        self.assertEqual(probe.checked_location("LOCATION: " + expected + "\r\n"), expected)
        for endpoint in ("http://192.0.2.2:49494/device.xml", "http://example.com/device.xml",
                         "http://192.0.2.1:80/device.xml", "https://192.0.2.1:49494/device.xml",
                         "http://user@192.0.2.1:49494/device.xml"):
            with self.subTest(endpoint=endpoint), self.assertRaises(RuntimeError):
                probe.checked_location("LOCATION: " + endpoint + "\r\n")

    def test_wlan_cannot_fall_back_to_ethernet(self):
        self.assertEqual(probe.checked_wlan("8: wlan0 inet 192.0.2.16/24 scope global wlan0"),
                         "192.0.2.16")
        for text in ("8: wlan0 inet 10.0.2.16/24", "8: wlan0 inet 10.0.2.15/24", "",
                     "8: wlan0 inet 192.0.2.16/24\n8: wlan0 inet 192.0.2.17/24"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                probe.checked_wlan(text)


if __name__ == "__main__":
    unittest.main()
