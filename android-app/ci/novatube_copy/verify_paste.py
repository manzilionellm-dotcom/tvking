"""Vérifie le collage inter-applications sur un téléphone Android émulé."""
import hashlib
import json
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

from source_keyboard import verify_source_keyboard

serial, package, apk, output, component = sys.argv[1:]
out = Path(output)
mk_format = re.compile(r"(?<![A-Za-z0-9:])MK(?::[0-9A-F]{2}){5}(?![A-Za-z0-9:])")
tree_path = "/data/local/tmp/novatube-copy-window.xml"


def shell(*args):
    return subprocess.check_output(["adb", "-s", serial, "shell", *args],
                                   text=True, timeout=16).strip()


def window():
    # uiautomator active les sémantiques Flutter. Un changement de fenêtre
    # pendant la collecte est réessayé, sans réutiliser de hiérarchie périmée.
    shell("rm", "-f", tree_path)
    try:
        shell("uiautomator", "dump", tree_path)
        xml = shell("cat", tree_path)
        return [n.attrib for n in ET.fromstring(xml).iter("node")]
    except (ET.ParseError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return []


def wait_for(find, description, timeout=50):
    deadline = time.monotonic() + timeout
    last = []
    while time.monotonic() < deadline:
        nodes = window()
        if nodes:
            last = nodes
        match = find(nodes)
        if match:
            return match
        time.sleep(.35)
    # Pour diagnostiquer une variante d'Android, conserver les contrôles et
    # leur géométrie sans enregistrer le texte de l'appareil dans l'artefact.
    controls = [{k: n.get(k, "") for k in ("package", "class", "resource-id", "bounds")}
                for n in last]
    (out / "last-controls.json").write_text(json.dumps(controls, indent=2) + "\n")
    raise RuntimeError(description)


def label(node):
    return " ".join((node.get("text", ""), node.get("content-desc", ""))).strip()


def center(node):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", node["bounds"]))
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap(node):
    x, y = center(node)
    shell("input", "tap", str(x), str(y))


def welcome(nodes):
    own = [n for n in nodes if n.get("package") == package]
    code = next((m.group() for n in own if (m := mk_format.search(label(n)))), None)
    button = next((n for n in own if re.search(r"\b(?:copy code|copier le code)\b", label(n), re.I)
                   and n.get("enabled") == "true"), None)
    if code and button:
        return code, button


def belongs_to_settings(node):
    return node.get("package", "").startswith(("com.android.settings", "com.google.android.settings"))


def editable(nodes):
    return next((n for n in nodes if belongs_to_settings(n) and
                 n.get("class") == "android.widget.EditText" and n.get("enabled") == "true"), None)


def settings_search(nodes):
    for n in nodes:
        if not belongs_to_settings(n):
            continue
        if (re.search(r"(?:search_action_bar|search_bar|search_button)$", n.get("resource-id", "")) or
                re.search(r"search settings|recherch.*paramètres", label(n), re.I)):
            return n
    return None


# Vérifier le fichier réellement installé, pas uniquement le nom de l'activité.
base_apk = next(line[8:] for line in shell("pm", "path", package).splitlines()
                if line.startswith("package:") and line.endswith("/base.apk"))
with open(apk, "rb") as binary:
    apk_digest = hashlib.sha256(binary.read()).hexdigest()
if shell("sha256sum", base_apk).split()[0] != apk_digest:
    raise RuntimeError("L'empreinte de l'APK installé diffère de celle du build")

# Si le petit écran coupe la carte, la faire défiler avant le geste mesuré.
try:
    code, button = wait_for(welcome, "Carte du code indisponible", timeout=30)
except RuntimeError:
    bounds = wait_for(lambda ns: next((n for n in ns if n.get("package") == package
                                      and n.get("scrollable") == "true"), None),
                      "Écran d'accueil du LAB introuvable")
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", bounds["bounds"]))
    x = str((x1 + x2) // 2)
    shell("input", "swipe", x, str(y1 + (y2 - y1) * 3 // 4),
          x, str(y1 + (y2 - y1) // 3), "500")
    code, button = wait_for(welcome, "Code MK complet ou bouton de copie absent")

tap(button)
time.sleep(.7)
shell("am", "start", "-W", "-a", "android.settings.SETTINGS")
search = wait_for(lambda ns: editable(ns) or settings_search(ns),
                  "Recherche des paramètres Android introuvable")
tap(search)
field = wait_for(editable, "Le champ de recherche natif n'est pas ouvert")
tap(field)

# Le code affiché n'est jamais saisi ni transmis à adb. Seule l'action Coller
# de la plateforme peut introduire cette valeur dans l'autre application.
def pasted(nodes):
    field = editable(nodes)
    return field and field.get("text") == code

shell("input", "keyevent", "KEYCODE_PASTE")
try:
    wait_for(pasted, "Le collage n'a pas donné le code attendu", timeout=10)
except RuntimeError:
    # Certaines images système traitent le raccourci clavier Ctrl+V plutôt
    # que la touche Coller. Vider la recherche avant ce second vrai collage.
    shell("input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A")
    shell("input", "keyevent", "KEYCODE_DEL")
    shell("input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_V")
    wait_for(pasted, "Le texte collé diffère du code MK complet affiché", timeout=12)

proof = {
    "verified": True,
    "package": package,
    "apk_sha256": apk_digest,
    "android_api": shell("getprop", "ro.build.version.sdk"),
    "form_factor": "touchscreen phone emulator",
    "displayed_format": "MK:XX:XX:XX:XX:XX",
    "paste_destination": field["package"] + "/" + field["class"],
    "pasted_text_equals_displayed_code": True,
}
proof["source_keyboard"] = verify_source_keyboard(serial, package, component, shell, wait_for, tap)
(out / "proof.json").write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n")
shell("rm", "-f", tree_path)
