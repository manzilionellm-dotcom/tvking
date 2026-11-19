"""Installe le moteur Android NovaTube uniquement dans l'arbre téléphone de la CI."""
from pathlib import Path
import shutil
import subprocess

recipe = Path(__file__).resolve().parent
reference = recipe.parents[1] / "packages/native_video_player"
assets = recipe / "novatube_video"
phone = Path.cwd()
# Arbre Git du plugin du build 1794878682, commit 40906981373998a861c14cffaa7f7d88eb063e42.
tree = subprocess.check_output(["git", "-C", str(reference), "rev-parse",
                                "HEAD:android-app/packages/native_video_player"], text=True).strip()
if tree != "69add11887ee21ceedb335b222fe9d5a4e17345b":
    raise SystemExit("Le moteur vidéo diffère de la référence NovaTube 1794878682")
destination = phone / "packages/novatube_video"
destination.mkdir(parents=True, exist_ok=False)
shutil.copytree(reference / "android/src/main", destination / "android/src/main")
shutil.copyfile(reference / "android/build.gradle", destination / "android/build.gradle")
shutil.copyfile(reference / "pubspec.yaml", destination / "pubspec.yaml")
# Les deux plugins partagent le processus Android : noms de classes, canaux et
# fabrique de vue distincts laissent utilisables les écrans 7 MOTION existants.
for source in destination.rglob("*"):
    if source.is_file() and source.suffix in {".kt", ".gradle", ".xml", ".yaml"}:
        source.write_text(source.read_text().replace("native_video_player", "novatube_video"))
subprocess.run(["git", "apply", "--directory=packages/novatube_video",
                str(assets / "phone-controls.patch")], check=True)
kotlin = destination / "android/src/main/kotlin/com/manzilionellm"
(kotlin / "native_video_player").rename(kotlin / "novatube_video")
(destination / "lib").mkdir()
shutil.copyfile(assets / "novatube_video.dart.fixture", destination / "lib/novatube_video.dart")
subprocess.run(["git", "apply", str(assets / "phone-player.patch")], check=True)
shutil.copyfile(assets / "phone_video_test.dart.fixture", phone / "test/features/player/phone_video_test.dart")
