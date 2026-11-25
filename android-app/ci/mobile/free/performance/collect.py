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


def start(activity):
    response = adb("shell", "am", "start", "-W", "-a", "android.intent.action.MAIN",
                   "-c", "android.intent.category.LAUNCHER", "-n", activity)
    values = dict(line.split(": ", 1) for line in response.splitlines() if ": " in line)
    if values.get("Status") != "ok":
        raise RuntimeError(response)
    return {
        "launch_state": values.get("LaunchState"),
        "android_total_ms": int(values["TotalTime"]) if "TotalTime" in values else None,
        "command_wait_ms": int(values["WaitTime"]),
    }


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
    adb("logcat", "-c")
    cold = start(activity)
    ttff_ms = first_image()
    capture_pattern(shot)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1)
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    time.sleep(1)
    if not adb("shell", "pidof", PACKAGE):
        raise RuntimeError("Processus fermé avant la mesure de reprise")
    return {"cold": cold, "resume": start(activity), "open_to_first_frame_ms": ttff_ms}


def main():
    output = Path(sys.argv[1])
    apks = {"before": sys.argv[2], "after": sys.argv[3]}
    measurements = []
    for index in range(3):
        order = ("before", "after") if index % 2 == 0 else ("after", "before")
        for sample in order:
            trial = measure_trial(apks[sample], output / f"lecteur-{sample}.png")
            measurements.append({"edition": sample, "trial": index + 1, **trial})
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
