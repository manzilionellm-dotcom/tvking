"""Les erreurs d'infrastructure doivent être lisibles sans valider des exports."""

from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from run_recording_device import booted_emulator


class EmulatorLifecycleTest(unittest.TestCase):
    def test_early_exit_exposes_code_and_stderr_without_secret_or_success_proof(self):
        process = Mock()
        process.poll.return_value = 86
        process.wait.return_value = 86
        secret = "mot-de-passe-synthetique-test-ci"

        def launch(*args, **kwargs):
            kwargs["stdout"].write("Fatal emulator startup: " + secret + "\n")
            return process

        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            reports = Path(directory)
            with patch.dict(os.environ, {"NOVATUBE_UPLOAD_STORE_PASSWORD": secret}), \
                    patch("run_recording_device.prepare_emulator", return_value="novatube_test"), \
                    patch("run_recording_device.subprocess.Popen", side_effect=launch), \
                    redirect_stdout(output), self.assertRaisesRegex(ValueError, "code 86"):
                with booted_emulator(reports, Path("/unused-sdk"), preflight=True):
                    self.fail("Le contexte ne doit pas s'ouvrir après un arrêt prématuré")
            diagnostic = (reports / "recording-emulator-preflight.txt").read_text()
            self.assertIn("Fatal emulator startup", output.getvalue())
            self.assertIn("code avant nettoyage = 86", output.getvalue())
            self.assertNotIn(secret, output.getvalue())
            self.assertNotIn(secret, diagnostic)
            self.assertIn("[MASQUÉ]", diagnostic)
            self.assertFalse((reports / "recording-device-tests.json").exists())
        process.wait.assert_called_once_with(timeout=15)

    def test_exception_after_boot_still_stops_the_created_emulator(self):
        process = Mock()
        process.poll.return_value = None
        process.wait.return_value = 0
        with tempfile.TemporaryDirectory() as directory:
            with patch("run_recording_device.prepare_emulator", return_value="novatube_test"), \
                    patch("run_recording_device.subprocess.Popen", return_value=process), \
                    patch("run_recording_device.subprocess.run",
                          return_value=subprocess.CompletedProcess([], 0, "1\n", "")) as command, \
                    patch("run_recording_device.run"), redirect_stdout(io.StringIO()), \
                    self.assertRaisesRegex(ValueError, "échec du test"):
                with booted_emulator(Path(directory), Path("/unused-sdk")):
                    raise ValueError("échec du test")
            self.assertTrue(any(call.args[0][-2:] == ["emu", "kill"]
                                for call in command.call_args_list))
            self.assertFalse((Path(directory) / "recording-device-tests.json").exists())
        process.wait.assert_called_once_with(timeout=15)


if __name__ == "__main__":
    unittest.main()
