#!/usr/bin/env python3
"""Identité du ZIP Windows de test, sans installeur ni canal de mise à jour."""
from pathlib import Path
import re
import shutil


def prepare(app_dir):
    app_dir = Path(app_dir)
    runner = app_dir / "windows/runner"
    rc_path = runner / "Runner.rc"
    rc = rc_path.read_text(encoding="utf-8")
    for key, value in (
        ("CompanyName", "Zuno"), ("ProductName", "Zuno Cast test"),
        ("FileDescription", "Zuno Cast test"),
    ):
        rc, count = re.subn(r'(VALUE\s+"' + key + r'",\s*)"[^"]*"',
                            lambda match: match.group(1) + '"' + value + '"', rc)
        if count != 1:
            raise ValueError(f"Identité Windows absente : {key}")
    rc_path.write_text(rc, encoding="utf-8")
    main_path = runner / "main.cpp"
    main = main_path.read_text(encoding="utf-8")
    if 'L"tv_king"' not in main:
        raise ValueError("Titre Windows généré inattendu")
    main_path.write_text(main.replace('L"tv_king"', 'L"Zuno Cast test"'), encoding="utf-8")
    shutil.copyfile(app_dir / "ci/windows/app_icon.ico", runner / "resources/app_icon.ico")

    # Même exclusion Firebase que le build PC existant. Elle ne concerne
    # que ce checkout Windows et ne change pas le package Android.
    pubspec = app_dir / "pubspec.yaml"
    lines = pubspec.read_text(encoding="utf-8").splitlines(keepends=True)
    pubspec.write_text("".join(line for line in lines if not re.match(
        r"\s*(firebase_core|firebase_crashlytics)\s*:", line,
    )), encoding="utf-8")
    (app_dir / "lib/core/crash/crash_reporting_firebase.dart").write_text(
        "// Stub du ZIP Windows de test, identique au choix du build PC.\n"
        "Future<bool> attachCrashlytics() async => false;\n", encoding="utf-8",
    )


if __name__ == "__main__":
    prepare(Path.cwd())
    print("Zuno Cast test : nom Windows distinct, Firebase exclu du PC")
