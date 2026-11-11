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
            with patch.dict(os.environ, {"NOVATUBE_UPLOAD_STORE_PASSWORD": secret, "RUNNER_TEMP": directory}), \
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
            with patch.dict(os.environ, {"RUNNER_TEMP": directory}), \
                    patch("run_recording_device.prepare_emulator", return_value="novatube_test"), \
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

    def test_avd_creation_and_start_share_explicit_directory_and_keep_home(self):
        process = Mock()
        process.poll.return_value = None
        process.wait.return_value = 0
        original_home = os.environ.get("HOME")
        original_exists = Path.exists
        creation = []

        def command(argv, **kwargs):
            if str(argv[0]).endswith("/avdmanager"):
                creation.append((argv, kwargs["env"]))
                directory = Path(kwargs["env"]["ANDROID_AVD_HOME"])
                avd = argv[argv.index("--name") + 1]
                data = Path(argv[argv.index("--path") + 1])
                data.mkdir()
                (directory / (avd + ".ini")).write_text("path=" + str(data) + "\n")
            output = "1\n" if "sys.boot_completed" in argv else ""
            return subprocess.CompletedProcess(argv, 0, output, "")

        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {"RUNNER_TEMP": directory, "GITHUB_RUN_ID": "1234"}), \
                    patch("run_recording_device.subprocess.run", side_effect=command), \
                    patch("run_recording_device.subprocess.Popen", return_value=process) as launch, \
                    patch("run_recording_device.os.access", return_value=True), \
                    patch.object(Path, "exists", lambda path: str(path) == "/dev/kvm" or original_exists(path)), \
                    redirect_stdout(io.StringIO()):
                with booted_emulator(Path(directory) / "reports", Path("/unused-sdk"), preflight=True):
                    pass
            self.assertEqual(len(creation), 1)
            argv, environment = creation[0]
            expected = Path(directory).resolve() / "novatube-avds"
            self.assertEqual(environment["ANDROID_AVD_HOME"], str(expected))
            self.assertEqual(argv[argv.index("--path") + 1], str(expected / "novatube_export_1234.avd"))
            self.assertIs(launch.call_args.kwargs["env"], environment)
            self.assertEqual(environment.get("HOME"), original_home)
            self.assertTrue((expected / "novatube_export_1234.ini").is_file())
            self.assertFalse((Path(directory) / "reports/recording-device-tests.json").exists())


if __name__ == "__main__":
    unittest.main()
