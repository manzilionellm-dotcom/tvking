"""Contrôle de saisie par le clavier Android sur le véritable formulaire du LAB."""
import re
import struct
import subprocess
import time

# Source réservée aux exemples, jamais soumise au formulaire ni au réseau.
SAMPLE = "https://example.invalid/nova-lab.m3u"
RECT = r"\[(-?\d+),\s*(-?\d+)\]\[(-?\d+),\s*(-?\d+)\]"


def ime_frame(display_dump):
    # Android publie la surface réellement occupée par l’IME dans InsetsState.
    # Comparer les rectangles dans les pixels du même écran que UIAutomator.
    for line in display_dump.splitlines():
        if (re.search(r"\btype=ime\b", line, re.I)
                and re.search(r"\bvisible=true\b", line, re.I)):
            match = re.search(r"\bframe=" + RECT, line, re.I)
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


def verify_source_keyboard(serial, package, component, shell, wait_for, tap):
    def screen_size():
        raw = subprocess.check_output(["adb", "-s", serial, "exec-out", "screencap", "-p"],
                                      timeout=15)
        if raw[:8] != b"\x89PNG\r\n\x1a\n":
            raise RuntimeError("La taille d'écran ne peut pas être vérifiée")
        return struct.unpack(">II", raw[16:24])

    def orientation(expected):
        deadline = time.monotonic() + 18
        while time.monotonic() < deadline:
            w, h = screen_size()
            if (w > h) == (expected == "landscape") and w != h:
                return [w, h]
            time.sleep(.4)
        raise RuntimeError(f"Rotation {expected} non appliquée sur l'écran")

    def ime_shown():
        return bool(re.search(r"\bmInputShown=true\b", shell("dumpsys", "input_method")))

    def app_nodes(nodes):
        return (n for n in nodes if n.get("package") == package)

    def source_entry(nodes):
        return next((n for n in app_nodes(nodes) if re.search(
            r"add an? m3u|ajouter une liste m3u",
            n.get("content-desc", "") + " " + n.get("text", ""), re.I)), None)

    def url_field(nodes, text=None):
        for n in app_nodes(nodes):
            if n.get("class") != "android.widget.EditText" or n.get("enabled") != "true":
                continue
            if text is not None:
                if n.get("text") == text:
                    return n
            elif re.search(r"m3u|https?://", " ".join(n.get(k, "") for k in
                                                     ("content-desc", "text", "hint")), re.I):
                return n
        return None

    def geometry(nodes, value, size):
        field = url_field(nodes, value)
        if field is None or field.get("focused") != "true" or not ime_shown():
            return None
        match = re.fullmatch(RECT, field.get("bounds", ""))
        ime = ime_frame(shell("dumpsys", "window", "displays"))
        if match and ime:
            box = list(map(int, match.groups()))
            if clear_of_ime(box, ime, size):
                return {"screen_px": size, "field_px": box, "ime_px": ime,
                        "field_clear_of_ime": True, "ime_visible": True}

    def type_and_hide(field, suffix, expected, size):
        tap(field)
        wait_for(lambda ns: any(n.get("class") == "android.widget.EditText"
                                and n.get("focused") == "true" for n in app_nodes(ns))
                 and ime_shown(), "Le clavier Android ne s'ouvre pas au toucher")
        # En portrait le texte existant doit rester et accepter un caractère de plus.
        if suffix != expected:
            shell("input", "keyevent", "KEYCODE_MOVE_END")
        shell("input", "text", suffix)
        state = wait_for(lambda ns: geometry(ns, expected, size),
                         "Le texte exact et son champ actif dégagé du clavier ne sont pas vérifiés")
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
    try:
        field = wait_for(url_field, "Champ URL M3U absent", timeout=10)
    except RuntimeError:
        # Certaines interfaces TV donnent d'abord le focus au bouton touché.
        # Valider seulement s'il est encore visible, jamais dans un champ.
        focused_entry = wait_for(source_entry, "Le formulaire M3U ne s'ouvre pas", timeout=8)
        tap(focused_entry)
        field = wait_for(url_field, "Champ URL du formulaire introuvable")
    if ime_shown():
        raise RuntimeError("Le clavier s'est ouvert avant que l'utilisateur touche le champ")

    landscape = type_and_hide(field, SAMPLE, SAMPLE, orientation("landscape"))
    shell("settings", "put", "system", "user_rotation", "0")
    portrait_size = orientation("portrait")
    field = wait_for(lambda ns: url_field(ns, SAMPLE), "La rotation a effacé le texte saisi")
    portrait = type_and_hide(field, "8", SAMPLE + "8", portrait_size)

    # Choisir le paysage, puis retrouver la même valeur dans la même route.
    shell("settings", "put", "system", "user_rotation", "1")
    orientation("landscape")
    wait_for(lambda ns: url_field(ns, SAMPLE + "8"), "Texte perdu en revenant au paysage")
    # Repasser en portrait pour vérifier aussi la politique d'orientation de
    # l'accueil quand l'utilisateur quitte réellement le formulaire.
    shell("settings", "put", "system", "user_rotation", "0")
    orientation("portrait")
    shell("input", "keyevent", "KEYCODE_BACK")
    wait_for(source_entry, "Retour du formulaire vers l'accueil non confirmé")
    orientation("landscape")
    return {"landscape": landscape, "portrait": portrait,
            "initial_ime_hidden": True, "rotation_preserved_text": True,
            "welcome_restored_landscape": True, "ime_kind": "Android emulator system IME"}
