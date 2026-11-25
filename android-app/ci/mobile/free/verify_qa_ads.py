"""Contrôle les identifiants AdMob encodés dans l'APK final de test."""
import re
import subprocess
import sys

from ads.prepare_ads import TEST_APP, TEST_BANNER

apk, aapt = sys.argv[1:]
manifest = subprocess.check_output(
    [aapt, "dump", "xmltree", apk, "--file", "AndroidManifest.xml"], text=True,
)
if set(re.findall(r"ca-app-pub-[0-9]{16}~[0-9]{10}", manifest)) != {TEST_APP}:
    raise SystemExit("Identifiant d'application AdMob QA absent ou différent")
# Interroger la classe qui appelle AdView évite de compter les identifiants
# d'exemple présents indépendamment dans le SDK Google.
bridge = subprocess.check_output([
    "apkanalyzer", "dex", "code", "--class",
    "com.manzilionellm.tvking.tv_king.SevenMotionAds$Banner", apk,
], text=True)
if set(re.findall(r"ca-app-pub-[0-9]{16}/[0-9]{10}", bridge)) != {TEST_BANNER}:
    raise SystemExit("La classe de bannière ne contient pas exclusivement l'unité de test")
