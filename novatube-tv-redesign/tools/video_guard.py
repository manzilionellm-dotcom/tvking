#!/usr/bin/env python3
"""Freeze the existing APK, then reject changes outside the presentation DEX.

This checks binary preservation, not visual equivalence, HDR output, runtime
performance, signing identity, or whether a candidate was built from reviewed
sources. Those are separate release gates. No licence/provider call is made.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

BASE_SHA256 = "cc3481f0039cde8225b0dcce6ea93aad76a2bc424469663be782e28e6d2266d5"
PRESENTATION_DEX = "classes2.dex"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def signing_entry(name: str) -> bool:
    if not name.startswith("META-INF/"):
        return False
    leaf = name[len("META-INF/"):]
    return "/" not in leaf and (leaf == "MANIFEST.MF" or leaf.endswith((".RSA", ".DSA", ".EC", ".SF")))


def inventory(path: Path) -> dict[str, str]:
    result = {}
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate ZIP entries are forbidden")
        for item in archive.infolist():
            if item.is_dir():
                continue
            if item.filename.startswith("/") or ".." in item.filename.split("/"):
                raise ValueError("Unsafe archive path")
            digest = hashlib.sha256()
            with archive.open(item) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            result[item.filename] = digest.hexdigest()
    return result


def freeze(path: Path, require_known_base: bool = True) -> dict:
    digest = sha256_file(path)
    if require_known_base and digest != BASE_SHA256:
        raise ValueError("Wrong base APK. Expected NovaTube TV 334.2.6; refusing a mobile or unrelated build")
    entries = inventory(path)
    if "classes.dex" not in entries or PRESENTATION_DEX not in entries:
        raise ValueError("Expected primary and secondary DEX")
    native = sorted(name for name in entries if name.startswith("lib/") and name.endswith(".so"))
    if require_known_base and len(native) != 21:
        raise ValueError("Expected 21 native libraries")
    protected = {name: value for name, value in entries.items()
                 if name != PRESENTATION_DEX and not signing_entry(name)}
    return {"schema": 1, "base_sha256": digest, "protected_entries": protected,
            "native_libraries": native, "mutable_entries": [PRESENTATION_DEX],
            "manifest_policy": "unchanged for phase-1 review; version bump needs a separate reviewed gate",
            "does_not_prove": ["picture quality", "HDR", "performance", "signing certificate", "provider playback"]}


def verify(lock: dict, candidate: Path) -> dict:
    if lock.get("schema") != 1 or lock.get("mutable_entries") != [PRESENTATION_DEX]:
        raise ValueError("Unsupported or weakened lock policy")
    protected = lock.get("protected_entries")
    if not isinstance(protected, dict) or "classes.dex" not in protected or "AndroidManifest.xml" not in protected:
        raise ValueError("Incomplete lock")
    entries = inventory(candidate)
    changed = sorted(name for name, expected in protected.items() if entries.get(name) != expected)
    extra = sorted(name for name in entries if name not in protected
                   and name != PRESENTATION_DEX and not signing_entry(name))
    if PRESENTATION_DEX not in entries:
        changed.append(PRESENTATION_DEX)
    return {"ok": not changed and not extra, "candidate_sha256": sha256_file(candidate),
            "checked_entries": len(protected), "native_libraries": len(lock.get("native_libraries", [])),
            "changed_or_missing": changed, "unexpected_entries": extra,
            "scope": "binary preservation only; not Android execution or picture-quality validation"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    freeze_parser = commands.add_parser("freeze")
    freeze_parser.add_argument("apk", type=Path)
    freeze_parser.add_argument("lock", type=Path)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("lock", type=Path)
    verify_parser.add_argument("apk", type=Path)
    verify_parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.command == "freeze":
        record = freeze(args.apk)
        args.lock.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"protected_entries": len(record["protected_entries"]),
                          "native_libraries": len(record["native_libraries"]), "base_sha256": record["base_sha256"]}))
    else:
        result = verify(json.loads(args.lock.read_text()), args.apk)
        rendered = json.dumps(result, indent=2) + "\n"
        if args.report:
            args.report.write_text(rendered)
        print(rendered)
        raise SystemExit(0 if result["ok"] else 2)


if __name__ == "__main__":
    main()
