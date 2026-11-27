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

adb -s "$serial" logcat -v monotonic -s flutter:I NovaTubeQA:I | grep --line-buffered NovaTubeQA > "$out/qa-complet.txt" &
qa_log=$!
step "Accueil → Direct"
key KEYCODE_DPAD_CENTER 4
grab
if ! word 'mire|barres' >/dev/null; then
  tap_word 'live|direct'
fi
wait_word 'mire|barres'
shot 10-direct-3-zones
sleep 6
shot 11-direct-apercu-video

step "Chaîne sélectionnée → plein écran"
tap_word 'mire|barres' .18 .62
grab
if word 'barres|search' 0 .62 >/dev/null; then key KEYCODE_DPAD_CENTER 4; fi
alive "lecture plein écran"
shot 12-lecture-plein-ecran
sleep 8
shot 13-lecture-10s-plus-tard
# Relever le CPU de l'application, la mémoire du processus et les événements QA.
meter() {
  local pid
  pid="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r' | cut -d' ' -f1)"
  test -n "$pid"
  adb -s "$serial" shell "cat /proc/uptime; cat /proc/$pid/stat; getconf CLK_TCK 2>/dev/null || echo unknown" > "$out/proc-$1.txt"
  adb -s "$serial" shell dumpsys meminfo "$pkg" > "$out/memoire-$1.txt"
}
meter direct-avant
sleep 20
meter direct-apres
for iteration in $(seq 1 100); do
  # Une commande entière toutes les quatre secondes. Les ouvertures
  # remplacées et les échecs restent dans le journal.
  key KEYCODE_CHANNEL_DOWN 4
done
meter zaps-apres
adb -s "$serial" logcat -d -s flutter:I NovaTubeQA:I | grep NovaTubeQA > "$out/qa-lecteur.txt" || true
key KEYCODE_BACK 3
wait_word 'mire|barres'
kill "$qa_log" 2>/dev/null || true
shot 14-retour-direct
key KEYCODE_BACK 3
wait_home

# Les captures sont faites après l’ouverture de chaque page, jamais sur le
# simple focus de sa tuile. Les données du fournisseur sont toutes générées.
for page in 'movies|films:15-films' 'series:16-series' 'playlists|lists|sources:17-mes-listes' 'settings:18-reglages'; do
  label="${page%%:*}"
  fichier="${page#*:}"
  tap_word "$label"
  alive "$fichier"
  grab
  if word 'tonight' >/dev/null; then step "La tuile $label ne s’est pas ouverte"; exit 1; fi
  case "$fichier" in
    15-films) wait_word 'horizon' ;;
    16-series) wait_word 'aurora' ;;
  esac
  shot "$fichier"
  if [[ "$fichier" == 18-reglages ]]; then
    key KEYCODE_DPAD_CENTER 3
    wait_word 'access|reseller'
    shot 19-licence
    key KEYCODE_BACK 2
  fi
  key KEYCODE_BACK 3
  wait_home
done
rm -f "$out/instant.png"
step "Ce que l'application a réellement demandé au serveur local"
grep -c 'GET /novatube-test.m3u' "$out/serveur-local.txt" > "$out/requetes-liste.txt" || true
grep -c 'GET /logos/' "$out/serveur-local.txt" > "$out/requetes-logos.txt" || true
grep -c 'GET /live/.*\.ts' "$out/serveur-local.txt" > "$out/requetes-segments-video.txt" || true
step "liste : $(cat "$out/requetes-liste.txt") · logos : $(cat "$out/requetes-logos.txt") · segments vidéo : $(cat "$out/requetes-segments-video.txt")"
test "$(cat "$out/requetes-liste.txt")" -ge 1
test "$(cat "$out/requetes-segments-video.txt")" -ge 2
step "OK : liste importée en HTTP et vidéo réellement lue"
