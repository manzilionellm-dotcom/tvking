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
# Flutter génère maintenant `build.gradle.kts` (Kotlin DSL) au lieu de
# l'ancien `build.gradle` (Groovy). Détecté empiriquement au run #67.
BUILD_GRADLE="android/app/build.gradle.kts"
BUILD_GRADLE_GROOVY="android/app/build.gradle"
OVERLAY="android_overlay/google_cast"

echo "============================================="
echo "  Cast SDK overlay — diagnostic"
echo "============================================="
echo "Working dir: $(pwd)"
echo "Files in overlay:"
ls -la "$OVERLAY/"

# --- Sanity checks --------------------------------
# Détecte si on est en Kotlin DSL (.kts) ou Groovy (.gradle).
# Les Flutter récents utilisent .kts ; les anciens .gradle.
if [ ! -f "$BUILD_GRADLE" ]; then
  if [ -f "$BUILD_GRADLE_GROOVY" ]; then
    echo "Found Groovy build.gradle — using it"
    BUILD_GRADLE="$BUILD_GRADLE_GROOVY"
    BUILD_GRADLE_IS_KTS="false"
  else
    echo "❌ Ni $BUILD_GRADLE ni $BUILD_GRADLE_GROOVY — flutter create a foiré ?"
    ls -la android/app/ || true
    exit 1
  fi
else
  BUILD_GRADLE_IS_KTS="true"
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
cp -v "$OVERLAY/MainActivity.kt"               "$ANDROID_PKG_PATH/MainActivity.kt"
cp -v "$OVERLAY/GoogleCastApi.kt"              "$ANDROID_PKG_PATH/GoogleCastApi.kt"
cp -v "$OVERLAY/CastOptionsProviderImpl.kt"    "$ANDROID_PKG_PATH/CastOptionsProviderImpl.kt"
cp -v "$OVERLAY/GalleryExporter.kt"            "$ANDROID_PKG_PATH/GalleryExporter.kt"
cp -v "$OVERLAY/RecordingForegroundService.kt" "$ANDROID_PKG_PATH/RecordingForegroundService.kt"
cp -v "$OVERLAY/RecordingServiceBridge.kt"     "$ANDROID_PKG_PATH/RecordingServiceBridge.kt"

ls -la "$ANDROID_PKG_PATH/"

# --- 2. Patch build.gradle (dependencies) -----------
if grep -q "play-services-cast-framework" "$BUILD_GRADLE"; then
  echo "Cast deps déjà présentes dans $BUILD_GRADLE — skip"
else
  # Append un NOUVEAU bloc dependencies à la fin du fichier.
  # Gradle accepte les blocs dependencies multiples — il fusionne.
  # Syntaxe différente selon Kotlin DSL ou Groovy.
  if [ "$BUILD_GRADLE_IS_KTS" = "true" ]; then
    cat >> "$BUILD_GRADLE" <<'KTS_EOF'

// === Cast SDK overlay ===
// Dépendances Google Cast Framework + AndroidX MediaRouter
// ajoutées par apply_cast_patch.sh APRÈS `flutter create`.
// Syntaxe Kotlin DSL : implementation("...") avec parenthèses.
dependencies {
    implementation("com.google.android.gms:play-services-cast-framework:21.5.0")
    implementation("androidx.mediarouter:mediarouter:1.6.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.fragment:fragment:1.6.2")
}
KTS_EOF
  else
    cat >> "$BUILD_GRADLE" <<'GROOVY_EOF'

// === Cast SDK overlay ===
dependencies {
    implementation 'com.google.android.gms:play-services-cast-framework:21.5.0'
    implementation 'androidx.mediarouter:mediarouter:1.6.0'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'androidx.fragment:fragment:1.6.2'
}
GROOVY_EOF
  fi
  echo "✅ Patched $BUILD_GRADLE"
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
  echo "✅ Patched AndroidManifest (Cast)"
fi

# --- 3b. Patch AndroidManifest pour RecordingForegroundService ---
# Permissions + déclaration du service. Idempotent.
if grep -q "RecordingForegroundService" "$MANIFEST"; then
  echo "Service Recording déjà déclaré — skip"
else
  # Permissions juste après <manifest ...>  (avant <application>).
  # FOREGROUND_SERVICE + WAKE_LOCK requis dès Android 9.
  # FOREGROUND_SERVICE_MEDIA_PLAYBACK requis depuis Android 14 pour
  # spécifier le type "mediaPlayback".
  # POST_NOTIFICATIONS requis depuis Android 13 pour afficher la
  # notification du foreground service.
  PERMS='    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.WAKE_LOCK" />\n    <uses-permission android:name="android.permission.USE_BIOMETRIC" />'
  sed -i "s|<application|${PERMS}\n\n    <application|" "$MANIFEST"

  # Déclaration du service avant </application>.
  SVC='        <service android:name=".RecordingForegroundService" android:foregroundServiceType="mediaPlayback" android:exported="false" />'
  sed -i "s|</application>|${SVC}\n    </application>|" "$MANIFEST"
  echo "✅ Patched AndroidManifest (Service + permissions)"
fi

echo "----- AFTER: build.gradle (last 30 lines) -----"
tail -30 "$BUILD_GRADLE"
echo "----- AFTER: AndroidManifest.xml -----"
cat "$MANIFEST"

echo "============================================="
echo "  ✅ Cast SDK overlay applied"
echo "============================================="
