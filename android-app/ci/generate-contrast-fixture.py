#!/usr/bin/env python3
"""Crée une mire vidéo locale SDR, sans téléchargement ni flux fournisseur."""

import json
from pathlib import Path
import subprocess


app = Path(__file__).resolve().parents[1]
output = app / "packages/native_video_player/android/src/androidTest/assets/contrast_sdr.mp4"
output.parent.mkdir(parents=True, exist_ok=True)

# Quatre plages grises immobiles : les mesures au centre des plages ne
# dépendent ni du sous-échantillonnage chroma ni des contours de compression.
# Deux minutes donnent aux émulateurs lents le temps de faire OFF/ON/OFF,
# avec un fichier très petit puisque toutes les images sont identiques.
pattern = (
    "color=c=0x303030:s=256x144:r=15:d=120,"
    "drawbox=x=64:y=0:w=64:h=ih:color=0x606060:t=fill,"
    "drawbox=x=128:y=0:w=64:h=ih:color=0xb0b0b0:t=fill,"
    "drawbox=x=192:y=0:w=64:h=ih:color=0xe0e0e0:t=fill"
)
subprocess.run([
    "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
    "-f", "lavfi", "-i", pattern, "-an", "-c:v", "libx264",
    "-preset", "veryfast", "-crf", "10", "-profile:v", "baseline",
    "-level", "3.0", "-g", "30", "-keyint_min", "30", "-sc_threshold", "0",
    "-bf", "0", "-pix_fmt", "yuv420p", "-color_range", "tv",
    "-colorspace", "bt709", "-color_trc", "bt709", "-color_primaries", "bt709",
    "-fflags", "+bitexact", "-flags:v", "+bitexact", "-movflags", "+faststart",
    str(output),
], check=True)
probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-show_streams", "-of", "json", str(output),
], text=True))
assert len(probe["streams"]) == 1, "La mire doit être muette."
stream = probe["streams"][0]
assert stream["codec_name"] == "h264"
assert (stream["width"], stream["height"]) == (256, 144)
assert stream["pix_fmt"] == "yuv420p"
assert stream["color_transfer"] == stream["color_primaries"] == "bt709"
assert float(stream["duration"]) >= 120
print(json.dumps({"fixture": str(output), "bytes": output.stat().st_size,
                  "width": 256, "height": 144, "duration_seconds": 120,
                  "color_transfer": "bt709", "audio": False}))
