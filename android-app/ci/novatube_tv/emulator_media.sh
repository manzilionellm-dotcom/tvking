#!/usr/bin/env bash
# =========================================================
#  emulator_media.sh — Import M3U HTTP, écran Direct 3 zones, lecture
# =========================================================
#  Appelé par emulator_smoke.sh (même émulateur, toujours HORS RÉSEAU).
#  Usage : emulator_media.sh <serial> <sortie> <paquet> <dossier_media>
#
#  La box ne peut joindre QUE sa boucle locale (pare-feu). `adb reverse`
#  relie le port 8080 de la box à un petit serveur HTTP local du runner, qui
#  sert la liste M3U de test et ses mires (make_test_media.sh). On rejoue
#  exactement le geste d'un client à la télécommande :
#    OK sur « Ajouter une liste M3U » → taper l'adresse → Entrée
#    → accueil → OK sur « Direct » → aperçu → OK = plein écran → Retour.
#  Le journal du serveur local prouve ce que l'app a VRAIMENT demandé
#  (liste, logos, segments vidéo = lecture effective).
# =========================================================
set -euo pipefail
serial="$1"; out="$2"; pkg="$3"; media="$4"
srv_pid=""
stop_server() { [[ -n "$srv_pid" ]] && kill "$srv_pid" >/dev/null 2>&1 || true; }
trap stop_server EXIT

step() { printf '%s  [média] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$out/etapes.txt"; }
alive() {
  local pid
  pid="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r' || true)"
  [[ -n "$pid" ]] || { step "ÉCHEC : application arrêtée ($1)"; return 1; }
}
shot() { adb -s "$serial" exec-out screencap -p > "$out/$1.png"; }
key() { adb -s "$serial" shell input keyevent "$1"; sleep "${2:-3}"; }

step "Serveur local de test sur 127.0.0.1:8080 (mires générées)"
python3 -m http.server 8080 --bind 127.0.0.1 --directory "$media" \
  > "$out/serveur-local.txt" 2>&1 &
srv_pid=$!
sleep 2
curl -fsS -o /dev/null http://127.0.0.1:8080/novatube-test.m3u
adb -s "$serial" reverse tcp:8080 tcp:8080

step "Import M3U HTTP : OK sur « Ajouter une liste M3U »"
key KEYCODE_DPAD_CENTER 6
alive "formulaire M3U"
shot 07-formulaire-m3u
adb -s "$serial" shell input text 'http://127.0.0.1:8080/novatube-test.m3u'
sleep 2
shot 08-adresse-saisie
# Entrée peut seulement déplacer le focus vers le bouton. On contrôle l'écran
# et le nombre de vrais GET avant d’envoyer une deuxième touche.
ui_script="$(dirname "$(readlink -f "$0")")/screen_label.py"
grab() { adb -s "$serial" exec-out screencap -p > "$out/instant.png"; }
word() { python3 "$ui_script" "$out/instant.png" "$1" "${2:-0}" "${3:-1}"; }
wait_word() {
  for attempt in $(seq 1 10); do
    grab
    if word "$@" >/dev/null; then return 0; fi
    sleep 1
  done
  step "Libellé introuvable après attente : $1"
  return 1
}
wait_home() {
  # Le texte de la tuile sélectionnée change de contraste. Ces deux repères
  # de l'accueil restent lisibles quel que soit le bouton qui a le focus.
  wait_word 'tonight'
  word 'favorites|playlists|settings' >/dev/null
}
tap_word() {
  wait_word "$@"
  local x y
  read -r x y < <(word "$@")
  adb -s "$serial" shell input tap "$x" "$y"
  sleep 3
}
key KEYCODE_ENTER 2
grab
if ! word 'tonight' >/dev/null; then key KEYCODE_DPAD_CENTER 2; fi
wait_home
alive "accueil après import"
shot 09-apres-import

qa="$(dirname "$(readlink -f "$0")")"
sha256sum "$NOVATUBE_EMULATOR_APK" > "$out/apk-teste.txt"
adb -s "$serial" shell cat /proc/meminfo | head -1 > "$out/memoire-appareil.txt"
pid="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')"
trace() { adb -s "$serial" logcat -d --pid="$pid" -v monotonic -s flutter:I NovaTubeQA:I | grep -E 'NovaTubeQA|Lecteur ouvert|Lecteur fermé' > "$1" || true; }
list_shown() { grab; word 'recent|favorites' 0 .45 >/dev/null && word 'mire|barres' .18 .72 >/dev/null; }
tap_word 'live|direct'
wait_word 'mire|barres'
# Toucher puis revenir par le D-pad établit le focus sur la ligne de la mire.
tap_word 'mire' .18 .62
grab
if word 'recent|favorites' 0 .45 >/dev/null; then key KEYCODE_DPAD_CENTER 2; fi
key KEYCODE_BACK 1
wait_word 'recent|favorites' 0 .45
for trial in $(seq 1 21); do
  case $(( (trial-1) % 7 )) in
    5) mode=double ;;
    6) mode=focus-double ;;
    *) mode=simple ;;
  esac
  prefix="$(printf '%02d-%s' "$trial" "$mode")"
  # Le focus revient sur la chaîne quittée; vérifier l'aperçu avant chaque OK.
  sleep 4
  same="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')"
  test "$same" = "$pid"
  adb -s "$serial" logcat -c
  if [[ "$mode" == focus-double ]]; then
    adb -s "$serial" shell input keyevent 20
    sleep .15
    adb -s "$serial" shell input keyevent 23 23
  elif [[ "$mode" == double ]]; then
    adb -s "$serial" shell input keyevent 23 23
  else
    adb -s "$serial" shell input keyevent 23
  fi
  for poll in $(seq 1 24); do
    trace "$out/$prefix.log"
    if grep -q 'action=preview_to_full outcome=first_frame' "$out/$prefix.log" && grep -q 'phase=first_render ' "$out/$prefix.log"; then break; fi
    sleep .35
  done
  sleep .8
  trace "$out/$prefix.log"
  for attempt in 1 2 3 4; do
    if list_shown; then break; fi
    key KEYCODE_BACK .6
  done
  if ! list_shown; then
    shot "$prefix-ecran"
    if word 'tonight' >/dev/null; then tap_word 'live|direct'; else exit 22; fi
    wait_word 'recent|favorites' 0 .45
  fi
  if [[ "$mode" == focus-double ]]; then key KEYCODE_DPAD_UP .2; fi
done
key KEYCODE_BACK 1
