#!/usr/bin/env python3
# =========================================================
#  patch_gradle.py — build.gradle.kts du build Zuno TV
# =========================================================
#  Appelé par le workflow racine `.github/workflows/build-zuno-tv.yml` :
#
#      python3 ci/tv/patch_gradle.py android/app/build.gradle.kts
#
#  Même philosophie que patch_manifest.py : `android/` est versionné et
#  partagé avec le téléphone, donc les réglages propres à l'APK TV sont
#  appliqués au moment du build, de façon idempotente et commentée.
#
#  Ce qu'il fait :
#    1. applicationId `com.sevenmotion.tv.seven_tv` — l'IDENTITÉ HISTORIQUE
#       de « 7 MOTION TV » (canal seventv-latest / lien /7tv). En gardant
#       le même package ET la même clé de signature, les box qui ont déjà
#       l'app la mettent à jour PAR-DESSUS (favoris/activation conservés)
#       au lieu de voir « Application non installée ». Le `namespace`
#       (chemin Kotlin/R) n'est PAS touché.
#    2. Signature : lit `android/key.properties` (écrit par le workflow
#       depuis les secrets GitHub) → signingConfig « release » avec la clé
#       maîtresse 7 MOTION. Sans key.properties, repli sur la config
#       « debug » — que le workflow remplace par le keystore FIXE du projet
#       (jamais la clé jetable du runner). Dans les deux cas : signatures
#       v1 + v2 + v3 (les box < Android 7 ne savent vérifier que la v1).
#    3. R8 + shrinkResources (APK plus léger) avec les règles keep du
#       projet (ci/proguard-rules.pro, copié par le workflow).
#    4. `pickFirst **/libc++_shared.so` : media_kit ET d'autres plugins
#       embarquent la même lib → conflit de packaging sans cette ligne.
#    5. minSdk 21 (Android 5) — COMPATIBILITÉ TOUTES BOX (26/09/2026).
#       Flutter ≥ 3.35 impose Android 7 par défaut ; les box Android 5/6
#       (vieilles MXQ, Fire TV Stick Fire OS 5…) affichaient alors « App non
#       installée ». Le moteur Flutter embarqué est TOUJOURS compilé pour
#       l'API 21 (vérifié dans libflutter.so : .note.android.ident = 21) :
#       la limite est une règle de l'outil, pas du binaire. On passe par une
#       variable (`kBoxMinSdk`) car l'outil Flutter réécrit à la volée tout
#       `minSdk = 16…23` littéral ; le build ajoute
#       --android-skip-build-dependency-validation, et le manifeste déclare
#       tools:overrideLibrary pour les 4 plugins qui annoncent 24.
# =========================================================
import re
import sys

TV_APPLICATION_ID = "com.sevenmotion.tv.seven_tv"

LOADER = (
    "import java.util.Properties\n"
    "import java.io.FileInputStream\n\n"
)

KEYSTORE_BLOCK = (
    "val keystoreProperties = Properties()\n"
    'val keystorePropertiesFile = rootProject.file("key.properties")\n'
    "if (keystorePropertiesFile.exists()) {\n"
    "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
    "}\n\n"
)

SIGNING_BLOCK = (
    "android {\n"
    '    packaging { jniLibs { pickFirsts.add("**/libc++_shared.so") } }\n'
    "    signingConfigs {\n"
    '        getByName("debug") {\n'
    "            enableV1Signing = true\n"
    "            enableV2Signing = true\n"
    "            enableV3Signing = true\n"
    "        }\n"
    '        create("release") {\n'
    '            val sf = keystoreProperties.getProperty("storeFile")\n'
    "            if (sf != null) {\n"
    "                storeFile = file(sf)\n"
    '                storePassword = keystoreProperties.getProperty("storePassword")\n'
    '                keyAlias = keystoreProperties.getProperty("keyAlias")\n'
    '                keyPassword = keystoreProperties.getProperty("keyPassword")\n'
    "            }\n"
    "            enableV1Signing = true\n"
    "            enableV2Signing = true\n"
    "            enableV3Signing = true\n"
    "        }\n"
    "    }"
)

RELEASE_BLOCK = (
    "release {\n"
    "            isMinifyEnabled = true\n"
    "            isShrinkResources = true\n"
    '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")\n'
    "            signingConfig = if (keystorePropertiesFile.exists()) "
    'signingConfigs.getByName("release") else signingConfigs.getByName("debug")'
)


def patch(s: str) -> str:
    # --- 1. applicationId TV ---
    s, n = re.subn(
        r'applicationId\s*=\s*"[^"]+"',
        f'applicationId = "{TV_APPLICATION_ID}"',
        s,
        count=1,
    )
    if n == 0:
        raise SystemExit("❌ applicationId introuvable dans build.gradle.kts")

    # --- 2. Signature (idempotent : on ne réinjecte pas si déjà là) ---
    if 'create("release")' not in s:
        if "import java.util.Properties" not in s:
            s = LOADER + s
        s = s.replace("android {", KEYSTORE_BLOCK + SIGNING_BLOCK, 1)

    # --- 3. R8 + choix de la signature sur le buildType release ---
    if "isMinifyEnabled" not in s:
        # Le template Flutter écrit :
        #   release {
        #       // commentaires…
        #       signingConfig = signingConfigs.getByName("debug")
        #   }
        # On remplace tout le bloc jusqu'à la ligne signingConfig incluse.
        s, n = re.subn(
            r'release \{[^}]*?signingConfig = signingConfigs\.getByName\("debug"\)',
            RELEASE_BLOCK,
            s,
            count=1,
            flags=re.S,
        )
        if n == 0:
            raise SystemExit("❌ bloc buildTypes.release introuvable dans build.gradle.kts")
    # --- 4. minSdk 21 (voir en-tête, point 5) ---
    if "kBoxMinSdk" not in s:
        s, n = re.subn(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = kBoxMinSdk", s, count=1)
        if n == 0:
            raise SystemExit("❌ minSdk = flutter.minSdkVersion introuvable dans build.gradle.kts")
        # Déclaration APRÈS les `import` (Kotlin exige les imports en tête de
        # script) : juste avant le 1er bloc de code de niveau racine
        # (`val keystoreProperties…` injecté plus haut, sinon `android {`).
        decl = "// Compatibilité toutes box (Android 5+) — cf. ci/tv/patch_gradle.py\nval kBoxMinSdk = 21\n\n"
        anchor = "val keystoreProperties" if "val keystoreProperties" in s else "android {"
        s = s.replace(anchor, decl + anchor, 1)
    return s


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_gradle.py <build.gradle.kts>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        s = f.read()
    s = patch(s)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
    for must in (TV_APPLICATION_ID, "enableV1Signing", "isMinifyEnabled", "pickFirsts", "minSdk = kBoxMinSdk"):
        if must not in s:
            print("❌ build.gradle.kts TV incomplet, manque :", must, file=sys.stderr)
            return 1
    print("✓ build.gradle.kts Zuno TV patché :", path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
