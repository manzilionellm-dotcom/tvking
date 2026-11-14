"""Observer un vrai renderer et ses paquets ; aucune réponse réseau fabriquée."""
from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET

import run_datasync_evidence as rec

HOST_IP = "192.0.2.1"
DIRECT_URI = "http://127.0.0.1:18765/live/pattern.ts"
OLD_RELAY_AGENT = "NOVATUBE-Probe-Old-Relay-After-UI-Stop"
DISPLAY = ":94.0"
DISPLAY_WIDTH, DISPLAY_HEIGHT = 1280, 720


def require(value, message):
    if not value:
        raise ValueError(message)


def utc():
    return datetime.now(timezone.utc).isoformat()


def relay_uri(value, guest_ip):
    """Fermer la cible au vrai relais DLNA de l'adresse DHCP observée."""
    try:
        uri = urllib.parse.urlsplit(value)
        return bool(uri.scheme == "http" and uri.hostname == guest_ip
                    and uri.port and 1 <= uri.port <= 65535
                    and not uri.username and not uri.password and not uri.query and not uri.fragment
                    and re.fullmatch(r"/relay/[A-Za-z0-9]{10}\.ts", uri.path))
    except ValueError:
        return False


class Prefix:
    """Réassembler seulement les en-têtes TCP ; ne pas conserver le flux vidéo."""
    def __init__(self):
        self.start = None
        self.data = bytearray(16384)
        self.present = bytearray(16384)
        self.end = 0
        self.intervals = []

    def feed(self, sequence, payload):
        if self.start is None or not payload:
            return
        offset = (sequence - self.start) & 0xffffffff
        if offset >= 0x80000000:
            return
        last = offset + len(payload)
        merged = []
        left, right = offset, last
        for a, b in self.intervals:
            if b < left:
                merged.append((a, b))
            elif right < a:
                merged.append((left, right))
                left, right = a, b
            else:
                left, right = min(left, a), max(right, b)
        merged.append((left, right))
        self.intervals = merged
        count = min(len(payload), max(0, len(self.data) - offset))
        if count:
            self.data[offset:offset + count] = payload[:count]
            self.present[offset:offset + count] = b"\x01" * count
        while self.end < len(self.present) and self.present[self.end]:
            self.end += 1

    def header(self):
        value = bytes(self.data[:self.end])
        split = value.find(b"\r\n\r\n")
        return value[:split + 4] if split >= 0 else b""

    def body_bytes(self):
        header = self.header()
        return sum(max(0, b - max(a, len(header))) for a, b in self.intervals) if header else 0


class Pcap:
    """Lire progressivement le PCAP réel écrit par tcpdump, sans doublons TCP."""
    def __init__(self, path, guest_ip, renderer_pid):
        self.path, self.guest_ip, self.renderer_pid = Path(path), guest_ip, renderer_pid
        self.offset, self.endian = 0, None
        self.flows, self.refused_direct = {}, []
        self.direct_syn = {}

    def update(self):
        if not self.path.exists():
            return
        with self.path.open("rb") as source:
            if self.endian is None:
                header = source.read(24)
                if len(header) < 24:
                    return
                require(header[:4] in (b"\xd4\xc3\xb2\xa1", b"\xa1\xb2\xc3\xd4"),
                        "Format PCAP inattendu")
                self.endian = "<" if header[:4] == b"\xd4\xc3\xb2\xa1" else ">"
                require(struct.unpack(self.endian + "I", header[20:24])[0] == 1,
                        "La capture doit porter de vraies trames Ethernet")
                self.offset = 24
            source.seek(self.offset)
            while True:
                header = source.read(16)
                if len(header) < 16:
                    return
                seconds, micros, size, original = struct.unpack(self.endian + "IIII", header)
                require(0 < size <= original <= 262144, "Longueur PCAP incohérente")
                packet = source.read(size)
                if len(packet) < size:
                    return
                self.offset += 16 + size
                self.packet(packet, seconds + micros / 1000000)

    def packet(self, packet, when):
        if len(packet) < 54 or packet[12:14] != b"\x08\x00" or packet[23] != 6:
            return
        ip_start = 14
        tcp_start = ip_start + (packet[ip_start] & 15) * 4
        total = struct.unpack(">H", packet[16:18])[0]
        require(len(packet) >= 14 + total, "Paquet IP tronqué")
        if struct.unpack(">H", packet[20:22])[0] & 0x3fff:
            return
        a, b = str(ipaddress.ip_address(packet[26:30])), str(ipaddress.ip_address(packet[30:34]))
        sport, dport, sequence = struct.unpack(">HHI", packet[tcp_start:tcp_start + 8])
        flags = packet[tcp_start + 13]
        start = tcp_start + ((packet[tcp_start + 12] >> 4) * 4)
        payload = packet[start:14 + total]
        if a == b == "127.0.0.1":
            if dport == 18765 and flags & 2 and not flags & 16:
                self.direct_syn[sport] = when
            if sport == 18765 and flags & 4 and dport in self.direct_syn:
                self.refused_direct.append({"sourcePort": dport, "synAt": self.direct_syn[dport], "resetAt": when})
            return
        if {a, b} != {HOST_IP, self.guest_ip}:
            return
        outgoing = a == HOST_IP
        key = (sport, dport) if outgoing else (dport, sport)
        flow = self.flows.setdefault(key, {"request": Prefix(), "response": Prefix(),
            "closed": False, "owner": False, "firstAt": when, "lastAt": when})
        flow["lastAt"] = when
        stream = flow["request" if outgoing else "response"]
        if flags & 2:
            stream.start = (sequence + 1) & 0xffffffff
        stream.feed(sequence, payload)
        if flags & 5:
            flow["closed"] = True

    def note_socket_owners(self, text):
        pattern = re.compile(re.escape(HOST_IP) + r":(\d+)\s+" + re.escape(self.guest_ip) + r":(\d+)")
        for line in text.splitlines():
            if not re.search(r"\bpid=" + str(self.renderer_pid) + r"\b", line):
                continue
            match = pattern.search(line)
            if match and (key := tuple(map(int, match.groups()))) in self.flows:
                self.flows[key]["owner"] = True

    def relay(self, uri):
        parsed = urllib.parse.urlsplit(uri)
        matches = []
        for (source_port, port), flow in self.flows.items():
            if port != parsed.port or not flow["owner"]:
                continue
            request, response = flow["request"].header(), flow["response"].header()
            if not request or not response or OLD_RELAY_AGENT.encode() in request:
                continue
            if not request.startswith(("GET " + parsed.path + " HTTP/1.").encode()):
                continue
            if not re.match(rb"HTTP/1\.[01] (?:200|206)\b", response):
                continue
            matches.append({"sourcePort": source_port, "destinationPort": port,
                "bytes": flow["response"].body_bytes(), "closed": flow["closed"],
                "requestHeader": request.decode("iso-8859-1"), "responseHeader": response.decode("iso-8859-1"),
                "firstAt": flow["firstAt"], "lastAt": flow["lastAt"], "ownerPid": self.renderer_pid})
        return {"rendererGetObserved": bool(matches), "relayBytes": sum(x["bytes"] for x in matches),
                "relayConnectionClosed": bool(matches) and all(x["closed"] for x in matches), "connections": matches}


class RendererProbe:
    """Observer URI/état UPnP, sockets possédés, octets et vraies images X11."""
    def __init__(self, *, stage, guest_ip, renderer_pid, friendly_name, control_url, service_type,
                 environment, spawn, stop_process):
        self.stage, self.guest_ip, self.renderer_pid = Path(stage), guest_ip, renderer_pid
        self.friendly_name, self.control_url, self.service_type = friendly_name, control_url, service_type
        self.environment, self.spawn, self.stop_process = environment, spawn, stop_process
        self.video_path = self.stage / "renderer-demo.mp4"
        self.started_wall = time.time()
        self.pcap = Pcap(self.stage / "tap.pcap", guest_ip, renderer_pid)
        self.loopback = Pcap(self.stage / "loopback.pcap", guest_ip, renderer_pid)
        self.history, self.errors = [], []
        self.lock, self.done = threading.Lock(), threading.Event()
        self.counter, self.frame_counter, self.sample_counter, self.last_relay = 0, 0, 0, None
        self.thread = threading.Thread(target=self.watch, name="rygel-observer", daemon=True)
        self.thread.start()

    def command(self, arguments, timeout=15, binary=False):
        return subprocess.run([str(x) for x in arguments], env=self.environment,
            capture_output=True, text=not binary, timeout=timeout, check=True).stdout

    def soap(self, action):
        require(action in ("GetMediaInfo", "GetTransportInfo"), "Seules les lectures UPnP sont permises au banc")
        uri = urllib.parse.urlsplit(self.control_url)
        payload = ('<?xml version="1.0" encoding="utf-8"?>'
            '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
            '<s:Body><u:' + action + ' xmlns:u="' + self.service_type + '"><InstanceID>0</InstanceID></u:' + action + '></s:Body></s:Envelope>').encode()
        connection = http.client.HTTPConnection(uri.hostname, uri.port, timeout=3)
        try:
            connection.request("POST", uri.path or "/", body=payload, headers={
                "Content-Type": 'text/xml; charset="utf-8"', "SOAPAction": '"' + self.service_type + "#" + action + '"',
                "Connection": "close"})
            response = connection.getresponse()
            body = response.read(1024 * 1024)
            require(response.status == 200, f"Lecture UPnP {action} refusée : HTTP {response.status}")
            ET.fromstring(body)
            return body
        finally:
            connection.close()

    def watch(self):
        while not self.done.is_set():
            try:
                media, transport = self.soap("GetMediaInfo"), self.soap("GetTransportInfo")
                media_after = self.soap("GetMediaInfo")
                uri = ET.fromstring(media).findtext(".//{*}CurrentURI") or ""
                uri_after = ET.fromstring(media_after).findtext(".//{*}CurrentURI") or ""
                state = ET.fromstring(transport).findtext(".//{*}CurrentTransportState") or ""
                sockets = self.command(["ss", "-Htnp"])
                with self.lock:
                    self.pcap.update()
                    self.loopback.update()
                    self.pcap.note_socket_owners(sockets)
                    self.counter += 1
                    stem = f"renderer-state-{self.counter:04d}"
                    (self.stage / (stem + "-media.xml")).write_bytes(media)
                    (self.stage / (stem + "-media-after.xml")).write_bytes(media_after)
                    (self.stage / (stem + "-transport.xml")).write_bytes(transport)
                    (self.stage / (stem + "-sockets.txt")).write_text(sockets)
                    # Un SetURI entre les deux lectures ne permet pas
                    # d'attribuer cet état à l'une des deux ressources.
                    require(uri == uri_after, "URI Rygel modifiée pendant le relevé d'état")
                    self.history.append({"atUtc": utc(), "wallTime": time.time(), "uri": uri,
                        "transportState": state, "rawStatePrefix": stem})
                    if relay_uri(uri, self.guest_ip):
                        self.last_relay = uri
            except (ValueError, OSError, ET.ParseError, http.client.HTTPException, subprocess.SubprocessError) as error:
                with self.lock:
                    self.errors.append({"atUtc": utc(), "error": str(error)})
            self.done.wait(0.5)

    def video_window(self):
        tree = self.command(["xwininfo", "-display", DISPLAY, "-root", "-tree"])
        candidates = []
        for identifier in dict.fromkeys(re.findall(r"^\s*(0x[0-9a-fA-F]+)\s", tree, re.M)):
            detail = self.command(["xwininfo", "-display", DISPLAY, "-id", identifier])
            if "Map State: IsViewable" not in detail:
                continue
            values = {}
            for key in ("Absolute upper-left X", "Absolute upper-left Y", "Width", "Height"):
                match = re.search(re.escape(key) + r":\s*(-?\d+)", detail)
                require(match, "Géométrie de fenêtre X11 incomplète")
                values[key] = int(match.group(1))
            x, y, width, height = (values[key] for key in ("Absolute upper-left X", "Absolute upper-left Y", "Width", "Height"))
            if width >= 320 and height >= 180 and 0 <= x < x + width <= DISPLAY_WIDTH and 0 <= y < y + height <= DISPLAY_HEIGHT:
                candidates.append({"id": identifier, "bounds": [x, y, x + width, y + height],
                    "display": DISPLAY, "rendererPid": self.renderer_pid, "rawWindow": detail})
        require(len(candidates) == 1, "Fenêtre vidéo Xvfb absente ou ambiguë")
        return candidates[0]

    def motion(self, phase):
        require(re.fullmatch(r"[a-z0-9-]+", phase), "Nom de phase invalide")
        window = self.video_window()
        left, top, right, bottom = window["bounds"]
        width, height = right - left, bottom - top
        crop = (left + width // 5, top + height // 5, width * 3 // 5, height * 3 // 5)
        self.frame_counter += 1
        stem = f"renderer-{phase}-{self.frame_counter:04d}"
        files, pixels, contrasts = [], [], []
        (self.stage / (stem + "-window.json")).write_text(json.dumps(window, indent=2) + "\n")
        for index in range(3):
            filename = stem + f"-frame-{index}.png"
            png = self.command(["ffmpeg", "-nostdin", "-v", "error", "-f", "x11grab", "-video_size",
                f"{DISPLAY_WIDTH}x{DISPLAY_HEIGHT}", "-i", DISPLAY, "-frames:v", "1", "-f", "image2pipe",
                "-vcodec", "png", "pipe:1"], binary=True)
            (self.stage / filename).write_bytes(png)
            x, y, w, h = crop
            frame = rec.command(["ffmpeg", "-nostdin", "-v", "error", "-f", "image2pipe", "-i", "pipe:0",
                "-vf", f"crop={w}:{h}:{x}:{y},scale=64:36,format=gray", "-frames:v", "1", "-f", "rawvideo", "pipe:1"],
                binary=True, input_value=png)
            require(len(frame) == 64 * 36, "Image Xvfb non lisible")
            files.append(filename)
            pixels.append(frame)
            contrasts.append(max(frame) - min(frame))
            time.sleep(0.7)
        differences = [sum(abs(a-b) for a, b in zip(first, second)) / len(first)
                       for first, second in zip(pixels, pixels[1:])]
        return {"videoMotion": min(contrasts) > 25 and min(differences) > 1.0,
            "frameFiles": files, "frameContrast": contrasts, "frameDifferences": differences,
            "receiverVideoWindow": window}

    def sample(self, phase):
        with self.lock:
            require(self.history, "Aucun état réel du renderer encore observé")
            current = dict(self.history[-1])
            require(time.time() - current["wallTime"] <= 8, "État du renderer périmé")
            uri = current["uri"]
            target = uri if relay_uri(uri, self.guest_ip) else self.last_relay
            self.pcap.update()
            self.loopback.update()
            refused = [x for x in self.loopback.refused_direct if x["synAt"] >= self.started_wall]
            direct = [x for x in self.history if x["uri"] == DIRECT_URI]
            stopped = [x for x in direct if x["transportState"] == "STOPPED"
                       and any(r["resetAt"] <= x["wallTime"] for r in refused)]
            network = self.pcap.relay(target) if target else {
                "rendererGetObserved": False, "relayBytes": 0, "relayConnectionClosed": False, "connections": []}
        renderer_log = (self.stage / "rygel.txt").read_text(errors="replace")
        genuine_error = "Error from GStreamer element" in renderer_log and "Going to STOPPED state" in renderer_log
        result = {**current, **network, "phase": phase, "atUtc": utc(), "relayUri": target,
            "directErrorObserved": bool(refused and direct and genuine_error), "directStoppedObserved": bool(stopped),
            "rendererErrorLog": "rygel.txt", "rendererGstreamerErrorObserved": genuine_error,
            "directConnectionResets": refused, "directStates": direct,
            "videoMotion": False, "frameFiles": [], "frameContrast": [], "frameDifferences": [], "receiverVideoWindow": {}}
        if current["transportState"] == "PLAYING" and relay_uri(uri, self.guest_ip):
            try:
                result.update(self.motion(phase))
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                result["motionError"] = str(error)
        self.sample_counter += 1
        (self.stage / f"renderer-sample-{phase}-{self.sample_counter:04d}.json").write_text(json.dumps(result, indent=2) + "\n")
        return result

    def wait_stopped(self, uri, timeout=20):
        require(relay_uri(uri, self.guest_ip), "Ancien URI relais non valide")
        entered_wall = time.time()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self.lock:
                self.pcap.update()
                current = dict(self.history[-1]) if self.history else {}
                network = self.pcap.relay(uri)
            if (current.get("transportState") == "STOPPED"
                    and entered_wall <= current.get("wallTime", 0) <= time.time()
                    and time.time() - current["wallTime"] <= 8
                    and network["relayConnectionClosed"]):
                parsed = urllib.parse.urlsplit(uri)
                connection = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=3)
                try:
                    connection.request("GET", parsed.path, headers={"User-Agent": OLD_RELAY_AGENT, "Connection": "close"})
                    reply = connection.getresponse()
                    body = reply.read(65536)
                    result = {**current, **network, "atUtc": utc(), "relayUri": uri,
                        "oldUriHttpStatus": reply.status, "oldUriRefused": reply.status == 404,
                        "oldUriError": None, "oldUriResponseBodySha256": hashlib.sha256(body).hexdigest()}
                    (self.stage / "old-relay-after-ui-stop.json").write_text(json.dumps(result, indent=2) + "\n")
                    require(reply.status == 404, "L'ancien relais est encore accessible après l'arrêt UI")
                    return result
                finally:
                    connection.close()
            time.sleep(0.5)
        raise ValueError("Le renderer ou sa connexion relais ne s'est pas arrêté après l'action UI")

    @contextmanager
    def recording(self, events):
        require(not self.video_path.exists(), "Vidéo renderer déjà présente")
        events("renderer-video-start", audioRecorded=False, source="private-Xvfb")
        process = self.spawn(["ffmpeg", "-nostdin", "-v", "warning", "-f", "x11grab", "-framerate", "15",
            "-video_size", f"{DISPLAY_WIDTH}x{DISPLAY_HEIGHT}", "-i", DISPLAY,
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24", "-pix_fmt", "yuv420p", str(self.video_path)],
            "renderer-video-log.txt")
        try:
            time.sleep(1)
            require(process.poll() is None, "L'enregistrement Xvfb n'a pas démarré")
            yield
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGINT)
                    process.wait(timeout=15)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    self.stop_process(process)
            events("renderer-video-stop")

    def close(self):
        self.done.set()
        self.thread.join(timeout=12)
        (self.stage / "renderer-state-history.json").write_text(json.dumps(self.history, indent=2) + "\n")
        (self.stage / "renderer-observer-errors.json").write_text(json.dumps(self.errors, indent=2) + "\n")
        require(not self.thread.is_alive(), "Le suivi du renderer n'a pas terminé")
