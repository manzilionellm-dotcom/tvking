#!/usr/bin/env bash
# Démarrage de la même livraison Play sur Android tactile et Android TV.
set -Eeuo pipefail
apk=$(realpath "$1")
out=$(realpath -m "$2")
mkdir -p "$out"
sdk=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
export PATH="$sdk/platform-tools:$sdk/emulator:$PATH"
pkg=com.sevenmotion.novatube.max
serial=emulator-5554
avd=""
serial_adb() { adb -s "$serial" "$@"; }
stop_device() {
  if [[ -n "$avd" ]]; then
    timeout 5s adb -s "$serial" emu kill >/dev/null 2>&1 || true
    if [[ -n "${emulator_pid:-}" ]]; then kill "$emulator_pid" 2>/dev/null || true; fi
    if [[ -n "${emulator_pid:-}" ]]; then wait "$emulator_pid" || true; fi
    avdmanager delete avd -n "$avd" > /dev/null 2>&1 || true
    avd=""
  fi
}
diagnostic() {
  rc=$?
  if ((rc)); then
    echo "Échec du contrôle en ligne $1 (code $rc)" > "$out/etape-echec.txt"
    tail -40 "$out/emulator-${device:-tactile}.log" 2>/dev/null || true
    df -h /
    timeout 4s adb devices || true
    timeout 6s adb -s "$serial" logcat -d -b crash > "$out/plantages.log" 2>/dev/null || true
  fi
  return "$rc"
}
trap 'diagnostic "$LINENO"' ERR
trap stop_device EXIT
for device in tactile television; do
  if [[ "$device" == tactile ]]; then
    image='system-images;android-30;google_apis;x86_64'
  else
    sdkmanager --list > "$RUNNER_TEMP/max-android-images.txt"
    image=$(python3 - "$RUNNER_TEMP/max-android-images.txt" <<'PY'
from pathlib import Path
import re,sys
packages=set(re.findall(r'system-images;android-(\d+);(android-tv|google-tv);x86_64\b',Path(sys.argv[1]).read_text()))
candidates=sorted((int(api), tag) for api,tag in packages if 28<=int(api)<=36)
if not candidates: raise SystemExit('Aucune image Android TV x86_64 dans le SDK')
api,tag=min(candidates,key=lambda x:(x[1]!="android-tv",abs(x[0]-30),-x[0]));print(f'system-images;android-{api};{tag};x86_64')
PY
)
  fi
  echo "Installation de $image"
  df -h /
  sdkmanager emulator platform-tools "$image" > "$out/sdk-$device.log"
  avd=max-$device
  avdmanager list device > "$out/peripheriques-$device.log"
  label=pixel_2
  if [[ "$device" == television ]] && grep -q '"tv_1080p"' "$out/peripheriques-$device.log"; then label=tv_1080p; fi
  printf 'no\n' | avdmanager create avd --force -n "$avd" -k "$image" -d "$label" > "$out/avd-$device.log" 2>&1
  "$sdk/emulator/emulator" -avd "$avd" -port 5554 -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data -gpu swiftshader -accel on -memory 3072 -cores 2 -camera-back none -camera-front none > "$out/emulator-$device.log" 2>&1 &
  emulator_pid=$!
  for _ in {1..110}; do
    kill -0 "$emulator_pid"
    if [[ "$(timeout 6s adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then break; fi
    sleep 4
  done
  test "$(timeout 6s adb -s "$serial" shell getprop sys.boot_completed | tr -d '\r')" = 1
  serial_adb root > "$out/root-$device.log"
  serial_adb wait-for-device
  test "$(serial_adb shell id -u | tr -d '\r')" = 0
  serial_adb shell settings put global window_animation_scale 0
  serial_adb shell settings put global transition_animation_scale 0
  serial_adb shell settings put global animator_duration_scale 0
  serial_adb shell svc power stayon true
  for fw in iptables ip6tables; do serial_adb shell "$fw" -w -I OUTPUT 1 '!' -o lo -j REJECT; done
  serial_adb shell input keyevent 82
  serial_adb install -g -r "$apk" | grep -q Success
  category=android.intent.category.LAUNCHER
  forms=(telephone tablette)
  if [[ "$device" == television ]]; then
    serial_adb shell pm list features | grep 'android.software.leanback'
    category=android.intent.category.LEANBACK_LAUNCHER
    forms=(television)
  fi
  for form in "${forms[@]}"; do
    case "$form" in
      telephone) size=1080x2160; density=420 ;;
      tablette) size=1600x2560; density=240 ;;
      television) size=1920x1080; density=320 ;;
    esac
    serial_adb shell wm size "$size"
    serial_adb shell wm density "$density"
    serial_adb shell am force-stop "$pkg"
    serial_adb logcat -c
    component=$(serial_adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c "$category" "$pkg" | tr -d '\r' | tail -1)
    [[ "$component" == "$pkg/"* ]]
    serial_adb shell am start -W -n "$component" > "$out/start-$form.log"
    grep -q 'Status: ok' "$out/start-$form.log"
    visible=false
    for _ in {1..16}; do
      serial_adb exec-out screencap -p > "$out/$form.png"
      tesseract "$out/$form.png" "$out/ocr-$form" --psm 11 >/dev/null 2>&1 || true
      if grep -Eiq 'M3U|Xtream|Bienvenue|Welcome' "$out/ocr-$form.txt"; then visible=true; break; fi
      sleep 2
    done
    if [[ "$visible" != true ]]; then cat "$out/ocr-$form.txt"; fi
    test "$visible" = true
    serial_adb shell pidof "$pkg" >/dev/null
    serial_adb shell dumpsys activity activities > "$out/activite-$form.log"
    grep -Ei 'topResumedActivity|mResumedActivity|ResumedActivity' "$out/activite-$form.log" | grep -F "$pkg" >/dev/null
    if serial_adb logcat -b crash -d | grep -Eq 'FATAL EXCEPTION|Fatal signal'; then exit 1; fi
    echo "$form - $image - $category - accueil Flutter affiche" | tee -a "$out/demarrages.txt"
  done
  stop_device
  if [[ "$device" == tactile ]]; then sdkmanager --uninstall "$image" >/dev/null; fi
done
