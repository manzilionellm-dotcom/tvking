#!/usr/bin/env python3
"""Diagnostic TAP/SSDP/HTTP jetable ; aucune preuve Play ou FGS.

Le namespace réseau Linux doit être neuf. Le SDK et les outils officiels
dnsmasq/gmediarender/GStreamer/iproute2/tcpdump sont préparés en amont.
Ce script ne télécharge, n'installe et ne modifie aucune application.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid
import xml.etree.ElementTree as ET

IMAGE = "system-images;android-35;default;x86_64"
ENGINE_VERSION = "37.2.13.0"
ENGINE_BUILD = "16740729"
TAP = "ntprobe0"
HOST_IP = "192.0.2.1"
NETWORK = ipaddress.ip_network("192.0.2.0/24")
SERIAL = "emulator-5582"
ADB_SOCKET = "tcp:127.0.0.1:5037"
RECEIVER_SHA256 = "22a18fa5d813e21ad7fdbf5fcf1f172dfdda8f4389a9aa4c15975079e16793f6"
FRIENDLY_NAME = "NOVATUBE TAP network diagnostic"
SSDP_TYPE = "urn:schemas-upnp-org:device:MediaRenderer:1"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def stop_owned_process(child):
    """Arrêter seulement notre groupe ; accepter sa disparition entre signaux."""
    for sig, seconds in ((signal.SIGTERM, 8), (signal.SIGKILL, 5)):
        if child.poll() is not None:
            return
        try:
            os.killpg(child.pid, sig)
        except ProcessLookupError:
            pass
        try:
            child.wait(timeout=seconds)
            return
        except subprocess.TimeoutExpired:
            pass
    raise RuntimeError("Un processus du diagnostic ne s'est pas arrêté")


def checked_location(response):
    matches = re.findall(r"(?im)^location:\s*(\S+)\s*$", response)
    require(matches, "No real renderer LOCATION observed in the TAP response capture")
    for location in matches:
        uri = urllib.parse.urlsplit(location)
        if (uri.scheme == "http" and uri.hostname == HOST_IP and
                not uri.username and not uri.password and uri.port == 49494 and
                not uri.fragment):
            return location
    raise RuntimeError("Renderer LOCATION was not the isolated TAP receiver")


def checked_wlan(text):
    addresses = re.findall(r"\binet (\d+\.\d+\.\d+\.\d+)/\d+", text)
    addresses = [a for a in addresses if ipaddress.ip_address(a) in NETWORK and a != HOST_IP]
    require(len(addresses) == 1, "wlan0 did not receive one address on the TAP subnet")
    return addresses[0]


def run_diagnostic(args):
    output = args.output.resolve()
    require(not output.exists(), "Output directory must be new")
    output.mkdir(parents=True)
    report = {"status": "not-run", "purpose": "network-diagnostic-only",
              "playEvidence": False, "foregroundServiceEvidence": False,
              "novatubeInstalled": False, "receiverMediaPlaybackObserved": False,
              "aabModified": False, "observations": {}}
    processes, handles = [], []
    temporary = None
    namespace_owned = tap_created = adb_owned = False
    adb_server = None
    environment = dict(os.environ)
    # Aucun serveur ou appareil ADB hérité ne peut devenir une cible de cleanup.
    for key in ("ADB_SERVER_SOCKET", "ANDROID_ADB_SERVER_ADDRESS", "ANDROID_ADB_SERVER_PORT",
                "ANDROID_SERIAL", "ADB_VENDOR_KEYS"):
        environment.pop(key, None)

    def run(command, *, timeout=30, input_text=None, check=True):
        command = [str(part) for part in command]
        completed = subprocess.run(command, input=input_text, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   timeout=timeout, env=environment)
        if check and completed.returncode:
            raise RuntimeError(f"Command failed ({completed.returncode}): {shlex.join(command)}\n{completed.stdout[-3000:]}")
        return completed.stdout

    def spawn(command, log_name, *, capture_name=None):
        log = (output / log_name).open("w", encoding="utf-8")
        handles.append(log)
        target = log
        if capture_name is not None:
            # Le parent ouvre le PCAP avant l'abandon de privilèges de tcpdump.
            # Les diagnostics restent séparés des octets de la capture.
            target = (output / capture_name).open("wb")
            handles.append(target)
        child = subprocess.Popen([str(part) for part in command], stdout=target,
                                 stderr=log, env=environment,
                                 start_new_session=True)
        processes.append(child)
        return child

    sdk = args.sdk_root.resolve()
    adb = sdk / "platform-tools/adb"

    def device(*command, timeout=30, check=True):
        require(adb_owned and adb_server.poll() is None,
                "Le serveur ADB privé suivi n'est plus actif")
        return run([adb, "-s", SERIAL, *command], timeout=timeout, check=check)

    def shell(command, timeout=30, check=True):
        return device("shell", shlex.join(["sh", "-c", command]), timeout=timeout, check=check)

    def packet_exchange(request_path, host, port, *, udp=False):
        remote = "/data/local/tmp/ntprobe-request.txt"
        device("push", request_path, remote)
        # Après EOF du fichier, Toybox remplace -W par le délai -q. Sans -q,
        # ce délai vaut -1 et le vrai M-SEARCH peut laisser nc ouvert indéfiniment.
        command = f"toybox nc {'-u ' if udp else ''}-w 4 -W 4 -q 4 {host} {port} < {remote}"
        # Toybox peut signaler son délai même après avoir reçu une réponse valide.
        return shell(command, timeout=12, check=False)

    try:
        require(os.geteuid() == 0, "Run only inside a disposable root-owned network namespace")
        require(args.parent_netns != os.readlink("/proc/self/ns/net"),
                "Refusing to alter the caller's network namespace")
        links = json.loads(run(["ip", "-json", "link", "show"]))
        require({item["ifname"] for item in links} == {"lo"},
                "Namespace must contain loopback only; existing networking is never altered")
        namespace_owned = True
        require(Path("/dev/net/tun").exists(), "TUN/TAP kernel device unavailable")
        require(Path("/dev/kvm").exists(), "KVM unavailable")
        for tool in ("ip", "dnsmasq", "gst-inspect-1.0", "tcpdump"):
            require(shutil.which(tool), f"Missing preinstalled dependency: {tool}")
        # Binaire extrait du paquet Ubuntu exact, sans installation de service
        # ni exécution des scripts de maintenance sur le réseau hôte.
        renderer = args.renderer.resolve()
        require(renderer.is_file() and sha256(renderer) == RECEIVER_SHA256,
                "Le récepteur extrait diffère du binaire Ubuntu relu")
        emulator = sdk / "emulator/emulator"
        avdmanager = sdk / "cmdline-tools/latest/bin/avdmanager"
        image_properties = sdk / "system-images/android-35/default/x86_64/source.properties"
        for path in (adb, emulator, avdmanager, image_properties):
            require(path.is_file(), f"Missing preinstalled SDK dependency: {path}")
        version = run([emulator, "-version"])
        (output / "emulator-version.txt").write_text(version)
        require(f"version {ENGINE_VERSION}" in version and f"build_id {ENGINE_BUILD}" in version,
                "Emulator differs from the REC3-observed engine; review before changing the pin")
        (output / "emulator-help-wifi-tap.txt").write_text(run([emulator, "-help-wifi-tap"]))
        properties = image_properties.read_text()
        require("AndroidVersion.ApiLevel=35" in properties.replace(" ", "") and
                "SystemImage.Abi=x86_64" in properties.replace(" ", ""), "Unexpected system image")
        (output / "system-image-source.properties").write_text(properties)
        (output / "gstreamer-version.txt").write_text(run(["gst-inspect-1.0", "--version"]))
        for plugin in ("playbin", "ximagesink", "autoaudiosink"):
            (output / f"gstreamer-{plugin}.txt").write_text(run(["gst-inspect-1.0", plugin]))
        receiver_help = run([renderer, "--help-all"])
        (output / "gmediarender-help.txt").write_text(receiver_help)
        require("interface-name" in receiver_help and "gstout-videosink" in receiver_help,
                "Receiver lacks the expected real network/GStreamer backend")
        (output / "distribution-packages.txt").write_text(run(
            ["dpkg-query", "-W", "libupnp17t64", "libixml11t64", "dnsmasq-base", "iproute2", "tcpdump",
             "libgstreamer1.0-0", "gstreamer1.0-plugins-base"], check=False))
        report["observations"]["binaries"] = {
            str(path): {"bytes": path.stat().st_size, "sha256": sha256(path)}
            for path in (emulator, adb, renderer)}

        name = tempfile.mkdtemp(prefix="novatube-tap-diagnostic-")
        temporary = Path(name)
        environment["ANDROID_AVD_HOME"] = str(temporary / "avds")
        environment["ANDROID_USER_HOME"] = str(temporary / "android-user")
        environment["ANDROID_TMP"] = str(temporary / "android-tmp")
        # Ports standards, isolés par le namespace : l'émulateur et tous les
        # clients trouvent le même serveur, sans dépendre d'un scan hors plage.
        environment["ADB_SERVER_SOCKET"] = ADB_SOCKET
        environment["ANDROID_ADB_SERVER_PORT"] = "5037"
        for key in ("ANDROID_AVD_HOME", "ANDROID_USER_HOME", "ANDROID_TMP"):
            Path(environment[key]).mkdir()
        run(["ip", "link", "set", "lo", "up"])
        run(["ip", "tuntap", "add", "dev", TAP, "mode", "tap"])
        tap_created = True
        run(["ip", "address", "add", HOST_IP + "/24", "dev", TAP])
        run(["ip", "link", "set", TAP, "up"])
        capture = spawn(["tcpdump", "-i", TAP, "-n", "-s", "0", "-U", "-w", "-"],
                        "tcpdump.txt", capture_name="tap.pcap")
        spawn(["dnsmasq", "--no-daemon", "--port=0", "--no-resolv", "--no-hosts",
               "--interface=" + TAP, "--bind-interfaces", "--log-dhcp",
               "--dhcp-range=192.0.2.16,192.0.2.32,255.255.255.0,1h",
               "--dhcp-option=3," + HOST_IP,
               "--dhcp-leasefile=" + str(temporary / "leases")], "dhcp.txt")
        receiver = spawn([renderer, "--interface-name=" + TAP, "--port=49494",
                          "--friendly-name=" + FRIENDLY_NAME,
                          "--uuid=" + str(uuid.uuid4()), "--gstout-videosink=ximagesink"], "receiver.txt")
        avd_path = Path(environment["ANDROID_AVD_HOME"]) / "nt_tap_probe.avd"
        run([avdmanager, "create", "avd", "--name", "nt_tap_probe", "--package", IMAGE,
             "--path", avd_path, "--force"], input_text="no\n", timeout=90)
        config = avd_path / "config.ini"
        values = {"hw.lcd.width": 720, "hw.lcd.height": 1280, "hw.lcd.density": 320,
                  "hw.ramSize": 2048, "hw.keyboard": "yes", "showDeviceFrame": "no"}
        lines = [line for line in config.read_text().splitlines()
                 if line.split("=", 1)[0].strip() not in values]
        config.write_text("\n".join(lines + [f"{key}={value}" for key, value in values.items()]) + "\n")
        # Serveur ADB au premier plan : son PID/groupe reste suivi comme les
        # autres processus. Aucun serveur auto-détaché ne retient le namespace.
        # ADB exige « localhost » pour cette écoute ; l'adresse numérique
        # ADB_SOCKET reste réservée aux clients sur la même boucle locale.
        adb_server = spawn([adb, "-L", "tcp:localhost:5037", "server", "nodaemon"], "adb-server.txt")
        adb_owned = True
        time.sleep(1)
        require(adb_server.poll() is None, "Le serveur ADB privé n'a pas démarré")
        # Backend TAP Wi-Fi historique de QEMU, distinct du TAP netsimd expérimental.
        emulator_process = spawn([
            emulator, "-avd", "nt_tap_probe", "-port", "5582", "-no-window", "-no-audio",
            "-no-boot-anim", "-no-snapshot", "-gpu", "software", "-memory", "2048",
            "-cores", "2", "-accel", "on", "-feature", "VirtioWifi,-WiFiPacketStream",
            "-wifi-tap", TAP], "android-emulator.txt")
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            require(capture.poll() is None, "La capture PCAP s'est arrêtée avant les échanges")
            require(emulator_process.poll() is None, "Android emulator exited before boot")
            require(receiver.poll() is None, "Real renderer exited before discovery")
            if device("shell", "getprop", "sys.boot_completed", check=False).strip() == "1":
                break
            time.sleep(3)
        else:
            raise RuntimeError("Android did not boot within 300 seconds")
        device("shell", "input", "keyevent", "82")
        device("shell", "svc", "data", "disable")
        device("shell", "svc", "wifi", "enable")
        # DHCP et l'association Wi-Fi peuvent finir après sys.boot_completed.
        deadline = time.monotonic() + 60
        wlan = ""
        while time.monotonic() < deadline:
            wlan = device("shell", "ip", "-o", "-4", "address", "show", "wlan0", check=False)
            try:
                guest_ip = checked_wlan(wlan)
                break
            except RuntimeError:
                time.sleep(3)
        else:
            (output / "android-wlan.txt").write_text(wlan)
            raise RuntimeError("No TAP address on wlan0 within 60 seconds; inspect DHCP/emulator logs")
        nc_help = device("shell", "toybox", "nc", "--help", check=False)
        (output / "android-netcat-help.txt").write_text(nc_help)
        require(all(flag in nc_help for flag in ("-u", "-w", "-W", "-q", "-l", "-p")),
                "Android netcat lacks options required by this bounded network probe")
        (output / "android-wlan.txt").write_text(wlan)
        guest_ip = checked_wlan(wlan)
        report["observations"]["wlanAddress"] = guest_ip
        (output / "android-routes.txt").write_text(device("shell", "ip", "route", "show", "table", "all"))
        (output / "android-connectivity.txt").write_text(device("shell", "dumpsys", "connectivity"))
        request = temporary / "msearch.txt"
        request.write_bytes(("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
                             'MAN: "ssdp:discover"\r\nMX: 1\r\nST: ' + SSDP_TYPE + "\r\n\r\n").encode())
        # Toybox connecte son socket UDP à l'adresse multicast ; ce socket peut
        # écarter les réponses unicast SSDP. On observe les réponses véritables
        # passivement sur le TAP. La réception par NOVATUBE reste non vérifiée.
        ssdp_capture = spawn(["tcpdump", "-i", TAP, "-n", "-s", "0", "-A", "-l",
                              "udp", "and", "src", "host", HOST_IP, "and", "dst", "host", guest_ip],
                             "real-renderer-ssdp-replies.txt")
        time.sleep(1)
        require(ssdp_capture.poll() is None, "SSDP response capture did not start")
        response = packet_exchange(request, "239.255.255.250", 1900, udp=True)
        (output / "android-ssdp-response.txt").write_text(response)
        time.sleep(2)
        observed_replies = (output / "real-renderer-ssdp-replies.txt").read_text()
        location = checked_location(observed_replies)
        report["observations"]["rendererLocationFromRealSsdpCapture"] = location
        report["observations"]["ssdpRendererResponseObservedOnTap"] = True
        report["observations"]["ssdpReceiptByNovatubeProven"] = False
        uri = urllib.parse.urlsplit(location)
        target = urllib.parse.urlunsplit(("", "", uri.path or "/", uri.query, ""))
        request.write_bytes((f"GET {target} HTTP/1.1\r\nHost: {HOST_IP}:49494\r\nConnection: close\r\n\r\n").encode())
        description = packet_exchange(request, HOST_IP, 49494)
        (output / "android-renderer-description.http").write_text(description)
        # Le mode texte de subprocess normalise CRLF avant l'analyse HTTP.
        header, separator, body = description.partition("\n\n")
        require(separator and " 200 " in header.splitlines()[0], "Android could not GET the real device description")
        document = ET.fromstring(body)
        device_type = document.findtext(".//{*}deviceType")
        friendly_name = document.findtext(".//{*}friendlyName")
        require(device_type == SSDP_TYPE and friendly_name == FRIENDLY_NAME, "Description was not our actual renderer")
        require(any(s.text == "urn:schemas-upnp-org:service:AVTransport:1"
                    for s in document.findall(".//{*}serviceType")), "Actual renderer has no AVTransport")
        report["observations"]["androidToRendererHttpGet"] = True

        # Le chemin retour transporte une vraie requête TCP/HTTP. Cet endpoint
        # ne joue aucun rôle DLNA et n'est pas le relais NOVATUBE : il renvoie
        # seulement un marqueur dont les octets sont comparés sur les deux côtés.
        token = ("NOVATUBE-TAP-RETURN-" + str(uuid.uuid4()) + "\n").encode()
        wire = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: " + str(len(token)).encode() + b"\r\n\r\n" + token
        response_file = temporary / "return-response.http"
        response_file.write_bytes(wire)
        device("push", response_file, "/data/local/tmp/ntprobe-return.http")
        return_server = spawn([adb, "-s", SERIAL, "shell", shlex.join([
            "sh", "-c", "toybox nc -l -p 18765 -w 15 -W 10 < /data/local/tmp/ntprobe-return.http"
        ])], "android-return-server-request.txt")
        time.sleep(1)
        connection = http.client.HTTPConnection(guest_ip, 18765, timeout=8)
        try:
            connection.request("GET", "/novatube-network-diagnostic.txt")
            reply = connection.getresponse()
            payload = reply.read()
            require(reply.status == 200 and payload == token, "Genuine HTTP return path failed")
        finally:
            connection.close()
        return_server.wait(timeout=15)
        request_text = (output / "android-return-server-request.txt").read_text()
        require("GET /novatube-network-diagnostic.txt HTTP/1.1" in request_text,
                "Android did not record the real incoming HTTP GET")
        require(capture.poll() is None and (output / "tap.pcap").stat().st_size > 24,
                "La capture PCAP des échanges est absente ou s'est arrêtée")
        report["observations"]["hostToAndroidHttpGet"] = True
        report["observations"]["returnBodySha256"] = hashlib.sha256(payload).hexdigest()
        report["status"] = "tap-ssdp-and-bidirectional-http-observed"
    except Exception as error:
        report["status"] = "blocked"
        report["error"] = str(error)
        raise
    finally:
        # Chaque arrêt est indépendant : un logcat en échec ne doit jamais
        # empêcher l'arrêt de l'émulateur ni celui du serveur ADB possédé.
        cleanup_errors = []
        if namespace_owned and adb_owned:
            for kind in ("logcat", "emulator", "adb"):
                if adb_server.poll() is not None:
                    break
                try:
                    if kind == "logcat":
                        (output / "android-logcat.txt").write_text(device("logcat", "-d", "-t", "1200", timeout=10, check=False))
                    elif kind == "emulator":
                        device("emu", "kill", timeout=10, check=False)
                    else:
                        run([adb, "kill-server"], timeout=10, check=False)
                except (OSError, subprocess.SubprocessError, RuntimeError) as error:
                    cleanup_errors.append(f"{kind}: {error}")
        for child in reversed(processes):
            try:
                stop_owned_process(child)
            except (OSError, subprocess.SubprocessError, RuntimeError) as error:
                cleanup_errors.append(str(error))
        if namespace_owned and tap_created:
            try:
                run(["ip", "link", "delete", "dev", TAP])
            except (OSError, subprocess.SubprocessError, RuntimeError) as error:
                cleanup_errors.append(f"TAP: {error}")
        for handle in handles:
            handle.close()
        if temporary is not None:
            shutil.rmtree(temporary, ignore_errors=True)
        report["cleanupErrors"] = cleanup_errors
        if cleanup_errors and report["status"] != "blocked":
            report["status"] = "cleanup-incomplete"
        report["completedAtUtc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        (output / "network-diagnostic.json").write_text(json.dumps(report, indent=2) + "\n")
        sys.stdout.write(json.dumps(report, indent=2) + "\n")
        sys.stdout.flush()
    require(report["status"] == "tap-ssdp-and-bidirectional-http-observed",
            "Le diagnostic ou son nettoyage n'est pas complet")


def main():
    def interrupted(signum, _frame):
        # Un arrêt CI doit traverser finally. Les signaux suivants attendront
        # ce nettoyage borné ; le namespace PID extérieur borne le dernier recours.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise RuntimeError(f"Diagnostic interrompu par le signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-diagnostic", action="store_true", required=True)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--renderer", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--parent-netns", required=True)
    run_diagnostic(parser.parse_args())


if __name__ == "__main__":
    main()
