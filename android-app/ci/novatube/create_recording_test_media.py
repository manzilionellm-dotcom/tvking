#!/usr/bin/env python3
"""Prépare deux mires versionnées ; régénération locale explicite avec FFmpeg."""

import argparse
import hashlib
from pathlib import Path
import subprocess

MEDIA_ROOT = Path(__file__).with_name("recording-test-media")
EXPECTED_SHA256 = {
    "novatube-h264-aac.ts": "81724394c63e0b5294ba57e47c0e2c631ded3c28e0b0589610c768a64c019694",
    "novatube-hevc-aac.ts": "877f42e6f1ce221f66818f96ffb34337cd5f188e3cb7eada0443ec99ab514396",
}


def create(destination: Path) -> None:
    """La CI copie exactement les clips relus et décodés avant le commit."""
    destination.mkdir(parents=True, exist_ok=True)
    for name, digest in EXPECTED_SHA256.items():
        data = (MEDIA_ROOT / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError("Mire synthétique modifiée : " + name)
        (destination / name).write_bytes(data)


def regenerate(destination: Path) -> None:
    """Commande documentée de fabrication, jamais exécutée par le workflow."""
    destination.mkdir(parents=True, exist_ok=True)
    for codec, name, options in (
        ("libx264", "novatube-h264-aac.ts", ["-profile:v", "baseline"]),
        ("libx265", "novatube-hevc-aac.ts", ["-x265-params", "pools=none:frame-threads=1:log-level=error"]),
    ):
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
            "-t", "2", "-c:v", codec, "-preset", "ultrafast", *options,
            "-pix_fmt", "yuv420p", "-b:v", "160k", "-g", "25",
            "-c:a", "aac", "-b:a", "48k", "-ac", "1", "-f", "mpegts",
            str(destination / name),
        ], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regenerate", type=Path,
                        help="Fabriquer de nouvelles mires dans ce dossier avec FFmpeg local")
    args = parser.parse_args()
    if args.regenerate is not None:
        regenerate(args.regenerate)
    else:
        create(Path(__file__).resolve().parents[2] / "android/app/src/androidTest/assets")
