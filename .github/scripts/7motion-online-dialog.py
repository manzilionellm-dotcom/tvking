"""Répond seulement au contrôleur de notifications d'un émulateur de test vierge."""
import re
import subprocess
import sys
import time
from pathlib import Path
from xml.etree import ElementTree as ET

dest = Path(sys.argv[1])
controller = {"com.android.permissioncontroller", "com.google.android.permissioncontroller"}
waited = False
start = time.monotonic()
until = start + 95


def adb(*args, timeout=10):
    return subprocess.run(["adb", *args], capture_output=True, timeout=timeout)


while time.monotonic() < until:
    try:
        dump = adb("shell", "uiautomator", "dump", "/sdcard/proof-dialog.xml", timeout=12)
        if dump.returncode or b"dumped to" not in dump.stdout.lower():
            time.sleep(1)
            continue
        data = adb("exec-out", "cat", "/sdcard/proof-dialog.xml").stdout
        root = ET.fromstring(data)
        nodes = list(root.iter("node"))
        labels = " ".join(n.get("text", "") for n in nodes).lower()
        selected = None
        action = ""
        if "permission controller isn't responding" in labels:
            name = "android:id/aerr_close" if waited else "android:id/aerr_wait"
            selected = next((n for n in nodes if n.get("resource-id") == name), None)
            action = "fermer uniquement le contrôleur Android bloqué" if waited else "attendre le contrôleur Android bloqué"
            waited = True
        elif "7 motion test" in labels and "notification" in labels:
            selected = next((n for n in nodes if n.get("package") in controller and
                             n.get("resource-id", "").endswith(":id/permission_deny_button")), None)
            action = "refuser les notifications du test comme sur le téléphone"
        if selected is not None:
            bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", selected.get("bounds", ""))
            if bounds:
                x1, y1, x2, y2 = map(int, bounds.groups())
                moment = int(time.monotonic() - start)
                (dest / f"dialogue-{moment}.xml").write_bytes(data)
                print(f"{moment}s : {action}", flush=True)
                adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
                time.sleep(5)
                if action.startswith("refuser"):
                    break
        elif waited and "support" in labels and "mk:" in labels:
            break
    except (subprocess.TimeoutExpired, ET.ParseError):
        pass
    time.sleep(1)
state = adb("shell", "dumpsys", "package", "com.manzilionellm.tvking.qa.startup")
for line in state.stdout.decode(errors="replace").splitlines():
    if "POST_NOTIFICATIONS: granted=" in line:
        print(line.strip(), flush=True)
