#!/usr/bin/env python3
"""Mesures utilisateur sur l'APK installé ; mire, film et récepteur synthétiques du runner."""
import argparse
import io
import json
import os
from pathlib import Path
import re
import statistics
import sys
import time
from urllib.parse import urlsplit

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "novatube_play_review"))
from record_review import Scenario, displayed_pattern

NS_PER_MS = 1_000_000
clock = time.monotonic_ns


class Bench(Scenario):
    def setup(self, component, profile, origin, repeats):
        self.component, self.profile = component, profile
        self.origin, self.repeats = origin.rstrip("/"), repeats
        self.receiver_dir = Path(os.environ.get("NOVATUBE_RECEIVER_DIR", self.out))
        self.lab_mode = "both"  # captures ADB réessayées sur les deux éditions LAB comparées
        self.report.update(profile=profile, fixture=self.origin, trials=[], errors=[],
                           repeats_per_temperature=repeats, clock="runner CLOCK_MONOTONIC",
                           local_measurement="borne du geste ADB à la première mire plein écran observée")
        badging = self.adb("shell", "dumpsys", "package", self.package)
        if not re.search(r"\bversionCode=" + str(self.expected_version) + r"\b", badging):
            raise ValueError("Version de NovaTube installée différente de la version annoncée")
        location = self.adb("shell", "pm", "path", self.package).strip().splitlines()
        if len(location) != 1 or not location[0].startswith("package:"):
            raise ValueError("APK universel absent")
        digest = self.adb("shell", "sha256sum", location[0][8:], timeout=100).split()[0]
        if digest != self.expected_digest:
            raise ValueError("Empreinte installée divergente")
        self.report.update(apk_sha256=digest, version_code=self.expected_version,
                           android_api=int(self.adb("shell", "getprop", "ro.build.version.sdk").strip()))
        features = self.adb("shell", "pm", "list", "features")
        if ("android.software.leanback" in features) != (profile == "tv"):
            raise ValueError("Le profil du banc ne correspond pas aux capacités Android")
        self.restart()
        if not self.lab_home(2):
            self.open_import_form()
            self.adb("shell", "input", "text", self.origin + "/review.m3u")
            self.key("KEYCODE_ENTER", 3)
            if not self.lab_home(4):
                self.key("KEYCODE_DPAD_CENTER", 1)
        if not self.lab_home(40):
            raise RuntimeError("L'accueil ou la playlist synthétique n'a pas chargé")
        self.save()

    def open_import_form(self):
        # Le formulaire peut arriver après une transition lente. Sur l'accueil,
        # « playlist » figure aussi dans le sous-titre, distinct du bouton M3U.
        self.tap(self.lab_import_button())
        selected = time.monotonic()
        deadline = selected + 100
        ok_sent = False
        while time.monotonic() < deadline:
            words = self.words()
            names = {w for w, _, _ in words}
            if (names & {"paste", "coller", "file", "fichier"} and
                    names & {"source", "url", "http", "name", "nom", "optional", "optionnel", "username"}):
                self.screenshot("source-form")
                return
            # Le champ URL et le clavier constituent un second témoin. On
            # n'envoie jamais OK tant qu'un éditeur de NovaTube a le focus.
            edit = self.accessibility_point(r"m3u url|url m3u|https?://", package=self.package)
            if edit and not (names & {"welcome", "bienvenue"}):
                self.screenshot("source-form")
                return
            row = [(w, x, y) for w, x, y in words if .3 < y/self.height < .75]
            button = next(((x, y) for w, x, y in row if w in {"m3u", "playlist", "liste"}
                           and x < self.width * .5 and any(
                               ow == "xtream" and abs(oy-y) < self.height*.04 for ow, _, oy in row)), None)
            if button and not ok_sent and time.monotonic() - selected > 9:
                # La première sélection peut simplement donner le focus au
                # bouton sur Android TV. Le formulaire doit encore être absent.
                self.key("KEYCODE_DPAD_CENTER", .4)
                ok_sent = True
            time.sleep(.35)
        raise RuntimeError("Formulaire M3U absent après sélection du bouton et contrôle du focus")

    def save(self):
        super().save()
        groups = {}
        for trial in self.report.get("trials", []):
            if not trial.get("ok"):
                continue
            key = trial["path"] + "/" + trial["temperature"]
            groups.setdefault(key, []).append(trial["delay_ms"])
        result = {key: dict(n=len(values), minimum_ms=min(values), median_ms=statistics.median(values),
                            maximum_ms=max(values)) for key, values in groups.items()}
        record = {**self.report, "summary": result}
        target = self.out / "measurements.json"
        tmp = target.with_suffix(".tmp")
        tmp.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        tmp.replace(target)

    def restart(self):
        self.adb("shell", "am", "force-stop", self.package)
        self.adb("shell", "am", "start", "-W", "-n", self.component, timeout=60)

    def tap(self, point):
        if point is None:
            raise RuntimeError("Commande de l'interface absente")
        started = clock()
        self.adb("shell", "input", "tap", str(point[0]), str(point[1]))
        return started

    def locate(self, expr, bounds=(0, 0, 1, 1), timeout=8, semantics=None):
        p = self.find(expr, bounds=bounds, timeout=timeout)
        if p is None and semantics:
            p = self.accessibility_point(semantics, region=bounds, package=self.package)
        return p

    def image(self):
        before = clock()
        raw = self.adb("exec-out", "screencap", "-p", binary=True)
        after = clock()
        with Image.open(io.BytesIO(raw)) as im:
            frame, bars = displayed_pattern(im)
        return before, after, raw, frame, bars

    def verify_not_fullscreen(self):
        if self.image()[-1] >= 5:
            raise RuntimeError("Une mire plein écran était déjà visible avant la commande mesurée")

    def first_picture(self, started, trial):
        first, last_blank = None, started
        deadline = time.monotonic() + 46
        while time.monotonic() < deadline:
            before, after, raw, frame, bars = self.image()
            if bars >= 5:
                if first is None:
                    first = frame
                    (self.out / (trial["id"] + "-first.png")).write_bytes(raw)
                    trial["first_visible_lower_ms"] = round((last_blank - started) / NS_PER_MS, 1)
                    trial["first_visible_upper_ms"] = round((after - started) / NS_PER_MS, 1)
                    trial["bars"] = bars
                else:
                    moved = sum(max(p) > 30 for p in ImageChops.difference(first, frame).getdata())
                    if moved >= frame.width * frame.height * .008:
                        (self.out / (trial["id"] + "-motion.png")).write_bytes(raw)
                        trial["changing_pixels"] = moved
                        trial["delay_ms"] = trial["first_visible_upper_ms"]
                        return
            elif first is None:
                last_blank = before
            time.sleep(.16)
        raise TimeoutError("Aucune preuve de première image plein écran suivie de mouvement")

    def focused_target(self, point, expr):
        # Confirmer uniquement si le même libellé est toujours à la même place.
        # Un lecteur déjà ouvert peut avoir son propre titre, à un autre endroit.
        words = self.words()
        return any(re.fullmatch(expr, word) and abs(x - point[0]) < self.width * .06 and
                   abs(y - point[1]) < self.height * .035 for word, x, y in words)

    def open_tab(self, path):
        vocab = "live|direct" if path == "live" else "movies|films|cinema"
        semantics = r"\b(live|direct)\b" if path == "live" else r"\b(movies|films|cin[eé]ma)\b"
        tab = self.locate(vocab, timeout=12, semantics=semantics)
        self.tap(tab)
        marker = "orion" if path == "movie" else "mire"
        if not self.find(marker, timeout=4) and self.focused_target(tab, vocab):
            # Le hub contient parfois un titre recommandé. « Tonight » est un
            # témoin supplémentaire qu'on est encore sur l'accueil, avant OK.
            if self.find("tonight|soir", timeout=1):
                self.key("KEYCODE_DPAD_CENTER", .5)

    def play_point(self):
        return self.locate("play|watch|lire|lecture|regarder|resume|reprendre", timeout=7,
                           semantics=r"\b(play|watch|lire|regarder|resume|reprendre)\b")

    def live_point(self):
        # Dans l'écran Direct, la liste des chaînes occupe la colonne centrale.
        return self.locate("mire", (.14, 0, .68, 1), timeout=10,
                           semantics=r"mire locale")

    def movie_detail(self):
        point = self.locate("orion", timeout=10, semantics=r"\borion\b")
        if point is None:
            # Un catalogue M3U peut s'ouvrir sur les catégories avant la grille.
            category = self.locate("all|tous|toutes|movies|films|cinema", (0, .12, .36, 1), timeout=2)
            if category:
                self.tap(category)
            point = self.locate("orion", timeout=12, semantics=r"\borion\b")
        self.tap(point)
        if self.play_point() is None and self.focused_target(point, "orion"):
            self.key("KEYCODE_DPAD_CENTER", .5)

    def back_to_item(self, path):
        for _ in range(3):
            self.key("KEYCODE_BACK", .65)
            point = self.live_point() if path == "live" else self.play_point()
            if point is not None and self.image()[-1] < 5:
                return point
        raise RuntimeError("Retour vers l'élément à rouvrir non confirmé")

    def receiver_event(self, started):
        journal = self.receiver_dir / "receiver-events.jsonl"
        try:
            lines = journal.read_text().splitlines()
        except FileNotFoundError:
            return None
        for line in reversed(lines):
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            timestamp = event.get("monotonic_ns", 0)
            if event.get("event") == "first_real_frame_decoded" and timestamp >= started:
                return timestamp
        return None

    def casting(self, trial):
        point = self.cast_point(2)
        if point is None:
            self.key("KEYCODE_DPAD_CENTER", .35)
            point = self.cast_point(8)
        picker_start = self.tap(point)
        device = self.locate("receiver", timeout=16, semantics=r"NOVATUBE QA Receiver")
        device_visible = clock()
        trial["picker_to_visible_target_upper_ms"] = round((device_visible - picker_start) / NS_PER_MS, 1)
        started = self.tap(device)
        deadline = time.monotonic() + 55
        first = None
        while time.monotonic() < deadline:
            first = self.receiver_event(started)
            state = self.receiver()
            if first is not None and state["state"] == "PLAYING" and state["decoded_frames"] >= 10:
                break
            time.sleep(.4)
        else:
            raise RuntimeError("Première image horodatée et lecture effective du récepteur DLNA absentes")
        trial["receiver_first_frame_monotonic_ns"] = first
        trial["selection_monotonic_ns"] = started
        trial["delay_ms"] = round((first - started) / NS_PER_MS, 1)
        trial["decoded_frames_after_start"] = state["decoded_frames"]
        self.allow_notifications()
        # Vérifier la continuité distante au retour à l'accueil et le Stop par l'interface.
        self.key("KEYCODE_HOME", .7)
        count = self.receiver()["decoded_frames"]
        time.sleep(3)
        delta = self.receiver()["decoded_frames"] - count
        if delta < 10:
            raise RuntimeError("La diffusion en arrière-plan ne progresse pas")
        trial["decoded_frames_in_background"] = delta
        self.adb("shell", "am", "start", "-n", self.component)
        time.sleep(1.5)
        point = self.accessibility_point(r"stop casting|arrêter la diffusion|arrêter le cast")
        if point is None:
            self.key("KEYCODE_DPAD_CENTER", .3)
            point = self.accessibility_point(r"stop casting|arrêter la diffusion|arrêter le cast")
        self.tap(point)
        deadline = time.monotonic() + 12
        while self.receiver()["state"] != "STOPPED":
            if time.monotonic() >= deadline:
                raise RuntimeError("Arrêt du récepteur non confirmé")
            time.sleep(.35)

    def trial(self, path, index, temperature):
        result = {"id": f"{path}-{index+1}-{temperature}", "path": path, "temperature": temperature, "ok": False}
        self.report["trials"].append(result)
        try:
            item = "live" if path == "cast" else path
            if temperature == "cold":
                self.restart()
                if not self.lab_home(22):
                    raise RuntimeError("Accueil LAB absent après arrêt du processus")
                self.open_tab(item)
                if item == "movie":
                    self.movie_detail()
                point = self.live_point() if item == "live" else self.play_point()
            else:
                point = self.back_to_item(item)
            self.verify_not_fullscreen()
            started = self.tap(point)
            try:
                self.first_picture(started, result)
                result["start_gesture"] = "touch"
            except TimeoutError:
                expr = "mire" if item == "live" else "play|watch|lire|lecture|regarder|resume|reprendre"
                if not self.focused_target(point, expr) or self.image()[-1] >= 5:
                    raise
                # Un premier tap a pu donner uniquement le focus. Le délai
                # total conserve cette attente. On mesure aussi OK séparément.
                confirmed = clock()
                self.adb("shell", "input", "keyevent", "KEYCODE_DPAD_CENTER")
                self.first_picture(confirmed, result)
                result["start_gesture"] = "focus_touch_then_dpad_center"
                result["time_before_confirm_ms"] = round((confirmed-started) / NS_PER_MS, 1)
                result["delay_after_confirm_ms"] = result["delay_ms"]
                for bound in ("first_visible_lower_ms", "first_visible_upper_ms"):
                    result[bound] = round(result[bound] + result["time_before_confirm_ms"], 1)
                result["delay_ms"] = result["first_visible_upper_ms"]
            if path == "cast":
                result["local_delay_ms"] = result.pop("delay_ms")
                self.casting(result)
            result["ok"] = True
        except Exception as exc:
            result["error"] = str(exc)
            raise
        finally:
            self.save()

    def touch_record_control(self, start):
        if self.profile != "tv":
            return super().touch_record_control(start)
        # Sur TV l'icône REC peut disparaître avec la barre. La touche dédiée
        # reste active dans le lecteur plein écran, pour démarrer et arrêter.
        name = "tv-remote-start" if start else "tv-remote-stop"
        self.screenshot(name)
        self.key("KEYCODE_R", .35)
        return {"control": "KEYCODE_R", "event": "start" if start else "stop",
                "screenshot": name + ".png"}

    def step(self, text, **details):
        if self.profile == "tv":
            text = {
                "Touchscreen recording check started in the normal player":
                    "Android TV remote REC check started in the normal player",
                "User recorded the moving test pattern and its tone by touch; shared MP4 survived app restart":
                    "Android TV remote REC produced moving video and tone; shared MP4 survived app restart",
            }.get(text, text)
        return super().step(text, **details)

    def exercise(self):
        paths = ["live", "movie"] + (["cast"] if self.profile == "phone" else [])
        for path in paths:
            try:
                for i in range(self.repeats):
                    for temp in ["cold", "warm"]:
                        self.trial(path, i, temp)
            except Exception as exc:
                self.report["errors"].append({"path": path, "reason": str(exc)})
                self.save()
        # Une capture REC sur la source VPN. Le lecteur est remis dans l'état Direct après les parcours.
        try:
            self.restart()
            if not self.lab_home(24):
                raise RuntimeError("Accueil absent pour la vérification REC")
            self.open_tab("live")
            self.tap(self.live_point())
            self.local_pattern_motion()
            self.verify_handset_recording()
            if self.profile == "tv":
                self.report["tv_local_recording"] = self.report.pop("handset_local_recording")
        except Exception as exc:
            self.report["errors"].append({"path": "record", "reason": str(exc)})
            self.save()
        self.report["validated"] = not self.report["errors"]
        self.save()
        return self.report["validated"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--serial", default="emulator-5554")
    p.add_argument("--component", required=True)
    p.add_argument("--package", required=True)
    p.add_argument("--expected-version", required=True, type=int)
    p.add_argument("--expected-digest", required=True)
    args = p.parse_args()
    args.out.mkdir(exist_ok=True, parents=True)
    profile = os.environ["NOVATUBE_PERF_PROFILE"]
    origin = os.environ["NOVATUBE_QA_ORIGIN"]
    if profile not in ("phone", "tv") or urlsplit(origin).hostname not in ("192.0.2.1", "127.0.0.1", "10.0.2.2"):
        p.error("Profil ou source de mire hors du banc")
    bench = Bench(args.out, args.serial, expected_version=args.expected_version,
                  package=args.package, expected_digest=args.expected_digest)
    try:
        bench.setup(args.component, profile, origin, int(os.environ.get("NOVATUBE_PERF_REPEATS", "3")))
        if not bench.exercise():
            raise RuntimeError("Parcours incomplet : " + str(bench.report["errors"]))
    except Exception as exc:
        bench.report.setdefault("errors", []).append({"stage": "run", "reason": str(exc)})
        bench.save()
        raise


if __name__ == "__main__":
    main()
