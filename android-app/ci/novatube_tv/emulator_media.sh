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

qa_dir="$(dirname "$(readlink -f "$0")")"
python3 "$qa_dir/pilot_live_source.py" serve "$RUNNER_TEMP/novatube-encoded" --duration 6350 > "$out/live-source.log" 2>&1 &
feed=$!
logger=""
cleanup_feed() { kill "$feed" 2>/dev/null || true; [[ -z "$logger" ]] || kill "$logger" 2>/dev/null || true; stop_server; }
trap cleanup_feed EXIT
for j in $(seq 1 40); do if curl -fsS http://127.0.0.1:18471/A/index.m3u8 >/dev/null 2>&1; then break; fi; sleep 1; done
curl -fsS http://127.0.0.1:18471/A/index.m3u8 > "$out/manifeste-initial.txt"
adb -s "$serial" reverse tcp:18471 tcp:18471
adb -s "$serial" logcat -c
adb -s "$serial" logcat -v monotonic -s NovaDriver:I NovaTubeQA:I flutter:I '*:S' > "$out/chronologie.txt" &
logger=$!
step "Plein écran sur la mire après ouverture de l’aperçu"
tap_word 'live|direct'
wait_word 'mire|barres' .18 .72
sleep 5
pid="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')"
tap_word 'mire' .18 .62
grab
if word 'recent|favorites' 0 .45 >/dev/null; then key KEYCODE_DPAD_CENTER 1; fi
for k in $(seq 1 20); do
  adb -s "$serial" logcat -d --pid="$pid" -v monotonic -s NovaTubeQA:I flutter:I | grep NovaTubeQA > "$out/rendu.log" || true
  if grep -q 'action=preview_to_full outcome=first_frame .*view=' "$out/rendu.log"; then break; fi
  sleep .5
done
shot premier-rendu-verifie
sha256sum "$NOVATUBE_EMULATOR_APK" > "$out/apk-teste.txt"
python3 - "$out" <<'VERIFY'
import json,re,sys
from pathlib import Path
d=Path(sys.argv[1]); lines=(d/'rendu.log').read_text().splitlines()
actions=[l for l in lines if 'action=preview_to_full outcome=first_frame' in l]
assert len(actions)==1,actions
m=re.search(r'elapsed_ms=(\d+) view=(\d+) epoch=(\d+) render_ms=(\d+)',actions[0]); assert m,actions
key=f'view={m[2]} epoch={m[3]} phase='
render=[l for l in lines if key+'first_render' in l]; decoder=[l for l in lines if key+'decoder_ready' in l]; release=[l for l in lines if 'phase=preview_release' in l]
assert len(render)==1 and len(release)==1 and len(decoder)>=1
assert lines.index(release[0])<lines.index(decoder[0])<lines.index(render[0])<lines.index(actions[0])
result={'action_elapsed_ms':int(m[1]),'view':int(m[2]),'epoch':int(m[3]),'render_elapsed_realtime_ms':int(m[4]),'release_log':release[0],'decoder_log':decoder[0],'render_log':render[0],'action_log':actions[0]}
(d/'preuve-rendu.json').write_text(json.dumps(result,indent=2)); print(json.dumps(result))
VERIFY
python3 "$qa_dir/hour_measure.py" "$serial" "$pkg" "$out"
