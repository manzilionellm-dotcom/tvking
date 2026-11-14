"""Exécuter le vrai parcours mediaPlayback dans des espaces Linux jetables.

Le parent vérifie l'archive AAB et prépare les dépendances avant l'isolation.
Ce processus ne télécharge rien, n'accepte aucun accord et ne change aucun
binaire d'application ou de renderer. Toutes les créations réseau sont locales
au namespace validé ; les montages Rygel sont privés et en lecture seule.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET

import run_datasync_evidence as rec
from probe_tap_network import checked_wlan, stop_owned_process, ENGINE_VERSION, ENGINE_BUILD
from mediaplayback_observations import RendererProbe, HOST_IP, DIRECT_URI, DISPLAY
# Charger le scénario du banc approuvé avant que les helpers du binaire
# ajoutent leur dossier à sys.path : l'AAB8 contient aussi un ancien scénario.
from mediaplayback_scenario import execute_ui

TAP = "ntprobe0"
RENDERER_PORT = 19494
FRIENDLY_NAME = "NOVATUBE test renderer"
ADB_SOCKET = "tcp:127.0.0.1:5037"
SERIAL = "emulator-5582"


def require(value, message):
    if not value:
        raise ValueError(message)


def namespace_guards(parent_netns, parent_mntns):
    """Refuser toute création privilégiée dans les vues de l'appelant."""
    require(os.geteuid() == 0, "Le runtime exige le root du namespace jetable")
    require(os.readlink("/proc/self/ns/net") != parent_netns, "Namespace réseau de l'appelant refusé")
    require(os.readlink("/proc/self/ns/mnt") != parent_mntns, "Namespace montages de l'appelant refusé")
    require(os.getpid() == 1, "Le runtime doit être le PID initial du namespace privé")


def fixture_aac_config(probe):
    """Vérifier l'AudioSpecificConfig que le lecteur Android devra recevoir.

    Le décodage tolérant de FFmpeg ne suffit pas : média3 décodait alors que
    le moov initial ne contenait pas les deux octets AAC-LC requis. Le flux
    source immuable est précisément AAC-LC, 48 kHz, mono : ASC1188.
    """
    audio = [stream for stream in probe.get("streams", []) if stream.get("codec_type") == "audio"]
    require(len(audio) == 1, "Une unique piste audio de mire est requise")
    audio = audio[0]
    lines = [line for line in audio.get("extradata", "").splitlines() if line.strip()]
    require(len(lines) == 1 and lines[0].startswith("00000000:"), "AudioSpecificConfig AAC absente ou ambiguë")
    hexadecimal = lines[0].split(":", 1)[1].strip().split("  ", 1)[0].replace(" ", "")
    require(audio.get("codec_name") == "aac" and audio.get("profile") == "LC"
            and audio.get("sample_rate") == "48000" and audio.get("channels") == 1
            and audio.get("extradata_size") == 2 and hexadecimal == "1188",
            "AudioSpecificConfig AAC-LC 48kHz mono incorrecte : refuser la fixture")
    return hexadecimal


class Fixture:
    """La mire H264/AAC remuxée en vrai MP4, disponible seulement via Android.

    Playbin0.42.5 accepte video/mp4 mais pas video/mp2t. On conserve les
    pistes encodées du projet et produit de vrais fragments MP4 continus ;
    ni le MIME d'un TS ni la liste de formats du renderer ne sont falsifiés.
    """
    def __init__(self, path, stage):
        require(rec.digest(path) == rec.FIXTURE_SHA256, "Mire différente de l'AAB8")
        self.path, self.stage = path, stage
        self.lock, self.requests, self.processes = threading.Lock(), [], set()
        self.stopped = False
        self.server, self.thread = None, None

    def stream_command(self):
        return ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-stream_loop", "-1", "-re", "-i", str(self.path), "-map", "0:v:0", "-map", "0:a:0",
            "-c", "copy", "-bsf:a", "aac_adtstoasc", "-movflags",
            "+frag_keyframe+empty_moov+default_base_moof+delay_moov", "-f", "mp4", "pipe:1"]

    def validate_remux(self):
        """Décoder un vrai échantillon produit avec les mêmes options du muxer."""
        target = self.stage / "fixture-fmp4-decode-check.mp4"
        command = self.stream_command()
        command.remove("-re")
        command[-1:] = ["-t", "4", str(target)]
        subprocess.run(command, capture_output=True, check=True, timeout=30)
        probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-show_data",
            "-of", "json", str(target)], timeout=20))
        kinds = [(x.get("codec_type"), x.get("codec_name")) for x in probe["streams"]]
        require(kinds == [("video", "h264"), ("audio", "aac")]
                and "mp4" in probe["format"]["format_name"]
                and 4 <= float(probe["format"]["duration"]) < 5, "Mire MP4 H264/AAC invalide")
        audio_config = fixture_aac_config(probe)
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-xerror", "-err_detect", "explode",
            "-i", str(target), "-f", "null", "-"], capture_output=True, check=True, timeout=30)
        provenance = {"sourceSha256": rec.FIXTURE_SHA256, "sourceFile": self.path.name,
            "mode": "stream-copy-to-fragmented-mp4", "servedUri": DIRECT_URI, "contentType": "video/mp4",
            "streamCommand": self.stream_command(), "sampleCommand": command, "sampleFile": target.name,
            "sampleSha256": rec.digest(target), "sampleFullDecode": True, "sampleProbe": probe,
            "audioSpecificConfigHex": audio_config, "audioTranscoded": False, "videoTranscoded": False,
            "ffmpegVersion": subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0]}
        (self.stage / "fixture-fmp4-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")

    def start(self):
        self.validate_remux()
        owner = self
        media_path = urllib.parse.urlsplit(DIRECT_URI).path
        playlist = (f'#EXTM3U\n#EXTINF:-1 tvg-id="novatube-test" group-title="Demonstration",{rec.CHANNEL}\n'
                    + DIRECT_URI + "\n").encode()

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_HEAD(self):
                if self.path not in ("/playlist.m3u", media_path):
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", "audio/x-mpegurl" if self.path == "/playlist.m3u" else "video/mp4")
                self.send_header("Connection", "close")
                self.end_headers()

            def do_GET(self):
                if self.path == "/playlist.m3u":
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/x-mpegurl")
                    self.send_header("Content-Length", str(len(playlist)))
                    self.end_headers()
                    self.wfile.write(playlist)
                    return
                if self.path != media_path:
                    self.send_error(404)
                    return
                self.send_response(200)
                # Flux fragmenté continu : longueur inconnue, pas de promesse
                # de Range. Une demande Range reçoit légalement le flux200.
                self.send_header("Content-Type", "video/mp4")
                self.send_header("Connection", "close")
                self.end_headers()
                record = {"startedAtUtc": datetime.now(timezone.utc).isoformat(), "bytes": 0,
                    "peer": list(self.client_address), "userAgent": self.headers.get("User-Agent", ""), "path": self.path}
                with owner.lock:
                    # La fermeture et la création utilisent le même verrou :
                    # aucun ffmpeg ne peut apparaître après l'inventaire final.
                    if owner.stopped:
                        return
                    stderr_file = f"fixture-stream-{len(owner.requests) + 1:03d}.txt"
                    stderr = (owner.stage / stderr_file).open("wb")
                    try:
                        process = subprocess.Popen(owner.stream_command(), stdout=subprocess.PIPE,
                            stderr=stderr, start_new_session=True)
                    except BaseException:
                        stderr.close()
                        raise
                    record["stderrFile"] = stderr_file
                    owner.processes.add(process)
                    owner.requests.append(record)
                try:
                    while data := process.stdout.read(1316):
                        self.wfile.write(data)
                        self.wfile.flush()
                        record["bytes"] += len(data)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    pass
                finally:
                    stop_owned_process(process)
                    process.stdout.close()
                    stderr.close()
                    record["endedAtUtc"] = datetime.now(timezone.utc).isoformat()
                    with owner.lock:
                        owner.processes.discard(process)

        self.server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self):
        with self.lock:
            self.stopped = True
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        with self.lock:
            processes = list(self.processes)
        for child in processes:
            stop_owned_process(child)
        if self.thread:
            self.thread.join(timeout=3)
        (self.stage / "fixture-requests.json").write_text(json.dumps(self.requests, indent=2) + "\n")


class Runtime:
    def __init__(self, args):
        self.args = args
        self.stage = args.output.resolve()
        self.private = args.private_root.resolve()
        self.sdk = args.sdk_root.resolve()
        self.prepared = args.prepared.resolve()
        self.processes, self.handles, self.mounts, self.cleanup_errors = [], [], [], []
        self.namespace_owned = self.tap_owned = self.adb_owned = self.reverse_owned = False
        self.command_errors = 0
        self.adb_server = self.device = self.renderer = self.fixture = None
        self.environment = dict(os.environ)
        for name in ("ADB_SERVER_SOCKET", "ANDROID_ADB_SERVER_ADDRESS", "ANDROID_ADB_SERVER_PORT", "ANDROID_SERIAL",
                     "ADB_VENDOR_KEYS", "DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS", "DBUS_SYSTEM_BUS_ADDRESS",
                     "LD_LIBRARY_PATH", "LD_PRELOAD", "GUPNP_CONTEXT_MANAGER", "RYGEL_PLUGIN_PATH", "RYGEL_ENGINE_PATH"):
            self.environment.pop(name, None)

    def run(self, command, *, timeout=30, input_text=None, check=True):
        try:
            result = subprocess.run([str(x) for x in command], env=self.environment, input=input_text,
                capture_output=True, text=True, timeout=timeout, check=check)
            return result.stdout
        except subprocess.SubprocessError as error:
            if self.stage.exists():
                self.command_errors += 1
                value = getattr(error, "stderr", "") or getattr(error, "output", "") or ""
                if isinstance(value, bytes):
                    value = value.decode("utf-8", errors="replace")
                (self.stage / f"command-error-{self.command_errors:03d}.txt").write_text(str(error) + "\n" + value)
            raise

    def spawn(self, command, log_name, *, capture_name=None):
        log = (self.stage / log_name).open("wb")
        self.handles.append(log)
        target = log
        if capture_name:
            target = (self.stage / capture_name).open("wb")
            self.handles.append(target)
        child = subprocess.Popen([str(x) for x in command], env=self.environment, stdout=target,
            stderr=log, start_new_session=True)
        self.processes.append(child)
        return child

    def mount(self, arguments, target):
        self.run(["mount", *arguments])
        self.mounts.append(str(target))

    def setup(self):
        namespace_guards(self.args.parent_netns, self.args.parent_mntns)
        links = json.loads(self.run(["ip", "-json", "link", "show"]))
        require({x["ifname"] for x in links} == {"lo"}, "Le namespace réseau doit être neuf")
        self.namespace_owned = True
        require(not self.stage.exists() and not self.private.exists(), "Les dossiers du runtime doivent être neufs")
        self.stage.mkdir(parents=True)
        self.private.mkdir(parents=True)
        for tool in ("ip", "mount", "umount", "findmnt", "dnsmasq", "tcpdump", "ss", "Xvfb", "xauth", "xwininfo",
                     "xdpyinfo", "dbus-run-session", "ffmpeg", "ffprobe", "gst-inspect-1.0"):
            require(shutil.which(tool), "Dépendance préparée absente : " + tool)
        require(Path("/dev/kvm").exists() and Path("/dev/net/tun").exists(), "KVM ou TUN absent")
        manifest = json.loads((self.prepared / "prepared.json").read_text())
        require(manifest["aabSha256"] == rec.AAB_SHA256 and manifest["appCommit"] == rec.APP_COMMIT,
                "Identité AAB préparée incorrecte")
        for relative, expected in manifest["files"].items():
            path = (self.prepared / relative).resolve()
            require(path.is_relative_to(self.prepared) and path.is_file() and rec.digest(path) == expected,
                    "Fichier préparé modifié : " + relative)
        self.manifest = manifest
        self.original = Path(manifest["originalSource"])
        self.helpers = rec.original_helpers(self.original)
        version = self.run([self.sdk / "emulator/emulator", "-version"])
        (self.stage / "emulator-version.txt").write_text(version)
        require(f"version {ENGINE_VERSION}" in version and f"build_id {ENGINE_BUILD}" in version,
                "Moteur différent du diagnostic TAP réussi")
        for plugin in ("playbin", "souphttpsrc", "tsdemux", "qtdemux", "h264parse", "avdec_h264", "aacparse", "avdec_aac",
                       "videoconvert", "videoscale", "ximagesink", "audioconvert", "audioresample", "filesink"):
            (self.stage / ("gstreamer-" + plugin + ".txt")).write_text(self.run(["gst-inspect-1.0", plugin]))
        # Toute propagation et tout montage viennent après les deux gardes.
        self.run(["mount", "--make-rprivate", "/"])
        lower = self.private / "share-lower"
        lower.mkdir()
        self.mount(["--bind", "/usr/share", lower], lower)
        self.run(["mount", "-o", "remount,bind,ro", lower])
        layer = self.prepared / "share-layer"
        require((layer / "rygel/xml/MediaRenderer2.xml").is_file(), "XML Rygel officiel absent")
        require(not any(mark in str(path) for path in (layer, lower) for mark in (",", ":", "\n")),
                "Chemins d'overlay non représentables sans ambiguïté")
        self.mount(["-t", "overlay", "overlay", "-o", f"ro,lowerdir={layer}:{lower}", "/usr/share"], "/usr/share")
        mounted = self.run(["findmnt", "-n", "-o", "FSTYPE,OPTIONS", "--target", "/usr/share"])
        require(mounted.startswith("overlay ") and "ro," in mounted and str(layer) in mounted,
                "Les données Rygel ne sont pas dans l'overlay privé attendu")
        (self.stage / "private-share-mount.txt").write_text(mounted)
        # Rygel 0.42.5 charge obligatoirement /etc/rygel.conf avant sa
        # configuration utilisateur. Exposer seulement le fichier officiel
        # extrait, en conservant /etc existant comme couche basse readonly.
        # Ces montages restent après les gardes réseau/montages/PID privées.
        system_config = self.prepared / "renderer/etc/rygel.conf"
        config_sha = manifest["files"].get("renderer/etc/rygel.conf")
        require(config_sha and system_config.is_file() and rec.digest(system_config) == config_sha,
                "Configuration système officielle Rygel absente ou modifiée")
        etc_layer, etc_lower = self.private / "etc-layer", self.private / "etc-lower"
        etc_layer.mkdir()
        etc_lower.mkdir()
        shutil.copyfile(system_config, etc_layer / "rygel.conf")
        require(rec.digest(etc_layer / "rygel.conf") == config_sha
                and {path.name for path in etc_layer.iterdir()} == {"rygel.conf"},
                "La couche /etc doit contenir uniquement la configuration officielle intacte")
        require(not any(mark in str(path) for path in (etc_layer, etc_lower) for mark in (",", ":", "\n")),
                "Chemins d'overlay /etc non représentables sans ambiguïté")
        self.mount(["--bind", "/etc", etc_lower], etc_lower)
        self.run(["mount", "-o", "remount,bind,ro", etc_lower])
        self.mount(["-t", "overlay", "overlay", "-o", f"ro,lowerdir={etc_layer}:{etc_lower}", "/etc"], "/etc")
        etc_mounted = self.run(["findmnt", "-n", "-o", "FSTYPE,OPTIONS", "--target", "/etc"])
        require(etc_mounted.startswith("overlay ") and "ro," in etc_mounted and str(etc_layer) in etc_mounted
                and rec.digest(Path("/etc/rygel.conf")) == config_sha,
                "Configuration système Rygel hors de l'overlay privé attendu")
        (self.stage / "private-etc-mount.txt").write_text(etc_mounted)
        (self.stage / "rygel-system-config-sha256.txt").write_text(config_sha + "\n")
        # Les sockets X11 et leurs fichiers de verrou ne rejoignent pas /tmp hôte.
        self.mount(["-t", "tmpfs", "-o", "mode=1777,size=128m", "tmpfs", "/tmp"], "/tmp")
        for name, folder in (("ANDROID_AVD_HOME", "avds"), ("ANDROID_USER_HOME", "android-user"),
                             ("ANDROID_TMP", "android-tmp"), ("XDG_CONFIG_HOME", "config"),
                             ("XDG_CACHE_HOME", "cache"), ("XDG_RUNTIME_DIR", "runtime")):
            path = self.private / folder
            path.mkdir(mode=0o700)
            self.environment[name] = str(path)
        self.environment.update({"ADB_SERVER_SOCKET": ADB_SOCKET, "ANDROID_ADB_SERVER_PORT": "5037",
            "DISPLAY": DISPLAY, "XAUTHORITY": str(self.private / "Xauthority"),
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(self.private / "no-system-bus"),
            "LD_LIBRARY_PATH": str(self.prepared / "renderer/usr/lib/x86_64-linux-gnu"),
            "GST_DEBUG_NO_COLOR": "1", "GST_DEBUG": "2", "G_MESSAGES_DEBUG": "all"})
        (self.private / "Xauthority").touch(mode=0o600)
        self.run(["xauth", "-f", self.private / "Xauthority"], input_text="add :94 . " + secrets.token_hex(16) + "\nexit\n")
        self.run(["ip", "link", "set", "lo", "up"])
        self.run(["ip", "tuntap", "add", "dev", TAP, "mode", "tap"])
        self.tap_owned = True
        self.run(["ip", "address", "add", HOST_IP + "/24", "dev", TAP])
        self.run(["ip", "link", "set", TAP, "up"])
        self.capture = self.spawn(["tcpdump", "-i", TAP, "-n", "-s", "0", "-U", "-w", "-"],
            "tcpdump.txt", capture_name="tap.pcap")
        self.loop_capture = self.spawn(["tcpdump", "-i", "lo", "-n", "-s", "0", "-U", "-w", "-", "tcp", "port", "18765"],
            "loopback-tcpdump.txt", capture_name="loopback.pcap")
        self.spawn(["dnsmasq", "--no-daemon", "--port=0", "--no-resolv", "--no-hosts", "--interface=" + TAP,
            "--bind-interfaces", "--log-dhcp", "--dhcp-range=192.0.2.16,192.0.2.32,255.255.255.0,1h",
            "--dhcp-option=3," + HOST_IP, "--dhcp-leasefile=" + str(self.private / "leases")], "dhcp.txt")
        self.xvfb = self.spawn(["Xvfb", ":94", "-screen", "0", "1280x720x24", "-nolisten", "tcp", "-auth", self.private / "Xauthority"], "xvfb.txt")
        for _ in range(30):
            require(self.xvfb.poll() is None, "Xvfb s'est arrêté")
            try:
                (self.stage / "xvfb-display.txt").write_text(self.run(["xdpyinfo", "-display", DISPLAY], timeout=3))
                break
            except subprocess.SubprocessError:
                time.sleep(0.5)
        else:
            raise ValueError("Affichage Xvfb privé indisponible")
        self.start_android()
        self.start_renderer()

    def start_android(self):
        adb = self.sdk / "platform-tools/adb"
        self.adb_server = self.spawn([adb, "-L", "tcp:localhost:5037", "server", "nodaemon"], "adb-server.txt")
        self.adb_owned = True
        time.sleep(1)
        require(self.adb_server.poll() is None, "Le serveur ADB privé n'a pas démarré")
        avd = self.private / "avds/novatube_media.avd"
        self.run([self.sdk / "cmdline-tools/latest/bin/avdmanager", "create", "avd", "--name", "novatube_media",
            "--package", self.helpers.IMAGE, "--path", avd, "--force"], input_text="no\n", timeout=90)
        config = avd / "config.ini"
        values = {"hw.lcd.width": 1080, "hw.lcd.height": 1920, "hw.lcd.density": 420, "hw.mainKeys": "no",
                  "hw.ramSize": 2048, "hw.keyboard": "yes", "showDeviceFrame": "no"}
        lines = [line for line in config.read_text().splitlines() if line.split("=", 1)[0].strip() not in values]
        config.write_text("\n".join(lines + [f"{key}={value}" for key, value in values.items()]) + "\n")
        self.emulator = self.spawn([self.sdk / "emulator/emulator", "-avd", "novatube_media", "-port", "5582",
            "-no-window", "-no-audio", "-no-boot-anim", "-no-snapshot", "-gpu", "software", "-memory", "2048",
            "-cores", "2", "-accel", "on", "-skin", "1080x1920", "-feature", "VirtioWifi,-WiFiPacketStream", "-wifi-tap", TAP], "android-emulator.txt")
        runtime = self
        class Device(self.helpers.Device):
            def command(self, *args, timeout=60):
                require(runtime.adb_owned and runtime.adb_server.poll() is None, "Serveur ADB privé arrêté")
                return runtime.run([self.adb, "-s", SERIAL, *args], timeout=timeout)
            def binary(self, *args):
                require(runtime.adb_owned and runtime.adb_server.poll() is None, "Serveur ADB privé arrêté")
                return subprocess.run([str(self.adb), "-s", SERIAL, *args], env=runtime.environment,
                    capture_output=True, timeout=60, check=True).stdout
        self.device = Device(adb)
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            require(self.emulator.poll() is None and self.capture.poll() is None, "Émulateur ou capture arrêté")
            try:
                if self.device.command("shell", "getprop", "sys.boot_completed", timeout=10).strip() == "1":
                    break
            except subprocess.SubprocessError:
                pass
            time.sleep(2)
        else:
            raise ValueError("Android n'a pas démarré")
        for args in (("input", "keyevent", "82"), ("svc", "data", "disable"), ("svc", "wifi", "enable"),
                     ("settings", "put", "system", "accelerometer_rotation", "0"), ("settings", "put", "system", "user_rotation", "0")):
            self.device.command("shell", *args)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            raw = self.device.command("shell", "ip", "-o", "-4", "address", "show", "wlan0")
            try:
                self.guest_ip = checked_wlan(raw)
                break
            except RuntimeError:
                time.sleep(2)
        else:
            raise ValueError("Adresse DHCP TAP absente")
        (self.stage / "android-wlan.txt").write_text(raw)
        (self.stage / "android-routes.txt").write_text(self.device.command("shell", "ip", "route", "show", "table", "all"))

    def start_renderer(self):
        # Le fichier local par défaut n'est lu qu'après le fichier système
        # officiel monté plus haut ; aucun chemin de configuration hôte.
        config = Path(self.environment["XDG_CONFIG_HOME"]) / "rygel.conf"
        require(config.parent == self.private / "config", "Configuration utilisateur Rygel hors du dossier privé")
        pcm = str(self.stage / "receiver.pcm")
        require('"' not in pcm and "\n" not in pcm, "Chemin PCM non sûr")
        config.write_text("[general]\ninterface=" + TAP + f"\nport={RENDERER_PORT}\nipv6=false\nenable-transcoding=false\n"
            "allow-upload=false\nallow-deletion=false\nlog-level=*:5\n\n[Playbin]\nenabled=true\ntitle=" + FRIENDLY_NAME + "\n"
            "video-sink=videoconvert ! videoscale ! video/x-raw,width=960,height=540,pixel-aspect-ratio=1/1 ! ximagesink sync=true\n"
            'audio-sink=audioconvert ! audioresample ! audio/x-raw,format=S16LE,rate=48000,channels=2 ! filesink location="' + pcm + '" sync=true\n' +
            "".join(f"\n[{name}]\nenabled=false\n" for name in ("Tracker3", "Tracker", "MediaExport", "MPRIS", "External", "LMS", "GstLaunch", "Test", "Ruih")))
        (self.stage / "rygel-config.txt").write_text(config.read_text())
        self.ssdp = self.spawn(["tcpdump", "-i", TAP, "-n", "-s", "0", "-A", "-l", "udp", "and", "src", "host", HOST_IP], "renderer-ssdp.txt")
        self.rygel = self.spawn(["dbus-run-session", "--", self.prepared / "renderer/usr/bin/rygel",
            "--plugin-path", self.prepared / "playbin-plugins", "--engine-path", self.prepared / "empty-engines"], "rygel.txt")
        deadline = time.monotonic() + 45
        location, observed_locations = None, set()
        while time.monotonic() < deadline:
            require(self.rygel.poll() is None and self.ssdp.poll() is None, "Rygel ou sa capture SSDP s'est arrêté")
            for value in re.findall(r"(?im)^location:\s*(\S+)", (self.stage / "renderer-ssdp.txt").read_text(errors="replace")):
                observed_locations.add(value)
                uri = urllib.parse.urlsplit(value)
                if uri.scheme == "http" and uri.hostname == HOST_IP and uri.port == RENDERER_PORT:
                    location = value
                    break
            if location:
                break
            time.sleep(0.5)
        (self.stage / "renderer-locations.json").write_text(json.dumps({"expectedHost": HOST_IP,
            "expectedPort": RENDERER_PORT, "observedLocations": sorted(observed_locations)}, indent=2) + "\n")
        require(location, "Aucune LOCATION SSDP de Rygel ne correspond au port privé configuré 19494")
        uri = urllib.parse.urlsplit(location)
        connection = http.client.HTTPConnection(uri.hostname, uri.port, timeout=5)
        try:
            connection.request("GET", uri.path, headers={"Connection": "close"})
            reply = connection.getresponse(); body = reply.read(1024 * 1024)
            require(reply.status == 200, "Description Rygel non lisible")
        finally:
            connection.close()
        (self.stage / "renderer-description.xml").write_bytes(body)
        document = ET.fromstring(body)
        require(document.findtext(".//{*}friendlyName") == FRIENDLY_NAME, "Nom du vrai renderer incorrect")
        require(document.findtext(".//{*}deviceType") == "urn:schemas-upnp-org:device:MediaRenderer:2", "Type Rygel inattendu")
        services = [node for node in document.findall(".//{*}service")
                    if (node.findtext("{*}serviceType") or "").startswith("urn:schemas-upnp-org:service:AVTransport:")]
        require(len(services) == 1, "Service AVTransport absent ou ambigu")
        service = services[0]
        control = urllib.parse.urljoin(location, service.findtext("{*}controlURL") or "")
        target = urllib.parse.urlsplit(control)
        require(target.scheme == "http" and target.hostname == HOST_IP and target.port == RENDERER_PORT,
                "Le service de contrôle quitte notre renderer privé")
        binary = str((self.prepared / "renderer/usr/bin/rygel").resolve())
        pids = []
        for proc in Path("/proc").iterdir():
            if proc.name.isdigit():
                try:
                    if os.readlink(proc / "exe") == binary:
                        pids.append(int(proc.name))
                except OSError:
                    pass
        require(len(pids) == 1, "PID du vrai binaire Rygel absent ou ambigu")
        require(os.getpgid(pids[0]) == self.rygel.pid, "Rygel n'appartient pas au groupe démarré ici")
        # Aucun service côté renderer sur le port Android : le direct devra
        # vraiment échouer. L'observateur démarre après ce contrôle préalable.
        listeners = self.run(["ss", "-Hltn"])
        require(not re.search(r":18765\s", listeners), "Le port direct Android existe à tort côté renderer")
        (self.stage / "listeners-before-reverse.txt").write_text(listeners)
        self.renderer = RendererProbe(stage=self.stage, guest_ip=self.guest_ip, renderer_pid=pids[0],
            friendly_name=FRIENDLY_NAME, control_url=control, service_type=service.findtext("{*}serviceType"),
            environment=self.environment, spawn=self.spawn, stop_process=stop_owned_process)

    def scenario(self):
        apk = self.prepared / self.manifest["apkRelativePath"]
        self.device.command("install", str(apk), timeout=180)
        installed = self.device.command("shell", "dumpsys", "package", rec.PACKAGE)
        require(re.search(r"\bversionCode=8\b", installed) and re.search(r"\bversionName=0\.1\.8\b", installed),
                "Version installée différente de l'AAB8")
        (self.stage / "installed-package.txt").write_text(installed)
        self.fixture = Fixture(self.original / "ci/novatube/recording-test-media/novatube-h264-aac.ts", self.stage)
        self.fixture.start()
        self.device.command("reverse", "tcp:18765", "tcp:8765")
        self.reverse_owned = True
        reverse = self.device.command("reverse", "--list")
        require(len([x for x in reverse.splitlines() if "tcp:18765 tcp:8765" in x]) == 1, "Reverse Android non vérifié")
        (self.stage / "adb-reverse.txt").write_text(reverse)
        self.device.command("shell", "am", "start", "-W", "-n", rec.PACKAGE + "/" + self.manifest["identity"]["launcher"])
        translations = {language: json.loads((self.original / "lib/l10n" / f"app_{language}.arb").read_text()) for language in ("en", "fr")}
        # Les helpers d'enregistrement utilisent os.environ. Ces variables
        # sont celles du seul runtime déjà isolé, jamais celles du runner hôte.
        os.environ.update(self.environment)
        observations = execute_ui(self.device, self.helpers, translations, self.stage, self.renderer)
        require(self.capture.poll() is None and self.loop_capture.poll() is None and self.rygel.poll() is None,
                "Une source de preuves s'est arrêtée avant la qualification")
        pcm = self.stage / "receiver.pcm"
        require(pcm.is_file() and pcm.stat().st_size >= 48000 * 2 * 2, "Audio PCM décodé insuffisant")
        with pcm.open("rb") as source:
            sample = source.read(192000)
        require(any(value for value in sample), "Audio PCM entièrement nul")
        observations["rendererPcm"] = {"bytes": pcm.stat().st_size, "format": "S16LE", "rate": 48000,
            "channels": 2, "nonZeroSamplesObserved": True, "physicalSpeaker": False}
        return observations

    def close(self):
        def attempt(label, function):
            try:
                function()
            except Exception as error:
                self.cleanup_errors.append(label + ": " + str(error))
        if self.renderer:
            attempt("observateur Rygel", self.renderer.close)
        if self.fixture:
            attempt("mire", self.fixture.close)
        if self.namespace_owned and self.adb_owned and self.adb_server.poll() is None:
            if self.device is not None:
                for name, arguments in (("logcat", ("logcat", "-d", "-t", "2000")),
                                        ("services", ("shell", "dumpsys", "activity", "services", rec.PACKAGE))):
                    attempt(name, lambda name=name, arguments=arguments: (self.stage / ("final-" + name + ".txt")).write_text(self.device.command(*arguments, timeout=10)))
                if self.reverse_owned:
                    attempt("reverse", lambda: self.device.command("reverse", "--remove", "tcp:18765", timeout=10))
                attempt("émulateur", lambda: self.device.command("emu", "kill", timeout=10))
            if self.adb_server.poll() is None:
                attempt("ADB", lambda: self.run([self.sdk / "platform-tools/adb", "kill-server"], timeout=10))
        for child in reversed(self.processes):
            attempt("processus", lambda child=child: stop_owned_process(child))
        if self.namespace_owned and self.tap_owned:
            attempt("TAP", lambda: self.run(["ip", "link", "delete", "dev", TAP]))
        if self.namespace_owned:
            for target in reversed(self.mounts):
                attempt("montage " + target, lambda target=target: self.run(["umount", target]))
        for handle in self.handles:
            attempt("journal", handle.close)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("output", "private-root", "sdk-root", "prepared"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--parent-netns", required=True)
    parser.add_argument("--parent-mntns", required=True)
    args = parser.parse_args()
    runtime = Runtime(args)
    report = {"status": "blocked", "qualified": False, "googleSubmission": False}
    def interrupted(signum, _frame):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise RuntimeError(f"Arrêt demandé par le signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        runtime.setup()
        report["observations"] = runtime.scenario()
        report["status"] = "observed-mediaPlayback-flow-human-review-required"
        report["qualified"] = True
    except BaseException as error:
        report["error"] = str(error)
        raise
    finally:
        runtime.close()
        report["cleanupErrors"] = runtime.cleanup_errors
        if runtime.cleanup_errors:
            report["qualified"] = False
            report["status"] = "cleanup-incomplete"
        report["completedAtUtc"] = datetime.now(timezone.utc).isoformat()
        # Le parent possède déjà ce dossier ; un refus des gardes ne lance
        # aucun processus, et peut uniquement produire son diagnostic texte.
        if runtime.stage.exists():
            (runtime.stage / "runtime-result.json").write_text(json.dumps(report, indent=2) + "\n")
        sys.stdout.write(json.dumps(report, indent=2) + "\n")
    require(report["qualified"], "Preuve mediaPlayback ou nettoyage incomplet")


if __name__ == "__main__":
    main()
