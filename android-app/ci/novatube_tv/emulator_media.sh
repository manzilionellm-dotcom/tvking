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

# Appelé depuis la phase média, sur l'accueil NovaTube après l'import.
qa_dir="$(dirname "$(readlink -f "$0")")"
sha256sum "$NOVATUBE_EMULATOR_APK" > "$out/apk-mesure-sha256.txt"
adb -s "$serial" shell cat /proc/meminfo | head -1 > "$out/memoire-appareil.txt"
fixed_pid="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')"
same_pid() {
  local current
  current="$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')"
  [[ "$current" == "$fixed_pid" ]]
}
measure_pss() {
  same_pid
  adb -s "$serial" shell dumpsys meminfo "$pkg" > "$out/pss-$1.txt"
  echo "$1 $(date -u +%T) $(awk '/TOTAL PSS:/ {print $3}' "$out/pss-$1.txt")" | tee -a "$out/pss-kib.txt"
}
log_trial() {
  adb -s "$serial" logcat -d --pid="$fixed_pid" -v monotonic -s flutter:I NovaTubeQA:I | grep 'NovaTubeQA' > "$out/$1.txt" || true
}
cycle() {
  local tag="$1" cut="$2"
  same_pid
  tap_word 'live|direct'
  wait_word 'mire|barres'
  # Même chaîne animée sur chaque passage. Le délai d'attente laisse démarrer l'aperçu.
  sleep 4
  # Les marqueurs Telecommande et Media3 proviennent du même essai.
  adb -s "$serial" logcat -c
  tap_word 'mire|barres' .18 .62
  grab
  if word 'barres|search' 0 .62 >/dev/null; then key KEYCODE_DPAD_CENTER 1; fi
  for attempt in $(seq 1 16); do
    log_trial "$tag"
    if grep -q 'action=open_screen outcome=first_frame' "$out/$tag.txt"; then break; fi
    sleep .5
  done
  if grep -q 'action=open_screen outcome=first_frame' "$out/$tag.txt"; then
    echo "$tag first_frame" | tee -a "$out/ouvertures.txt"
  else
    echo "$tag sans_confirmation" | tee -a "$out/ouvertures.txt"
  fi
  if ((cut > 0)); then
    sleep 3
    python3 "$qa_dir/outage_probe.py" "$serial" "$out" "$cut"
  fi
  log_trial "$tag"
  key KEYCODE_BACK 1
  wait_word 'mire|barres'
  key KEYCODE_BACK 1
  wait_home
}
# Le profil porte uniquement sur l'application et les mires du banc.
# Le tampon de sched est purgé dans le fichier à intervalles courts.
adb -s "$serial" shell 'getprop ro.build.type; getenforce; getprop ro.build.version.sdk' > "$out/instrument-android.txt"
trace_pid=""
if adb -s "$serial" shell perfetto --txt --background -c - -o /data/misc/perfetto-traces/novatube-memory.pftrace < "$qa_dir/memory.pbtxt" > "$out/perfetto-start.txt" 2>&1; then
  for _ in $(seq 1 5); do
    trace_pid="$(adb -s "$serial" shell pidof perfetto | tr -d '\r' || true)"
    [[ "$trace_pid" =~ ^[0-9]+$ ]] && break
    sleep 1
  done
fi
# Un diagnostic indisponible ne supprime pas les relevés FD, threads et codecs.
snapshot() {
  local label="$1"
  adb -s "$serial" shell cat /proc/uptime > "$out/uptime-$label.txt"
  measure_pss "$label"
  # Le système de test reste en mode enforcing; on écrit uniquement les
  # classes de FD. Les noms individuels des fichiers ne sont pas publiés.
  adb -s "$serial" shell "wc -l < /proc/$fixed_pid/maps; ls /proc/$fixed_pid/fd | wc -l; ls /proc/$fixed_pid/task | wc -l" > "$out/resources-$label.txt"
  adb -s "$serial" shell "for t in /proc/$fixed_pid/task/*; do cat \$t/comm 2>/dev/null || :; done" | tr -d '\r' | sort | uniq -c > "$out/threads-$label.txt"
  adb -s "$serial" shell "ls -l /proc/$fixed_pid/fd" | python3 -c 'import collections,sys; v=collections.Counter()
for l in sys.stdin:
 if " -> " in l:
  p=l.split(" -> ",1)[1].strip()
  k=next((x for x in ("socket:","pipe:","anon_inode:","/dev/ashmem","/memfd:","/dev/","/data/","/system/","/apex/") if p.startswith(x)),"other")
  v[k]+=1
for k in sorted(v):print(k,v[k])' > "$out/fd-classes-$label.txt"
  adb -s "$serial" shell dumpsys media.codec > "$out/codecs-$label.txt" 2>&1 || true
}
finish_profile() {
  if [[ "$trace_pid" =~ ^[0-9]+$ ]]; then adb -s "$serial" shell kill -INT "$trace_pid" 2>/dev/null || true; fi
  for _ in $(seq 1 15); do
    [[ -z "$(adb -s "$serial" shell pidof perfetto 2>/dev/null | tr -d '\r')" ]] && break
    sleep 1
  done
  adb -s "$serial" pull /data/misc/perfetto-traces/novatube-memory.pftrace "$out/android.pftrace" || true
  stop_server
}
trap finish_profile EXIT
sleep 18
snapshot initial
for n in $(seq 1 8); do
  cycle "cycle-$n" 0
  sleep 7
  snapshot "cycle-$n"
done
start=$SECONDS
for deadline in 30 60 120; do
  delay=$((start + deadline - SECONDS))
  if ((delay > 0)); then sleep "$delay"; fi
  snapshot "repos-$deadline"
done
