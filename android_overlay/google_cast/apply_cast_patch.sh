#!/usr/bin/env bash
# =========================================================
#  apply_cast_patch.sh — Active le Google Cast SDK natif
# =========================================================
#  Exécuté par le workflow CI APRÈS `flutter create` qui régénère
#  le dossier `android/`. Le script :
#
#    1. Copie MainActivity.kt + GoogleCastApi.kt + CastOptionsProviderImpl.kt
#       depuis android_overlay/ vers le package Android généré.
#       (overwrite la MainActivity par défaut qui est juste un
#        `class MainActivity: FlutterActivity()`)
#
#    2. Patche `android/app/build.gradle` pour ajouter les dépendances
#       Google Cast Framework + AndroidX MediaRouter + AppCompat
#       + Fragment (requis par MediaRouteChooserDialog).
#
#    3. Patche `android/app/src/main/AndroidManifest.xml` pour ajouter
#       la `<meta-data>` qui dit au Cast SDK où trouver notre
#       `CastOptionsProviderImpl`.
#
#  Le script est IDEMPOTENT — si un patch a déjà été appliqué
#  (cas du rebuild d'un même run), il skip.
# =========================================================

set -euo pipefail

ANDROID_PKG_PATH="android/app/src/main/kotlin/com/manzilionellm/tvking"
MANIFEST="android/app/src/main/AndroidManifest.xml"
BUILD_GRADLE="android/app/build.gradle"
OVERLAY="android_overlay/google_cast"

echo "== Cast SDK overlay =="

# --- 1. Copy Kotlin files ---------------------------------
mkdir -p "$ANDROID_PKG_PATH"
cp -v "$OVERLAY/MainActivity.kt"            "$ANDROID_PKG_PATH/"
cp -v "$OVERLAY/GoogleCastApi.kt"           "$ANDROID_PKG_PATH/"
cp -v "$OVERLAY/CastOptionsProviderImpl.kt" "$ANDROID_PKG_PATH/"

# --- 2. Patch build.gradle (dependencies) -----------------
if [ ! -f "$BUILD_GRADLE" ]; then
  echo "❌ $BUILD_GRADLE introuvable"
  exit 1
fi

if grep -q "play-services-cast-framework" "$BUILD_GRADLE"; then
  echo "Cast dependencies déjà présentes dans $BUILD_GRADLE — skip"
else
  python3 - "$BUILD_GRADLE" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

deps_block = (
    "\n    implementation 'com.google.android.gms:play-services-cast-framework:21.5.0'"
    "\n    implementation 'androidx.mediarouter:mediarouter:1.6.0'"
    "\n    implementation 'androidx.appcompat:appcompat:1.7.0'"
    "\n    implementation 'androidx.fragment:fragment:1.6.2'\n"
)

# Cherche le bloc `dependencies { ... }`. On insère deps_block juste
# avant la closing brace. Si pas de bloc existant, on en crée un.
match = re.search(r"(dependencies\s*\{)([^}]*?)(\})", content, flags=re.DOTALL)
if match:
    new_content = content[:match.end(2)] + deps_block + content[match.end(2):]
else:
    new_content = content.rstrip() + "\n\ndependencies {" + deps_block + "}\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
print("Patched build.gradle with Cast dependencies")
PY
fi

# --- 3. Patch AndroidManifest.xml (OPTIONS_PROVIDER) ------
if [ ! -f "$MANIFEST" ]; then
  echo "❌ $MANIFEST introuvable"
  exit 1
fi

if grep -q "OPTIONS_PROVIDER_CLASS_NAME" "$MANIFEST"; then
  echo "Cast OPTIONS_PROVIDER déjà présent dans $MANIFEST — skip"
else
  # Insère le bloc meta-data avant </application>
  python3 - "$MANIFEST" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

meta = (
    '        <meta-data\n'
    '            android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME"\n'
    '            android:value="com.manzilionellm.tvking.CastOptionsProviderImpl" />\n'
)

# Insère juste avant </application>
new_content = content.replace("</application>", meta + "    </application>", 1)
if new_content == content:
    print("⚠ </application> introuvable — manifest non patché")
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
print("Patched AndroidManifest with OPTIONS_PROVIDER_CLASS_NAME")
PY
fi

echo "✅ Cast SDK overlay applied"
