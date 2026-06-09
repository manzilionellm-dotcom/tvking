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

MANIFEST="android/app/src/main/AndroidManifest.xml"
# Flutter génère maintenant `build.gradle.kts` (Kotlin DSL) au lieu de
# l'ancien `build.gradle` (Groovy). Détecté empiriquement au run #67.
BUILD_GRADLE="android/app/build.gradle.kts"
BUILD_GRADLE_GROOVY="android/app/build.gradle"
OVERLAY="android_overlay/google_cast"

# Détection DYNAMIQUE du package Java/Kotlin que flutter create a
# choisi. Avec `--org com.manzilionellm.tvking --project-name tv_king`,
# Flutter peut générer SOIT `com.manzilionellm.tvking` SOIT
# `com.manzilionellm.tvking.tv_king` selon la version. Sans détection,
# le MainActivity custom de mon overlay n'est PAS la classe que le
# manifest référence → mes MethodChannel ne sont jamais câblés au
# runtime → MissingPluginException "Bridge natif manquant".
#
# On lit le `package ...;` du MainActivity généré par Flutter et on
# l'utilise pour :
#   1. Copier les .kt overlay AU MÊME endroit (overwrite le default)
#   2. Réécrire la déclaration `package ...` dans nos .kt
#   3. Référencer le bon FQCN dans le manifest meta-data Cast
echo "============================================="
echo "  Détection du package Flutter généré"
echo "============================================="
FLUTTER_MAIN=$(find android/app/src/main/kotlin -name "MainActivity.kt" 2>/dev/null | head -1)
if [ -z "$FLUTTER_MAIN" ]; then
  echo "❌ MainActivity.kt non trouvé après flutter create"
  echo "Structure de android/app/src/main/ :"
  find android/app/src/main -type f 2>/dev/null | head -20
  exit 1
fi
echo "MainActivity trouvé : $FLUTTER_MAIN"
DETECTED_PKG=$(grep -m1 "^package " "$FLUTTER_MAIN" | sed -E 's/^package +([^;]+);?\s*$/\1/' | tr -d '[:space:]')
if [ -z "$DETECTED_PKG" ]; then
  echo "❌ Impossible de lire le package depuis $FLUTTER_MAIN"
  head -5 "$FLUTTER_MAIN"
  exit 1
fi
echo "Package détecté : $DETECTED_PKG"
ANDROID_PKG_PATH=$(dirname "$FLUTTER_MAIN")
echo "Path d'installation : $ANDROID_PKG_PATH"

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

# --- 1. Copy Kotlin files avec PACKAGE corrigé -----
# On copie chaque .kt overlay au path détecté, en RÉÉCRIVANT la
# déclaration `package com.manzilionellm.tvking` par le package réel
# détecté ($DETECTED_PKG). Sans ça, les classes sont chargées mais ne
# matchent pas la référence du manifest → mes MethodChannel handlers
# ne sont jamais bound.
mkdir -p "$ANDROID_PKG_PATH"
for kt_file in MainActivity.kt GoogleCastApi.kt CastOptionsProviderImpl.kt \
               GalleryExporter.kt RecordingForegroundService.kt \
               RecordingServiceBridge.kt MulticastLockBridge.kt \
               NativeHttpBridge.kt; do
  src="$OVERLAY/$kt_file"
  dst="$ANDROID_PKG_PATH/$kt_file"
  # sed rewrite : `package com.manzilionellm.tvking` → `package $DETECTED_PKG`
  sed "s|^package com\.manzilionellm\.tvking\$|package $DETECTED_PKG|" "$src" > "$dst"
  echo "  ✓ $kt_file → $dst (package: $DETECTED_PKG)"
done

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
  # Le FQCN référence le package DÉTECTÉ (pas en dur com.manzilionellm.tvking)
  # pour matcher où Flutter create a réellement mis les classes.
  META="        <meta-data android:name=\"com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME\" android:value=\"${DETECTED_PKG}.CastOptionsProviderImpl\" />"
  sed -i "s|</application>|${META}\n    </application>|" "$MANIFEST"
  echo "✅ Patched AndroidManifest (Cast → ${DETECTED_PKG}.CastOptionsProviderImpl)"
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
  # ACCESS_WIFI_STATE = requis pour `WifiManager.createWifiLock()`,
  # qu'on utilise dans RecordingForegroundService pour empêcher
  # Android de mettre le WiFi en sommeil pendant l'enregistrement
  # quand l'écran s'éteint. Sans ce lock, en ~30 s d'inactivité,
  # le WiFi peut se mettre en mode économie et tuer la socket HTTP
  # du downloader → enregistrement arrêté après ~30 s en background.
  PERMS='    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.WAKE_LOCK" />\n    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />\n    <uses-permission android:name="android.permission.USE_BIOMETRIC" />'
  sed -i "s|<application|${PERMS}\n\n    <application|" "$MANIFEST"

  # Déclaration du service avant </application>.
  # `android:name=".RecordingForegroundService"` est relatif au package
  # racine de l'application (déclaré dans <manifest package="..."> ou
  # dans <namespace> du build.gradle). Donc ça marche quel que soit
  # le package détecté.
  SVC='        <service android:name=".RecordingForegroundService" android:foregroundServiceType="mediaPlayback" android:exported="false" />'
  sed -i "s|</application>|${SVC}\n    </application>|" "$MANIFEST"
  echo "✅ Patched AndroidManifest (Service + permissions)"
fi

# --- 3c. Permissions DÉCOUVERTE RÉSEAU (Cast / DLNA) ----------------
# Bloc INDÉPENDANT et idempotent (clé : CHANGE_WIFI_MULTICAST_STATE).
# C'EST LE CORRECTIF du "le cast ne trouve aucune TV" :
#
#   - CHANGE_WIFI_MULTICAST_STATE : OBLIGATOIRE pour que
#     WifiManager.MulticastLock fonctionne. Sans elle, mDNS
#     (multicast_dns → 224.0.0.251, service _googlecast._tcp) et
#     SSDP (239.255.255.250, DLNA) n'obtiennent jamais les réponses
#     des récepteurs → picker vide → aucun cast possible.
#   - ACCESS_NETWORK_STATE : exigée par le Cast Framework et par
#     notre détection de connectivité (relais HLS local).
#   - INTERNET : présente dans le manifest debug généré par Flutter,
#     mais ABSENTE du manifest "main" → manquerait en build release.
#     On la déclare explicitement pour être robustes quel que soit
#     le type de build.
#
# `flutter create` ne déclare AUCUNE de ces 3 dans le manifest main ;
# le bloc 3b n'ajoute qu'ACCESS_WIFI_STATE. On comble le trou ici.
if grep -q "CHANGE_WIFI_MULTICAST_STATE" "$MANIFEST"; then
  echo "Permissions découverte réseau déjà présentes — skip"
else
  NET_PERMS='    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />\n    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />'
  sed -i "s|<application|${NET_PERMS}\n\n    <application|" "$MANIFEST"
  echo "✅ Patched AndroidManifest (INTERNET + ACCESS_NETWORK_STATE + CHANGE_WIFI_MULTICAST_STATE)"
fi

echo "----- AFTER: build.gradle (last 30 lines) -----"
tail -30 "$BUILD_GRADLE"
echo "----- AFTER: AndroidManifest.xml -----"
cat "$MANIFEST"

echo "============================================="
echo "  ✅ Cast SDK overlay applied"
echo "============================================="
