#!/usr/bin/env python3
"""Vérifie le contrat JNI des préférences dans l'APK TV réellement minifié.

Le build 216 contenait les bons noms dans libapp.so, mais ses méthodes DEX
attendaient une classe Continuation renommée par R8. Chercher des chaînes
dans l'APK ne suffit donc pas : on lit les classes et membres effectivement
définis avec dexdump, l'outil officiel des Android SDK Build Tools.

Usage : python3 ci/tv/verify_apk_jni.py app.apk --dexdump /sdk/build-tools/36.1.0/dexdump
"""

import argparse
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


ABIS = ("armeabi-v7a", "arm64-v8a", "x86_64")
PREFERENCES = "Lio/flutter/plugins/sharedpreferences/"
CONTINUATION = "Lkotlin/coroutines/Continuation;"
GET_ALL = (
    "(Ljava/lang/String;Ljava/util/List;"
    "Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
)
KOTLIN_CLASSES = (
    "Lkotlin/Unit;",
    "Lkotlin/Result;",
    "Lkotlin/Result$Failure;",
    CONTINUATION,
    "Lkotlin/coroutines/intrinsics/CoroutineSingletons;",
    "Lkotlin/coroutines/intrinsics/IntrinsicsKt;",
)


def parse_dexdump(output):
    """Sépare les définitions, sans confondre références et membres déclarés."""
    classes = {}
    for block in re.split(r"(?=^Class #\d+\b)", output, flags=re.MULTILINE):
        descriptor = re.search(r"^  Class descriptor\s*:\s*'([^']+)'", block, re.M)
        if not descriptor:
            continue
        superclass = re.search(r"^  Superclass\s*:\s*'([^']+)'", block, re.M)
        entry = {
            "superclass": superclass[1] if superclass else None,
            "methods": set(),
            "fields": set(),
        }
        # Les champs et méthodes sont des sections distinctes du dexdump.
        sections = re.split(
            r"^  (Static fields|Instance fields|Direct methods|Virtual methods)\s*-\s*$",
            block,
            flags=re.MULTILINE,
        )
        for index in range(1, len(sections), 2):
            kind = "methods" if sections[index].endswith("methods") else "fields"
            entry[kind].update(re.findall(
                r"^      name\s*:\s*'([^']+)'\n\s*type\s*:\s*'([^']+)'",
                sections[index + 1],
                flags=re.MULTILINE,
            ))
        classes[descriptor[1]] = entry
    return classes


def has_member(classes, owner, kind, name, signature):
    """JNI peut trouver un membre hérité : suivre les vraies superclasses."""
    visited = set()
    while owner in classes and owner not in visited:
        visited.add(owner)
        entry = classes[owner]
        if (name, signature) in entry[kind]:
            return True
        owner = entry["superclass"]
    return False


def verify(apk, dexdump):
    errors = []
    classes = {}
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as temporary:
        names = set(archive.namelist())
        dex_files = sorted(name for name in names if re.fullmatch(r"classes\d*\.dex", name))
        if not dex_files:
            raise ValueError("Aucun DEX dans l'APK")
        for name in dex_files:
            path = Path(temporary, name)
            path.write_bytes(archive.read(name))
            result = subprocess.run(
                [str(dexdump), str(path)],
                check=True,
                capture_output=True,
                text=True,
                timeout=30,
            )
            classes.update(parse_dexdump(result.stdout))

        # Les trois architectures livrées doivent embarquer le même contrat
        # Dart et le pont natif. Les DEX communs sont vérifiés juste après.
        for abi in ABIS:
            for library in ("libapp.so", "libdartjni.so"):
                name = f"lib/{abi}/{library}"
                if name not in names or not archive.getinfo(name).file_size:
                    errors.append(f"Bibliothèque absente ou vide : {name}")
                elif library == "libapp.so" and GET_ALL.encode() not in archive.read(name):
                    errors.append(f"Signature JNI getAll absente du Dart compilé : {abi}")

    for descriptor in KOTLIN_CLASSES:
        if descriptor not in classes:
            errors.append(f"Classe Kotlin JNI absente ou renommée : {descriptor}")

    # Le binding Dart appelle le registrar ; celui-ci délègue au plugin.
    # Vérifier les deux empêche un faux succès dû à une simple référence DEX.
    methods = (
        (PREFERENCES + "SharedPreferencesApiRegistrar;", "getAll", GET_ALL),
        (PREFERENCES + "LegacySharedPreferencesPlugin;", "getAll", GET_ALL),
        ("Lcom/github/dart_lang/jni/PortContinuation;", "<init>", "(J)V"),
        ("Lcom/github/dart_lang/jni/PortContinuation;", "resumeWith", "(Ljava/lang/Object;)V"),
        ("Lcom/github/dart_lang/jni/JniUtils;", "fromReferenceAddress", "(J)Ljava/lang/Object;"),
        (CONTINUATION, "resumeWith", "(Ljava/lang/Object;)V"),
        ("Lkotlin/Result$Failure;", "<init>", "(Ljava/lang/Throwable;)V"),
        (
            "Lkotlin/coroutines/intrinsics/IntrinsicsKt;",
            "getCOROUTINE_SUSPENDED",
            "()Ljava/lang/Object;",
        ),
    )
    fields = (
        ("Lkotlin/Unit;", "INSTANCE", "Lkotlin/Unit;"),
        ("Lkotlin/Result;", "value", "Ljava/lang/Object;"),
        ("Lkotlin/Result$Failure;", "exception", "Ljava/lang/Throwable;"),
    )
    for kind, members in (("methods", methods), ("fields", fields)):
        for owner, name, signature in members:
            if not has_member(classes, owner, kind, name, signature):
                actual = sorted(
                    descriptor for member, descriptor in classes.get(owner, {}).get(kind, ())
                    if member == name
                )
                errors.append(
                    f"Membre JNI absent ou renommé : {owner}.{name}{signature}"
                    + (f" ; signatures trouvées : {actual}" if actual else "")
                )
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--dexdump", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        errors = verify(arguments.apk, arguments.dexdump)
    except (OSError, ValueError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        print(f"Échec de lecture du contrat JNI : {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"ERREUR : {error}", file=sys.stderr)
        return 1
    print("JNI préférences vérifié dans les DEX et les 3 ABI : Kotlin, registrar et pont natif intacts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
