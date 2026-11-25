#!/usr/bin/env bash
set -euo pipefail
out="$GITHUB_WORKSPACE/diagnostic"
apk="$RUNNER_TEMP/delivered.apk"
package="${EXPECTED_PACKAGE:-com.manzilionellm.tvking.qa.perf}"
network_mode="${NETWORK_MODE:-offline}"
case "$network_mode" in
  offline) port=5554 ;;
  online) port=5556; out="$out/en-ligne" ;;
  *) exit 2 ;;
esac
export ANDROID_SERIAL="emulator-$port"
export ANDROID_AVD_HOME="$RUNNER_TEMP/diagnostic-avd-$network_mode"
mkdir -p "$out" "$ANDROID_AVD_HOME"
build_tools="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
"$build_tools/aapt" dump badging "$apk" > "$out/apk.txt"
"$build_tools/apksigner" verify --print-certs "$apk" > "$out/signature.txt"
grep -qF "package: name='$package'" "$out/apk.txt"
grep -qF "native-code: 'arm64-v8a'" "$out/apk.txt"
image="system-images;android-$ANDROID_API;$IMAGE_TAG;x86_64"
sudo setfacl -m "u:$(id -un):rw" /dev/kvm
sdkmanager emulator "$image" > "$out/sdk.txt"
avdmanager create avd --force --name diagnostic --package "$image" --device pixel_2 <<< no
"$ANDROID_HOME/emulator/emulator" -avd diagnostic -port "$port" -no-window -no-audio -no-boot-anim \
  -no-snapshot -no-metrics -gpu swiftshader -accel on -cores 2 -memory 2048 -partition-size 2048 \
  > "$out/emulator.log" 2>&1 &
emulator_pid=$!
trap 'adb emu kill >/dev/null 2>&1 || true' EXIT
for ((i=0; i<120; i++)); do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then tail -50 "$out/emulator.log"; exit 1; fi
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then break; fi
  sleep 3
done
[[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]
abi="$(adb shell getprop ro.product.cpu.abilist | tr -d '\r')"
bridge="$(adb shell getprop ro.dalvik.vm.native.bridge | tr -d '\r')"
printf 'API=%s\nAVD=x86_64 %s\nABI=%s\nNative bridge=%s\nPage bytes=%s\n' "$ANDROID_API" "$IMAGE_TAG" "$abi" "$bridge" "$(adb shell getconf PAGE_SIZE | tr -d '\r')" | tee "$out/device.txt"
if [[ ",$abi," != *,arm64-v8a,* ]]; then
  echo 'INCOMPATIBLE_ABI — cette image ne déclare pas arm64-v8a.' | tee "$out/result.txt"
  exit 1
fi
if [[ "$network_mode" == online ]]; then
  # L'état VALIDATED est attribué par Android à un accès Internet fonctionnel.
  adb shell svc wifi enable
  adb shell svc data enable
  for ((i=0; i<20; i++)); do
    adb shell dumpsys connectivity > "$out/connectivity.txt"
    if grep -E 'NetworkAgentInfo' "$out/connectivity.txt" | grep 'VALIDATED' > "$out/validated.txt"; then break; fi
    sleep 2
  done
  if [[ ! -s "$out/validated.txt" ]]; then
    echo 'NETWORK_UNCONFIRMED — Android ne signale pas de réseau Internet validé.' | tee "$out/result.txt"
    exit 1
  fi
else
  adb shell svc wifi disable
  adb shell svc data disable
fi
echo "Network mode=$network_mode" >> "$out/device.txt"
adb shell svc power stayon true
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
adb shell input keyevent 82
adb install "$apk" | tee "$out/install.txt"
activity="$(adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER "$package" | tr -d '\r' | tail -1)"
[[ "$activity" == "$package/"* ]]
adb logcat -b all -c
adb logcat -b all -v threadtime > "$out/logcat.txt" &
logcat_pid=$!
trap 'kill "$logcat_pid" 2>/dev/null || true; wait "$logcat_pid" || true; adb emu kill >/dev/null 2>&1 || true' EXIT
timeout 12 adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \
  -n "$activity" > "$out/launch.txt" 2>&1 || true
cat "$out/launch.txt"
for ((i=1; i<=24; i++)); do
  pid="$(adb shell pidof "$package" | tr -d '\r' || true)"
  printf '%s %s\n' "$i" "${pid:-absent}" >> "$out/process.txt"
  if ((i == 3 || i == 12)); then adb exec-out screencap -p > "$out/capture-$i.png" || true; fi
  sleep 2
done
snapshot() {
  adb shell dumpsys activity exit-info "$package" > "$out/exit-info.txt" || true
  adb shell dumpsys activity activities > "$out/activities.txt" || true
  adb shell dumpsys window windows > "$out/window.txt" || true
  adb exec-out screencap -p > "$out/final.png" || true
  if timeout 18 adb shell uiautomator dump /sdcard/diagnostic.xml > "$out/dump.txt" 2>&1; then
    adb pull /sdcard/diagnostic.xml "$out/ui.xml" >> "$out/dump.txt" 2>&1 || true
  fi
}
snapshot
# La mire est un accueil Flutter : deux éléments propres à cet écran donnent une
# preuve plus précise que le processus vivant ou le nom figurant sur le splash.
if ! adb shell pidof "$package" >/dev/null; then
  echo 'PROCESS_EXITED — le processus est absent après le lancement.' | tee "$out/result.txt"
  grep -Ein 'FATAL EXCEPTION|Fatal signal|Abort message|UnsatisfiedLinkError|Missing application ID|Process: com\.manzilionellm\.tvking' "$out/logcat.txt" | tail -35 || true
  head -45 "$out/exit-info.txt"
  exit 1
fi
if [[ -s "$out/ui.xml" ]] && grep -iq 'notifi' "$out/ui.xml" && grep -Eq 'resource-id="(com.android|com.google.android).permissioncontroller:id/permission_deny_button"' "$out/ui.xml"; then
  # Un nouvel utilisateur peut refuser les notifications et accéder au lecteur.
  cp "$out/ui.xml" "$out/permission-initiale.xml"
  button="$(python3 - "$out/ui.xml" <<'PYBUTTON'
import re, sys
from xml.etree import ElementTree
root = ElementTree.parse(sys.argv[1])
for node in root.iter("node"):
    resource = node.get("resource-id", "")
    if resource.endswith("permissioncontroller:id/permission_deny_button"):
        bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if bounds:
            x1, y1, x2, y2 = map(int, bounds.groups())
            print((x1 + x2) // 2, (y1 + y2) // 2)
            break
PYBUTTON
)"
  if [[ "$button" =~ ^([0-9]+)\ +([0-9]+)$ ]]; then
    adb shell input tap "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    sleep 5
    snapshot
  fi
fi
if [[ -s "$out/ui.xml" ]] && grep -Eiq 'MK:([0-9a-f]{2}:){4}[0-9a-f]{2}' "$out/ui.xml" && grep -Eiq 'Support|Assistance' "$out/ui.xml"; then
  for pass in 1 2; do
    adb shell dumpsys activity activities > "$out/foreground-$pass.txt"
    if ! grep -E 'topResumedActivity|mResumedActivity|ResumedActivity:' "$out/foreground-$pass.txt" | grep -F "$package/" > "$out/resumed-$pass.txt"; then
      echo 'NOT_FOREGROUND — l’activité de 7 MOTION ne détient pas le premier plan.' | tee "$out/result.txt"
      exit 1
    fi
    if ((pass == 1)); then sleep 8; fi
  done
  echo "HOME_VISIBLE — assistance et identifiant affichés, activité au premier plan sur deux contrôles séparés de huit secondes ($network_mode)." | tee "$out/result.txt"
elif [[ -s "$out/ui.xml" ]] && grep -q 'com.android.permissioncontroller\|com.google.android.permissioncontroller' "$out/ui.xml"; then
  echo 'PERMISSION_DIALOG — intervention requise avant confirmation de l’accueil.' | tee "$out/result.txt"
  exit 1
else
  echo 'HOME_UNCONFIRMED — processus vivant, accueil non confirmé. Voir les captures et la fenêtre active.' | tee "$out/result.txt"
  exit 1
fi
