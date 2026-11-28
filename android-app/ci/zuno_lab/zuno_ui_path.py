"""Reconnaissance du parcours TV ZUNO. Seuls des contrôles identifiés peuvent agir."""
import re
import unicodedata


def normalized(value):
    plain = unicodedata.normalize("NFKD", value.lower())
    return " ".join(re.findall(r"[a-z0-9]+", "".join(c for c in plain if not unicodedata.combining(c))))


def control(nodes, words, size, labels, below=0):
    """Bouton accessible exact ou groupe de mots contigus sur la même ligne OCR."""
    wanted = {normalized(value) for value in labels}
    for label, x, y, _ in nodes:
        if y >= below and any(normalized(line) in wanted for line in label.splitlines()):
            return x, y
    width, height = size
    for text in sorted(wanted, key=lambda value: -len(value.split())):
        tokens = text.split()
        for word, x, y in words:
            if y < below or word != tokens[0]:
                continue
            neighbours = sorted((xx, yy, w) for w, xx, yy in words
                                if xx > x and abs(yy - y) <= max(4, height * .012))
            span = [(x, y)]
            for (xx, yy, w), expected in zip(neighbours, tokens[1:]):
                if w != expected or xx - span[-1][0] > width * .14:
                    break
                span.append((xx, yy))
            if len(span) == len(tokens):
                return sum(x for x, _ in span) / len(span), sum(y for _, y in span) / len(span)
    return None


def next_step(nodes, words, size, phase, entered_via_sources=False, back_sent=False):
    """Trois phases. Un écran inattendu ne produit aucune commande."""
    def find(*labels, below=0):
        return control(nodes, words, size, labels, below)

    if find("notifications") and find("allow", "autoriser"):
        return "notifications", find("allow", "autoriser")
    if find("language", "langue", "deutsch") and find("english") and not find("live", "direct"):
        return "english", find("english")

    if phase == "after-submit":
        # « Mire » seule désigne aussi la chaîne B et certains en-têtes.
        a = find("mire a")
        if a and find("mire b"):
            return "channel-a", a
        if find("my sources", "mes sources") and find("my list", "ma liste"):
            return "return-to-hub", None
        hub = find("live", "direct")
        if hub and find("movies", "films", "series", "server", "serveur", "settings", "reglages"):
            return "live", hub
        if entered_via_sources and back_sent and find("settings", "reglages") and find("my sources", "mes sources"):
            return "return-from-settings", None
        button = find("sign in and load", "se connecter et charger")
        if button and (find("add my source", "ajouter ma source") or find("paste", "coller")):
            return "submit-button", button
        all_channels = find("all channels", "toutes les chaines")
        if all_channels and find("live", "direct", "favorites", "favoris"):
            return "all-channels", all_channels
        return "wait", None

    # L’écran dédié et le formulaire d’accueil comportent les mêmes deux modes.
    form = (find("add my source", "ajouter ma source") or
            (find("paste", "coller") and find("file", "fichier")))
    chip = find("m3u url")
    if form:
        if phase == "choose" and chip:
            return "choose-m3u", chip
        if phase == "url":
            fields = [(x, y) for _, x, y, c in nodes if c.endswith("EditText")]
            if len(fields) == 1:
                return "type-url", fields[0]
            if not fields and chip:
                # Le champ est sous la rangée Xtream/M3U. Un champ serveur
                # voisin de Nom/Mot de passe appartient encore au mode Xtream.
                if find("username", "identifiant", "password", "passe"):
                    return "wait", None
                target = find("http", below=chip[1] + size[1] * .012)
                if target:
                    return "type-url", target
        return "wait", None

    add = find("add m3u", "ajouter m3u")
    if add and (find("my sources", "mes sources") or find("add xtream", "ajouter xtream")):
        return "add-m3u", add
    src = find("my sources", "mes sources", "sources")
    if src and find("settings", "reglages") and not find("movies", "films"):
        return "settings-sources", src
    if find("live", "direct") or find("movies", "films", "series"):
        server = find("server", "serveur")
        if server:
            return "server", server
        settings = find("settings", "reglages")
        if settings:
            return "settings", settings
    return "wait", None
