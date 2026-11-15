#!/usr/bin/env python3
"""Apply phase 1 to the owner's pinned 334.2.6 maintenance source, offline.

Copies only Java sources into a new directory. Never copies signing material,
contacts a server, changes a licence, signs an APK, or publishes anything.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil

PACKAGE = Path("com/manthefew/direct")


def once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError("Source anchor mismatch; do not apply to a different base")
    return text.replace(old, new, 1)


def patch_sources(maintenance: Path, output: Path, kit: Path | None = None) -> dict:
    kit = kit or Path(__file__).resolve().parent
    source = maintenance / "src"
    lock = json.loads((kit / "source-lock.json").read_text())
    if output.exists():
        raise ValueError("Choose a fresh output directory; existing data are never overwritten")
    java_files = sorted(path.relative_to(source).as_posix() for path in source.rglob("*.java"))
    expected = sorted((PACKAGE / name).as_posix() for name in lock)
    if java_files != expected or any(path.is_symlink() for path in source.rglob("*")):
        raise ValueError("Unexpected source files or symbolic links")
    if output.resolve().is_relative_to(source.resolve()):
        raise ValueError("Output cannot be placed inside the original sources")
    for name, digest in lock.items():
        path = source / PACKAGE / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError("Not the pinned 334.2.6 source: " + name)
    shutil.copytree(source, output / "src")
    target = output / "src" / PACKAGE
    for name in ("NovaTubeWelcome.java", "NovaTubePalette.java"):
        shutil.copyfile(kit / "payload" / name, target / name)

    path = target / "AtlasAppearance.java"
    content = path.read_text()
    content = once(content, '''            boolean day = hour >= 7 && hour < 19;
            backgroundTop = light ? 0xffe8eef6 : day ? 0xff0e1b2c : 0xff080f1c;
            backgroundBottom = light ? 0xffd8e3f0 : day ? 0xff070d17 : 0xff030710;
            surface = light ? 0xfff6f9fd : day ? 0xff14253b : 0xff0e1c2e;
            accent = color(remoteAccent, light ? 0xff286497 : 0xff78a8d8);
            text = light ? 0xff12283f : 0xffe7eef8;
            muted = light ? 0xff425b73 : 0xffa9bacd;''', '''            // Stable petrol/black default; an explicit owner override is still respected.
            backgroundTop = light ? NovaTubePalette.LIGHT_BACKGROUND_TOP : NovaTubePalette.BACKGROUND_TOP;
            backgroundBottom = light ? NovaTubePalette.LIGHT_BACKGROUND_BOTTOM : NovaTubePalette.BACKGROUND_BOTTOM;
            surface = light ? NovaTubePalette.LIGHT_SURFACE : NovaTubePalette.SURFACE;
            accent = color(remoteAccent, light ? NovaTubePalette.LIGHT_ACCENT : NovaTubePalette.ACCENT);
            text = light ? NovaTubePalette.LIGHT_TEXT : NovaTubePalette.TEXT;
            muted = light ? NovaTubePalette.LIGHT_MUTED : NovaTubePalette.MUTED;''')
    content = once(content, '? "platform_change" : "blue_ghost"', '? "platform_change" : "petrol_black"')
    path.write_text(content)

    path = target / "DirectSources.java"
    content = path.read_text()
    content = once(content, '''    static void showWelcomeEditor(Activity activity) {
        if (!alive(activity) || welcomeEditorOpen(activity)) return;
        showEditor(activity, new Session(), null, false, true);
    }''', '''    static void showWelcomeEditor(Activity activity) {
        showWelcomeEditor(activity, false);
    }

    /** Display the requested input form. This does not save, import or grant access. */
    static void showWelcomeEditor(Activity activity, boolean m3u) {
        if (!alive(activity) || welcomeEditorOpen(activity)) return;
        showEditor(activity, new Session(), null, false, true, m3u);
    }''')
    content = once(content, '''    private static void showEditor(final Activity activity, final Session session, final Source previous,
                                   final boolean suggestion, final boolean localOnly) {
        if (!alive(activity)''', '''    private static void showEditor(final Activity activity, final Session session, final Source previous,
                                   final boolean suggestion, final boolean localOnly) {
        showEditor(activity, session, previous, suggestion, localOnly, false);
    }

    private static void showEditor(final Activity activity, final Session session, final Source previous,
                                   final boolean suggestion, final boolean localOnly, final boolean startWithM3u) {
        if (!alive(activity)''')
    content = once(content, '''        type.check(previous != null && TYPE_M3U.equals(previous.type) ? m3u.getId() : xtream.getId());''', '''        boolean initialM3u = previous != null ? TYPE_M3U.equals(previous.type) : startWithM3u;
        type.check(initialM3u ? m3u.getId() : xtream.getId());''')
    path.write_text(content)

    path = target / "NovaTubeAtmosphere.java"
    content = path.read_text()
    replacements = {
        "0x14396F9D": "0x143B7869", "0x002A5785": "0x0028463C",
        "0x002D7DAD": "0x00428F7E", "0x182D7DAD": "0x18428F7E", "0x063D9CCB": "0x0655AD99",
        "165, 218, 247": "174, 220, 203", "185, 231, 255": "201, 237, 222",
        "0xFFE4F4FF": "0xFFEEF5F2", "0xFFE8F5FF": "0xFFEEF5F2", "0xFFBBDDF4": "0xFFBDDED0",
        "0xFF00BCEC": "0xFF64C8B8", "0xFF00D7F4": "0xFF80D5C2", "0xFF00CFF4": "0xFF64C8B8",
    }
    for old, new in replacements.items():
        if old not in content:
            raise ValueError("Missing atmosphere colour anchor")
        content = content.replace(old, new)
    path.write_text(content)

    immutable = ("AtlasActivation.java", "AtlasPanel.java", "M3uGateway.java", "AtlasCinema.java")
    for name in immutable:
        if (target / name).read_bytes() != (source / PACKAGE / name).read_bytes():
            raise AssertionError("Protected source changed: " + name)
    report = {"phase": 1, "compiled": False, "published": False,
              "immutable_sources": list(immutable),
              "changed_sources": [name for name in lock if (target / name).read_bytes() != (source / PACKAGE / name).read_bytes()],
              "added_sources": ["NovaTubePalette.java"],
              "scope": "welcome/input forms and palette; live layout not rebuilt"}
    (output / "source-patch-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--maintenance", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(patch_sources(args.maintenance, args.output), indent=2))


if __name__ == "__main__":
    main()
