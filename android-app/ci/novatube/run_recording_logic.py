#!/usr/bin/env python3
"""Teste la politique d'export NOVATUBE sur JVM, sans simuler les codecs Android."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def verify(cache: Path) -> None:
    app_root = Path(__file__).resolve().parents[2]
    # Même liste de JAR officiels et mêmes SHA-256 que les tests Cast existants.
    # Le runner Cast n'est ni modifié ni exécuté ici.
    loader = importlib.util.spec_from_file_location(
        "novatube_pinned_jvm_dependencies", app_root / "ci/cast_test/run_native_logic.py"
    )
    if loader is None or loader.loader is None:
        raise RuntimeError("Chargement de la liste JVM épinglée impossible")
    dependencies = importlib.util.module_from_spec(loader)
    loader.loader.exec_module(dependencies)
    sources = (
        app_root / "android/app/src/main/kotlin/com/sevenmotion/novatube/GalleryExportPolicy.kt",
        app_root / "ci/novatube/GalleryExportPolicyTest.kt",
        app_root / "android/app/src/main/kotlin/com/sevenmotion/novatube/PlayRecordingStopper.kt",
        app_root / "ci/novatube/PlayRecordingStopperTest.kt",
    )
    for source in sources:
        if not source.is_file():
            raise RuntimeError(f"Source native absente : {source.name}")

    cache.mkdir(parents=True, exist_ok=True)
    print("Vérification des 12 dépendances Kotlin/JUnit épinglées…", flush=True)
    with ThreadPoolExecutor(max_workers=4) as downloads:
        jars = list(downloads.map(
            lambda artifact: dependencies.ensure_artifact(cache, artifact), dependencies.ARTIFACTS
        ))
    classpath = os.pathsep.join(map(str, jars))
    with tempfile.TemporaryDirectory(prefix="novatube-recording-jvm-classes-") as classes:
        print("Compilation de la politique d'export et de ses tests…", flush=True)
        subprocess.run(
            ["java", "-cp", classpath, "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
             "-no-stdlib", "-no-reflect", "-classpath", classpath, "-jvm-target", "17",
             "-d", classes, *map(str, sources)],
            cwd=app_root, check=True,
        )
        print("Exécution des tests GalleryExportPolicy…", flush=True)
        subprocess.run(
            ["java", "-cp", classes + os.pathsep + classpath, "org.junit.runner.JUnitCore",
             "com.sevenmotion.novatube.GalleryExportPolicyTest",
             "com.sevenmotion.novatube.PlayRecordingStopperTest"],
            cwd=app_root, check=True,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache-dir", type=Path,
        default=Path(tempfile.gettempdir()) / "zuno-cast-kotlin-jars",
        help="Cache partagé des JAR dont les SHA-256 sont revérifiés à chaque passage.",
    )
    args = parser.parse_args()
    try:
        verify(args.cache_dir.expanduser().resolve())
    except subprocess.CalledProcessError as error:
        print(f"La vérification Kotlin/JUnit a échoué (code {error.returncode}).", file=sys.stderr)
        return 1
    except (OSError, RuntimeError) as error:
        print(f"La préparation des tests natifs a échoué : {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
