#!/usr/bin/env python3
"""Banc dataSync du seul AAB NOVATUBE déjà livré par le run épinglé.

Le script de preuves et le binaire ont deux provenances distinctes. Les
vérificateurs, traductions et outils Android sont réutilisés depuis le commit
exact du binaire. Aucune compilation, injection Dart ou commande démarrant
un service à la place de l'utilisateur n'est admise dans ce scénario.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
import zipfile


REPOSITORY = "manzilionellm-dotcom/tvking"
BRANCH = "feature/novatube-play-aab"
CONFIRMATION = "CAPTURER_NOVATUBE_DATASYNC"
# Seul bloc à mettre à jour pour un prochain binaire : relire les preuves du
# nouveau build, puis adapter aussi checkout/run-id/artifact-ids dans le YAML.
# Le vérificateur du commit original contrôle sa propre version du manifeste.
APP_COMMIT = "6b66f0a8302b0cb34c540bb671a4d6d7fae190c6"
APP_RUN = "43597754114"
APP_ATTEMPT = "1"
ARTIFACT_ID = "14115570586"
ARCHIVE_SHA256 = "fb508bea33c8421fcc32448287ba2f676a031ad4196d1ccdbdc253a4f5a26d7d"
AAB_SHA256 = "cc5dab113e0300a7ecec765085eb21a68d11e0acff1594d17490c72433dae8ef"
FIXTURE_SHA256 = "81724394c63e0b5294ba57e47c0e2c631ded3c28e0b0589610c768a64c019694"
PACKAGE = "com.sevenmotion.novatube"
SYSTEM_UI = "com.android.systemui"
CHANNEL = "NOVATUBE_TEST_PATTERN"
PLAYLIST_URL = "http://10.0.2.2:8765/playlist.m3u"
RECORDINGS = "/sdcard/Android/data/" + PACKAGE + "/files/Recordings"
WORKFLOW = ".github/workflows/novatube-play-aab.yml"
# Empreinte du workflow relu avec ce banc ponctuel. La moindre modification
# exige une nouvelle revue du YAML et du SHA du script, pas une garde élargie.
WORKFLOW_SHA256 = "60250d98b61adf8425115c6c6c6978c6bb8fd9eacf81f27e89994f8bb5b7b9b5"
# Le vérificateur de livraison lit déjà le YAML avec WorkflowLoader. Cette
# seconde empreinte contrôle exactement le nouveau job sans permettre que
# son ajout assouplisse les gardes des trois jobs historiques.
DATASYNC_JOB_SHA256 = "590f6eefb468bf54aa089d3aea0344d575c7a1f577b570f06d9002da1126831f"
SCRIPT_ROOT = Path(__file__).resolve().parents[3]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def command(arguments, *, cwd=None, timeout=120, binary=False, input_value=None):
    return subprocess.run([str(value) for value in arguments], cwd=cwd, capture_output=True,
                          text=not binary, input=input_value, check=True, timeout=timeout).stdout


def safe_error(error) -> str:
    text = str(error)
    for name, value in os.environ.items():
        if value and any(word in name.upper() for word in ("PASSWORD", "TOKEN", "SECRET", "CREDENTIAL")):
            text = text.replace(value, "[MASQUÉ]")
    return text


def runtime_context(environment=None) -> dict:
    env = os.environ if environment is None else environment
    owner, sha = REPOSITORY.split("/", 1)[0], env.get("GITHUB_SHA", "")
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
            and env.get("GITHUB_REPOSITORY") == REPOSITORY
            and env.get("GITHUB_REPOSITORY_OWNER") == owner
            and env.get("GITHUB_REF") == "refs/heads/" + BRANCH
            and env.get("GITHUB_ACTOR") == owner and env.get("GITHUB_TRIGGERING_ACTOR") == owner
            and env.get("GITHUB_WORKFLOW_REF") == REPOSITORY + "/" + WORKFLOW + "@refs/heads/" + BRANCH
            and env.get("GITHUB_WORKFLOW_SHA") == sha and env.get("GITHUB_JOB") == "capture_datasync"
            and env.get("NOVATUBE_DATASYNC_CONFIRMATION") == CONFIRMATION
            and re.fullmatch(r"[0-9a-f]{40}", sha) is not None and env.get("REVIEWED_COMMIT") == sha,
            "Run de preuves hors du workflow, job, propriétaire, mode, événement, branche ou SHA approuvés")
    for name in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", env.get(name, "")) is not None, "Contexte de run absent")
    require(not any(value for name, value in env.items() if name.startswith("NOVATUBE_UPLOAD_")
                    or name == "NOVATUBE_KEYSTORE_PATH"), "Une clé de livraison est inutile et interdite ici")
    return {"scriptCommit": sha, "evidenceRunId": env["GITHUB_RUN_ID"],
            "evidenceRunAttempt": env["GITHUB_RUN_ATTEMPT"]}


def verify_workflow_bytes(data: bytes) -> None:
    require(hashlib.sha256(data).hexdigest() == WORKFLOW_SHA256,
            "Le workflow diffère de sa configuration de preuves exactement revue")


def verify_datasync_job(job: dict) -> None:
    require(isinstance(job, dict), "Job dataSync absent")
    canonical = json.dumps(job, sort_keys=True, separators=(",", ":")).encode("utf-8")
    require(hashlib.sha256(canonical).hexdigest() == DATASYNC_JOB_SHA256,
            "Le job dataSync diffère de ses gardes, étapes ou binaire exactement approuvés")


def preflight(original_source: Path) -> dict:
    context = runtime_context()
    verify_workflow_bytes((SCRIPT_ROOT / WORKFLOW).read_bytes())
    require(command(["git", "rev-parse", "HEAD"], cwd=SCRIPT_ROOT).strip() == context["scriptCommit"],
            "Le checkout du script n'est pas celui approuvé")
    require(not command(["git", "status", "--porcelain", "--untracked-files=no"], cwd=SCRIPT_ROOT).strip(),
            "Le script versionné a changé")
    command(["git", "merge-base", "--is-ancestor", APP_COMMIT, context["scriptCommit"]], cwd=SCRIPT_ROOT)
    require(command(["git", "rev-parse", "HEAD"], cwd=original_source).strip() == APP_COMMIT,
            "Les helpers ne proviennent pas du commit exact du binaire")
    require(not command(["git", "status", "--porcelain", "--untracked-files=no"], cwd=original_source).strip(),
            "Les sources originales ont changé")
    return context


def original_helpers(original_source: Path):
    # Ce dossier a été vérifié par git avant l'import. Les gardes du banc
    # initial restent intactes ; seules ses fonctions de lecture/conversion
    # sont appelées, avec le contexte ORIGINAL explicite de l'AAB.
    sys.path.insert(0, str(original_source / "ci/novatube"))
    return importlib.import_module("run_play_evidence")


def extract_original_archive(archive_directory: Path, destination: Path) -> Path:
    archives = [path for path in archive_directory.iterdir() if path.is_file()]
    require(len(archives) == 1 and not archives[0].is_symlink(), "Une seule archive immuable est attendue")
    require(digest(archives[0]) == ARCHIVE_SHA256, "L'archive n'est pas l'artefact approuvé " + ARTIFACT_ID)
    destination.mkdir()
    with zipfile.ZipFile(archives[0]) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Entrée d'archive ambiguë")
        for name in names:
            path = PurePosixPath(name)
            require(not path.is_absolute() and len(path.parts) == 1 and name not in (".", ".."),
                    "Chemin d'archive inattendu")
            with archive.open(name) as source, (destination / name).open("wb") as target:
                shutil.copyfileobj(source, target)
    return destination


def original_context() -> dict:
    return {"sourceCommit": APP_COMMIT, "runId": APP_RUN, "runAttempt": APP_ATTEMPT,
            "runUrl": f"https://github.com/{REPOSITORY}/actions/runs/{APP_RUN}"}


def normalized(value: str) -> str:
    return " ".join(value.replace("\\n", "\n").split()).casefold()


def labels(node) -> set[str]:
    result = set()
    for key in ("text", "content-desc"):
        value = node.get(key, "").replace("\\n", "\n")
        result.update(normalized(part) for part in (value, *value.splitlines()) if part.strip())
    return result


def observed_labels(xml: str, package=PACKAGE) -> set[str]:
    return set().union(*(labels(node) for node in ET.fromstring(xml).iter("node") if node.get("package") == package))


def bounds(node, *, width=1080, height=1920) -> tuple[int, int, int, int] | None:
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if match:
        left, top, right, bottom = map(int, match.groups())
        if 0 <= left < right <= width and 0 <= top < bottom <= height:
            return left, top, right, bottom
    return None


def target_bounds(xml: str, text: str, package=PACKAGE):
    matches = [bounds(node) for node in ET.fromstring(xml).iter("node")
               if node.get("package") == package and normalized(text) in labels(node)
               and node.get("enabled", "true") == "true" and bounds(node)]
    require(bool(matches), "Élément visible absent : " + text)
    return min(matches, key=lambda rect: (rect[2] - rect[0]) * (rect[3] - rect[1]))


def recording_notification(xml: str) -> str:
    # Une action homonyme d'une autre notification n'est jamais utilisée.
    # On exige le conteneur Android réellement observé de notre notification.
    matches = []
    for node in ET.fromstring(xml).iter("node"):
        if node.get("package") != SYSTEM_UI or not node.get("resource-id", "").endswith("/expandableNotificationRow"):
            continue
        content = ET.tostring(node, encoding="unicode")
        if {normalized("Enregistrement en cours"), normalized(CHANNEL)} <= observed_labels(content, SYSTEM_UI):
            matches.append(content)
    require(len(matches) == 1, "Notification d'enregistrement absente ou ambiguë")
    return matches[0]


def video_surfaces(xml: str) -> list:
    # Le lecteur natif crée SurfaceView(context). Ne pas confondre ce
    # composant avec la FlutterSurfaceView globale ou une vue homonyme.
    return [bounds(node) for node in ET.fromstring(xml).iter("node")
            if node.get("package") == PACKAGE
            and node.get("class") in ("android.view.SurfaceView", "android.view.TextureView")
            and bounds(node)]


def foreground_service(text: str) -> dict:
    blocks = re.split(r"(?m)(?=^\s*\* ServiceRecord\{)", text)
    matches = []
    component = re.compile(re.escape(PACKAGE) + r"/(?:\.RecordingForegroundService|"
                           + re.escape(PACKAGE) + r"\.RecordingForegroundService)\b")
    for block in blocks:
        header = next((line for line in block.splitlines() if "* ServiceRecord{" in line), "")
        if component.search(header):
            matches.append(block)
    active = [block for block in matches if re.search(r"\bisForeground=true\b", block)]
    require(len(active) <= 1, "Plusieurs services d'enregistrement actifs inattendus")
    if not active:
        return {"foreground": False, "type": None}
    match = re.search(r"\bforegroundServiceType=(0x[0-9a-fA-F]+|[0-9]+|dataSync)\b", active[0])
    require(match is not None, "Type FGS absent du relevé Android")
    value = match[1]
    kind = 1 if value == "dataSync" else int(value, 16 if value.startswith("0x") else 10)
    require(kind == 1, "Le service observé n'est pas exclusivement dataSync")
    require(re.search(r"\bforegroundId=1001\b", active[0]) is not None, "Notification FGS inattendue")
    return {"foreground": True, "type": kind}


def qualify(observations: dict) -> None:
    require(observations.get("notificationPermission") is True, "Préparation des notifications non attestée")
    require(observations.get("userRecTap") is True and observations.get("userNotificationStopTap") is True,
            "Action utilisateur observée manquante")
    require(observations.get("serviceBefore") == {"foreground": False, "type": None}
            and observations.get("serviceDuring") == {"foreground": True, "type": 1}
            and observations.get("serviceBackground") == {"foreground": True, "type": 1}
            and observations.get("serviceAfter") == {"foreground": False, "type": None},
            "Cycle de vie dataSync incomplet")
    growth, stopped = observations.get("backgroundSizes", []), observations.get("stoppedSizes", [])
    require(len(growth) == 2 and growth[0] > 0 and growth[1] > growth[0] + 1880,
            "Aucune progression réelle du fichier en arrière-plan")
    require(len(stopped) == 2 and stopped[0] >= growth[1] and stopped[1] == stopped[0],
            "L'écriture ne s'est pas stabilisée après l'arrêt")
    require(observations.get("notificationRemoved") is True and observations.get("fixtureServerStopped") is True,
            "Notification ou source encore active pendant la relecture")
    require(observations.get("liveMotion") is True and observations.get("replayMotion") is True,
            "Lecture réelle de la mire et du fichier non observée")
    recording = observations.get("recordingProbe", {})
    require(recording.get("videoCodec") == "h264" and recording.get("audioCodec") == "aac"
            and recording.get("decodedSeconds", 0) >= 6
            and recording.get("decodeScope") == "all-except-final-1s"
            and recording.get("excludedTailSeconds") == 1,
            "Partie utile du fichier enregistré non décodable ou trop courte")
    video = observations.get("videoProbe", {})
    require(video.get("videoCodec") == "h264" and 20 <= video.get("durationSeconds", 0) <= 181
            and video.get("decodeScope") == "entire-file" and video.get("excludedTailSeconds") == 0,
            "Capture de démonstration absente, trop courte ou invalide")
    timeline = observations.get("videoTimeline", [])
    require(len(timeline) == 4 and all(isinstance(value, (int, float)) for value in timeline)
            and 0 <= timeline[0] < timeline[1] < timeline[2] < timeline[3]
            and timeline[2] - timeline[1] >= 8
            and timeline[3] + 1 <= video["durationSeconds"],
            "La vidéo ne contient pas toute la séquence REC, Home, arrêt et relecture")


class FixtureServer:
    """Un vrai flux local décodable, jamais un faux fournisseur ou récepteur."""
    def __init__(self, fixture: Path):
        require(digest(fixture) == FIXTURE_SHA256, "Mire synthétique différente")
        self.fixture, self.processes, self.requests = fixture, set(), []
        self.lock, self.server, self.thread = threading.Lock(), None, None
        self.stopped = False

    def __enter__(self):
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *arguments):
                pass

            def do_GET(self):
                if self.path == "/playlist.m3u":
                    payload = (f'#EXTM3U\n#EXTINF:-1 tvg-id="novatube-test" group-title="Demonstration",{CHANNEL}\n'
                               'http://10.0.2.2:8765/novatube.ts\n').encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/x-mpegurl")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                    return
                if self.path != "/novatube.ts":
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", "video/mp2t")
                self.send_header("Connection", "close")
                self.end_headers()
                event = {"startedUtc": datetime.now(timezone.utc).isoformat(), "bytes": 0}
                with owner.lock:
                    if owner.stopped:
                        return
                    process = subprocess.Popen([
                        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-stream_loop", "-1",
                        "-re", "-i", str(owner.fixture), "-c", "copy", "-f", "mpegts", "pipe:1",
                    ], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                    owner.processes.add(process)
                    owner.requests.append(event)
                try:
                    while data := process.stdout.read(1316):
                        self.wfile.write(data)
                        self.wfile.flush()
                        event["bytes"] += len(data)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    pass
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                    process.stdout.close()
                    event["endedUtc"] = datetime.now(timezone.utc).isoformat()
                    with owner.lock:
                        owner.processes.discard(process)

        self.server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    def stop(self):
        with self.lock:
            self.stopped = True
        if self.server is not None:
            self.server.shutdown()
            self.server.server_close()
            self.server = None
        with self.lock:
            processes = list(self.processes)
        for process in processes:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        if self.thread is not None:
            self.thread.join(timeout=3)

    def __exit__(self, *arguments):
        self.stop()


class Scenario:
    def __init__(self, device, helpers, translations, stage: Path):
        self.device, self.helpers, self.translations, self.stage = device, helpers, translations, stage
        self.events, self.counter, self.language = [], 0, None
        self.started = time.monotonic()

    def event(self, action: str, **details):
        self.events.append({"action": action, "seconds": round(time.monotonic() - self.started, 3),
                            "atUtc": datetime.now(timezone.utc).isoformat(), **details})

    def observe(self, name: str) -> str:
        xml = self.device.hierarchy()
        self.counter += 1
        filename = f"{self.counter:02d}-{name}.xml"
        (self.stage / filename).write_text(xml, encoding="utf-8")
        self.event("observe", state=name, uiFile=filename)
        return xml

    def wait(self, predicate, label: str, timeout=45):
        deadline, last = time.monotonic() + timeout, ""
        while time.monotonic() < deadline:
            try:
                value = predicate()
                if value:
                    return value
            except (ValueError, ET.ParseError, subprocess.SubprocessError) as error:
                last = safe_error(error)
            time.sleep(1)
        raise ValueError(label + " : " + last)

    def wait_labels(self, texts, *, package=PACKAGE, timeout=45):
        def probe():
            if package == PACKAGE:
                self.device.foreground()
            xml = self.device.hierarchy()
            return xml if all(normalized(text) in observed_labels(xml, package) for text in texts) else None
        return self.wait(probe, "Libellés non observés : " + ", ".join(texts), timeout)

    def translated(self, key: str) -> str:
        return self.translations[self.language][key]

    def tap_rectangle(self, rectangle, description):
        left, top, right, bottom = rectangle
        self.event("tap", target=description, observedBounds=list(rectangle))
        self.device.command("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))

    def tap(self, text: str, package=PACKAGE, scroll=False):
        for attempt in range(5 if scroll else 1):
            xml = self.observe("before-tap")
            try:
                rectangle = target_bounds(xml, text, package)
                self.tap_rectangle(rectangle, text)
                return
            except ValueError:
                if not scroll or attempt == 4:
                    raise
                rectangles = [bounds(node) for node in ET.fromstring(xml).iter("node")
                              if node.get("package") == package and node.get("scrollable") == "true" and bounds(node)]
                require(bool(rectangles), "Aucune zone de défilement observée")
                left, top, right, bottom = max(rectangles, key=lambda value: (value[2] - value[0]) * (value[3] - value[1]))
                self.event("scroll", observedBounds=[left, top, right, bottom])
                self.device.command("shell", "input", "swipe", str((left + right) // 2),
                                    str(top + (bottom - top) * 4 // 5), str((left + right) // 2),
                                    str(top + (bottom - top) // 4), "350")

    def service(self, expected: bool, name: str) -> dict:
        def probe():
            raw = self.device.command("shell", "dumpsys", "activity", "services", PACKAGE)
            state = foreground_service(raw)
            return (raw, state) if state["foreground"] is expected else None
        raw, state = self.wait(probe, "État dataSync non atteint", 15)
        (self.stage / (name + "-services.txt")).write_text(raw, encoding="utf-8")
        self.event("service", phase=name, **state)
        return state

    def recording_file(self) -> str:
        listing = self.device.command("shell", "find", RECORDINGS, "-maxdepth", "1", "-type", "f")
        paths = [line.strip() for line in listing.splitlines() if line.strip().endswith(".ts")]
        require(len(paths) == 1, "Un seul enregistrement neuf est attendu")
        path = paths[0]
        require(str(PurePosixPath(path).parent) == RECORDINGS and "\n" not in path and "\r" not in path,
                "Chemin d'enregistrement inattendu")
        return path

    def size(self, path: str) -> int:
        # adb shell réassemble les arguments : citer le nom de fichier qui
        # peut contenir des espaces, même si la mire actuelle n'en contient pas.
        value = self.device.command("shell", "stat", "-c", "%s", shlex.quote(path)).strip()
        require(value.isdigit(), "Taille de fichier non observable")
        return int(value)

    def motion(self, name: str) -> bool:
        xml = self.observe(name + "-player")
        rectangles = video_surfaces(xml)
        require(bool(rectangles), "Surface vidéo réelle absente de la hiérarchie ; aucune zone inventée")
        left, top, right, bottom = max(rectangles, key=lambda value: (value[2] - value[0]) * (value[3] - value[1]))
        # Utiliser le centre de la surface observée évite l'horloge et les
        # commandes de la barre : leur animation ne prouve pas la lecture.
        width, height = right - left, bottom - top
        x, y, width, height = left + width // 5, top + height // 5, width * 3 // 5, height * 3 // 5
        samples = []
        for index in range(3):
            self.device.foreground()
            png = self.device.binary("exec-out", "screencap", "-p")
            require(self.helpers.png_dimensions(png) == (1080, 1920),
                    "Le lecteur a quitté le portrait prévu ; aucune capture tournée n'est qualifiée")
            (self.stage / f"{name}-frame-{index}.png").write_bytes(png)
            pixels = command(["ffmpeg", "-nostdin", "-v", "error", "-f", "image2pipe", "-i", "pipe:0",
                              "-vf", f"crop={width}:{height}:{x}:{y},scale=64:36,format=gray",
                              "-frames:v", "1", "-f", "rawvideo", "pipe:1"], binary=True, input_value=png)
            require(len(pixels) == 64 * 36 and max(pixels) - min(pixels) > 25, "Surface vidéo vide ou uniforme")
            samples.append(pixels)
            time.sleep(0.7)
        differences = [sum(abs(a - b) for a, b in zip(first, second)) / len(first)
                       for first, second in zip(samples, samples[1:])]
        require(min(differences) > 1.0, "Image vidéo sans mouvement observable")
        self.event("motion", phase=name, observedSurface=[left, top, right, bottom], meanPixelDifferences=differences)
        return True

    def prepare_live(self):
        xml, self.language = self.helpers.await_screen(self.device, self.translations, "home")
        self.tap(self.translated("tvNavServer"), scroll=True)
        self.wait_labels([self.translated("tvMySources"), self.translated("tvAddM3u")])
        self.tap(self.translated("tvAddM3u"))
        xml = self.wait_labels([self.translated("tvAddListTitle"), self.translated("tvFieldM3uUrl")])
        editors = [bounds(node) for node in ET.fromstring(xml).iter("node") if node.get("package") == PACKAGE
                   and node.get("class") == "android.widget.EditText" and node.get("enabled") == "true" and bounds(node)]
        require(len(editors) == 1, "Champ M3U absent ou ambigu")
        self.tap_rectangle(editors[0], self.translated("tvFieldM3uUrl"))
        self.device.command("shell", "input", "text", PLAYLIST_URL)
        self.wait_labels([PLAYLIST_URL])
        ime = self.device.command("shell", "dumpsys", "input_method")
        if re.search(r"\bmInputShown=true\b", ime):
            self.device.command("shell", "input", "keyevent", "KEYCODE_BACK")
        self.tap(self.translated("tvAddListValidate"), scroll=True)
        self.wait_labels([self.translated("tvMySources"), self.translated("tvMyListHint")], timeout=90)
        self.device.command("shell", "input", "keyevent", "KEYCODE_BACK")
        self.helpers.await_screen(self.device, self.translations, "home")
        self.tap(self.translated("tvNavLive"))
        self.wait_labels([CHANNEL])
        self.tap(CHANNEL, scroll=True)
        self.wait_labels([CHANNEL, self.translated("tvRec")])
        self.observe("live-loaded")

    def stop_notification(self):
        self.device.command("shell", "cmd", "statusbar", "expand-notifications")
        self.wait_labels(["Enregistrement en cours", CHANNEL], package=SYSTEM_UI)
        xml = recording_notification(self.observe("notification-before-stop"))
        if normalized("Arrêter") not in observed_labels(xml, SYSTEM_UI):
            # Android peut replier les actions. Choisir seulement un bouton
            # d'expansion réellement présent dans la notification observée.
            root = ET.fromstring(xml)
            candidates = [node for node in root.iter("node") if node.get("package") == SYSTEM_UI
                          and node.get("resource-id", "").endswith("/expand_button") and bounds(node)]
            require(len(candidates) == 1, "Notification repliée sans bouton d'expansion non ambigu")
            self.tap_rectangle(bounds(candidates[0]), "notification expand_button")
            self.wait_labels(["Enregistrement en cours", CHANNEL, "Arrêter"], package=SYSTEM_UI)
        xml = recording_notification(self.observe("notification-action-before-stop"))
        self.tap_rectangle(target_bounds(xml, "Arrêter", SYSTEM_UI), "Arrêter dans la notification d'enregistrement")
        self.event("user-notification-stop")

    def navigate_replay(self):
        self.device.command("shell", "cmd", "statusbar", "collapse")
        self.device.command("shell", "am", "start", "-W", "-n", PACKAGE + "/" + PACKAGE + ".NovatubeActivity")
        for _ in range(4):
            xml = self.device.hierarchy()
            if self.helpers.recognized_screen(xml, self.translations, "home"):
                break
            self.device.foreground()
            self.device.command("shell", "input", "keyevent", "KEYCODE_BACK")
            time.sleep(0.5)
        else:
            raise ValueError("Retour à l'accueil non observé")
        self.tap(self.translated("tvNavSettings"), scroll=True)
        self.tap(self.translated("tvMyRecordings"), scroll=True)
        self.wait_labels([self.translated("tvMyRecordings"), CHANNEL])
        self.observe("saved-recording-list")
        self.tap(CHANNEL)
        self.wait_labels([CHANNEL])


def probe_media(path: Path, *, transport_stream=False) -> dict:
    result = json.loads(command(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name,width,height",
                                 "-show_entries", "format=duration,format_name", "-of", "json", path]))
    streams = result.get("streams", [])
    video = next((item for item in streams if item.get("codec_type") == "video"), {})
    audio = next((item for item in streams if item.get("codec_type") == "audio"), {})
    duration = float(result.get("format", {}).get("duration", 0))
    require(math.isfinite(duration) and duration > 0, "Durée du média absente ou invalide")
    excluded_tail = 1 if transport_stream else 0
    decoded_seconds = duration - excluded_tail
    if transport_stream:
        require(result.get("format", {}).get("format_name") == "mpegts" and decoded_seconds >= 6,
                "Enregistrement TS sans six secondes utiles décodables")
    # Un arrêt réseau peut couper la dernière image d'un TS. Conserver le
    # fichier brut et contrôler strictement tout sauf sa dernière seconde,
    # puis imposer sa vraie relecture par l'app. La vidéo MP4 de l'écran est
    # toujours décodée intégralement ; aucune troncature n'y est tolérée.
    interval = ["-t", f"{decoded_seconds:.6f}"] if transport_stream else []
    command(["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-i", path,
             *interval, "-f", "null", "-"], timeout=180)
    return {"videoCodec": video.get("codec_name"), "audioCodec": audio.get("codec_name"),
            "width": video.get("width"), "height": video.get("height"),
            "durationSeconds": duration, "decodedSeconds": decoded_seconds,
            "decodeScope": "all-except-final-1s" if transport_stream else "entire-file",
            "excludedTailSeconds": excluded_tail, "sha256": digest(path)}


@contextmanager
def screen_recording(device, destination: Path, events):
    remote = "/sdcard/novatube-datasync-demo.mp4"
    events("video-start", audioRecorded=False)
    process = subprocess.Popen([str(device.adb), "-s", "emulator-5582", "shell", "screenrecord", "--time-limit", "180",
                                "--size", "720x1280", "--bit-rate", "4000000", remote],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    pid = None
    try:
        time.sleep(1)
        require(process.poll() is None, "screenrecord n'a pas démarré")
        pid = device.command("shell", "pidof", "screenrecord").strip()
        require(re.fullmatch(r"[1-9][0-9]*", pid) is not None, "Processus screenrecord absent ou ambigu")
        events("video-process-confirmed", remotePid=int(pid))
        yield
    finally:
        if pid is not None and process.poll() is None:
            try:
                device.command("shell", "kill", "-2", pid)
            except subprocess.SubprocessError:
                pass
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=10)
        error = process.stderr.read().decode("utf-8", errors="replace")
        process.stderr.close()
        (destination.parent / "screenrecord-log.txt").write_text(safe_error(error), encoding="utf-8")
        # Même une vidéo partielle est récupérée pour diagnostic. Elle ne
        # rejoindra le dossier de preuves que si qualify() réussit ensuite.
        try:
            device.command("pull", remote, str(destination), timeout=90)
        except subprocess.SubprocessError:
            if destination.exists():
                destination.unlink()
        events("video-stop")


def execute_scenario(device, helpers, translations, fixture: Path, stage: Path) -> dict:
    flow, observations = Scenario(device, helpers, translations, stage), {}
    # Préparation explicite d'un appareil jetable, pas une demande d'accès
    # prétendument proposée par le bouton REC. Aucune autre permission.
    device.command("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
    permission = device.command("shell", "dumpsys", "package", PACKAGE)
    observations["notificationPermission"] = bool(re.search(r"android\.permission\.POST_NOTIFICATIONS:\s+granted=true", permission))
    (stage / "notification-permission.txt").write_text(permission, encoding="utf-8")
    require(observations["notificationPermission"], "Autorisation de notification non vérifiée")
    flow.event("permission-precondition", permission="POST_NOTIFICATIONS", method="adb-pm-grant-on-disposable-emulator")
    try:
        with FixtureServer(fixture) as server:
            flow.prepare_live()
            observations["liveMotion"] = flow.motion("live")
            observations["serviceBefore"] = flow.service(False, "before")
            with screen_recording(device, stage / "datasync-demo.mp4", flow.event):
                # Un tap sur la surface réelle dévoile la barre si elle a
                # disparu. Pas de touche REC envoyée à un écran inconnu.
                xml = device.hierarchy()
                if normalized(flow.translated("tvRec")) not in observed_labels(xml):
                    surfaces = video_surfaces(xml)
                    require(len(surfaces) == 1, "Commandes masquées sans surface non ambiguë")
                    flow.tap_rectangle(surfaces[0], "surface vidéo observée")
                flow.wait_labels([flow.translated("tvRec")])
                flow.tap(flow.translated("tvRec"))
                observations["userRecTap"] = True
                flow.event("user-rec")
                flow.wait_labels([flow.translated("tvStop")])
                observations["serviceDuring"] = flow.service(True, "recording")
                recording = flow.wait(flow.recording_file, "Fichier d'enregistrement absent", 15)
                device.command("shell", "input", "keyevent", "KEYCODE_HOME")
                activity = device.command("shell", "dumpsys", "activity", "activities")
                resumed = [line for line in activity.splitlines() if "topResumedActivity=" in line or "mResumedActivity:" in line]
                require(resumed and all(PACKAGE + "/" not in line for line in resumed), "L'app n'est pas passée en arrière-plan")
                (stage / "background-activity.txt").write_text(activity, encoding="utf-8")
                flow.event("home-background")
                first = flow.size(recording)
                time.sleep(8)
                second = flow.size(recording)
                observations["backgroundSizes"] = [first, second]
                observations["serviceBackground"] = flow.service(True, "background")
                flow.event("background-file-growth", sizes=[first, second])
                flow.stop_notification()
                observations["userNotificationStopTap"] = True
                observations["serviceAfter"] = flow.service(False, "after-stop")
                flow.wait(lambda: "enregistrement en cours" not in observed_labels(device.hierarchy(), SYSTEM_UI),
                          "Notification non retirée", 15)
                flow.observe("notification-after-stop")
                observations["notificationRemoved"] = True
                time.sleep(1)
                first = flow.size(recording)
                time.sleep(2)
                second = flow.size(recording)
                observations["stoppedSizes"] = [first, second]
                saved = stage / "recorded-original.ts"
                device.command("pull", recording, str(saved), timeout=60)
                observations["recordingProbe"] = probe_media(saved, transport_stream=True)
                require(saved.stat().st_size == second, "Le fichier récupéré a changé après son arrêt")
                server.stop()
                observations["fixtureServerStopped"] = True
                flow.event("fixture-server-stopped-before-replay")
                flow.navigate_replay()
                observations["replayMotion"] = flow.motion("replay")
                time.sleep(2)
            observations["videoProbe"] = probe_media(stage / "datasync-demo.mp4")
            start = next(event["seconds"] for event in flow.events if event["action"] == "video-start")
            observations["videoTimeline"] = [
                next(event["seconds"] for event in flow.events if event["action"] == action) - start
                for action in ("user-rec", "home-background", "user-notification-stop")
            ] + [next(event["seconds"] for event in flow.events
                      if event["action"] == "motion" and event.get("phase") == "replay") - start]
            observations["fixtureRequests"] = list(server.requests)
        qualify(observations)
        return observations
    finally:
        (stage / "events.json").write_text(json.dumps(flow.events, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (stage / "observations.json").write_text(json.dumps(observations, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def capture(arguments, context: dict):
    original_source = arguments.original_source.resolve()
    helpers = original_helpers(original_source)
    output, diagnostics = arguments.output.resolve(), arguments.diagnostics.resolve()
    require(not output.exists(), "Dossier de preuves déjà présent")
    diagnostics.mkdir(parents=True, exist_ok=False)
    temporary_root = Path(os.environ.get("RUNNER_TEMP", ""))
    require(temporary_root.is_absolute() and temporary_root.is_dir(), "Dossier temporaire du runner absent")
    sdk_text = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME", "")
    require(sdk_text and Path(sdk_text).is_absolute(), "Android SDK absent")
    sdk = Path(sdk_text)
    require(Path("/dev/kvm").exists(), "KVM absent")
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        command(["sudo", "chown", f"{os.getuid()}:{os.getgid()}", "/dev/kvm"])
    translations = {language: json.loads((original_source / "lib/l10n" / f"app_{language}.arb").read_text(encoding="utf-8"))
                    for language in ("en", "fr")}
    with tempfile.TemporaryDirectory(prefix="novatube-datasync-", dir=temporary_root) as folder:
        temporary, stage = Path(folder), Path(folder) / "observations"
        stage.mkdir()
        try:
            verified = extract_original_archive(arguments.archive_dir.resolve(), temporary / "verified")
            aab, provenance = helpers.validate_artifact(verified, original_context())
            require(digest(aab) == AAB_SHA256, "AAB différent du binaire épinglé")
            bundletool = helpers.download_bundletool(temporary)
            identity = helpers.verify_real_bundle(aab, bundletool, provenance)
            helpers.run([sdk / "cmdline-tools/latest/bin/sdkmanager", helpers.IMAGE, "emulator", "platform-tools",
                         "build-tools;" + helpers.BUILD_TOOLS], timeout=900)
            apk = helpers.convert_bundle(aab, bundletool, temporary, sdk)
            with helpers.booted_device(sdk, temporary, diagnostics, helpers.DEVICES[0]) as device:
                device.command("install", str(apk), timeout=180)
                installed = device.command("shell", "dumpsys", "package", PACKAGE)
                require(re.search(r"\bversionCode=" + str(provenance["versionCode"]) + r"\b", installed) is not None
                        and re.search(r"\bversionName=" + re.escape(provenance["versionName"]) + r"\b", installed) is not None,
                        "La version installée ne correspond pas au binaire approuvé")
                (stage / "installed-package.txt").write_text(installed, encoding="utf-8")
                device.command("shell", "am", "start", "-W", "-n", PACKAGE + "/" + identity["launcher"])
                observations = execute_scenario(device, helpers, translations,
                    original_source / "ci/novatube/recording-test-media/novatube-h264-aac.ts", stage)
            require(digest(aab) == AAB_SHA256, "L'AAB a changé")
            report = {"status": "observed-datasync-flow", "humanReviewRequired": True,
                      "humanReviewPending": ["synthetic-pattern-visible-live", "synthetic-pattern-visible-in-local-replay",
                                             "rec-home-notification-stop-actions-legible"], **context,
                      "binarySource": original_context(), "artifactId": ARTIFACT_ID, "archiveSha256": ARCHIVE_SHA256,
                      "aabSha256": AAB_SHA256, "package": PACKAGE,
                      "versionName": provenance["versionName"], "versionCode": provenance["versionCode"],
                      "uploadCertificateSha256": provenance["uploadCertificateSha256"], "appRecompiled": False,
                      "apkSigning": "ephemeral-emulator-only", "fixtureSha256": FIXTURE_SHA256,
                      "notificationPermissionPreparation": "Explicit adb pm grant on disposable emulator; no in-app prompt claimed.",
                      "observations": observations, "mediaPlayback": {"status": "not-demonstrated", "receiverAvailable": False},
                      "audioRecorded": False, "googleSubmission": False,
                      "files": {path.name: digest(path) for path in stage.iterdir() if path.is_file()}}
            (stage / "evidence.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(stage, output)
        except BaseException as error:
            shutil.copytree(stage, diagnostics / "unqualified-observations")
            (diagnostics / "diagnostic.json").write_text(json.dumps({"status": "failed", "qualified": False,
                "error": safe_error(error), "binarySource": original_context(), **context}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-source", type=Path, required=True)
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--archive-dir", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--diagnostics", type=Path)
    arguments = parser.parse_args()
    try:
        context = preflight(arguments.original_source.resolve())
        if arguments.preflight:
            print("Provenances script/binaire et workflow immuable vérifiés ; aucune application lancée.")
            return 0
        require(arguments.archive_dir and arguments.output and arguments.diagnostics, "Dossiers de preuves incomplets")
        capture(arguments, context)
        print("Parcours dataSync observé ; revue humaine de la vidéo requise. mediaPlayback non démontré.")
        return 0
    except (ValueError, KeyError, OSError, ET.ParseError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print("Preuve dataSync non qualifiée : " + safe_error(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
