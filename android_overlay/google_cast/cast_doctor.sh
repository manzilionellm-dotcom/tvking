#!/usr/bin/env bash
# =========================================================
#  cast_doctor.sh — Diagnostic runtime du Cast (BLACK7 ROYAL)
# =========================================================
#  Dit EN CLAIR pourquoi le cast échoue, sans lire le logcat brut.
#  100% LECTURE SEULE sur l'appareil (seul `adb logcat -c` vide le
#  tampon de logs pour capturer une fenêtre propre). N'affiche QUE des
#  booléens / compteurs / noms de permissions — jamais de contenu réseau.
#
#  USAGE :
#     ./cast_doctor.sh [applicationId]
#  Ex. :
#     ./cast_doctor.sh com.manzilionellm.tvking.tv_king
#  Si l'applicationId n'est pas donné, il est auto-détecté.
#
#  PRÉREQUIS : `adb` dans le PATH, téléphone branché en USB avec le
#  débogage activé. (`aapt` optionnel : améliore le check meta-data.)
#
#  CODE DE SORTIE : 0 si tout est vert, non-zéro sinon.
# =========================================================

set -uo pipefail

PKG="${1:-}"
FAILS=0
WARNS=0

# ----- Affichage -----
if [ -t 1 ]; then
  G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[36m'; Z=$'\e[0m'
else
  G=""; R=""; Y=""; B=""; Z=""
fi
ok()   { echo "${G}[OK]${Z}   $*"; }
fail() { echo "${R}[FAIL]${Z} $*"; FAILS=$((FAILS+1)); }
warn() { echo "${Y}[WARN]${Z} $*"; WARNS=$((WARNS+1)); }
info() { echo "${B}[INFO]${Z} $*"; }
hr()   { echo "---------------------------------------------"; }

echo "============================================="
echo "  cast_doctor — diagnostic Cast (lecture seule)"
echo "============================================="

# ----- 1. Appareil + app installée -----
hr
if ! command -v adb >/dev/null 2>&1; then
  fail "adb introuvable dans le PATH. Installe les platform-tools Android."
  exit 2
fi
STATE="$(adb get-state 2>/dev/null || true)"
if [ "$STATE" != "device" ]; then
  fail "Aucun appareil connecté (adb get-state = '${STATE:-vide}')."
  echo "   → Branche le téléphone en USB + active le débogage USB."
  exit 2
fi
ok "Appareil connecté (adb)."

# Auto-détection de l'applicationId si non fourni.
if [ -z "$PKG" ]; then
  PKG="$(adb shell pm list packages 2>/dev/null | tr -d '\r' \
        | sed 's/^package://' | grep -i 'manzilionellm' | head -1)"
fi
if [ -z "$PKG" ]; then
  fail "App non trouvée sur l'appareil (aucun package 'manzilionellm')."
  echo "   → Installe l'APK, ou passe l'applicationId en argument."
  exit 2
fi
if ! adb shell pm path "$PKG" >/dev/null 2>&1; then
  fail "Package '$PKG' non installé."
  exit 2
fi
ok "App installée : $PKG"

DUMP="$(adb shell dumpsys package "$PKG" 2>/dev/null | tr -d '\r')"

# ----- 2. Permissions réseau requises -----
hr
echo "Permissions réseau (nécessaires au cast) :"
REQUIRED_PERMS=(
  "android.permission.INTERNET"
  "android.permission.ACCESS_NETWORK_STATE"
  "android.permission.CHANGE_WIFI_MULTICAST_STATE"
  "android.permission.ACCESS_WIFI_STATE"
)
MULTICAST_OK=1
for p in "${REQUIRED_PERMS[@]}"; do
  if echo "$DUMP" | grep -q "$p"; then
    ok "$p"
  else
    fail "$p  ABSENTE"
    [ "$p" = "android.permission.CHANGE_WIFI_MULTICAST_STATE" ] && MULTICAST_OK=0
  fi
done

# ----- 3. Meta-data OPTIONS_PROVIDER + classe présente -----
hr
echo "Cast OptionsProvider (meta-data) :"
AAPT="$(command -v aapt 2>/dev/null || true)"
if [ -z "$AAPT" ] && [ -n "${ANDROID_HOME:-}" ]; then
  AAPT="$(ls "$ANDROID_HOME"/build-tools/*/aapt 2>/dev/null | sort | tail -1 || true)"
fi
if [ -n "$AAPT" ]; then
  APK_PATH="$(adb shell pm path "$PKG" 2>/dev/null | tr -d '\r' | sed 's/^package://' | head -1)"
  TMP_APK="$(mktemp -t cast_doctor_XXXX.apk)"
  if adb pull "$APK_PATH" "$TMP_APK" >/dev/null 2>&1; then
    XML="$("$AAPT" dump xmltree "$TMP_APK" AndroidManifest.xml 2>/dev/null || true)"
    if echo "$XML" | grep -q "OPTIONS_PROVIDER_CLASS_NAME"; then
      FQCN="$(echo "$XML" | grep -A2 "OPTIONS_PROVIDER_CLASS_NAME" | grep -oE '"[A-Za-z0-9_.]+CastOptionsProviderImpl"' | tr -d '"' | head -1)"
      if [ -n "$FQCN" ]; then
        ok "meta-data présente → $FQCN"
        # La classe pointe-t-elle vers le package de l'app ?
        if echo "$FQCN" | grep -q "^${PKG%.*}"; then
          ok "FQCN cohérent avec le package de l'app."
        else
          warn "FQCN '$FQCN' semble hors du package app ($PKG)."
        fi
      else
        warn "meta-data présente mais FQCN illisible."
      fi
    else
      fail "meta-data OPTIONS_PROVIDER_CLASS_NAME ABSENTE → Cast SDK non initialisé."
    fi
    rm -f "$TMP_APK"
  else
    info "Impossible de pull l'APK pour l'analyse aapt — check meta-data sauté."
    rm -f "$TMP_APK"
  fi
else
  info "aapt introuvable (installe Android build-tools) — check meta-data sauté."
  info "Permissions ci-dessus restent fiables (via dumpsys)."
fi
# Services médias (proxy de manifest correct) :
for svc in "RecordingForegroundService" "ScreenRecordService"; do
  if echo "$DUMP" | grep -q "$svc"; then ok "Service déclaré : $svc"; else
    warn "Service $svc non vu dans dumpsys (non bloquant pour le cast)."; fi
done

# ----- 4. Capture logcat pendant un scan -----
hr
echo "Capture des logs pendant un scan Cast."
adb logcat -c >/dev/null 2>&1 || true
echo "${Y}👉 OUVRE MAINTENANT le picker Cast dans l'app (icône cast)…${Z}"
echo "   Capture en cours (~15 s)…"
LOG="$(timeout 15 adb logcat -v brief 2>/dev/null \
      | grep -E "MulticastLock|MainActivity|Cast|mDNS|ssdp|discovery\.|multicast_lock|MissingPlugin|no route|errno" \
      || true)"

has() { echo "$LOG" | grep -qiE "$1"; }

# Wiring des channels natifs
if has "Cast channel failed|MulticastLock channel failed|channel failed"; then
  fail "Câblage d'un MethodChannel ÉCHOUÉ (✗ ... channel failed)."
  echo "   → Cause : MainActivity custom mal chargé / dépendance native KO."
elif has "channel wired|configureFlutterEngine"; then
  ok "MethodChannels câblés."
else
  info "Pas de trace de câblage (relance le scan, ou app pas redémarrée)."
fi

# MissingPluginException
if has "MissingPluginException"; then
  fail "MissingPluginException → MainActivity custom non chargé (package)."
  echo "   → Fix : vérifier DETECTED_PKG dans apply_cast_patch.sh."
fi

# BUG D — MainActivity pas en FlutterFragmentActivity
if has "ACTIVITY_TYPE|not a FragmentActivity|as\? FragmentActivity"; then
  fail "ACTIVITY_TYPE → MainActivity n'étend pas FlutterFragmentActivity."
  echo "   → Le dialog Cast natif est introuvable. Relancer apply_cast_patch.sh"
  echo "     (l'assertion FlutterFragmentActivity doit passer)."
fi

# BUG C — init Cast SDK échouée (vs GMS absent)
if has "cast.sdk_init_failed|CAST_UNAVAILABLE"; then
  REASON="$(echo "$LOG" | grep -oE "reason[\": ]+[a-z_]+" | tail -1 || true)"
  fail "Init Cast SDK échouée (${REASON:-init_error})."
  echo "   → Si 'no_gms' : téléphone sans Play Services (normal)."
  echo "   → Sinon 'init_error' : meta-data OPTIONS_PROVIDER fausse → classe"
  echo "     introuvable. Vérifier la cohérence du package (apply_cast_patch.sh)."
fi

# BUG A — flux non wrappé envoyé en mp2t → TV refuse
if has "TV a refusé|content.?type.*mp2t|format_decision.*direct"; then
  warn "Flux possiblement envoyé en MPEG-TS direct (BUG A)."
  echo "   → Un Chromecast pur refuse le mp2t. Le wrap HLS doit s'activer"
  echo "     (cast.format_decision = hls-wrap attendu pour un Chromecast)."
fi

# Partie 0 — App ID receiver effectif
APPID_LINE="$(echo "$LOG" | grep -oE "cast.receiver_app_id=[A-Z0-9]+" | tail -1 || true)"
if [ -n "$APPID_LINE" ]; then
  APPID="${APPID_LINE#cast.receiver_app_id=}"
  if [ "$APPID" = "CC1AD845" ]; then
    info "Receiver = Default Media Receiver ($APPID) — marche partout, sans branding."
  else
    info "Receiver = custom ($APPID) — doit être PUBLIÉ sur la Cast Console,"
    echo "       sinon : TV trouvée mais lecture qui ne démarre pas."
  fi
else
  info "App ID receiver non capturé (ouvre une session cast pour le voir)."
fi

# BUG B — relais HLS injoignable par la TV
if has "cast.relay_unreachable"; then
  fail "La TV ne joint pas le serveur HLS local (isolation AP / WiFi invité)."
  echo "   → Mettre TV et téléphone sur le MÊME WiFi, ou mode QR code."
fi

# MulticastLock
if has "multicast_lock.acquire_failed|discovery.multicast_lock_failed"; then
  fail "MulticastLock NON acquis pendant le scan."
  if [ "$MULTICAST_OK" -eq 0 ]; then
    echo "   → Cause : permission CHANGE_WIFI_MULTICAST_STATE absente."
  else
    echo "   → Permission présente : WiFi indisponible ou bridge natif KO."
  fi
elif has "MulticastLock acquired|MulticastLock acquis"; then
  ok "MulticastLock acquis."
else
  info "Pas de trace MulticastLock (scan non détecté ?)."
fi

# Devices trouvés
DEV_LINE="$(echo "$LOG" | grep -oE 'discovery.finish.*devices[^0-9]*[0-9]+' | tail -1 || true)"
if [ -n "$DEV_LINE" ]; then
  N="$(echo "$DEV_LINE" | grep -oE '[0-9]+' | tail -1)"
  if [ "${N:-0}" -gt 0 ]; then ok "Appareils découverts : $N"; else
    info "0 appareil découvert pendant la fenêtre."; fi
else
  info "Compteur de découverte non capturé."
fi

# Erreurs réseau de session
if has "no route to host|errno = 113|errno = 101|errno = 111|cast.network_unreachable"; then
  fail "Erreur RÉSEAU pendant la session (TV injoignable en TCP)."
  echo "   → Causes probables : TV endormie / WiFi différent / isolation AP."
fi

# ----- 5. Heuristique même sous-réseau -----
hr
echo "Réseau du téléphone (heuristique même WiFi) :"
WIFI_IP="$(adb shell ip -f inet addr show wlan0 2>/dev/null | tr -d '\r' \
          | grep -oE 'inet [0-9.]+' | awk '{print $2}' | head -1)"
if [ -n "$WIFI_IP" ]; then
  SUBNET="$(echo "$WIFI_IP" | cut -d. -f1-3)"
  ok "IP WiFi du téléphone : $WIFI_IP (sous-réseau $SUBNET.x)"
  info "→ Vérifie que ta TV a une IP en $SUBNET.x. Si elle est sur un"
  info "  autre sous-réseau (ex. WiFi invité) → cast impossible (probable)."
else
  warn "Pas d'IP WiFi détectée (téléphone en 4G ou WiFi off ?)."
  echo "   → Le cast exige le téléphone sur le MÊME WiFi que la TV."
fi

# ----- VERDICT -----
hr
echo "============================================="
if [ "$FAILS" -eq 0 ]; then
  echo "${G}=> VERDICT : aucun blocage détecté.${Z}"
  echo "   Si le cast échoue encore, c'est côté receiver (publication"
  echo "   du receiver custom sur la Cast Console) ou TV (allumée ?)."
  echo "============================================="
  exit 0
else
  echo "${R}=> VERDICT : $FAILS problème(s) détecté(s)" \
       "${WARNS:+(+ $WARNS avertissement(s))}.${Z}"
  echo "   Corrige les lignes [FAIL] ci-dessus (chaque ligne donne la"
  echo "   cause + l'action). Cause n°1 d'un picker vide : permission"
  echo "   multicast manquante → relancer apply_cast_patch.sh."
  echo "============================================="
  exit 1
fi
