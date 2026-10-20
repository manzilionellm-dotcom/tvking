#!/usr/bin/env python3
"""Prépare uniquement l'APK tactile ZUNO de test, dans le checkout de CI.

Le manifeste et Gradle sont propres à ce build. L'activité TV versionnée
reste intacte : on crée une autre activité, puis on la désigne au lanceur.
Les ponts Google Cast sont ceux de 7 MOTION, avec les mêmes dépendances ;
seuls le nom de classe et le relais de cycle de vie ZUNO sont adaptés.
Aucune clé client, aucun canal de publication n'entre dans cette préparation.
"""
import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
TEST_PACKAGE = "com.sevenmotion.tv.seven_tv.casttest"
TEST_LABEL = "Zuno Cast test"
NATIVE_FILES = (
    "GoogleCastApi.kt", "CastOptionsProviderImpl.kt", "GalleryExporter.kt",
    "RecordingForegroundService.kt", "RecordingServiceBridge.kt",
    "MulticastLockBridge.kt", "PlaybackForegroundService.kt",
)
PERMISSIONS = (
    "INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE",
    "CHANGE_WIFI_MULTICAST_STATE", "FOREGROUND_SERVICE",
    "FOREGROUND_SERVICE_MEDIA_PLAYBACK", "POST_NOTIFICATIONS", "WAKE_LOCK",
    "USE_BIOMETRIC",
)


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise ValueError(f"Structure native inattendue : {before!r}")
    return text.replace(before, after, 1)


def touch_activity(source, namespace):
    """Conserve les ponts existants et ajoute les cinq rappels du lecteur ZUNO.

    Une modification future des callbacks de l'overlay arrête le build :
    on ne doit ni doubler une méthode Kotlin ni oublier un arrêt natif.
    """
    source = replace_once(source, "package com.manzilionellm.tvking",
                          f"package {namespace}")
    source = replace_once(source, "class MainActivity : FlutterFragmentActivity()",
                          "class ZunoCastActivity : FlutterFragmentActivity()")
    source = replace_once(
        source, "import io.flutter.embedding.engine.FlutterEngine",
        "import io.flutter.embedding.engine.FlutterEngine\n"
        "import com.manzilionellm.native_video_player.logic.AppForeground",
    )
    source = replace_once(
        source, "override fun onUserLeaveHint() {\n",
        "override fun onUserLeaveHint() {\n"
        "        AppForeground.onUserLeaveHint()\n",
    )
    for method in ("onPause", "onStop", "onResume", "onWindowFocusChanged"):
        if f"override fun {method}(" in source:
            raise ValueError(f"Relire le cycle de vie de l'overlay : {method}")
    callbacks = """

    // Le lecteur natif doit recevoir le même cycle Android que dans ZUNO TV.
    // La garde Cast du lecteur décide ensuite si une reprise locale est permise.
    override fun onPause() {
        AppForeground.onPause()
        super.onPause()
    }

    override fun onStop() {
        AppForeground.onStop()
        super.onStop()
    }

    override fun onResume() {
        AppForeground.onResume()
        super.onResume()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        AppForeground.onWindowFocus(hasFocus)
    }
"""
    if not source.rstrip().endswith("\n}"):
        raise ValueError("Fin de classe de l'overlay inattendue")
    return source.rstrip()[:-2] + callbacks + "}\n"


def mobile_manifest(source, namespace):
    ET.register_namespace("android", ANDROID[1:-1])
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    root = ET.fromstring(source, parser=parser)
    app = root.find("application")
    if app is None:
        raise ValueError("Application Android absente")
    activity = app.find("activity")
    if activity is None or activity.get(ANDROID + "name") not in (
        ".MainActivity", f"{namespace}.MainActivity", f"{namespace}.ZunoCastActivity",
    ):
        raise ValueError("Activité de départ inattendue")

    app.set(ANDROID + "label", TEST_LABEL)
    app.set(ANDROID + "usesCleartextTraffic", "true")
    app.set(ANDROID + "allowBackup", "false")
    app.attrib.pop(ANDROID + "banner", None)
    activity.set(ANDROID + "name", f"{namespace}.ZunoCastActivity")
    activity.set(ANDROID + "supportsPictureInPicture", "true")
    activity.set(ANDROID + "resizeableActivity", "true")
    activity.attrib.pop(ANDROID + "screenOrientation", None)

    # Un APK tactile s'ouvre dans le lanceur téléphone/tablette. La variante
    # TV garde son propre manifeste ; aucun lanceur Leanback ici.
    for feature in list(root.findall("uses-feature")):
        if "leanback" in feature.get(ANDROID + "name", ""):
            root.remove(feature)
    for intent in activity.findall("intent-filter"):
        for category in list(intent.findall("category")):
            if category.get(ANDROID + "name") == "android.intent.category.LEANBACK_LAUNCHER":
                intent.remove(category)
    launcher = activity.find("intent-filter")
    if launcher is None:
        raise ValueError("Intent du lanceur Android absent")
    if not any(c.get(ANDROID + "name") == "android.intent.category.LAUNCHER"
               for c in launcher.findall("category")):
        ET.SubElement(launcher, "category", {ANDROID + "name": "android.intent.category.LAUNCHER"})

    declared = {p.get(ANDROID + "name") for p in root.findall("uses-permission")}
    for permission in PERMISSIONS:
        name = "android.permission." + permission
        if name not in declared:
            ET.SubElement(root, "uses-permission", {ANDROID + "name": name})
    metadata_name = "com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"
    if not any(m.get(ANDROID + "name") == metadata_name for m in app.findall("meta-data")):
        ET.SubElement(app, "meta-data", {
            ANDROID + "name": metadata_name,
            ANDROID + "value": f"{namespace}.CastOptionsProviderImpl",
        })
    for name in ("RecordingForegroundService", "PlaybackForegroundService"):
        fqcn = f"{namespace}.{name}"
        if not any(s.get(ANDROID + "name") == fqcn for s in app.findall("service")):
            ET.SubElement(app, "service", {
                ANDROID + "name": fqcn,
                ANDROID + "foregroundServiceType": "mediaPlayback",
                ANDROID + "exported": "false",
            })
    ET.indent(root, space="    ")
    return ET.tostring(root, encoding="unicode") + "\n"


def test_gradle(source, overlay_script):
    # Refuse un checkout déjà préparé avec les clés d'une version client.
    if "key.properties" in source or 'getByName("release")' in source:
        raise ValueError("Ce script exige le Gradle de base, sans signature client")
    source, count = re.subn(r'applicationId\s*=\s*"[^"]+"',
                            f'applicationId = "{TEST_PACKAGE}"', source, count=1)
    if count != 1:
        raise ValueError("applicationId absent")
    source, count = re.subn(r"minSdk\s*=\s*(flutter\.minSdkVersion|24)",
                            "minSdk = 24", source, count=1)
    if count != 1:
        raise ValueError("minSdk de base absent")
    if 'signingConfig = signingConfigs.getByName("debug")' not in source:
        raise ValueError("La signature de débogage attendue est absente")
    if "// ZUNO CAST TEST" not in source:
        # Réutilise les versions fixées dans le vrai overlay 7 MOTION,
        # sans maintenir un deuxième jeu de versions de SDK indépendant.
        dependencies = re.findall(r'^\s*implementation\("([^"]+)"\)', overlay_script, re.M)
        if len(dependencies) != 4 or not any("play-services-cast-framework:" in d for d in dependencies):
            raise ValueError("Relire les dépendances Google Cast de l'overlay")
        source += '\n// ZUNO CAST TEST — ajouté uniquement dans le checkout du build tactile.\n'
        source += 'android { packaging { jniLibs { pickFirsts.add("**/libc++_shared.so") } } }\n'
        source += "dependencies {\n"
        source += "".join(f'    implementation("{dep}")\n' for dep in dependencies)
        source += "}\n"
    return source


def prepare(app_dir):
    app_dir = Path(app_dir)
    if (app_dir / "android/key.properties").exists():
        raise ValueError("Un build Cast de test n'utilise aucun key.properties client")
    gradle_path = app_dir / "android/app/build.gradle.kts"
    gradle = gradle_path.read_text(encoding="utf-8")
    namespace_match = re.search(r'namespace\s*=\s*"([\w.]+)"', gradle)
    if not namespace_match:
        raise ValueError("namespace Android absent")
    namespace = namespace_match.group(1)
    kotlin_dir = app_dir / "android/app/src/main/kotlin" / namespace.replace(".", "/")
    tv_activity = kotlin_dir / "MainActivity.kt"
    tv_before = tv_activity.read_bytes()
    if b"AppForeground.onStop()" not in tv_before:
        raise ValueError("Le garde-fou du lecteur TV de base est absent")
    overlay = app_dir / "android_overlay/google_cast"
    manifest_path = app_dir / "android/app/src/main/AndroidManifest.xml"
    # Tout valider avant d'écrire un fichier de compilation.
    writes = {
        gradle_path: test_gradle(gradle, (overlay / "apply_cast_patch.sh").read_text(encoding="utf-8")),
        manifest_path: mobile_manifest(manifest_path.read_text(encoding="utf-8"), namespace),
        kotlin_dir / "ZunoCastActivity.kt": touch_activity((overlay / "MainActivity.kt").read_text(encoding="utf-8"), namespace),
    }
    for name in NATIVE_FILES:
        writes[kotlin_dir / name] = replace_once(
            (overlay / name).read_text(encoding="utf-8"),
            "package com.manzilionellm.tvking", f"package {namespace}",
        )
    for path, text in writes.items():
        path.write_text(text, encoding="utf-8")
    if tv_activity.read_bytes() != tv_before:
        raise RuntimeError("L'activité TV ne doit jamais être réécrite")
    return namespace


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-dir", type=Path, default=Path.cwd())
    args = parser.parse_args()
    namespace = prepare(args.app_dir)
    print(f"APK tactile de test : {TEST_PACKAGE} · {namespace}.ZunoCastActivity · activité TV préservée")
