"""Les erreurs d'infrastructure doivent être lisibles sans valider des exports."""

from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from run_recording_device import booted_emulator, capture_test_logcat


class AndroidDiagnosticTest(unittest.TestCase):
    def test_all_and_crash_keep_system_causes_and_mask_secrets_in_files_and_console(self):
        secret = "secret-synthetique-diagnostic-ci"
        all_log = "ActivityManager: killing test process " + secret + "\n" + "\n".join(
            f"all line {index}" for index in range(350)) + "\nAndroidRuntime: " + secret + "\n"
        crash_log = "AndroidRuntime: FATAL EXCEPTION " + secret + "\n" + "\n".join(
            f"crash line {index}" for index in range(350)) + "\nDEBUG: " + secret + "\n"
        console = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            reports = Path(directory)
            with patch.dict(os.environ, {"NOVATUBE_UPLOAD_KEY_PASSWORD": secret}), \
                    patch("run_recording_device.run", side_effect=[all_log, crash_log]) as command, \
                    redirect_stdout(console):
                capture_test_logcat(Path("/unused-adb"), reports)
            for buffer, filename, cause in (
                ("all", "recording-android-logcat.txt", "ActivityManager: killing test process"),
                ("crash", "recording-android-logcat-crash.txt", "AndroidRuntime: FATAL EXCEPTION"),
            ):
                saved = (reports / filename).read_text()
                self.assertIn(cause, saved)
                self.assertIn(buffer + " line 0", saved)
                self.assertIn(buffer + " line 349", saved)
                self.assertNotIn(secret, saved)
                self.assertIn("[MASQUÉ]", saved)
            self.assertEqual([call.args[0][5] for call in command.call_args_list], ["all", "crash"])
            for call in command.call_args_list:
                self.assertEqual(call.args[0][-5:], ["-d", "-v", "threadtime", "-t", "3000"])
                self.assertNotIn("*:S", call.args[0])
                self.assertEqual(call.kwargs["timeout"], 20)
            self.assertNotIn(secret, console.getvalue())
            self.assertIn("[MASQUÉ]", console.getvalue())
            self.assertIn("all line 349", console.getvalue())
            self.assertIn("crash line 349", console.getvalue())
            self.assertNotIn("all line 0", console.getvalue())
            self.assertLessEqual(len(console.getvalue().splitlines()), 202)
            self.assertFalse((reports / "recording-device-tests.json").exists())

    def test_all_buffer_timeout_preserves_partial_output_and_independent_crash_buffer(self):
        secret = "secret-partiel-diagnostic-ci"
        failure = subprocess.TimeoutExpired(["adb", "logcat"], 20,
                                            output=("libc: partial abort " + secret).encode())
        console = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            reports = Path(directory)
            with patch.dict(os.environ, {"GITHUB_TOKEN": secret}), \
                    patch("run_recording_device.run", side_effect=[failure, "DEBUG: native backtrace\n"]) as command, \
                    redirect_stdout(console):
                capture_test_logcat(Path("/unused-adb"), reports)
            all_log = (reports / "recording-android-logcat.txt").read_text()
            self.assertIn("indisponible", all_log)
            self.assertIn("libc: partial abort [MASQUÉ]", all_log)
            self.assertEqual((reports / "recording-android-logcat-crash.txt").read_text(),
                             "DEBUG: native backtrace\n")
            self.assertNotIn(secret, console.getvalue())
            self.assertEqual(command.call_count, 2)
            self.assertFalse((reports / "recording-device-tests.json").exists())

    def test_crash_buffer_failure_does_not_discard_all_buffer_or_expose_error_secret(self):
        secret = "secret-erreur-diagnostic-ci"
        console = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            reports = Path(directory)
            with patch.dict(os.environ, {"NOVATUBE_UPLOAD_STORE_PASSWORD": secret}), \
                    patch("run_recording_device.run", side_effect=["lmkd: killed test process\n", OSError(secret)]) as command, \
                    redirect_stdout(console):
                capture_test_logcat(Path("/unused-adb"), reports)
            self.assertEqual((reports / "recording-android-logcat.txt").read_text(),
                             "lmkd: killed test process\n")
            crash_log = (reports / "recording-android-logcat-crash.txt").read_text()
            self.assertIn("indisponible", crash_log)
            self.assertIn("[MASQUÉ]", crash_log)
            self.assertNotIn(secret, crash_log)
            self.assertNotIn(secret, console.getvalue())
            self.assertEqual(command.call_count, 2)
            self.assertFalse((reports / "recording-device-tests.json").exists())


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
