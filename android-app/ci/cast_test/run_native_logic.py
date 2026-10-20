#!/usr/bin/env python3
"""Compile et teste la garde réseau Cast, sans Gradle, Android ni flux réel."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.request import urlopen


MAVEN_CENTRAL = "https://repo.maven.apache.org/maven2/"

# Versions utilisées par le compilateur Kotlin 2.0.21 et le runner JUnit.
# Les sommes portent sur les JAR officiels, et sont contrôlées aussi en cache.
ARTIFACTS = (
    (
        "org/jetbrains/kotlin/kotlin-compiler-embeddable/2.0.21/kotlin-compiler-embeddable-2.0.21.jar",
        "9fa8cdd1de0dccffe154c997d423ec6b5f53cd6d9177e3a77a9b0de03fb1bc81",
    ),
    (
        "org/jetbrains/kotlin/kotlin-stdlib/2.0.21/kotlin-stdlib-2.0.21.jar",
        "f31cc53f105a7e48c093683bbd5437561d1233920513774b470805641bedbc09",
    ),
    (
        "org/jetbrains/kotlin/kotlin-script-runtime/2.0.21/kotlin-script-runtime-2.0.21.jar",
        "9c111f8d08ade455566272d561921adc2b2cb6b7a4ccee38d9829c5e3a1ca6a3",
    ),
    (
        "org/jetbrains/kotlin/kotlin-reflect/1.6.10/kotlin-reflect-1.6.10.jar",
        "3277ac102ae17aad10a55abec75ff5696c8d109790396434b496e75087854203",
    ),
    (
        "org/jetbrains/kotlin/kotlin-daemon-embeddable/2.0.21/kotlin-daemon-embeddable-2.0.21.jar",
        "b1a0a73c5022f8dd05a638c6b76b2bd7361818a1f3860ff2644133b1dd2bdb03",
    ),
    (
        "org/jetbrains/intellij/deps/trove4j/1.0.20200330/trove4j-1.0.20200330.jar",
        "c5fd725bffab51846bf3c77db1383c60aaaebfe1b7fe2f00d23fe1b7df0a439d",
    ),
    (
        "org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.6.4/kotlinx-coroutines-core-jvm-1.6.4.jar",
        "c24c8bb27bb320c4a93871501a7e5e0c61607638907b197aef675513d4c820be",
    ),
    (
        "org/jetbrains/annotations/13.0/annotations-13.0.jar",
        "ace2a10dc8e2d5fd34925ecac03e4988b2c0f851650c94b8cef49ba1bd111478",
    ),
    (
        "org/jetbrains/kotlin/kotlin-test/2.0.21/kotlin-test-2.0.21.jar",
        "a897b28c6a3ea8ec8f00ed766941a0c0df993d7f65908875879868e08ceb8985",
    ),
    (
        "org/jetbrains/kotlin/kotlin-test-junit/2.0.21/kotlin-test-junit-2.0.21.jar",
        "49e2b46d14c47417eb2f19eec0ad21c86d90b81fbd84a5cdb118483d380d87f9",
    ),
    (
        "junit/junit/4.13.2/junit-4.13.2.jar",
        "8e495b634469d64fb8acfa3495a065cbacc8a0fff55ce1e31007be4c16dc57d3",
    ),
    (
        "org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar",
        "66fdef91e9739348df7a096aa384a5685f4e875584cce89386a7a47251c4d8e9",
    ),
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_artifact(cache: Path, artifact: tuple[str, str]) -> Path:
    maven_path, expected = artifact
    target = cache / maven_path.rsplit("/", 1)[-1]
    if target.is_file() and sha256_file(target) == expected:
        return target

    # Un téléchargement partiel ou une erreur de somme ne remplace jamais
    # le JAR utilisable. Le fichier temporaire reste dans le même volume.
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=target.name + ".", suffix=".tmp", dir=cache, delete=False
        ) as output:
            temporary = Path(output.name)
            with urlopen(MAVEN_CENTRAL + maven_path, timeout=60) as response:
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    output.write(chunk)
        if sha256_file(temporary) != expected:
            raise RuntimeError(f"Somme SHA-256 incorrecte : {target.name}")
        temporary.replace(target)
        return target
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def verify(cache: Path) -> None:
    app_root = Path(__file__).resolve().parents[2]
    package = app_root / "packages/native_video_player"
    logic = package / (
        "android/src/main/kotlin/com/manzilionellm/native_video_player/logic"
    )
    sources = (
        logic / "CastNetworkHandoff.kt",
        logic / "BackgroundGate.kt",
        package / "logic-test/src/test/kotlin/CastNetworkHandoffTest.kt",
    )
    for source in sources:
        if not source.is_file():
            raise RuntimeError(f"Source native absente : {source.name}")

    cache.mkdir(parents=True, exist_ok=True)
    print("Vérification des 12 dépendances Kotlin/JUnit épinglées…", flush=True)
    with ThreadPoolExecutor(max_workers=4) as downloads:
        jars = list(downloads.map(lambda artifact: ensure_artifact(cache, artifact), ARTIFACTS))
    # Seuls les JAR déclarés ci-dessus sont chargés, même si le cache contient
    # d'autres fichiers. Aucun bytecode d'une ancienne exécution n'est repris.
    classpath = os.pathsep.join(map(str, jars))
    with tempfile.TemporaryDirectory(prefix="zuno-cast-jvm-classes-") as classes:
        print("Compilation de la garde réseau native et de ses tests…", flush=True)
        subprocess.run(
            [
                "java",
                "-cp",
                classpath,
                "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
                "-no-stdlib",
                "-no-reflect",
                "-classpath",
                classpath,
                "-jvm-target",
                "17",
                "-d",
                classes,
                *map(str, sources),
            ],
            cwd=app_root,
            check=True,
        )
        print("Exécution des tests CastNetworkHandoff…", flush=True)
        subprocess.run(
            [
                "java",
                "-cp",
                classes + os.pathsep + classpath,
                "org.junit.runner.JUnitCore",
                "com.manzilionellm.native_video_player.logic.CastNetworkHandoffTest",
            ],
            cwd=app_root,
            check=True,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(tempfile.gettempdir()) / "zuno-cast-kotlin-jars",
        help="Dossier des JAR vérifiés ; les classes compilées restent temporaires.",
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
