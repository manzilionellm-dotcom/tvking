"""Démarrage Android mesuré sur un périphérique de test dédié. Aucun journal brut n'est exporté."""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone


def adb(*args, timeout=45, check=True):
    return subprocess.run(["adb", *args], capture_output=True, timeout=timeout, check=check).stdout.decode(errors="replace").strip()


def sha256_file(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def installed_hashes(package):
    paths = adb("shell", "pm", "path", package, check=False).splitlines()
    results = {}
    for row in paths:
        if row.startswith("package:"):
            path = row.removeprefix("package:").strip()
            digest = adb("shell", "sha256sum", path).split()[0]
            if not re.fullmatch("[a-f0-9]{64}", digest):
                raise RuntimeError("Empreinte Android illisible")
            results[Path(path).name] = digest
    return results


def is_foreground(package):
    tasks = adb("shell", "dumpsys", "activity", "activities")
    return any(package + "/" in line for line in tasks.splitlines()
               if re.search(r"mResumedActivity|topResumedActivity|ResumedActivity:|Resumed:", line))


def process(package):
    return adb("shell", "pidof", "-s", package, check=False)


def diagnostics(out, package, result, label):
    # Les piles Java sont réduites aux noms de classes/méthodes. Aucune donnée de message,
    # URL, MAC, valeur de champ, ni description libre n’entre dans les artefacts.
    tasks = adb("shell", "dumpsys", "activity", "activities")
    window = adb("shell", "dumpsys", "window", "windows")
    component_re = r"[a-zA-Z][a-zA-Z0-9_.]+/[.a-zA-Z0-9_$]+"
    resumed = [m for l in (tasks + "\n" + window).splitlines()
               if any(k in l for k in ("ResumedActivity","mCurrentFocus","mFocusedApp","topResumed","Resumed:"))
               for m in re.findall(component_re,l)]
    crash = adb("logcat", "-b", "crash", "-d", "-t", "250", check=False)
    belongs = any("Process: "+package+"," in l or ">>> "+package+" <<<" in l for l in crash.splitlines())
    info = adb("shell", "dumpsys", "activity", "exit-info", package, check=False)
    record = {"launch_reply": dict(re.findall(r"^(Status|LaunchState|Activity|TotalTime|WaitTime):\s*(["+
                      r"a-zA-Z0-9_./$-]+)", result, re.M)),
              "observed_foreground_components": sorted(set(resumed)),
              "process_exists": bool(process(package)), "crash_buffer_names_package": belongs,
              "exit_reasons": re.findall(r"reason=([0-9]+) \(([A-Z_ ]+)\)", info)[:12],
              "java_exception_types": re.findall(r"\b([a-zA-Z0-9_.$]+(?:Error|Exception))\b", crash)[:30] if belongs else [],
              "java_stack_symbols": re.findall(r"\bat ([a-zA-Z0-9_.$]+)\(",crash)[:40] if belongs else [],
              "native_signals": re.findall(r"signal (\d+) \((SIG[A-Z]+)\)",crash)[:5] if belongs else []}
    (out / ("system-" + label + ".json")).write_text(json.dumps(record,indent=2))


def stats(samples):
    ordered = sorted(samples)
    if not ordered:
        return {}
    return {"median_ms": statistics.median(ordered),
            "p95_nearest_rank_ms": ordered[math.ceil(.95 * len(ordered)) - 1],
            "max_ms": ordered[-1], "under_3000_ms": sum(ms < 3000 for ms in ordered)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--package", required=True)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--count", type=int, default=30)
    args = parser.parse_args()
    out, pkg = args.out, args.package
    if not re.fullmatch(r"[a-z][a-z0-9_.]+", pkg) or not (1 <= args.count <= 100):
        parser.error("Arguments non valides")
    out.mkdir(parents=True, exist_ok=True)
    if adb("shell", "getprop", "ro.kernel.qemu") != "1" and os.getenv("ZUNO_DEDICATED_DEVICE") != "yes":
        raise SystemExit("Pour un appareil physique, confirmer ZUNO_DEDICATED_DEVICE=yes sur une box de test dédiée")
    expected = sha256_file(args.apk)
    before = installed_hashes(pkg)
    if before and before != {"base.apk": expected}:
        raise SystemExit("Une autre installation occupe déjà le paquet. Utiliser un appareil de test distinct.")
    if not before:
        adb("install", str(args.apk.resolve()), timeout=180)
    installed = installed_hashes(pkg)
    if installed != {"base.apk": expected}:
        raise RuntimeError("Octets installés différents de l'APK monolithique prévu")
    component = ""
    for category in ["LEANBACK_LAUNCHER", "LAUNCHER"]:
        result = adb("shell", "cmd", "package", "resolve-activity", "--brief", "-a",
                     "android.intent.action.MAIN", "-c", "android.intent.category." + category, pkg)
        options = [s.strip() for s in result.splitlines() if s.startswith(pkg + "/")]
        if options:
            component = options[-1]
            break
    if not component:
        raise RuntimeError("Activité officielle introuvable")
    metadata = {"apk_sha256": expected, "installed_before_series": installed, "component": component,
                "model": adb("shell", "getprop", "ro.product.model"), "api": adb("shell", "getprop", "ro.build.version.sdk"),
                "ram": adb("shell", "cat", "/proc/meminfo").splitlines()[0], "size": adb("shell", "wm", "size"),
                "display_density": adb("shell", "wm", "density"), "serial_recorded": False,
                "measure": "am start -W; host captures full command time; TotalTime is optional on HOT. No source of video or panel timing."}
    (out / "device.json").write_text(json.dumps(metadata, indent=2))
    rows = []
    adb("shell", "wm", "dismiss-keyguard", check=False)
    with (out / "launches.csv").open("w", newline="") as f:
        fields = ["index", "kind", "utc", "status", "pid_continuity", "launch_state",
                  "android_total_ms", "android_wait_ms", "host_command_ms", "foreground_after", "observation"]
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for i in range(1, args.count + 1):
            for kind in ["cold", "warm"]:
                if kind == "cold":
                    adb("shell", "am", "force-stop", pkg)
                    prep = not process(pkg)
                    old = ""
                else:
                    old = process(pkg)
                    adb("shell", "input", "keyevent", "KEYCODE_HOME")
                    time.sleep(.7)
                    prep = bool(old) and not is_foreground(pkg)
                stamp = datetime.now(timezone.utc).isoformat()
                start = time.monotonic_ns()
                result = adb("shell", "am", "start", "-W", "-a", "android.intent.action.MAIN",
                             "-c", "android.intent.category." + category, "-n", component, check=False)
                elapsed = (time.monotonic_ns() - start) / 1e6
                # Un processus peut mourir après la réponse du gestionnaire d'activités.
                time.sleep(3 if i in (1, args.count) else .5)
                alive = process(pkg)
                foreground = is_foreground(pkg)
                values = dict(re.findall(r"^(Status|LaunchState|TotalTime|WaitTime):\s*(\S+)", result, re.M))
                continuous = bool(alive) and (kind == "cold" or old == alive)
                ok = prep and values.get("Status") == "ok" and foreground and continuous
                row = dict(zip(fields, [i, kind, stamp, "ok" if ok else "error", continuous,
                    values.get("LaunchState", ""), values.get("TotalTime", ""), values.get("WaitTime", ""),
                    round(elapsed, 2), foreground, "activity_foreground"]))
                if i == 1 or (i == args.count and not ok):
                    diagnostics(out, pkg, result, f"{kind}-{i}")
                rows.append(row)
                writer.writerow(row)
                f.flush()
                if i in (1, args.count) and ok:
                    # Seul le condensat de l'écran est exporté. Une vue de démarrage peut afficher une MAC.
                    png = subprocess.check_output(["adb", "exec-out", "screencap", "-p"], timeout=20)
                    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
                        raise RuntimeError("Capture Android illisible")
                    (out / f"frame-{kind}-{i}.json").write_text(json.dumps({"utc": datetime.now(timezone.utc).isoformat(),
                        "sha256_png": hashlib.sha256(png).hexdigest(), "bytes": len(png), "screen_content": "unclassified"}))
    result = {}
    for kind in ["cold", "warm"]:
        subset = [r for r in rows if r["kind"] == kind]
        successful = [r for r in subset if r["status"] == "ok"]
        result[kind] = {"attempts": len(subset), "successes": len(successful),
                        "errors": len(subset) - len(successful), "host_command": stats([r["host_command_ms"] for r in successful]),
                        "android_total": stats([int(r["android_total_ms"]) for r in successful if str(r["android_total_ms"]).isdigit()])}
    result["installed_after_series"] = installed_hashes(pkg)
    (out / "summary.json").write_text(json.dumps(result, indent=2))
    return 0 if result["installed_after_series"] == installed and all(r["status"] == "ok" for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
