#!/usr/bin/env bash
# =========================================================
#  patch_info_plist.sh — Config iOS de l'app IPTV 7 MOTION
# =========================================================
#  Le dossier ios/ est GÉNÉRÉ à la volée par le CI (jamais commité,
#  comme android/). Ce script patche ios/Runner/Info.plist avec TOUT
#  ce dont l'app a besoin pour FONCTIONNER sur iPhone. Il est appelé
#  par les DEUX workflows iOS :
#    - build-ios.yml          (check de compilation, sans signature)
#    - build-ios-release.yml  (build signé .ipa → TestFlight/App Store)
#
#  Pourquoi ces clés (cf. docs/ios-app-store-playbook.md) :
#    - ATS NSAllowsArbitraryLoads : les flux IPTV (fournis par
#      l'utilisateur) sont souvent en HTTP clair → sans ça iOS bloque
#      tout. Justification à donner au reviewer Apple = dans le playbook.
#    - UIBackgroundModes=audio : lecture audio écran éteint (parité du
#      mode « Écouteurs » Android) + capability requise pour le PiP.
#    - Réseau local + Bonjour : découverte Chromecast / DLNA / AirPlay.
#    - On NE déclare PAS photo/micro → moins de friction de review Apple.
#
#  Idempotent : on supprime puis on (re)crée les clés tableau/dict pour
#  éviter les doublons quand le script tourne sur un Info.plist déjà
#  patché.
#
#  Usage : ci/ios/patch_info_plist.sh [chemin/Info.plist]
#          (défaut : ios/Runner/Info.plist)
# =========================================================
set -uo pipefail

PL="${1:-ios/Runner/Info.plist}"
PB=/usr/libexec/PlistBuddy

if [ ! -f "$PL" ]; then
  echo "⚠️  Info.plist introuvable ($PL) — rien à patcher."
  exit 0
fi

# Set d'une clé scalaire : Add si absente, sinon Set.
set_scalar() { # $1=keypath  $2=type(bool|string)  $3=value
  "$PB" -c "Add :$1 $2 $3" "$PL" 2>/dev/null \
    || "$PB" -c "Set :$1 $3" "$PL" 2>/dev/null \
    || true
}

# --- App Transport Security : HTTP clair pour les flux IPTV ---
"$PB" -c "Add :NSAppTransportSecurity dict" "$PL" 2>/dev/null || true
set_scalar "NSAppTransportSecurity:NSAllowsArbitraryLoads" bool true

# --- Audio en arrière-plan (mode « Écouteurs ») + capability PiP ---
"$PB" -c "Delete :UIBackgroundModes" "$PL" 2>/dev/null || true
"$PB" -c "Add :UIBackgroundModes array" "$PL" 2>/dev/null || true
"$PB" -c "Add :UIBackgroundModes:0 string audio" "$PL" 2>/dev/null || true

# --- Réseau local + Bonjour : découverte des TV (cast) ---
set_scalar "NSLocalNetworkUsageDescription" string \
  "7 MOTION recherche les TV (Chromecast / DLNA) sur ton reseau Wi-Fi pour caster ta video."
"$PB" -c "Delete :NSBonjourServices" "$PL" 2>/dev/null || true
"$PB" -c "Add :NSBonjourServices array" "$PL" 2>/dev/null || true
# Google Cast (générique + récepteur média par défaut CC1AD845).
"$PB" -c "Add :NSBonjourServices:0 string _googlecast._tcp" "$PL" 2>/dev/null || true
"$PB" -c "Add :NSBonjourServices:1 string _CC1AD845._googlecast._tcp" "$PL" 2>/dev/null || true
# AirPlay (picker système + RAOP).
"$PB" -c "Add :NSBonjourServices:2 string _airplay._tcp" "$PL" 2>/dev/null || true
"$PB" -c "Add :NSBonjourServices:3 string _raop._tcp" "$PL" 2>/dev/null || true
# Note : DLNA/UPnP utilise SSDP (multicast UDP 239.255.255.250:1900), qui
# n'est PAS du Bonjour → aucune entrée ici. Il est débloqué par la seule
# permission « réseau local » (NSLocalNetworkUsageDescription ci-dessus).

# --- Nom affiché sous l'icône ---
set_scalar "CFBundleDisplayName" string "7 MOTION"

# --- On ne demande AUCUNE permission inutile (friction de review) ---
"$PB" -c "Delete :NSPhotoLibraryUsageDescription" "$PL" 2>/dev/null || true
"$PB" -c "Delete :NSPhotoLibraryAddUsageDescription" "$PL" 2>/dev/null || true
"$PB" -c "Delete :NSMicrophoneUsageDescription" "$PL" 2>/dev/null || true
"$PB" -c "Delete :NSCameraUsageDescription" "$PL" 2>/dev/null || true

echo "--- Info.plist patché (iOS) ---"
"$PB" -c "Print :NSAppTransportSecurity" "$PL" 2>/dev/null || true
"$PB" -c "Print :UIBackgroundModes" "$PL" 2>/dev/null || true
"$PB" -c "Print :NSBonjourServices" "$PL" 2>/dev/null || true
