"""Contrôles activés et à l'écran du paquet Android interrogé. Le XML reste privé."""
import re
import subprocess
import xml.etree.ElementTree as ET


def _adb(*args, timeout, check):
    return subprocess.run(["adb", *args], capture_output=True, timeout=timeout, check=check).stdout


def visible_nodes(package, focused=None):
    # Le dump via /dev/tty peut perdre sa fin quand ADB est chargé. Une
    # copie privée sur cet AVD vierge évite de mélanger XML et notification.
    private = "/data/local/tmp/zuno-optics-ui.xml"
    _adb("shell", "rm", "-f", private, timeout=4, check=False)
    _adb("shell", "uiautomator", "dump", private, timeout=14, check=False)
    data = _adb("exec-out", "cat", private, timeout=6, check=False)
    start, end = data.find(b"<hierarchy"), data.rfind(b"</hierarchy>")
    if start < 0 or end < start:
        return []
    try:
        root = ET.fromstring(data[start:end+12])
    except ET.ParseError:
        return []
    items = []
    for node in root.iter("node"):
        if node.get("package") != package or node.get("enabled") != "true":
            continue
        box = [int(i) for i in re.findall(r"\d+", node.get("bounds", ""))]
        if len(box) != 4 or box[2] <= box[0] or box[3] <= box[1]:
            continue
        label = " ".join([node.get("content-desc", ""), node.get("text", "")]).lower().strip()
        if focused is not None and node.get("focused") == "true":
            focused.append(label)
            for child in node.iter("node"):
                if child is not node:
                    focused.append(" ".join((child.get("content-desc",""),child.get("text",""))).strip().lower())
        items.append((label, (box[0]+box[2])/2, (box[1]+box[3])/2, node.get("class","")))
    return items

