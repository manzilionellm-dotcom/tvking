"""Mesure l’activité Android et le signal natif, puis vérifie les pixels de la mire."""
import io
import json
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

PACKAGE = "com.manzilionellm.tvking.qa.perf"


def adb(*args):
    return subprocess.check_output(["adb", *args], timeout=45, text=True).strip()


def start(activity, completion):
    adb("logcat", "-c")
    adb("shell", "log", "-t", "SevenPerf", "SEVEN_PERF_LAUNCH")
    # am start -W peut rester en attente de WindowManager lors d'un changement
    # d'orientation. Le raster Flutter et la reprise indiquent l'événement réel.
    response = adb("shell", "am", "start", "-a", "android.intent.action.MAIN",
                   "-c", "android.intent.category.LAUNCHER", "-n", activity)
    if "Error" in response:
        raise RuntimeError(response)
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        events = adb("logcat", "-d", "-v", "epoch", "-s", "SevenPerf:I", "flutter:I", "AndroidRuntime:E")
        start_at = re.search(r"^(\d+\.\d+).*SEVEN_PERF_LAUNCH\b", events, re.M)
        end_at = re.search(r"^(\d+\.\d+).*" + completion + r"\b", events, re.M)
        if start_at and end_at:
            return round((float(end_at[1]) - float(start_at[1])) * 1000, 1)
        if "FATAL EXCEPTION" in events:
            raise RuntimeError("Le processus Android s'est arrêté pendant le lancement")
        time.sleep(0.25)
    raise TimeoutError("L'événement Flutter attendu n'est pas arrivé : " + completion)


def first_image():
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        logs = adb("logcat", "-d", "-s", "flutter:I", "AndroidRuntime:E")
        match = re.search(r"SEVEN_PERF_TTFF_US ([1-9][0-9]*)", logs)
        if match:
            return int(match.group(1)) / 1000
        if "FATAL EXCEPTION" in logs:
            raise RuntimeError("Le processus Android a quitté avant la première image")
        time.sleep(0.2)
    raise TimeoutError("Aucun signal de première image du lecteur Android")


def capture_pattern(output):
    for _ in range(10):
        data = subprocess.check_output(["adb", "exec-out", "screencap", "-p"], timeout=20)
        shot = Image.open(io.BytesIO(data)).convert("RGB")
        width, height = shot.size
        center = shot.crop((width * 3 // 10, height * 46 // 100,
                            width * 7 // 10, height * 54 // 100)).resize((32, 16))
        pixels = list(center.getdata())
        if sum(red > 120 and red > 2 * green and red > 2 * blue
               for red, green, blue in pixels) > len(pixels) // 2:
            output.write_bytes(data)
            return
        time.sleep(0.3)
    raise RuntimeError("Le lecteur a signalé une image, mais la mire rouge est absente")


def measure_trial(apk, shot):
    adb("install", "-r", apk)
    if adb("shell", "pm", "clear", PACKAGE) != "Success":
        raise RuntimeError("Impossible de réinitialiser les données de test")
    activity = adb("shell", "cmd", "package", "resolve-activity", "--brief",
                   "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER",
                   PACKAGE).splitlines()[-1]
    if not activity.startswith(PACKAGE + "/"):
        raise RuntimeError("Activité principale de 7 MOTION QA introuvable")
    adb("shell", "am", "force-stop", PACKAGE)
    cold = start(activity, "SEVEN_PERF_FIRST_UI")
    ttff_ms = first_image()
    capture_pattern(shot)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1)
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(1)
    if not adb("shell", "pidof", PACKAGE):
        raise RuntimeError("Processus fermé avant la mesure de reprise")
    return {"intent_to_first_raster_ms": cold, "intent_to_resume_event_ms": start(activity, "SEVEN_PERF_RESUMED"),
            "open_to_first_frame_ms": ttff_ms}


def main():
    output = Path(sys.argv[1])
    apks = {"before": sys.argv[2], "after": sys.argv[3]}
    measurements = []
    for index in range(3):
        order = ("before", "after") if index % 2 == 0 else ("after", "before")
        for sample in order:
            print(f"Essai {index + 1} : {sample}", flush=True)
            trial = measure_trial(apks[sample], output / f"lecteur-{sample}.png")
            measurements.append({"edition": sample, "trial": index + 1, **trial})
            (output / "essais.json").write_text(json.dumps(measurements, indent=2) + "\n")
            print(trial, flush=True)
    medians = {
        edition: statistics.median(t["open_to_first_frame_ms"] for t in measurements if t["edition"] == edition)
        for edition in apks
    }
    result = {
        "android": adb("shell", "getprop", "ro.build.version.release"),
        "abi": adb("shell", "getprop", "ro.product.cpu.abi"),
        "source": "loopback H.264/AAC MP4 640x360, 25 fps",
        "trials": measurements,
        "versions": {"before": "0.4.0", "after": "0.4.1"},
        "median_open_to_first_frame_ms": medians,
        "delta_after_minus_before_ms": medians["after"] - medians["before"],
    }
    report = json.dumps(result, indent=2)
    (output / "mesures.json").write_text(report + "\n")
    print(report)


if __name__ == "__main__":
    main()
