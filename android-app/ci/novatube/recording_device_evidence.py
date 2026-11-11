"""Lit les résultats instrumentés Android sans confondre lancement et réussite."""

import json
from pathlib import Path
import re

from common import require, sha256_file

TEST_CLASS = "com.sevenmotion.novatube.GalleryExporterInstrumentedTest"
TEST_METHODS = (
    "h264AacRecordingIsSavedAsReadablePublicMp4",
    "hevcRecordingIsConvertedToH264WithAudio",
    "playlistTextIsNeverPublishedAsAnMp4",
)


def instrumentation_results(text: str) -> int:
    require(re.search(r"^INSTRUMENTATION_CODE: -1\s*$", text, re.M) is not None,
            "Exécution Android non terminée avec succès")
    require(re.search(r"^OK \(3 tests\)\s*$", text, re.M) is not None,
            "Résumé des trois tests Android absent")
    require("FAILURES!!!" not in text and "INSTRUMENTATION_FAILED" not in text,
            "Échec Android présent dans le rapport")
    fields = {}
    completed = []
    for line in text.splitlines():
        if line.startswith("INSTRUMENTATION_STATUS: "):
            key, separator, value = line[len("INSTRUMENTATION_STATUS: "):].partition("=")
            if separator:
                fields[key] = value
        elif line.startswith("INSTRUMENTATION_STATUS_CODE:"):
            code = int(line.partition(":")[2].strip())
            require(code in (0, 1), "Un test Android a échoué ou a été ignoré")
            if code == 0:
                require(fields.get("class") == TEST_CLASS, "Classe de test Android inattendue")
                completed.append(fields.get("test"))
            fields = {}
    require(sorted(completed) == sorted(TEST_METHODS),
            "Les trois tests d'export Android doivent réussir une seule fois chacun")
    return len(completed)


def device_test_results(reports: Path, source_commit: str, apk_digest: str | None = None) -> dict:
    result = json.loads((reports / "recording-device-tests.json").read_text(encoding="utf-8"))
    log = reports / "recording-device-tests.txt"
    count = instrumentation_results(log.read_text(encoding="utf-8"))
    require(result.get("status") == "passed" and result.get("platform") == "Android Emulator AOSP"
            and result.get("apiLevel") == 35 and result.get("physicalDevice") is False
            and result.get("sourceCommit") == source_commit and result.get("passed") == count,
            "Preuve de test Android incompatible avec le build")
    require(result.get("reportSha256") == sha256_file(log), "Rapport Android modifié")
    require(re.fullmatch(r"[0-9a-f]{64}", str(result.get("apkSha256", ""))) is not None,
            "Empreinte de l'APK testé absente")
    if apk_digest is not None:
        require(result["apkSha256"] == apk_digest, "L'APK livré diffère de celui testé sur Android")
    return result
