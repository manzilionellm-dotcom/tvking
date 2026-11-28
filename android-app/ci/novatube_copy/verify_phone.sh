#!/usr/bin/env bash
# Emulateur téléphone jetable, APK déjà signé. La preuve compare le texte collé
# dans une autre application avec celui affiché par NovaTube.
set -euo pipefail
apk="$(realpath "${1:?APK absent}")"
out="$(mkdir -p "${2:?Répertoire de preuve absent}" && realpath "$2")"
package="${3:?Paquet Android absent}"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?SDK Android absent}}"
scripts="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$apk" && "$package" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]
serial="${ANDROID_SERIAL:-emulator-5554}"
[[ "$serial" =~ ^emulator-([0-9]+)$ ]]
port="${BASH_REMATCH[1]}"
export PATH="$sdk/platform-tools:$sdk/emulator:$PATH"
device=(adb -s "$serial")
work="$(mktemp -d)"
pid=''
finish() {
  if [[ -n "$pid" ]]; then
    adb -s "$serial" emu kill >/dev/null 2>&1 || true
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap finish EXIT
if [[ "$("${device[@]}" get-state 2>/dev/null || true)" != device ]]; then
  image='system-images;android-34;google_apis;x86_64'
  sdkmanager platform-tools emulator "$image" > "$out/sdk.txt"
  export ANDROID_AVD_HOME="$work/avd"
  mkdir -p "$ANDROID_AVD_HOME"
  printf 'no\n' | avdmanager create avd --force --name nova_copy_phone \
    --path "$ANDROID_AVD_HOME/nova_copy_phone.avd" --package "$image" --device pixel_2 >/dev/null
  emulator -avd nova_copy_phone -port "$port" -no-window -no-audio -no-boot-anim \
    -no-snapshot -gpu swiftshader -memory 3072 -cores 2 -no-metrics \
    -camera-front none -camera-back none > "$out/emulator.txt" 2>&1 &
  pid=$!
fi
for _ in $(seq 1 120); do
  if [[ -n "$pid" ]]; then kill -0 "$pid"; fi
  [[ "$("${device[@]}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 3
done
[[ "$("${device[@]}" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]
[[ "$("${device[@]}" shell getprop ro.kernel.qemu | tr -d '\r')" == 1 ]]
features="$("${device[@]}" shell pm list features)"
[[ "$features" == *android.hardware.touchscreen* && "$features" != *android.software.leanback* ]]
"${device[@]}" shell input keyevent KEYCODE_WAKEUP
"${device[@]}" shell wm dismiss-keyguard
"${device[@]}" shell settings put global window_animation_scale 0
"${device[@]}" shell settings put global transition_animation_scale 0
"${device[@]}" shell settings put system accelerometer_rotation 0
"${device[@]}" shell settings put system user_rotation 1
"${device[@]}" shell wm density 320
"${device[@]}" shell svc power stayon true
"${device[@]}" install -r "$apk"
component="$("${device[@]}" shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER "$package" | tr -d '\r' | tail -1)"
if [[ "$component" != "$package/"* ]]; then
  component="$("${device[@]}" shell cmd package resolve-activity --brief \
    -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$package" | tr -d '\r' | tail -1)"
fi
[[ "$component" == "$package/"* ]]
"${device[@]}" shell am start -W -n "$component" >/dev/null
python3 "$scripts/verify_paste.py" "$serial" "$package" "$apk" "$out"
