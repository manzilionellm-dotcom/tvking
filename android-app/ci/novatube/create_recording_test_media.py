#!/usr/bin/env python3
"""Crée deux clips synthétiques, sans playlist ni contenu externe."""

from pathlib import Path
import subprocess


def create(destination: Path) -> None:
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
    create(Path(__file__).resolve().parents[2] / "android/app/src/androidTest/assets")
