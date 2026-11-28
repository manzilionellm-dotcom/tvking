#!/usr/bin/env python3
"""Installe uniquement dans le checkout LAB le pont MediaStore de NovaTube mobile."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
MAIN = ROOT / "android/app/src/main"
KOTLIN = MAIN / "kotlin/com/example/tv_king"
ACTIVITY = KOTLIN / "MainActivity.kt"
MANIFEST = MAIN / "AndroidManifest.xml"
TEMPLATE = Path(__file__).resolve().with_name("local_recording")

def add_once(text, anchor, new):
    if new in text:
        return text
    if text.count(anchor) != 1:
        raise ValueError(f"Ancre inattendue dans le checkout NovaTube : {anchor!r}")
    return text.replace(anchor, new, 1)

def main():
    # Un build TV ordinaire réutilise le même MainActivity. Ce script est appelé
    # explicitement par la construction LAB, sans changer l'activité des autres éditions.
    target = KOTLIN / "novatube"
    target.mkdir(parents=True, exist_ok=True)
    for name in ("GalleryExporter.kt", "GalleryExportPolicy.kt"):
        shutil.copyfile(TEMPLATE / name, target / name)

    activity = ACTIVITY.read_text()
    anchor = "    private var pipChannel: MethodChannel? = null"
    activity = add_once(activity, anchor, anchor + "\n    private var gallery: com.example.tv_king.novatube.GalleryExporter? = null")
    anchor = "        super.configureFlutterEngine(flutterEngine)"
    activity = add_once(activity, anchor, anchor + """
        gallery = com.example.tv_king.novatube.GalleryExporter(
            flutterEngine.dartExecutor.binaryMessenger, applicationContext, this,
        )""")
    anchor = "        super.cleanUpFlutterEngine(flutterEngine)"
    activity = add_once(activity, anchor, "        gallery?.detach()\n        gallery = null\n" + anchor)
    anchor = "    override fun dispatchKeyEvent(event: KeyEvent): Boolean {"
    activity = add_once(activity, anchor, """    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        gallery?.onRequestPermissionsResult(requestCode, grantResults)
    }

""" + anchor)
    ACTIVITY.write_text(activity)

    manifest = MANIFEST.read_text()
    anchor = "    <application"
    # open_filex déclare déjà la permission de lecture requise sur les anciens Android.
    permission = '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />'
    manifest = add_once(manifest, anchor, permission + "\n" + anchor)
    MANIFEST.write_text(manifest)

if __name__ == "__main__":
    main()

