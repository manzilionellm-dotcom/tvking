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
shot 06-formulaire-m3u
adb -s "$serial" shell input text 'http://127.0.0.1:8080/novatube-test.m3u'
sleep 2
shot 07-adresse-saisie
key KEYCODE_ENTER 30
alive "import M3U"
shot 08-apres-import

step "Accueil → OK sur la première tuile (Direct)"
key KEYCODE_DPAD_CENTER 12
alive "écran Direct"
shot 09-direct-3-zones
# L'aperçu démarre après 1,5 s d'immobilité du focus (tv_live_preview.dart).
sleep 12
shot 10-direct-apercu-video

step "OK = lecture plein écran"
key KEYCODE_DPAD_CENTER 15
alive "lecture plein écran"
shot 11-lecture-plein-ecran
sleep 10
shot 12-lecture-10s-plus-tard
key KEYCODE_BACK 5
alive "retour au Direct"
shot 13-retour-direct

step "Ce que l'application a réellement demandé au serveur local"
grep -c 'GET /novatube-test.m3u' "$out/serveur-local.txt" > "$out/requetes-liste.txt" || true
grep -c 'GET /logos/' "$out/serveur-local.txt" > "$out/requetes-logos.txt" || true
grep -c 'GET /live/.*\.ts' "$out/serveur-local.txt" > "$out/requetes-segments-video.txt" || true
step "liste : $(cat "$out/requetes-liste.txt") · logos : $(cat "$out/requetes-logos.txt") · segments vidéo : $(cat "$out/requetes-segments-video.txt")"
test "$(cat "$out/requetes-liste.txt")" -ge 1
test "$(cat "$out/requetes-segments-video.txt")" -ge 2
step "OK : liste importée en HTTP et vidéo réellement lue"
