"""Installe le moteur Android NovaTube uniquement dans l'arbre téléphone de la CI."""
from pathlib import Path
import io
import shutil
import subprocess
import tarfile
import tempfile

recipe = Path(__file__).resolve().parent
assets = recipe / "novatube_video"
phone = Path.cwd()
# Arbre Git du plugin du build 1794878682, commit 40906981373998a861c14cffaa7f7d88eb063e42.
commit = "40906981373998a861c14cffaa7f7d88eb063e42"
expected_tree = "69add11887ee21ceedb335b222fe9d5a4e17345b"
plugin = "android-app/packages/native_video_player"
repo_root = subprocess.check_output(
    ["git", "-C", str(recipe), "rev-parse", "--show-toplevel"], text=True
).strip()
git = ["git", "-C", repo_root]
current_tree = subprocess.check_output([*git, "rev-parse", f"HEAD:{plugin}"], text=True).strip()
# Les recettes TV et téléphone peuvent avancer séparément. La recette téléphone
# utilise toujours le plugin de son build NovaTube, y compris dans un clone peu profond.
if current_tree != expected_tree:
    if subprocess.run([*git, "cat-file", "-e", f"{commit}^{{commit}}"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        subprocess.run([*git, "fetch", "--no-tags", "--depth=1", "origin", commit], check=True)
    current_tree = subprocess.check_output([*git, "rev-parse", f"{commit}:{plugin}"], text=True).strip()
if current_tree != expected_tree:
    raise SystemExit("Le moteur vidéo diffère de la référence NovaTube 1794878682")
destination = phone / "packages/novatube_video"
with tempfile.TemporaryDirectory(prefix="novatube-video-") as temp_dir:
    reference = Path(temp_dir)
    archive = subprocess.check_output([*git, "archive", expected_tree, "android/src/main", "android/build.gradle", "pubspec.yaml"])
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as content:
        content.extractall(reference, filter="data")
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
