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

# La liste et les réglages survivent au redémarrage comme sur la box réelle.
component="$(tr -d '\r\n' < "$out/activite-leanback.txt")"
test "${component%%/*}" = "$pkg"
sha256sum "$NOVATUBE_EMULATOR_APK" > "$out/apk-teste.txt"
adb -s "$serial" shell cat /proc/meminfo | head -1 > "$out/memoire-appareil.txt"
trace_pid() { adb -s "$serial" logcat -d --pid="$1" -v monotonic -s NovaTubeQA:I flutter:I; }
wait_stable() {
  local current="$1"
  for n in $(seq 1 23); do
    if trace_pid "$current" | grep -F '[BootGuard] app stable' > /dev/null; then return 0; fi
    if adb -s "$serial" shell cat "/data/user/0/$pkg/shared_prefs/FlutterSharedPreferences.xml" 2>/dev/null | grep -E 'name="(flutter\.)?bootguard\.attempts" value="0"' >/dev/null; then return 0; fi
    sleep 1
  done
  # Une fois passée la fenêtre BootGuard de 20 s sans changement de PID,
  # le prochain démarrage constitue aussi un démarrage isolé.
  [[ "$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')" == "$current" ]]
}
completed=0
for attempt in $(seq 1 36); do
  old="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')"
  wait_stable "$old" || { step "BootGuard : aucune confirmation stable avant le redémarrage"; exit 2; }
  adb -s "$serial" shell input keyevent KEYCODE_HOME
  sleep 1
  adb -s "$serial" shell am force-stop "$pkg"
  for spin in $(seq 1 30); do
    if ! adb -s "$serial" shell pidof "$pkg" >/dev/null; then break; fi
    sleep .2
  done
  if adb -s "$serial" shell pidof "$pkg" >/dev/null; then exit 3; fi
  adb -s "$serial" logcat -c
  launch="$out/froid-$attempt-android.txt"
  adb -s "$serial" shell am start -W -n "$component" | tr -d '\r' > "$launch"
  pid="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')"
  test "$pid" != "$old" && test -n "$pid"
  if ! grep -Fxq "Activity: $component" "$launch" || ! grep -Fxq 'Status: ok' "$launch" || ! grep -Fxq 'LaunchState: COLD' "$launch"; then
    step "Essai $attempt : lancement Android écarté, voir activité observée"
    continue
  fi
  completed=$((completed + 1))
  wait_home
  tap_word 'live|direct'
  wait_word 'mire|barres' .18 .72
  sleep 4
  # Un clic sur la même ligne de chaîne puis OK seulement si la liste reste ouverte.
  tap_word 'mire|barres' .18 .62
  grab
  if word 'recent|favorites' 0 .45 >/dev/null && word 'mire|barres' .18 .72 >/dev/null; then key KEYCODE_DPAD_CENTER .3; fi
  outfile="$out/froid-$attempt-rendu.log"
  for n in $(seq 1 35); do
    trace_pid "$pid" | grep 'NovaTubeQA' > "$outfile" || true
    if grep -q 'action=preview_to_full outcome=first_frame' "$outfile" && grep -q 'phase=first_render' "$outfile"; then break; fi
    sleep .5
  done
  sleep 1
  trace_pid "$pid" | grep 'NovaTubeQA' > "$outfile" || true
  printf '%s %s %s\n' "$completed" "$attempt" "$pid" >> "$out/froids.tsv"
  step "Lancement froid $completed sur 30 (tentative $attempt)"
  if [[ "$completed" = 30 ]]; then break; fi
done
test "$completed" = 30
