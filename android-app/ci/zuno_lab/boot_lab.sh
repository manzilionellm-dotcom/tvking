#!/usr/bin/env bash
# Appelé dans le même shell que le test. L'AVD est éphémère, sans compte.
set -euo pipefail
image="${1:?image Android}"
out="${2:?sortie}"
mkdir -p "$out"
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$image" >/dev/null
echo no | avdmanager create avd -f -n lab -k "$image" >/dev/null
sudo setfacl -m "u:$(id -un):rw" /dev/kvm
export ANDROID_SERIAL=emulator-5554
adb start-server
"$ANDROID_HOME/emulator/emulator" -avd lab -port 5554 -http-proxy http://127.0.0.1:9 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader -memory 1536 -cores 2 > "$RUNNER_TEMP/emulator.log" 2>&1 &
trap 'adb emu kill >/dev/null 2>&1 || true' EXIT
for i in {1..180}; do
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && adb shell pm list packages android | grep -q 'package:android'; then break; fi
  sleep 2
done
test "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1
adb shell svc power stayon true
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
adb shell input keyevent 82
# AVD vierge de test. Le parcours de configuration du système peut intercepter
# une activité après am start. Le test ci-dessous exige ensuite les pixels ZUNO.
adb shell settings put global device_provisioned 1
adb shell settings put secure user_setup_complete 1
adb shell settings put secure tv_user_setup_complete 1
if [[ "$image" == *android-tv* ]]; then adb shell wm size 1920x1080; fi
printf '%s\n' "$image" > "$out/image.txt"
