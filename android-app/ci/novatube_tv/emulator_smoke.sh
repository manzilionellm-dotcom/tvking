#!/usr/bin/env bash
# =========================================================
#  emulator_smoke.sh — NovaTube TV : installer, ouvrir, naviguer, rouvrir
# =========================================================
#  Usage : bash ci/novatube_tv/emulator_smoke.sh <apk> <dossier_de_sortie>
#
#  Ce que ce contrôle PROUVE (sur un émulateur Android 11 / API 30, la
#  version de la NVIDIA SHIELD de référence, en 1920×1080 densité 320 = la
#  taille logique d'une TV 1080p) :
#    1. l'APK signé s'installe proprement (installation neuve) ;
#    2. il démarre sans plantage et affiche son premier écran ;
#    3. la télécommande (touches D-pad) ouvre les formulaires M3U et Xtream ;
#    4. Retour revient à l'accueil ; un arrêt forcé puis une réouverture
#       fonctionnent (redémarrage de l'application) ;
#    5. aucune trace de plantage (« FATAL EXCEPTION », tampon crash, ANR).
#
#  Ce qu'il NE prouve PAS (et le rapport le dit) : la qualité d'image, le
#  HDR, le son, la lecture d'un vrai flux, le comportement sur une vraie
#  SHIELD. L'émulateur est HORS RÉSEAU (pare-feu interne, comme le contrôle
#  Zuno) : aucun appareil de test n'est créé dans le panel de production.
#
#  Captures produites (PNG) : 01 premier démarrage → 05 réouverture.
# =========================================================
set -euo pipefail

apk="$(readlink -f "$1")"
out="$(mkdir -p "$2" && readlink -f "$2")"
pkg="com.sevenmotion.novatube.tv"
api=30
image="system-images;android-${api};google_apis;x86_64"
serial="emulator-5554"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?ANDROID_HOME manquant}}"
emu_pid=""

finish() {
  local status=$?
  # Journal de l'app seulement (aucune liste, aucun identifiant : hors réseau
  # et aucune source saisie pendant ce contrôle).
  adb -s "$serial" logcat -d -v threadtime > "$out/logcat.txt" 2>/dev/null || true
  adb -s "$serial" exec-out screencap -p > "$out/99-dernier-ecran.png" 2>/dev/null || true
  printf '%s\n' "$status" > "$out/exit-code.txt"
  if [[ -n "$emu_pid" ]]; then
    adb -s "$serial" emu kill >/dev/null 2>&1 || true
    kill "$emu_pid" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap finish EXIT
trap 'printf "Échec à la ligne %s.\n" "$LINENO" > "$out/echec.txt"' ERR

step() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$out/etapes.txt"; }

step "Outils Android et image Android ${api}"
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$image" > "$out/sdk-install.txt" 2>&1
bt="$sdk/build-tools/35.0.0"
"$bt/apksigner" verify --verbose --print-certs "$apk" > "$out/signature.txt" 2>&1
"$bt/aapt" dump badging "$apk" > "$out/badging.txt"
grep -q "^package: name='${pkg}'" "$out/badging.txt"
grep -q "^application-label:'NovaTube'" "$out/badging.txt"
grep -q "^leanback-launchable-activity:" "$out/badging.txt"

step "Création et démarrage de l'émulateur"
printf 'no\n' | avdmanager create avd --force --name novatube \
  --package "$image" --device pixel_2 > "$out/avd-create.txt" 2>&1
"$sdk/emulator/emulator" -avd novatube -port 5554 \
  -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
  -gpu swiftshader -accel on -memory 3072 -cores 2 \
  -camera-back none -camera-front none > "$out/emulator.txt" 2>&1 &
emu_pid=$!
booted=false
for ((i = 0; i < 120; i++)); do
  kill -0 "$emu_pid"
  if [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    booted=true
    break
  fi
  sleep 5
done
test "$booted" = true
test "$(adb -s "$serial" shell getprop ro.build.version.sdk | tr -d '\r')" = "$api"
adb -s "$serial" shell getprop ro.build.version.release | tr -d '\r' > "$out/android-version.txt"

step "Mode TV 1080p, animations coupées, écran allumé"
adb -s "$serial" shell settings put global window_animation_scale 0
adb -s "$serial" shell settings put global transition_animation_scale 0
adb -s "$serial" shell settings put global animator_duration_scale 0
adb -s "$serial" shell svc power stayon true
adb -s "$serial" shell input keyevent 82
adb -s "$serial" shell wm size 1920x1080
adb -s "$serial" shell wm density 320

step "Hors réseau (aucun contact avec le serveur de production)"
# Le Wi-Fi reste « connecté » (l'app se comporte comme chez un client), mais
# le pare-feu de la box REJETTE toute sortie sauf la boucle locale : ni le
# serveur de production, ni Internet ne sont joignables. Seul un serveur
# local de test (adb reverse, phase média) l'est.
adb -s "$serial" root > "$out/adb-root.txt" 2>&1
adb -s "$serial" wait-for-device
test "$(adb -s "$serial" shell id -u | tr -d '\r')" = 0
for fw in iptables ip6tables; do
  adb -s "$serial" shell "$fw" -w -I OUTPUT 1 '!' -o lo -j REJECT
  adb -s "$serial" shell "$fw" -w -C OUTPUT '!' -o lo -j REJECT
done

step "Installation propre"
adb -s "$serial" install -r "$apk" > "$out/install.txt" 2>&1
grep -q Success "$out/install.txt"
component="$(adb -s "$serial" shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER "$pkg" \
  | tr -d '\r' | tail -1)"
printf '%s\n' "$component" > "$out/activite-leanback.txt"
[[ "$component" == "$pkg/"* ]]

alive() {
  local pid
  pid="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r' || true)"
  if [[ -z "$pid" ]]; then
    step "ÉCHEC : l'application n'est plus en vie ($1)"
    return 1
  fi
}
shot() { adb -s "$serial" exec-out screencap -p > "$out/$1.png"; }
key() { adb -s "$serial" shell input keyevent "$1"; sleep "${2:-3}"; }

step "Premier démarrage"
adb -s "$serial" logcat -c
adb -s "$serial" shell am start -W -n "$component" > "$out/demarrage-1.txt" 2>&1
sleep 35
alive "premier démarrage"
shot 01-premier-demarrage

step "Télécommande : OK sur le bouton qui a le focus (M3U)"
key KEYCODE_DPAD_CENTER 6
alive "ouverture formulaire"
shot 02-apres-ok
key KEYCODE_BACK 4
alive "retour"
shot 03-retour-accueil

step "Télécommande : droite puis OK (Xtream Codes)"
key KEYCODE_DPAD_RIGHT 2
key KEYCODE_DPAD_CENTER 6
alive "formulaire Xtream"
shot 04-apres-droite-ok
key KEYCODE_BACK 4

step "Arrêt forcé puis réouverture"
adb -s "$serial" shell am force-stop "$pkg"
sleep 3
adb -s "$serial" shell am start -W -n "$component" > "$out/demarrage-2.txt" 2>&1
sleep 30
alive "réouverture"
shot 05-reouverture

if [[ -n "${NOVATUBE_EMULATOR_APK:-}" ]]; then
  # Phase B : MÊME code, compilé avec l'adresse d'un Atlas LOCAL (le vrai
  # code serveur des routes /api/novatube4k/*, lancé sur le runner, port
  # 8788). La box l'atteint par sa boucle locale (adb reverse) : aucun
  # contact avec la production, aucun appareil de test dans le vrai panel.
  step "Phase B : variante reliée à l'Atlas local (essai serveur de 10 jours)"
  adb -s "$serial" install -r "$(readlink -f "$NOVATUBE_EMULATOR_APK")" > "$out/install-variante.txt" 2>&1
  grep -q Success "$out/install-variante.txt"
  adb -s "$serial" shell pm clear "$pkg" > /dev/null
  adb -s "$serial" reverse tcp:8788 tcp:8788
  adb -s "$serial" shell am start -W -n "$component" > "$out/demarrage-3.txt" 2>&1
  sleep 35
  alive "premier démarrage avec Atlas local"
  shot 06-bienvenue-atlas-local
fi

if [[ -n "${NOVATUBE_TEST_MEDIA:-}" ]]; then
  step "Phase média : import M3U HTTP, Direct 3 zones, lecture"
  if bash "$(dirname "$(readlink -f "$0")")/emulator_media.sh" \
      "$serial" "$out" "$pkg" "$NOVATUBE_TEST_MEDIA"; then
    step "Phase média : OK"
    echo ok > "$out/phase-media.txt"
  else
    # Les captures précédentes restent disponibles pour diagnostiquer le refus.
    step "Phase média : NON CONCLUANTE (voir captures 07 à 14)"
    echo echec > "$out/phase-media.txt"
    exit 1
  fi
fi

step "Recherche de plantages"
adb -s "$serial" logcat -d -b crash > "$out/tampon-crash.txt" 2>&1 || true
if grep -q "$pkg" "$out/tampon-crash.txt"; then
  step "ÉCHEC : plantage enregistré par Android"
  exit 1
fi
if adb -s "$serial" logcat -d | grep -E "FATAL EXCEPTION|ANR in ${pkg//./\\.}" > "$out/plantages.txt"; then
  if grep -q "$pkg" "$out/plantages.txt"; then
    step "ÉCHEC : FATAL EXCEPTION ou ANR"
    exit 1
  fi
fi
step "OK : installation, démarrage, navigation, réouverture sans plantage"
