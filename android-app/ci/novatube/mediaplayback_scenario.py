#!/usr/bin/env python3
"""Parcours Cast réel et qualification mediaPlayback, sans commande de lecture SOAP.

Le contrôleur fournit le vrai renderer et l'appareil provenant de l'AAB
vérifié. Ce module utilise seulement l'interface Android pour commencer et
arrêter le Cast. Les observations partielles restent des diagnostics.
"""

from __future__ import annotations

from datetime import datetime
import ipaddress
import json
import math
from pathlib import Path, PurePosixPath
import re
import subprocess
import time
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

import run_datasync_evidence as shared


PLAYLIST_URL = "http://127.0.0.1:18765/playlist.m3u"
PLAYBACK_TEXT = "Lecture audio en arrière-plan"
PACKAGE, CHANNEL, SYSTEM_UI = shared.PACKAGE, shared.CHANNEL, shared.SYSTEM_UI
require = shared.require


def playback_service(raw: str) -> dict:
    """Ne pas confondre le service REC1001/type1 et le service Cast1002/type2."""
    component = re.compile(re.escape(PACKAGE) + r"/(?:\.PlaybackForegroundService|"
                           + re.escape(PACKAGE) + r"\.PlaybackForegroundService)\b")
    matches = []
    for block in re.split(r"(?m)(?=^\s*\* ServiceRecord\{)", raw):
        header = next((line for line in block.splitlines() if "* ServiceRecord{" in line), "")
        if component.search(header) and re.search(r"\bisForeground=true\b", block):
            matches.append(block)
    require(len(matches) <= 1, "Plusieurs services Playback actifs inattendus")
    if not matches:
        return {"foreground": False, "type": None}
    lines = [line for line in matches[0].splitlines() if re.search(r"\bisForeground=true\b", line)]
    require(len(lines) == 1, "Ligne foreground Playback ambiguë")
    values = re.findall(r"\b(?:foregroundServiceType|types)=(0x[0-9a-fA-F]+|[0-9]+)\b", lines[0])
    require(len(values) == 1, "Type mediaPlayback numérique absent ou ambigu")
    kind = int(values[0], 16 if values[0].startswith("0x") else 10)
    require(kind == 2 and re.search(r"\bforegroundId=1002\b", lines[0]) is not None,
            "Le service n'est pas exclusivement mediaPlayback avec notification1002")
    return {"foreground": True, "type": 2}


def unique_button(xml: str, label: str) -> tuple[int, int, int, int]:
    matches = [shared.bounds(node) for node in ET.fromstring(xml).iter("node")
               if node.get("package") == PACKAGE and shared.normalized(label) in shared.labels(node)
               and node.get("enabled") == "true" and node.get("clickable") == "true" and shared.bounds(node)]
    require(len(matches) == 1, "Bouton Cast absent, désactivé ou ambigu : " + label)
    return matches[0]


def playback_notifications(xml: str) -> list:
    rows = []
    for node in ET.fromstring(xml).iter("node"):
        if node.get("package") == SYSTEM_UI and node.get("resource-id", "").endswith("/expandableNotificationRow"):
            labels = shared.observed_labels(ET.tostring(node, encoding="unicode"), SYSTEM_UI)
            if {shared.normalized(CHANNEL), shared.normalized(PLAYBACK_TEXT)} <= labels:
                rows.append(node)
    return rows


def validate_relay_uri(uri: str, guest_ip: str) -> str:
    require(isinstance(uri, str), "URI relais absente")
    address = ipaddress.IPv4Address(guest_ip)
    require(address in ipaddress.IPv4Network("192.0.2.0/24"), "Adresse Android hors du réseau TAP observé")
    value = urlsplit(uri)
    require(value.scheme == "http" and value.hostname == str(address) and value.port is not None
            and 1 <= value.port <= 65535 and value.username is None and value.password is None
            and not value.query and not value.fragment
            and re.fullmatch(r"/relay/[A-Za-z0-9]{10}\.ts", value.path) is not None,
            "URI autre que le relais local NOVATUBE sur l'adresse Android")
    return uri


def sample_time(sample: dict) -> datetime:
    value = datetime.fromisoformat(sample.get("atUtc", ""))
    require(value.tzinfo is not None and value.utcoffset().total_seconds() == 0,
            "Horodatage renderer UTC absent")
    return value


def validate_playing_sample(sample: dict, guest_ip: str) -> str:
    require(isinstance(sample, dict), "Observation renderer absente")
    uri = validate_relay_uri(sample.get("relayUri"), guest_ip)
    require(sample.get("uri") == uri and sample.get("transportState") == "PLAYING",
            "Le vrai AVTransport ne lit pas le relais attendu")
    require(sample.get("rendererGetObserved") is True and sample.get("relayConnectionClosed") is False
            and type(sample.get("relayBytes")) is int and sample["relayBytes"] > 1880,
            "Aucun GET renderer avec octets utiles sur cette connexion relais")
    require(sample.get("directErrorObserved") is True and sample.get("directStoppedObserved") is True,
            "Échec réel de la source loopback directe non observé")
    contrasts, differences, frames = sample.get("frameContrast", []), sample.get("frameDifferences", []), sample.get("frameFiles", [])
    require(sample.get("videoMotion") is True and len(contrasts) == 3 and len(differences) == 2
            and all(type(value) in (int, float) and math.isfinite(value) and value > 25 for value in contrasts)
            and all(type(value) in (int, float) and math.isfinite(value) and value > 1.0 for value in differences)
            and len(frames) == 3 and all(isinstance(value, str) and value for value in frames)
            and len(set(frames)) == 3, "Trois vraies images renderer contrastées et animées sont requises")
    window = sample.get("receiverVideoWindow", {})
    rectangle = window.get("bounds", []) if isinstance(window, dict) else []
    require(isinstance(window, dict) and re.fullmatch(r"0x[0-9a-fA-F]+", str(window.get("id", ""))) is not None
            and int(window["id"], 16) > 0 and type(window.get("rendererPid")) is int and window["rendererPid"] > 0
            and re.fullmatch(r":\d+(?:\.\d+)?", str(window.get("display", ""))) is not None
            and len(rectangle) == 4 and all(type(value) is int for value in rectangle)
            and 0 <= rectangle[0] < rectangle[2] and 0 <= rectangle[1] < rectangle[3],
            "Fenêtre vidéo X11 du vrai renderer non identifiée")
    sample_time(sample)
    return uri


def qualify(observations: dict) -> None:
    require(observations.get("notificationPermission") is True and observations.get("liveMotion") is True,
            "Permission ou lecture locale réelle non observée")
    require(observations.get("userCastTargetTap") is True and observations.get("userStopCastingTap") is True,
            "Les actions Cast de l'interface doivent être observées")
    require(observations.get("serviceBefore") == {"foreground": False, "type": None}
            and observations.get("serviceDuring") == {"foreground": True, "type": 2}
            and observations.get("serviceBackground") == {"foreground": True, "type": 2}
            and observations.get("serviceAfter") == {"foreground": False, "type": None},
            "Cycle mediaPlayback1002 incomplet")
    require(observations.get("notificationVisible") is True and observations.get("notificationRemoved") is True
            and observations.get("homeObserved") is True and observations.get("stillBackground") is True,
            "Notification ou maintien de l'app en arrière-plan non observés")
    samples = [observations.get(key, {}) for key in ("rendererConnected", "rendererBackgroundStart", "rendererBackgroundEnd")]
    require([sample.get("phase") for sample in samples] == ["connected", "background-start", "background-end"],
            "Phases renderer absentes ou réutilisées")
    uris = [validate_playing_sample(sample, observations.get("guestIp", "")) for sample in samples]
    require(len(set(uris)) == 1, "La connexion relais a changé pendant la preuve")
    require(len({frame for sample in samples for frame in sample["frameFiles"]}) == 9
            and sample_time(samples[0]) <= sample_time(samples[1]) < sample_time(samples[2]),
            "Les images renderer ne proviennent pas de trois observations successives distinctes")
    require(samples[1]["relayBytes"] >= samples[0]["relayBytes"]
            and samples[2]["relayBytes"] > samples[1]["relayBytes"] + 1880
            and (sample_time(samples[2]) - sample_time(samples[1])).total_seconds() >= 8,
            "Le relais ne progresse pas pendant huit secondes en arrière-plan")
    stopped = observations.get("rendererStopped", {})
    require(stopped.get("transportState") == "STOPPED" and stopped.get("relayConnectionClosed") is True
            and stopped.get("relayUri") == uris[0] and stopped.get("oldUriRefused") is True
            and stopped.get("oldUriHttpStatus") == 404
            and type(stopped.get("relayBytes")) is int and stopped["relayBytes"] >= samples[2]["relayBytes"],
            "Arrêt réel du renderer, fin de connexion ou retrait du jeton non observé")
    for key in ("phoneVideoProbe", "rendererVideoProbe"):
        video = observations.get(key, {})
        require(video.get("videoCodec") == "h264" and 20 <= video.get("durationSeconds", 0) <= 181
                and video.get("decodeScope") == "entire-file" and video.get("excludedTailSeconds") == 0,
                "Vidéo réelle absente, tronquée ou trop courte : " + key)
        timeline = observations.get(key.replace("Probe", "Timeline"), [])
        require(len(timeline) == 4 and all(type(value) in (int, float) and math.isfinite(value) for value in timeline)
                and 0 <= timeline[0] < timeline[1] < timeline[2] < timeline[3]
                and timeline[2] - timeline[1] >= 8 and timeline[3] + 1 <= video["durationSeconds"],
                "La vidéo ne contient pas Cast, Home, arrêt UI et arrêt réel : " + key)


class MediaPlaybackScenario(shared.Scenario):
    def prepare_live(self):
        # Même formulaire réellement observé dans REC ; seule l'adresse de
        # la fixture diffère pour forcer un véritable repli DLNA vers le relais.
        _, self.language = self.helpers.await_screen(self.device, self.translations, "home")
        self.tap(self.translated("tvNavServer"), scroll=True)
        self.wait_labels([self.translated("tvMySources"), self.translated("tvAddM3u")])
        self.tap(self.translated("tvAddM3u"))
        title, mode = self.translated("tvAddListTitle"), self.translated("playlistTypeM3u")
        self.wait_labels([title, mode])
        self.tap(mode)
        self.wait_labels([title, mode])
        xml = self.observe("m3u-form")
        self.tap_rectangle(shared.m3u_editor_bounds(xml, title, mode), "champ URL unique du mode M3U observé")
        self.device.command("shell", "input", "text", PLAYLIST_URL)
        self.wait_labels([PLAYLIST_URL])
        if re.search(r"\bmInputShown=true\b", self.device.command("shell", "dumpsys", "input_method")):
            self.device.command("shell", "input", "keyevent", "KEYCODE_BACK")
        self.tap(self.translated("tvAddListValidate"), scroll=True)
        self.wait_labels([self.translated("tvMySources"), self.translated("tvMyListHint")], timeout=90)
        self.device.command("shell", "input", "keyevent", "KEYCODE_BACK")
        self.helpers.await_screen(self.device, self.translations, "home")
        self.tap(self.translated("tvNavLive"))
        self.wait_labels([CHANNEL])
        self.tap(CHANNEL, scroll=True)
        self.player_controls([CHANNEL, self.translated("tvRec")])
        self.observe("live-loaded")

    def service(self, expected: bool, name: str) -> dict:
        def probe():
            raw = self.device.command("shell", "dumpsys", "activity", "services", PACKAGE)
            (self.stage / (name + "-services.txt")).write_text(raw, encoding="utf-8")
            state = playback_service(raw)
            return state if state["foreground"] is expected else None
        state = self.wait(probe, "État mediaPlayback non atteint", 20)
        self.event("playback-service", phase=name, **state)
        return state

    def cast_state(self, friendly_name: str, *, picker: bool) -> str:
        self.device.foreground()
        xml = self.observe("cast-picker" if picker else "cast-active")
        observed = shared.observed_labels(xml)
        title = self.translated("castSendTo" if picker else "castStopTooltip")
        require({shared.normalized(title), shared.normalized(friendly_name)} <= observed,
                "Sélecteur ou session Cast du vrai renderer non observés")
        unique_button(xml, friendly_name if picker else self.translated("castStopTooltip"))
        return xml

    def start_cast(self, friendly_name: str):
        self.device.foreground()
        xml = self.observe("cast-before-picker")
        require(bool(shared.video_surfaces(xml)), "Le sélecteur doit partir du lecteur vidéo observé")
        self.tap_rectangle(unique_button(xml, self.translated("castIdle")), self.translated("castIdle"))
        xml = self.wait(lambda: self.cast_state(friendly_name, picker=True), "Vrai renderer absent du sélecteur", 30)
        self.tap_rectangle(unique_button(xml, friendly_name), friendly_name)
        self.event("user-cast-target", friendlyName=friendly_name)
        self.wait(lambda: self.cast_state(friendly_name, picker=False), "Session Cast non établie dans l'interface", 100)

    def renderer_sample(self, renderer, phase: str, timeout=20) -> dict:
        def probe():
            sample = renderer.sample(phase)
            (self.stage / (phase + "-renderer.json")).write_text(json.dumps(sample, indent=2) + "\n", encoding="utf-8")
            require(sample.get("phase") == phase, "Phase renderer différente de celle demandée")
            validate_playing_sample(sample, renderer.guest_ip)
            for filename in sample["frameFiles"]:
                path = PurePosixPath(filename)
                require(not path.is_absolute() and ".." not in path.parts and path.suffix == ".png",
                        "Chemin PNG renderer inattendu")
                image = self.stage / filename
                require(image.is_file() and not image.is_symlink() and self.stage.resolve() in image.resolve().parents
                        and image.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), "PNG renderer absent")
            return sample
        value = self.wait(probe, "Lecture réelle du renderer non prouvée : " + phase, timeout)
        self.event("renderer-playing", phase=phase, uri=value["relayUri"], relayBytes=value["relayBytes"])
        return value

    def background_still_observed(self) -> bool:
        raw = self.device.command("shell", "dumpsys", "activity", "activities")
        (self.stage / "background-end-activity.txt").write_text(raw, encoding="utf-8")
        resumed = [line for line in raw.splitlines() if "topResumedActivity=" in line or "mResumedActivity:" in line]
        require(resumed and all(PACKAGE + "/" not in line for line in resumed), "NOVATUBE est revenu au premier plan")
        return True

    def notification(self, expected: bool) -> bool:
        self.device.command("shell", "cmd", "statusbar", "expand-notifications")
        def probe():
            xml = self.observe("playback-notification-visible" if expected else "playback-notification-removed")
            if expected:
                require(len(playback_notifications(xml)) == 1, "Notification playback visible absente ou ambiguë")
            else:
                require(any(node.get("package") == SYSTEM_UI
                            and node.get("resource-id", "").endswith("/notification_stack_scroller")
                            for node in ET.fromstring(xml).iter("node")), "Volet de notifications non reconnu")
                require(not playback_notifications(xml), "Notification playback encore visible")
            return xml
        self.wait(probe, "État visible de notification non atteint", 15)
        name = "playback-notification-present.png" if expected else "playback-notification-removed.png"
        (self.stage / name).write_bytes(self.device.binary("exec-out", "screencap", "-p"))
        self.event("playback-notification", visible=expected, imageFile=name)
        return True

    def stop_cast(self, friendly_name: str):
        self.device.command("shell", "cmd", "statusbar", "collapse")
        self.device.command("shell", "am", "start", "-W", "-n", PACKAGE + "/" + PACKAGE + ".NovatubeActivity")
        xml = self.wait(lambda: self.cast_state(friendly_name, picker=False), "Session Cast absente au retour", 20)
        self.tap_rectangle(unique_button(xml, self.translated("castStopTooltip")), self.translated("castStopTooltip"))
        self.event("user-stop-casting")


def execute_ui(device, helpers, translations, stage: Path, renderer) -> dict:
    """Le contrôleur conserve fixture et renderer actifs jusqu'à ce retour."""
    flow, observations = MediaPlaybackScenario(device, helpers, translations, stage), {"guestIp": renderer.guest_ip}
    require(isinstance(renderer.friendly_name, str) and renderer.friendly_name.strip(), "Nom réel du renderer absent")
    device.command("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
    permission = device.command("shell", "dumpsys", "package", PACKAGE)
    observations["notificationPermission"] = bool(re.search(r"android\.permission\.POST_NOTIFICATIONS:\s+granted=true", permission))
    (stage / "notification-permission.txt").write_text(permission, encoding="utf-8")
    require(observations["notificationPermission"], "Autorisation de notification non vérifiée")
    flow.event("permission-precondition", permission="POST_NOTIFICATIONS", method="adb-pm-grant-on-disposable-emulator")
    try:
        with shared.application_logs(device, stage):
            flow.prepare_live()
            flow.await_live_contrast()
            observations["liveMotion"] = flow.motion("live")
            observations["serviceBefore"] = flow.service(False, "before")
            with renderer.recording(flow.event), shared.screen_recording(device, stage / "mediaplayback-phone.mp4", flow.event):
                flow.start_cast(renderer.friendly_name)
                observations["userCastTargetTap"] = True
                observations["rendererConnected"] = flow.renderer_sample(renderer, "connected")
                observations["serviceDuring"] = flow.service(True, "casting")
                flow.home_background()
                observations["homeObserved"] = True
                observations["rendererBackgroundStart"] = flow.renderer_sample(renderer, "background-start")
                time.sleep(8)
                observations["rendererBackgroundEnd"] = flow.renderer_sample(renderer, "background-end")
                observations["stillBackground"] = flow.background_still_observed()
                observations["serviceBackground"] = flow.service(True, "background")
                observations["notificationVisible"] = flow.notification(True)
                flow.stop_cast(renderer.friendly_name)
                observations["userStopCastingTap"] = True
                observations["serviceAfter"] = flow.service(False, "after-stop")
                observations["rendererStopped"] = renderer.wait_stopped(observations["rendererConnected"]["relayUri"], timeout=20)
                flow.event("renderer-stop-confirmed")
                observations["notificationRemoved"] = flow.notification(False)
                # REC9 a mesuré 2,453 s d'écart entre les marqueurs muraux
                # et le MP4 ; conserver une fin visible sans assouplir qualify.
                time.sleep(5)
            observations["phoneVideoProbe"] = shared.probe_media(stage / "mediaplayback-phone.mp4")
            observations["rendererVideoProbe"] = shared.probe_media(renderer.video_path)
            for key, start_event in (("phoneVideoTimeline", "video-start"), ("rendererVideoTimeline", "renderer-video-start")):
                start = next(event["seconds"] for event in flow.events if event["action"] == start_event)
                observations[key] = [next(event["seconds"] for event in flow.events if event["action"] == action) - start
                                     for action in ("user-cast-target", "home-background", "user-stop-casting", "renderer-stop-confirmed")]
            qualify(observations)
            return observations
    except BaseException:
        # Capturer avant que le contrôleur ferme le renderer et la fixture.
        for filename, arguments in (
            ("failure-services.txt", ("shell", "dumpsys", "activity", "services", PACKAGE)),
            ("failure-activity.txt", ("shell", "dumpsys", "activity", "activities")),
        ):
            try:
                raw = device.command(*arguments, timeout=15)
            except (OSError, subprocess.SubprocessError) as error:
                raw = shared.safe_error(error)
            (stage / filename).write_text(raw, encoding="utf-8")
        try:
            flow.observe("failure-ui")
            (stage / "failure-screen.png").write_bytes(device.binary("exec-out", "screencap", "-p"))
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            (stage / "failure-ui-error.txt").write_text(shared.safe_error(error), encoding="utf-8")
        raise
    finally:
        (stage / "events.json").write_text(json.dumps(flow.events, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (stage / "observations.json").write_text(json.dumps(observations, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
