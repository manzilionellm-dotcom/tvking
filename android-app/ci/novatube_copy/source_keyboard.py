"""Contrôle de saisie par le clavier Android sur le véritable formulaire du LAB."""
import io
import json
import re
import struct
import subprocess
import time

# Source réservée aux exemples, jamais soumise au formulaire ni au réseau.
SAMPLE = "https://example.invalid/nova-lab.m3u"
RECT = r"\[(-?\d+),\s*(-?\d+)\]\s*\[(-?\d+),\s*(-?\d+)\]"
ANDROID_RECT = r"Rect\(\s*(-?\d+),\s*(-?\d+)\s*-\s*(-?\d+),\s*(-?\d+)\s*\)"


def find_url_field(nodes, package, value=None):
    # Après l'ouverture par le bouton M3U, le premier champ de la route tactile
    # est l'adresse. Le second champ est le nom facultatif. Flutter peut omettre
    # entièrement le hint Android d'un champ vide.
    fields = []
    for node in nodes:
        if (node.get("package") != package or node.get("class") != "android.widget.EditText"
                or node.get("enabled") != "true"):
            continue
        box = re.fullmatch(RECT, node.get("bounds", ""))
        if box:
            left, top, right, bottom = map(int, box.groups())
            if left < right and top < bottom:
                fields.append((top, left, node))
    if not fields:
        return None
    field = min(fields, key=lambda item: item[:2])[2]
    if value is None or value in field.get("text", "").splitlines():
        return field
    return None


def ime_frame(display_dump):
    # Android publie la surface réellement occupée par l’IME dans InsetsState.
    # Comparer les rectangles dans les pixels du même écran que UIAutomator.
    for line in display_dump.splitlines():
        if (re.search(r"\b(?:m)?type\s*=\s*(?:itype_)?ime\b", line, re.I)
                and re.search(r"\b(?:m)?visible\s*=\s*true\b", line, re.I)):
            prefix = r"\b(?:m)?frame\s*=\s*"
            match = re.search(prefix + RECT, line, re.I) or re.search(prefix + ANDROID_RECT, line, re.I)
            if match:
                left, top, right, bottom = map(int, match.groups())
                if right > left and bottom > top:
                    return [left, top, right, bottom]
    return None


def clear_of_ime(field, ime, size):
    l, t, r, b = field
    il, it, ir, ib = ime
    return (0 <= l < r <= size[0] and 0 <= t < b <= size[1]
            and (b <= it or t >= ib or r <= il or l >= ir))


def verify_source_keyboard(serial, package, component, shell, wait_for, tap, out):
    def screenshot():
        return subprocess.check_output(["adb", "-s", serial, "exec-out", "screencap", "-p"],
                                       timeout=15)

    def screen_size():
        raw = screenshot()
        if raw[:8] != b"\x89PNG\r\n\x1a\n":
            raise RuntimeError("La taille d'écran ne peut pas être vérifiée")
        return struct.unpack(">II", raw[16:24])

    def orientation(expected, timeout=18):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            w, h = screen_size()
            if (w > h) == (expected == "landscape") and w != h:
                return [w, h]
            time.sleep(.4)
        raise RuntimeError(f"Rotation {expected} non appliquée sur l'écran")

    def ime_shown():
        return bool(re.search(r"\b(?:m)?inputShown\s*=\s*true\b", shell("dumpsys", "input_method"), re.I))

    def app_nodes(nodes):
        return (n for n in nodes if n.get("package") == package)

    def source_entry(nodes):
        return next((n for n in app_nodes(nodes) if re.search(
            r"add an? m3u|ajouter une liste m3u",
            n.get("content-desc", "") + " " + n.get("text", ""), re.I)), None)

    def url_field(nodes, text=None):
        return find_url_field(nodes, package, text)

    def lock_rotation(value, expected):
        # L'état effectif du présent écran prime sur une valeur Settings obsolète.
        shell("wm", "user-rotation", "lock", str(value))
        shell("settings", "put", "system", "accelerometer_rotation", "0")
        shell("settings", "put", "system", "user_rotation", str(value))
        try:
            size = orientation(expected, timeout=8)
        except RuntimeError:
            # Les images où la route suit le capteur peuvent ignorer la rotation
            # verrouillée. Simuler alors la manipulation physique de l'appareil.
            shell("wm", "user-rotation", "free")
            shell("settings", "put", "system", "accelerometer_rotation", "1")
            gravity = "9.8:0:0" if value else "0:9.8:0"
            subprocess.run(["adb", "-s", serial, "emu", "sensor", "set", "acceleration", gravity],
                           check=True, timeout=10)
            size = orientation(expected)
        print(f"Formulaire {expected} confirmé sur {size[0]} x {size[1]} px", flush=True)
        return size

    def geometry(nodes, value, size, min_height):
        field = url_field(nodes, value)
        if field is None or field.get("focused") != "true" or not ime_shown():
            return None
        match = re.fullmatch(RECT, field.get("bounds", ""))
        ime = ime_frame(shell("dumpsys", "window", "displays"))
        if match and ime:
            box = list(map(int, match.groups()))
            if box[3] - box[1] >= min_height and clear_of_ime(box, ime, size):
                return {"screen_px": size, "field_px": box, "ime_px": ime,
                        "field_clear_of_ime": True, "ime_visible": True}

    def type_and_hide(field, suffix, expected, size):
        base = re.fullmatch(RECT, field["bounds"])
        if base is None:
            raise RuntimeError("Limites initiales du champ introuvables")
        _, top, _, bottom = map(int, base.groups())
        # La lecture d'un seul pixel de l'EditText ne constitue pas une preuve
        # de visibilité. Conserver la majeure partie de sa hauteur initiale.
        min_height = max(1, (bottom - top) * 3 // 4)
        tap(field)
        wait_for(lambda ns: (active := url_field(ns)) and active.get("focused") == "true"
                 and ime_shown(), "Le clavier Android ne s'ouvre pas au toucher")
        # En portrait le texte existant doit rester et accepter un caractère de plus.
        if suffix != expected:
            shell("input", "keyevent", "KEYCODE_MOVE_END")
        shell("input", "text", suffix)
        try:
            state = wait_for(lambda ns: geometry(ns, expected, size, min_height),
                             "Le texte exact et son champ actif dégagé du clavier ne sont pas vérifiés")
        except RuntimeError:
            dump = shell("dumpsys", "window", "displays")
            safe = {"screen_px": screen_size(), "ime_shown": ime_shown(), "ime_px": ime_frame(dump),
                    "min_field_height_px": min_height}
            safe["ime_insets"] = [
                line.strip()[:450] for line in dump.splitlines()
                if re.search(r"\b(?:m)?type\s*=\s*(?:itype_)?ime\b", line, re.I)
            ][:8]
            (out / "diagnostic-ime.json").write_text(json.dumps(safe, indent=2) + "\n")
            raise
        # Seul le champ déjà vérifié et synthétique est enregistré. Les autres
        # parties de l'écran et les suggestions du clavier sont exclues.
        try:
            from PIL import Image
            with Image.open(io.BytesIO(screenshot())) as screen:
                if list(screen.size) == size:
                    mark = "landscape" if size[0] > size[1] else "portrait"
                    screen.crop(state["field_px"]).save(out / f"diagnostic-champ-{mark}.png")
        except ImportError:
            pass
        print(f"Adresse synthétique exacte et champ visible au-dessus du clavier : {state}", flush=True)
        shell("input", "keyevent", "KEYCODE_BACK")
        wait_for(lambda ns: url_field(ns, expected) if not ime_shown() else None,
                 "Retour n'a pas masqué le clavier en conservant la saisie")
        return {**state, "typed_text_matched": True, "text_preserved_after_back": True}

    # Le test de collage a ouvert la recherche native des Paramètres. Redémarrer
    # l'activité NovaTube pour sélectionner le formulaire sur un accueil neuf.
    shell("am", "force-stop", package)
    shell("am", "start", "-W", "-n", component)
    entry = wait_for(source_entry, "Bouton Ajouter une liste M3U introuvable")
    tap(entry)

    def opened_or_welcome(ns):
        if url_field(ns) is not None and not source_entry(ns):
            return "form"
        if source_entry(ns):
            return "welcome"

    state = wait_for(opened_or_welcome, "Navigation vers la saisie M3U introuvable")
    if state == "welcome":
        # Le premier toucher peut se limiter à donner le focus au bouton TV.
        entry = wait_for(source_entry, "Bouton M3U introuvable après le premier toucher")
        tap(entry)
    wait_for(lambda ns: opened_or_welcome(ns) == "form", "Le formulaire tactile M3U ne s'ouvre pas")
    landscape_size = lock_rotation(1, "landscape")
    field = wait_for(url_field, "Champ URL M3U absent en paysage")
    if ime_shown():
        raise RuntimeError("Le clavier s'est ouvert avant que l'utilisateur touche le champ")

    landscape = type_and_hide(field, SAMPLE, SAMPLE, landscape_size)
    portrait_size = lock_rotation(0, "portrait")
    field = wait_for(lambda ns: url_field(ns, SAMPLE), "La rotation a effacé le texte saisi")
    portrait = type_and_hide(field, "8", SAMPLE + "8", portrait_size)

    # Choisir le paysage, puis retrouver la même valeur dans la même route.
    lock_rotation(1, "landscape")
    wait_for(lambda ns: url_field(ns, SAMPLE + "8"), "Texte perdu en revenant au paysage")
    # Repasser en portrait pour vérifier aussi la politique d'orientation de
    # l'accueil quand l'utilisateur quitte réellement le formulaire.
    lock_rotation(0, "portrait")
    shell("input", "keyevent", "KEYCODE_BACK")
    wait_for(source_entry, "Retour du formulaire vers l'accueil non confirmé")
    orientation("landscape")
    return {"landscape": landscape, "portrait": portrait,
            "initial_ime_hidden": True, "rotation_preserved_text": True,
            "welcome_restored_landscape": True, "ime_kind": "Android emulator system IME"}
