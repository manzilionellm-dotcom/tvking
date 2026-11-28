"""Exerce REC depuis le lecteur en plein écran sur l'émulateur Android TV de test.

La mire HLS A doit jouer et le catalogue ne contient que A et B. Le dossier des
pilotes optiques est passé par --pilot-dir. Les preuves utilisent uniquement
l'APK installé, les interfaces utilisateur et le MediaStore public Android.
"""
import argparse
import array
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

MEDIA = "content://media/external/video/media"
PROJECTION = "_id:_size:is_pending:owner_package_name:relative_path:mime_type:_display_name"


def external(command, **options):
    return subprocess.run(command, check=True, timeout=options.pop("timeout", 120), **options)


class Device:
    def __init__(self, serial):
        if not re.fullmatch(r"emulator-\d+", serial):
            raise ValueError("Ce banc utilise exclusivement un émulateur jetable de test.")
        self.adb = ["adb", "-s", serial]

    def shell(self, *args):
        cmd = self.adb + ["shell", shlex.join(args)]
        return external(cmd, capture_output=True, text=True, timeout=45).stdout.strip()

    def key(self, name):
        self.shell("input", "keyevent", name)

    def rows(self):
        result = self.shell("content", "query", "--uri", MEDIA, "--projection", PROJECTION)
        if result.startswith("No result found"):
            return {}
        rows = {}
        for line in result.splitlines():
            m = re.fullmatch(r"Row: \d+ _id=(\d+), _size=(\d+|NULL), is_pending=(\d+), "
                             r"owner_package_name=([^,]*), relative_path=([^,]*), "
                             r"mime_type=([^,]*), _display_name=(.*)", line.strip())
            if not m:
                raise RuntimeError(f"Réponse MediaStore inattendue : {line}")
            identifier, size, pending, owner, folder, mime_type, name = m.groups()
            rows[identifier] = dict(id=identifier, size=int(size) if size.isdigit() else 0,
                                    pending=int(pending), owner=owner, folder=folder,
                                    mime_type=mime_type, name=name)
        return rows

    def export(self, row, output):
        """Lire en tant que client indépendant, sans ouvrir le répertoire privé de l'app."""
        uri = f"{MEDIA}/{row['id']}"
        with output.open("wb") as dest:
            external(self.adb + ["exec-out", "content", "read", "--uri", uri],
                     stdout=dest, timeout=240)
        if output.stat().st_size != row["size"]:
            raise RuntimeError(f"Taille MediaStore {row['size']} / fichier lu {output.stat().st_size}")
        with output.open("rb") as source:
            return hashlib.file_digest(source, "sha256").hexdigest()


def wait_for_new_movie(device, existing, package, folder, timeout):
    deadline = time.monotonic() + timeout
    recent = []
    while time.monotonic() < deadline:
        rows = device.rows()
        recent = [r for i, r in rows.items() if i not in existing]
        hits = [r for r in recent if r["pending"] == 0 and r["size"] > 0 and
                r["folder"].strip("/") == folder.strip("/") and r["owner"] == package]
        if len(hits) > 1:
            raise RuntimeError(f"Un appui REC a publié plusieurs vidéos : {hits}")
        if len(hits) == 1:
            return hits[0]
        time.sleep(1.5)
    raise RuntimeError(f"Aucune vidéo publiée dans {folder} par {package}. Nouvelles lignes : {recent}")


def audio_tone(movie, raw, channel):
    # Une piste AAC déclarée mais muette ou issue de l'autre chaîne est un échec.
    external(["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", "1", "-i", str(movie),
              "-map", "0:a:0", "-t", "2", "-ac", "1", "-ar", "8000", "-f", "s16le", str(raw)])
    samples = array.array("h", raw.read_bytes())
    if sys.byteorder != "little":
        samples.byteswap()
    raw.unlink()
    if len(samples) < 8000:
        raise RuntimeError("La piste audio contient moins d'une seconde décodable.")
    # Additionner la puissance sur des fenêtres courtes tolère des sauts de phase entre segments.
    def amplitude(freq):
        omega = 2.0 * math.pi * freq / 8000
        length = 800
        cos = [math.cos(omega * k) for k in range(length)]
        sin = [math.sin(omega * k) for k in range(length)]
        values = []
        for offset in range(0, len(samples) - length + 1, length):
            window = samples[offset:offset + length]
            real = sum(a * b for a, b in zip(window, cos))
            imag = sum(a * b for a, b in zip(window, sin))
            values.append(math.hypot(real, imag) / length)
        return sum(values) / len(values)

    wanted, other = (440, 660) if channel == "A" else (660, 440)
    a, b = amplitude(wanted), amplitude(other)
    if a < 20 or a < 3 * b:
        raise RuntimeError(f"Fréquence de la chaîne {channel} non reconnue : {a:.1f} / {b:.1f}")
    return {"frequency_hz": wanted, "target_amplitude": round(a, 2), "other_amplitude": round(b, 2)}


def inspect_movie(movie, channel, seconds, output, extract):
    command = ["ffprobe", "-v", "error", "-show_entries",
               "format=format_name,duration:stream=codec_type,codec_name,width,height",
               "-of", "json", str(movie)]
    probe = json.loads(external(command, capture_output=True).stdout)
    video = next((s for s in probe["streams"] if s["codec_type"] == "video"), {})
    audio = next((s for s in probe["streams"] if s["codec_type"] == "audio"), {})
    duration = float(probe["format"]["duration"])
    if ("mp4" not in probe["format"]["format_name"].split(",") or video.get("codec_name") != "h264"
            or audio.get("codec_name") != "aac" or not seconds * 0.65 <= duration <= seconds * 1.75):
        raise RuntimeError(f"Format, pistes ou durée inattendus : {probe}")

    csv_file = output / f"mouvement-{channel}.csv"
    extract(movie, csv_file)
    with csv_file.open(newline="") as stream:
        frames = list(csv.DictReader(stream))
    decoded = [row for row in frames if row["channel"] == channel]
    wrong = [row for row in frames if row["channel"] not in (channel, "")]
    advancing = sum(0 < (int(b["source_frame"]) - int(a["source_frame"])) % (1 << 20) < (1 << 19)
                    for a, b in zip(decoded, decoded[1:]))
    if wrong or len(decoded) < 0.8 * len(frames) or advancing < 0.8 * len(decoded) or advancing < 10:
        raise RuntimeError(f"Image erronée ou figée : {len(decoded)}/{len(frames)}, "
                           f"{len(wrong)} mauvaises et {advancing} progressions.")
    tone = audio_tone(movie, output / "audio-temp.pcm", channel)
    return dict(channel=channel, duration_s=duration, stream_probe=probe,
                decoded_video_frames=len(frames), identified=len(decoded),
                advancing_pairs=advancing, audio=tone)


def verify_motion(device, directory, channel, frame, decode):
    # Mêmes positions centrales que clocked_record.py, en tenant compte de la barre système TV.
    previous = None
    deadline = time.monotonic() + 32
    while time.monotonic() < deadline:
        image, data = frame(device.adb, directory, time.monotonic())
        if image is None:
            previous = None
            continue
        image = image.convert("L")
        w, h = image.size
        current, index = "", None
        for top, bottom in ((0, 0), (0, 24), (0, 48), (24, 0), (24, 24), (48, 0), (48, 48)):
            vh = min(h - top - bottom, w * 9 / 16)
            vw = vh * 16 / 9
            x = (w - vw) / 2
            y = top + (h - top - bottom - vh) / 2
            current, index = decode([image.getpixel((round(x + vw * (496 + 32 * i) / 1920),
                                                       round(y + vh * 650 / 1080))) for i in range(30)])
            if current:
                break
        if current == channel and previous is not None and 0 < (index - previous) % (1 << 20) < (1 << 19):
            (directory / f"avant-rec-{channel}.png").write_bytes(data)
            return
        previous = index if current == channel else None
        time.sleep(0.25)
    raise RuntimeError(f"La chaîne {channel} en mouvement n'est pas visible au premier plan.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pilot-dir", required=True, type=Path)
    parser.add_argument("--package", required=True)
    parser.add_argument("--apk-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL", "emulator-5554"))
    parser.add_argument("--folder", default="Movies/NOVATUBE")
    parser.add_argument("--zap-key", default="KEYCODE_CHANNEL_DOWN")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{64}", args.apk_sha256) or args.seconds < 15:
        parser.error("Renseigner le SHA-256 de l'APK livré et une durée de 15 secondes ou plus.")
    args.output.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(args.pilot_dir.resolve()))
    from pilot_observer import frame
    from read_display_capture import decode, extract
    device = Device(args.serial)
    base_paths = device.shell("pm", "path", args.package).splitlines()
    if len(base_paths) != 1 or not base_paths[0].startswith("package:"):
        raise RuntimeError(f"Un APK universel était attendu : {base_paths}")
    installed_sha = device.shell("sha256sum", base_paths[0].removeprefix("package:")).split()[0]
    if installed_sha != args.apk_sha256:
        raise RuntimeError("L'APK installé diffère des octets à livrer.")
    component = device.shell("cmd", "package", "resolve-activity", "--brief",
                             "-a", "android.intent.action.MAIN", "-c",
                             "android.intent.category.LEANBACK_LAUNCHER", args.package).splitlines()[-1]
    if not component.startswith(args.package + "/"):
        raise RuntimeError(f"Activité Leanback introuvable : {component}")

    results = []
    for channel in ("A", "B"):
        if channel == "B":
            device.key(args.zap_key)
        verify_motion(device, args.output, channel, frame, decode)
        existing = set(device.rows())
        device.key("KEYCODE_R")
        time.sleep(args.seconds)
        device.key("KEYCODE_R")
        row = wait_for_new_movie(device, existing, args.package, args.folder, 150)
        if row["mime_type"] != "video/mp4" or not row["name"].lower().endswith(".mp4"):
            raise RuntimeError(f"Le nom public ou le type MIME n'est pas MP4 : {row}")
        movie = args.output / f"mire-{channel}.mp4"
        sha = device.export(row, movie)
        info = inspect_movie(movie, channel, args.seconds, args.output, extract)
        results.append(dict(uri=f"{MEDIA}/{row['id']}", media_store=row, sha256=sha, media=info))

    device.shell("am", "force-stop", args.package)
    device.shell("am", "start", "-W", "-n", component)
    current = device.rows()
    for result in results:
        before = result["media_store"]
        if current.get(before["id"]) != before:
            raise RuntimeError(f"Métadonnées perdues au redémarrage : {before}")
        fresh = args.output / "apres-relance.mp4"
        if device.export(before, fresh) != result["sha256"]:
            raise RuntimeError("La vidéo publique diffère après la relance de NovaTube.")
        fresh.unlink()
    report = dict(package=args.package, apk_sha256=installed_sha, stored_folder=args.folder,
                  elapsed_recording_per_channel_s=args.seconds, android_app_relaunched=True,
                  confirmed_external_read_before_and_after_relaunch=True, recordings=results)
    (args.output / "recording-proof.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print("Deux MP4 publics H.264/AAC ont la bonne image animée et la tonalité attendue. "
          "Les deux empreintes sont identiques après relance de l'application.", flush=True)


if __name__ == "__main__":
    main()
