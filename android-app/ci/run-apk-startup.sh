#!/usr/bin/env bash
# Ouvre les octets signés du build courant, sans reconstruire l'application.
# Réseau Android coupé avant installation : aucun appareil inscrit sur le panel
# et aucune playlist client. Cela ne prouve ni le Cast ni la lecture d'un flux.
set -Eeuo pipefail

startup_api="${STARTUP_API_LEVEL:?API Android manquante}"
case "$startup_api" in 29|35) ;; *) exit 2 ;; esac
startup_repo="$(git rev-parse --show-toplevel)"
startup_out="$startup_repo/artifacts/startup-api-$startup_api"
startup_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?SDK Android absent}}"
startup_serial=emulator-5554
startup_package=com.sevenmotion.tv.seven_tv
startup_image="system-images;android-$startup_api;google_apis;x86_64"
startup_avd="zuno_startup_api_$startup_api"
startup_pid=''
startup_apk="${STARTUP_APK_PATH:?Chemin APK du build manquant}"
startup_verifier="$startup_repo/android-app/ci/verify_apk_startup.py"
mkdir -p "$startup_repo/artifacts"
# Un dossier neuf évite qu'un ancien résultat vert survive à un contrôle raté.
mkdir "$startup_out"

startup_collect() {
  adb -s "$startup_serial" get-state >/dev/null 2>&1 || return 1
  adb -s "$startup_serial" logcat -d -v threadtime > "$startup_out/logcat.txt" 2>&1 &&
    adb -s "$startup_serial" logcat -b crash -d -v threadtime > "$startup_out/crash.txt" 2>&1 &&
    adb -s "$startup_serial" shell dumpsys activity activities > "$startup_out/final-activities.txt" 2>&1 &&
    adb -s "$startup_serial" shell dumpsys connectivity > "$startup_out/final-connectivity.txt" 2>&1 &&
    adb -s "$startup_serial" exec-out screencap -p > "$startup_out/final-screen.png" 2>/dev/null
}

startup_cleanup() {
  local startup_status=$?
  trap - EXIT
  # En cas d'échec, recueillir ce qui reste disponible. Après succès, préserver
  # les fichiers exacts déjà vérifiés : EXIT ne doit pas réécrire la preuve.
  if [[ ! -f "$startup_out/result.json" ]]; then startup_collect || true; fi
  printf '%s\n' "$startup_status" > "$startup_out/exit-code.txt"
  if [[ -n "$startup_pid" ]]; then
    adb -s "$startup_serial" emu kill >/dev/null 2>&1 || true
    kill "$startup_pid" >/dev/null 2>&1 || true
  fi
  exit "$startup_status"
}
trap startup_cleanup EXIT
trap 'printf "Échec à la ligne %s du contrôle.\n" "$LINENO" > "$startup_out/failure.txt"' ERR

git -C "$startup_repo" rev-parse HEAD > "$startup_out/checker-sha.txt"
test "$(cat "$startup_out/checker-sha.txt")" = "$STARTUP_SOURCE_SHA"
# L'APK a été téléchargé par l'ID renvoyé par l'upload du même job build-tv.
# Son SHA et sa taille sont recalculés avant toute installation.
python3 "$startup_verifier" archive "$startup_apk" "$startup_out"

sdkmanager platform-tools emulator 'build-tools;35.0.0' "$startup_image" \
  > "$startup_out/sdk-install.txt" 2>&1
"$startup_sdk/build-tools/35.0.0/apksigner" verify --verbose --print-certs "$startup_apk" \
  > "$startup_out/signature.txt" 2>&1
"$startup_sdk/build-tools/35.0.0/aapt" dump badging "$startup_apk" > "$startup_out/apk-badging.txt"
python3 "$startup_verifier" metadata "$startup_out"
# Ce vrai lancement vérifie aussi les bibliothèques du binaire QEMU. pipefail
# conserve son échec ; tee rend la cause visible sans devoir ouvrir l'artefact.
"$startup_sdk/emulator/emulator" -version 2>&1 | tee "$startup_out/emulator-version.txt"
"$startup_sdk/emulator/emulator" -accel-check > "$startup_out/kvm.txt" 2>&1
printf 'no\n' | avdmanager create avd --force --name "$startup_avd" \
  --package "$startup_image" --device pixel_2 > "$startup_out/avd-create.txt" 2>&1
"$startup_sdk/emulator/emulator" -avd "$startup_avd" -port 5554 \
  -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data \
  -gpu swiftshader -accel on -memory 2048 -cores 2 -skin 1280x720 \
  -camera-back none -camera-front none > "$startup_out/emulator.txt" 2>&1 &
startup_pid=$!

startup_booted=false
for ((startup_attempt=0; startup_attempt<120; startup_attempt++)); do
  kill -0 "$startup_pid"
  if [[ "$(adb -s "$startup_serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    startup_booted=true
    break
  fi
  sleep 5
done
test "$startup_booted" = true
test "$(adb -s "$startup_serial" shell getprop ro.build.version.sdk | tr -d '\r')" = "$startup_api"
printf '%s\n' "$startup_api" > "$startup_out/api.txt"
adb -s "$startup_serial" shell settings put global window_animation_scale 0
adb -s "$startup_serial" shell settings put global transition_animation_scale 0
adb -s "$startup_serial" shell settings put global animator_duration_scale 0
adb -s "$startup_serial" shell svc power stayon true
adb -s "$startup_serial" shell input keyevent 82
adb -s "$startup_serial" shell svc wifi disable
adb -s "$startup_serial" shell svc data disable
# Attendre réellement la disparition du réseau par défaut avant tout lancement.
for ((startup_attempt=0; startup_attempt<15; startup_attempt++)); do
  adb -s "$startup_serial" shell dumpsys connectivity > "$startup_out/connectivity.txt"
  if grep -Eq 'Active default network: (none|null)' "$startup_out/connectivity.txt"; then break; fi
  sleep 2
done
grep -Eq 'Active default network: (none|null)' "$startup_out/connectivity.txt"
timeout 180 adb -s "$startup_serial" install -r "$startup_apk" > "$startup_out/install.txt" 2>&1
grep -qx 'Success' "$startup_out/install.txt"
adb -s "$startup_serial" shell dumpsys package "$startup_package" > "$startup_out/installed-package.txt"
adb -s "$startup_serial" shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER \
  "$startup_package" > "$startup_out/launcher.txt"
startup_component="$(tr -d '\r' < "$startup_out/launcher.txt" | grep -E "^${startup_package//./\\.}/[A-Za-z0-9_.]+$")"
test -n "$startup_component"
adb -s "$startup_serial" shell am force-stop "$startup_package"
adb -s "$startup_serial" logcat -b all -c

startup_dump_ui() {
  local startup_file="$1"
  # UiAutomator peut revenir avec le code 0 sans produire de XML. Effacer le
  # précédent puis exiger un nouveau fichier évite des libellés périmés.
  adb -s "$startup_serial" shell rm -f /sdcard/zuno-startup.xml
  timeout 30 adb -s "$startup_serial" shell uiautomator dump /sdcard/zuno-startup.xml > "$startup_file.dump.txt" 2>&1
  adb -s "$startup_serial" shell test -s /sdcard/zuno-startup.xml
  adb -s "$startup_serial" pull /sdcard/zuno-startup.xml "$startup_file" > "$startup_file.pull.txt" 2>&1
}

startup_open() {
  local startup_phase_out="$startup_out/$1" startup_first_pid startup_current_pid
  mkdir -p "$startup_phase_out"
  adb -s "$startup_serial" shell am start -W -n "$startup_component" > "$startup_phase_out/start.txt" 2>&1
  grep -q '^Status: ok' "$startup_phase_out/start.txt"
  startup_first_pid="$(adb -s "$startup_serial" shell pidof "$startup_package" | tr -d '\r')"
  test -n "$startup_first_pid"
  # Un crash suivi d'un redémarrage ne peut passer grâce à une capture tardive.
  for ((startup_sample=0; startup_sample<15; startup_sample++)); do
    sleep 2
    startup_current_pid="$(adb -s "$startup_serial" shell pidof "$startup_package" | tr -d '\r')"
    test "$startup_current_pid" = "$startup_first_pid"
    adb -s "$startup_serial" shell dumpsys activity activities > "$startup_phase_out/activities.txt"
    grep -E 'mResumedActivity|topResumedActivity' "$startup_phase_out/activities.txt" | grep -Fq "$startup_package/"
    printf '%s\t%s\tforeground\n' "$startup_sample" "$startup_current_pid" >> "$startup_phase_out/samples.tsv"
  done
  startup_dump_ui "$startup_phase_out/ui.xml"
  adb -s "$startup_serial" exec-out screencap -p > "$startup_phase_out/screen.png"
}

startup_open cold
adb -s "$startup_serial" shell input keyevent KEYCODE_BACK
sleep 1
startup_dump_ui "$startup_out/quit-dialog.xml"
python3 "$startup_verifier" quit-dialog "$startup_out/quit-dialog.xml"
adb -s "$startup_serial" exec-out screencap -p > "$startup_out/quit-dialog.png"
# Dialogue observé : autofocus sur Continuer, puis Redémarrer, puis Quitter.
# On utilise les mêmes touches que la télécommande, sans forcer l'arrêt.
adb -s "$startup_serial" shell input keyevent KEYCODE_DPAD_DOWN
sleep 0.3
adb -s "$startup_serial" shell input keyevent KEYCODE_DPAD_DOWN
sleep 0.3
adb -s "$startup_serial" shell input keyevent KEYCODE_DPAD_CENTER
for ((startup_attempt=0; startup_attempt<10; startup_attempt++)); do
  sleep 1
  adb -s "$startup_serial" shell dumpsys activity activities > "$startup_out/after-back.txt"
  if python3 "$startup_verifier" background "$startup_out/after-back.txt" \
      > "$startup_out/background-check.txt" 2>&1; then break; fi
done
python3 "$startup_verifier" background "$startup_out/after-back.txt"
adb -s "$startup_serial" exec-out screencap -p > "$startup_out/after-back.png"
startup_open reopen
# Collecte obligatoire ici : une erreur adb n'est jamais « aucun crash ».
startup_collect
python3 "$startup_verifier" evidence "$startup_out"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$startup_out/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
