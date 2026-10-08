#!/usr/bin/env python3
"""Contrôle le binaire Android réel, après fusion et réduction R8.

Le test ne remplace pas Android : il vérifie ses composants déclarés,
ses ressources embarquées et l'alignement de chaque bibliothèque native.
Une notification reçue sur le téléphone reste une preuve distincte.
"""
import argparse
import hashlib
import io
import json
import struct
import wave
import zipfile

from loguru import logger

logger.remove()
from androguard.core.apk import APK

ANDROID = "{http://schemas.android.com/apk/res/android}"
CERT = "5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61"
RECEIVER = "com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
FORBIDDEN_PLAY = {
    "REQUEST_INSTALL_PACKAGES", "READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO",
    "READ_MEDIA_AUDIO", "USE_EXACT_ALARM", "FOREGROUND_SERVICE_MEDIA_PROJECTION",
    "RECEIVE_BOOT_COMPLETED",
}


def audit(path, store=False):
    apk = APK(str(path))
    errors = []
    package = apk.get_package()
    expected = "com.manzilionellm.tvking" if store else "com.manzilionellm.tvking.tv_king"
    if package != expected:
        errors.append("Identifiant différent de l'application attendue")
    if apk.get_min_sdk_version() != "24":
        errors.append("minSdk différent de 24")
    if int(apk.get_target_sdk_version()) < 35:
        errors.append("targetSdk inférieur à 35")
    certs = {hashlib.sha256(c.dump()).hexdigest() for c in apk.get_certificates()}
    if certs != {CERT}:
        errors.append("Certificat différent de la clé d'importation Play")
    root = apk.get_android_manifest_xml()
    receivers = [r for r in root.findall("application/receiver")
                 if r.get(ANDROID + "name") == RECEIVER]
    if len(receivers) != 1 or receivers[0].get(ANDROID + "exported") != "false":
        errors.append("Récepteur des rappels absent ou exporté")
    permissions = set(apk.get_permissions())
    if "android.permission.POST_NOTIFICATIONS" not in permissions:
        errors.append("Permission des notifications absente")
    if store:
        for permission in sorted(FORBIDDEN_PLAY):
            if "android.permission." + permission in permissions:
                errors.append("Permission retirée de la version Play encore présente : " + permission)
        if "android.permission.SCHEDULE_EXACT_ALARM" not in permissions:
            errors.append("Permission du magnétoscope absente")
        for service in root.findall("application/service"):
            if "mediaProjection" in service.get(ANDROID + "foregroundServiceType", ""):
                errors.append("Service de projection d'écran encore présent")
    resources = apk.get_android_resources()
    sound_id = resources.get_res_id_by_key(package, "raw", "goal_roar")
    if not sound_id:
        errors.append("Son goal_roar absent des ressources Android")
    libraries = []
    with zipfile.ZipFile(path) as archive:
        if sound_id:
            sounds = resources.get_resolved_res_configs(sound_id)
            if not sounds:
                errors.append("Son Android sans fichier associé")
            for _, name in sounds:
                with wave.open(io.BytesIO(archive.read(name))) as sound:
                    if sound.getnframes() == 0 or sound.getframerate() < 16000:
                        errors.append("Son Android vide ou invalide")
        for name in archive.namelist():
            if not (name.startswith(("lib/arm64-v8a/", "lib/x86_64/")) and name.endswith(".so")):
                continue
            data = archive.read(name)
            if data[:5] != b"\x7fELF\x02":
                errors.append("Bibliothèque native ELF64 invalide : " + name)
                continue
            endian = "<" if data[5] == 1 else ">"
            offset = struct.unpack_from(endian + "Q", data, 32)[0]
            size, count = struct.unpack_from(endian + "HH", data, 54)
            alignments = []
            for i in range(count):
                header = struct.unpack_from(endian + "IIQQQQQQ", data, offset + i * size)
                if header[0] == 1:
                    alignments.append(header[7])
            if not alignments or any(a < 16384 for a in alignments):
                errors.append("Bibliothèque non alignée sur 16 Ko : " + name)
            libraries.append(name)
    if not libraries:
        errors.append("Aucune bibliothèque native 64 bits contrôlée")
    return {
        "package": package, "versionCode": apk.get_androidversion_code(),
        "versionName": apk.get_androidversion_name(), "minSdk": apk.get_min_sdk_version(),
        "targetSdk": apk.get_target_sdk_version(), "goal_sound": bool(sound_id),
        "scheduled_receiver": bool(receivers), "native_libraries_checked": len(libraries),
        "errors": errors,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("apk")
    parser.add_argument("--play", action="store_true")
    args = parser.parse_args()
    result = audit(args.apk, args.play)
    print(json.dumps(result, ensure_ascii=False))
    raise SystemExit(1 if result["errors"] else 0)
