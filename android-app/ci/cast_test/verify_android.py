#!/usr/bin/env python3
"""Contrôle le manifeste fusionné et les ponts réellement embarqués dans l'APK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

from prepare_android import ANDROID, PERMISSIONS, TEST_LABEL, TEST_PACKAGE


def is_media_playback_type(value):
    # ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK vaut exactement 2.
    # apkanalyzer peut imprimer le nom OU l'entier encodé dans le manifeste
    # binaire (par exemple 0x2). Un autre bit associé reste interdit.
    if value == "mediaPlayback":
        return True
    if value is None or re.fullmatch(r"(?:[0-9]+|0[xX][0-9a-fA-F]+)", value) is None:
        return False
    return int(value, 16 if value.lower().startswith("0x") else 10) == 2


def verify(apk_path, manifest_path):
    root = ET.parse(manifest_path).getroot()
    app = root.find("application")
    assert root.get("package") == TEST_PACKAGE, "Package client ou inattendu"
    assert app is not None and app.get(ANDROID + "label") == TEST_LABEL, "Nom de test absent"
    sdk = root.find("uses-sdk")
    assert sdk is not None and sdk.get(ANDROID + "minSdkVersion") == "24", "minSdk tactile incorrect"
    assert int(sdk.get(ANDROID + "targetSdkVersion", "0")) >= 35, "targetSdk ancien"
    launcher_activities = [
        activity for activity in app.findall("activity")
        if any(c.get(ANDROID + "name") == "android.intent.category.LAUNCHER"
               for c in activity.findall("intent-filter/category"))
    ]
    assert len(launcher_activities) == 1, "Lanceur tactile ambigu"
    assert launcher_activities[0].get(ANDROID + "name") == "com.example.tv_king.ZunoCastActivity", "Mauvaise activité"
    assert not any(c.get(ANDROID + "name") == "android.intent.category.LEANBACK_LAUNCHER"
                   for c in root.iter("category")), "Lanceur TV dans l'APK tactile"
    assert not any("leanback" in f.get(ANDROID + "name", "") for f in root.findall("uses-feature")), "Feature TV dans l'APK tactile"
    permissions = {p.get(ANDROID + "name") for p in root.findall("uses-permission")}
    assert {"android.permission." + p for p in PERMISSIONS} <= permissions, "Permission Cast absente après fusion"
    assert any(m.get(ANDROID + "name") == "com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
               and m.get(ANDROID + "value") == "com.example.tv_king.CastOptionsProviderImpl"
               for m in app.findall("meta-data")), "Options Google Cast absentes"
    for service in ("RecordingForegroundService", "PlaybackForegroundService"):
        assert any(s.get(ANDROID + "name") == f"com.example.tv_king.{service}"
                   and is_media_playback_type(s.get(ANDROID + "foregroundServiceType"))
                   for s in app.findall("service")), f"Service absent ou type foreground incorrect : {service}"
    # Le build est debug, sans R8 : les noms de classes sont conservés dans
    # les DEX. Vérifier l'APK détecte un overlay oublié malgré un Dart valide.
    expected = {
        b"Lcom/example/tv_king/ZunoCastActivity;",
        b"Lcom/example/tv_king/GoogleCastApi;",
        b"Lcom/example/tv_king/MulticastLockBridge;",
        b"Lcom/google/android/gms/cast/framework/CastContext;",
    }
    with zipfile.ZipFile(apk_path) as archive:
        found = set()
        for name in archive.namelist():
            if name.startswith("classes") and name.endswith(".dex"):
                data = archive.read(name)
                found.update(item for item in expected if item in data)
        assert found == expected, "SDK ou pont natif absent des DEX"
    with open(apk_path, "rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {
        "sourceCommit": os.environ.get("GITHUB_SHA", "local"),
        "edition": "touch", "entrypoint": "lib/main_zuno_mobile.dart",
        "package": TEST_PACKAGE, "label": TEST_LABEL,
        "versionCode": root.get(ANDROID + "versionCode"),
        "versionName": root.get(ANDROID + "versionName"),
        "minSdk": 24, "googleCastBridge": True, "multicastBridge": True,
        "updatesDisabledByBuild": True, "signing": "runner-debug-key",
        "sha256": digest, "sizeBytes": Path(apk_path).stat().st_size,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    report = verify(args.apk, args.manifest)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
