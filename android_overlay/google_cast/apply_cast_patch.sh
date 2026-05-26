#!/usr/bin/env bash
# =========================================================
#  apply_cast_patch.sh — Active le Google Cast SDK natif
# =========================================================
#  Voir le commit "Cast 2/5" pour la description complète.
#  Cette version est ROBUSTE :
#    - `set -e` (fail on error) mais PAS `set -u` (variables unset
#      tolérées — sinon `cp -v` peut crasher si une var manque).
#    - `set -x` (trace commands) → chaque commande visible dans les
#      logs CI, pour diagnostiquer immédiatement quelle étape foire.
#    - Patches via sed pur (pas de python inline qui peut crasher
#      sur un regex inattendu).
#    - Vérif explicite du résultat après chaque patch.
# =========================================================

set -ex

ANDROID_PKG_PATH="android/app/src/main/kotlin/com/manzilionellm/tvking"
MANIFEST="android/app/src/main/AndroidManifest.xml"
BUILD_GRADLE="android/app/build.gradle"
OVERLAY="android_overlay/google_cast"

echo "============================================="
echo "  Cast SDK overlay — diagnostic"
echo "============================================="
echo "Working dir: $(pwd)"
echo "Files in overlay:"
ls -la "$OVERLAY/"

# --- Sanity checks --------------------------------
if [ ! -f "$BUILD_GRADLE" ]; then
  echo "❌ $BUILD_GRADLE introuvable — flutter create a foiré ?"
  ls -la android/app/ || true
  exit 1
fi
if [ ! -f "$MANIFEST" ]; then
  echo "❌ $MANIFEST introuvable"
  ls -la android/app/src/main/ || true
  exit 1
fi

echo "----- BEFORE: build.gradle (last 30 lines) -----"
tail -30 "$BUILD_GRADLE"
echo "----- BEFORE: AndroidManifest.xml -----"
cat "$MANIFEST"

# --- 1. Copy Kotlin files ---------------------------
mkdir -p "$ANDROID_PKG_PATH"
cp -v "$OVERLAY/MainActivity.kt"            "$ANDROID_PKG_PATH/MainActivity.kt"
cp -v "$OVERLAY/GoogleCastApi.kt"           "$ANDROID_PKG_PATH/GoogleCastApi.kt"
cp -v "$OVERLAY/CastOptionsProviderImpl.kt" "$ANDROID_PKG_PATH/CastOptionsProviderImpl.kt"

ls -la "$ANDROID_PKG_PATH/"

# --- 2. Patch build.gradle (dependencies) -----------
if grep -q "play-services-cast-framework" "$BUILD_GRADLE"; then
  echo "Cast deps déjà présentes dans $BUILD_GRADLE — skip"
else
  # Insère les deps Cast SDK juste avant la dernière `}` du fichier.
  # Approche bête mais sûre : on append un NOUVEAU bloc dependencies
  # à la fin du fichier. Gradle accepte les blocs dependencies multiples
  # — il les fusionne.
  cat >> "$BUILD_GRADLE" <<'GRADLE_EOF'

// === Cast SDK overlay ===
// Dépendances Google Cast Framework + AndroidX MediaRouter
// ajoutées par apply_cast_patch.sh APRÈS `flutter create`.
dependencies {
    implementation 'com.google.android.gms:play-services-cast-framework:21.5.0'
    implementation 'androidx.mediarouter:mediarouter:1.6.0'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'androidx.fragment:fragment:1.6.2'
}
GRADLE_EOF
  echo "✅ Patched build.gradle"
fi

# --- 3. Patch AndroidManifest.xml (OPTIONS_PROVIDER) -
if grep -q "OPTIONS_PROVIDER_CLASS_NAME" "$MANIFEST"; then
  echo "Cast OPTIONS_PROVIDER déjà présent — skip"
else
  # Insère la meta-data Cast juste avant </application>.
  # Sed simple, pas de regex complexe.
  META='        <meta-data android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME" android:value="com.manzilionellm.tvking.CastOptionsProviderImpl" />'
  # Le `&` dans META serait interprété par sed — on utilise un délimiteur
  # alternatif `|` et on échappe rien (notre string n'a pas de `|`).
  sed -i "s|</application>|${META}\n    </application>|" "$MANIFEST"
  echo "✅ Patched AndroidManifest"
fi

echo "----- AFTER: build.gradle (last 30 lines) -----"
tail -30 "$BUILD_GRADLE"
echo "----- AFTER: AndroidManifest.xml -----"
cat "$MANIFEST"

echo "============================================="
echo "  ✅ Cast SDK overlay applied"
echo "============================================="
