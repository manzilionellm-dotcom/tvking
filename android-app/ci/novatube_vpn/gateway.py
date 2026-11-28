"""Passerelle du banc sur le loopback du runner et compteurs des flux synthétiques."""
import argparse
import fcntl
import hmac
import ipaddress
import json
import os
from pathlib import Path
import select
import socket
import struct
import time

SERVER = ipaddress.ip_address("192.0.2.1").packed
CLIENT = ipaddress.ip_address("192.0.2.2").packed
TUNSETIFF = 0x400454CA
IFF_TUN = 0x0001
IFF_NO_PI = 0x1000


def observe(packet, outbound, stats):
    """Seuls les paquets TCP de la mire sont mesurés. Rien du contenu n'est enregistré."""
    if len(packet) < 40 or packet[0] >> 4 != 4 or packet[9] != 6:
        return
    src, dest = packet[12:16], packet[16:20]
    if (src, dest) != ((CLIENT, SERVER) if outbound else (SERVER, CLIENT)):
        return
    header = (packet[0] & 15) * 4
    if header < 20 or len(packet) < header + 20 or int.from_bytes(packet[6:8], "big") & 0x1fff:
        return
    sport, dport = struct.unpack_from("!HH", packet, header)
    tcp_len = (packet[header + 12] >> 4) * 4
    if tcp_len < 20 or len(packet) < header + tcp_len:
        return
    body = packet[header + tcp_len:]
    counters = stats["fixture_tcp"].setdefault(str(dport if outbound else sport),
                                               dict(get_packets=0, media_get_packets=0, response_bytes=0))
    if outbound and body.startswith(b"GET "):
        counters["get_packets"] += 1
        target = body.partition(b" HTTP/")[0].partition(b"?")[0].lower()
        if target.endswith((b".ts", b".mp4", b".m4s", b".m3u8", b".aac")):
            counters["media_get_packets"] += 1
    elif not outbound:
        counters["response_bytes"] += len(body)


def snapshot(path, stats):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(stats, indent=2) + "\n")
    tmp.replace(path)


def run(out, key):
    # L'interface persistante est créée par le script shell pour l'utilisateur du runner.
    tun = os.open("/dev/net/tun", os.O_RDWR)
    fcntl.ioctl(tun, TUNSETIFF, struct.pack("16sH", b"ntqa0", IFF_TUN | IFF_NO_PI))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.bind(("127.0.0.1", 21923))
        peer = None
        stats = dict(connected=False, android_ip="192.0.2.2", source_ip="192.0.2.1",
                     fixture_tcp={}, tunnel_packets_from_android=0, tunnel_packets_to_android=0)
        last_snapshot = 0
        while True:
            if time.monotonic() - last_snapshot >= 0.5:
                snapshot(out, stats)
                last_snapshot = time.monotonic()
            readable = select.select([udp, tun], [], [], .5)[0]
            if udp in readable:
                data, remote = udp.recvfrom(65535)
                if not hmac.compare_digest(data[:len(key)], key):
                    continue
                packet = data[len(key):]
                if not packet:
                    peer = remote
                    stats["connected"] = True
                    snapshot(out, stats)
                elif remote == peer and len(packet) >= 20 and packet[0] >> 4 == 4 and packet[12:16] == CLIENT:
                    observe(packet, True, stats)
                    os.write(tun, packet)
                    stats["tunnel_packets_from_android"] += 1
            if tun in readable:
                packet = os.read(tun, 65535)
                if peer and len(packet) >= 20 and packet[16:20] == CLIENT:
                    observe(packet, False, stats)
                    udp.sendto(key + packet, peer)
                    stats["tunnel_packets_to_android"] += 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("key_file", type=Path)
    args = parser.parse_args()
    run(args.output, args.key_file.read_bytes().strip())
