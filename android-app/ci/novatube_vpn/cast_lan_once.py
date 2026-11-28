#!/usr/bin/env python3
"""Un Cast depuis un téléphone avec VPN, sa socket LAN et sa mire décodée."""
import argparse
import json
import os
import subprocess
import time
import re
from pathlib import Path
from urllib.parse import urlsplit

from PIL import Image

from measure import Bench, displayed_pattern


def vpn_counts(out):
    state = json.loads((out / "vpn" / "tunnel.json").read_text())
    if (not state["connected"] or state["android_ip"] != "192.0.2.2"
            or state["source_ip"] != "192.0.2.1"):
        raise RuntimeError("Tunnel du banc inactif ou origine différente")
    flow = state["fixture_tcp"].get("18999", {})
    return flow.get("media_get_packets", 0), flow.get("response_bytes", 0)


def verify_session(out, receiver_dir, trial, interfaces, before):
    journal = receiver_dir / "receiver-events.jsonl"
    events = [json.loads(line) for line in journal.read_text().splitlines()]
    first = next((e for e in events if e["event"] == "first_real_frame_decoded"
                  and e["monotonic_ns"] == trial["receiver_first_frame_monotonic_ns"]), None)
    if not first or first["frame"] < 1:
        raise RuntimeError("Image horodatée du lecteur du récepteur absente")
    generation = first["generation"]
    session = [e for e in events if e.get("generation") == generation]
    decoder = next((e for e in session if e["event"] == "decoder_started" and e["transport"] == "slirp"), None)
    if not decoder:
        raise RuntimeError("Décodage via le routeur virtuel de l'émulateur absent")
    advertised = urlsplit(decoder["original_uri"])
    control = any(e["event"] == "soap" and e["action"] == "Play"
                  and e["host"] == "10.0.2.2:18999" and e["monotonic_ns"] >= trial["selection_monotonic_ns"]
                  for e in events)
    discovery = any(e["event"] == "device_description" and e["host"] == "10.0.2.2:18999"
                    for e in events)
    socket = next((e for e in session if e["event"] == "relay_socket_on_guest"
                   and e["advertised_ip"] == advertised.hostname and advertised.hostname in interfaces
                   and e["local_ip"] in interfaces
                   and e["local_port"] == advertised.port == decoder["slirp_guest_port"]
                   and e["peer_ip"].startswith("10.0.2.") and e["peer_ip"] != e["local_ip"]), None)
    redirect = any(e["event"] == "relay_port_redirected" and e["guest_port"] == advertised.port
                   and e["host_port"] == 19001 and e["monotonic_ns"] >= trial["selection_monotonic_ns"]
                   for e in events)
    if not (control and discovery and socket and redirect and advertised.path.startswith("/relay/")):
        raise RuntimeError("Découverte, commande DLNA, redirection NAT ou socket LAN absente")
    relay_bytes = max((e["connection_bytes"] for e in events if e["event"] == "relay_upstream_bytes"
                       and e["monotonic_ns"] >= trial["selection_monotonic_ns"]), default=0)
    if relay_bytes <= 131072:
        raise RuntimeError("Transfert de la mire depuis l'origine pendant ce Cast non confirmé")
    origin_proof = dict(origin_fixture_relay_bytes=relay_bytes)
    if before is not None:
        after = vpn_counts(out)
        gets, octets = after[0] - before[0], after[1] - before[1]
        if gets < 1 or octets <= 131072:
            raise RuntimeError("Requête média et transfert VPN pendant ce Cast non confirmés")
        origin_proof.update(media_gets_during_cast=gets, vpn_bytes_during_cast=octets)
    source = receiver_dir / f"receiver-{generation}-001.jpg"
    with Image.open(source) as picture:
        _, bars = displayed_pattern(picture)
        if bars < 5:
            raise RuntimeError(f"Mire du récepteur non reconnue ({bars}/6 barres)")
        picture.save(out / "cast-receiver-first.png")
    return dict(generation=generation, received_on_advertised_ip=(socket["local_ip"] == advertised.hostname),
                advertised_guest_ip=advertised.hostname, advertised_interface=interfaces[advertised.hostname],
                nat_guest_ip=socket["local_ip"], nat_guest_interface=interfaces[socket["local_ip"]],
                nat_guest_port=socket["local_port"], lan_peer=socket["peer_ip"], lan_peer_port=socket["peer_port"],
                transport="emulator virtual router (host NAT)", receiver_bars=bars,
                receiver_capture="cast-receiver-first.png", **origin_proof)


class SingleCast(Bench):
    def preload_with_vpn_off(self, component, profile, vpn_origin):
        server = "http://10.0.2.2:18999"
        playlist = (self.out / "media" / "review.m3u").read_text()
        media = [line for line in playlist.splitlines() if line and not line.startswith("#")]
        if media != [vpn_origin + "/pattern.ts", vpn_origin + "/movie/qa/lab/777.mp4"]:
            raise ValueError("Le M3U de préparation doit conserver les deux URL média accessibles par VPN")

        def switch(action):
            subprocess.run(["bash", str(Path(__file__).with_name("tunnel.sh")), action, self.serial,
                            self.package, str(self.out / "vpn")], check=True, timeout=75)

        switch("down")
        try:
            for _ in range(20):
                if "192.0.2.2/30" not in self.adb("shell", "ip", "-o", "-4", "addr", "show"):
                    break
                time.sleep(.5)
            else:
                raise RuntimeError("Le VPN Android reste actif avant l’import local")
            # La préparation utilise le formulaire normal d’import par URL.
            # Le serveur du banc, la passerelle et les URL média restent en place.
            os.environ["NOVATUBE_QA_LOCAL_PLAYLIST"] = "0"
            super().setup(component, profile, server, 1)
            for category, title in (("movie", "orion"), ("live", "mire")):
                self.restart()
                if not self.lab_home(30):
                    raise RuntimeError("Accueil absent après préparation du catalogue")
                self.open_tab(category)
                if self.locate(title, timeout=18, semantics=title) is None:
                    raise RuntimeError(f"Titre {title} absent du catalogue {category} avant activation du VPN")
                self.screenshot(f"prepared-catalogue-{category}")
            self.report.update(playlist_preparation_url=server + "/review.m3u",
                               prepared_catalogues=["Orion", "Mire locale"], preparation_vpn="off")
        finally:
            switch("up")
        self.origin = vpn_origin
        self.report.update(fixture=vpn_origin, measurement_vpn="on",
                           vpn_ready_monotonic_ns=time.monotonic_ns())
        self.save()
        # trial(cold) redémarre NovaTube avant la lecture et la sélection du récepteur.

    def casting(self, trial):
        addresses = self.adb("shell", "ip", "-o", "-4", "addr", "show")
        (self.out / "cast-android-v4.txt").write_text(addresses)
        entries = re.findall(r"^\d+:\s+(\S+)\s+inet\s+([.\d]+)/", addresses, flags=re.MULTILINE)
        interfaces = {ip: iface for iface, ip in entries if ip in ("10.0.2.15", "10.0.2.16")}
        enabled = os.environ["NOVATUBE_QA_VPN"] == "on"
        if not enabled and any(iface.startswith("tun") for iface, _ in entries):
            raise RuntimeError("Une interface de tunnel IPv4 est présente lors de l'essai VPN désactivé")
        # La lecture locale et l'import ont déjà eu lieu au début de cette fenêtre.
        before = vpn_counts(self.out) if enabled else None
        completed = False
        try:
            super().casting(trial)
            completed = True
        finally:
            if "receiver_first_frame_monotonic_ns" in trial:
                # Conserver les faits acquis même si le retour accueil ou Stop échoue ensuite.
                try:
                    self.report["cast_transport_proof"] = verify_session(
                        self.out, self.receiver_dir, trial, interfaces, before
                    )
                except Exception as exc:
                    self.report["cast_transport_error"] = str(exc)
                    if completed:
                        raise



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--serial", default="emulator-5554")
    parser.add_argument("--component", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--expected-version", required=True, type=int)
    parser.add_argument("--expected-digest", required=True)
    args = parser.parse_args()
    profile, origin = os.environ["NOVATUBE_PERF_PROFILE"], os.environ["NOVATUBE_QA_ORIGIN"].rstrip("/")
    vpn = os.environ.get("NOVATUBE_QA_VPN")
    sources = {"on": "http://192.0.2.1:18999", "off": "http://10.0.2.2:18999"}
    if profile != "phone" or sources.get(vpn) != origin:
        parser.error("Le téléphone et la source correspondant au mode VPN sont requis")
    args.out.mkdir(exist_ok=True, parents=True)
    bench = SingleCast(args.out, args.serial, expected_version=args.expected_version,
                       package=args.package, expected_digest=args.expected_digest)
    try:
        if vpn == "on" and os.environ.get("NOVATUBE_QA_PRELOAD_SOURCE") == "on":
            bench.preload_with_vpn_off(args.component, profile, origin)
        else:
            bench.setup(args.component, profile, origin, 1)
        bench.report["vpn_mode"] = vpn
        bench.trial("cast", 0, "cold")
        bench.report["validated"] = True
    except Exception as exc:
        bench.report["validated"] = False
        bench.report.setdefault("errors", []).append({"stage": "cast_lan_once", "reason": str(exc)})
        raise
    finally:
        bench.save()


if __name__ == "__main__":
    main()
