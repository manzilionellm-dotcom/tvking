#!/usr/bin/env bash
set -euo pipefail
apk=$(realpath "$1")
label=$2
out=$(realpath -m "$3")
mkdir -p "$out"
sdk=${ANDROID_SDK_ROOT:-$ANDROID_HOME}
export PATH="$sdk/platform-tools:$sdk/emulator:$PATH"
net=novatube-play-qa
uid=$(id -u)
gid=$(id -g)
sudo ip netns add "$net"
sudo ip -n "$net" link set lo up
test -z "$(sudo ip -n "$net" route show default)"
iso() { sudo ip netns exec "$net" setpriv --reuid="$uid" --regid="$gid" --init-groups env HOME="$HOME" PATH="$PATH" ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk" "$@"; }
device() { iso "$sdk/platform-tools/adb" -s emulator-5554 "$@"; }
cleanup() { iso timeout 6 "$sdk/platform-tools/adb" -s emulator-5554 emu kill >/dev/null 2>&1 || true; sudo ip netns delete "$net" || true; }
trap cleanup EXIT
if [[ "$label" == television ]]; then
    sdkmanager --list > "$RUNNER_TEMP/images.txt"
    image=$(python3 - "$RUNNER_TEMP/images.txt" <<'PY'
import re,sys
from pathlib import Path
opts = {(int(n), tag) for n,tag in re.findall(r'system-images;android-(\d+);(android-tv|google-tv);x86_64\b', Path(sys.argv[1]).read_text()) if 28 <= int(n) <= 36}
api, tag = min(opts, key=lambda t:(abs(t[0]-30),t[1]!='android-tv'))
print(f'system-images;android-{api};{tag};x86_64')
PY
)
    profile=tv_1080p; size=1920x1080; density=320
else
    image='system-images;android-30;google_apis;x86_64'
    case "$label" in
        tablette7) profile=nexus_7_2013; size=1200x1920; density=320 ;;
        tablette) profile=pixel_c; size=1080x1920; density=180 ;;
        telephone) profile=pixel_2; size=1080x1920; density=380 ;;
        *) exit 2 ;;
    esac
fi
sdkmanager --install emulator platform-tools "$image" > "$RUNNER_TEMP/sdk.log"
avdmanager list device > "$RUNNER_TEMP/hardware.txt"
if [[ "$label" == tablette7 ]]; then
    profile=$(python3 - "$RUNNER_TEMP/hardware.txt" <<'PY'
import re, sys
from pathlib import Path
found = re.findall(r'id:\s*\d+\s+or\s+"([^"]+)"', Path(sys.argv[1]).read_text())
options = [name for name in found if name in ['Nexus 7 2013', 'Nexus 7', 'nexus_7_2013', '7in WSVGA (Tablet)']]
if not options:
    raise SystemExit("No official seven-inch tablet profile available")
print(options[0])
PY
)
fi
grep -Fq "\"$profile\"" "$RUNNER_TEMP/hardware.txt"
printf 'no\n' | avdmanager create avd --force -n nvtest -k "$image" -d "$profile" > "$RUNNER_TEMP/avd.log" 2>&1
# The official TV image reads the host's public ADB key when QEMU starts.
mkdir -p "$HOME/.android"
if [[ ! -s "$HOME/.android/adbkey" ]]; then
    (umask 077; "$sdk/platform-tools/adb" keygen "$HOME/.android/adbkey" >/dev/null 2>&1)
fi
test -s "$HOME/.android/adbkey.pub"
iso "$sdk/platform-tools/adb" start-server >/dev/null 2>&1
iso "$sdk/emulator/emulator" -avd nvtest -port 5554 -no-window -no-audio -no-boot-anim -no-snapshot -wipe-data -gpu swiftshader -accel on -memory 3072 -cores 2 -camera-back none -camera-front none > "$RUNNER_TEMP/emulator.log" 2>&1 &
epid=$!
for _ in {1..120}; do
    kill -0 "$epid" || { tail -20 "$RUNNER_TEMP/emulator.log"; exit 1; }
    if [[ "$(iso timeout 3 "$sdk/platform-tools/adb" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then break; fi
    sleep 3
done
test "$(device shell getprop sys.boot_completed | tr -d '\r')" = 1
device shell settings put global device_provisioned 1
device shell settings put secure user_setup_complete 1
device shell input keyevent KEYCODE_WAKEUP
device shell wm dismiss-keyguard
device shell wm size "$size"
device shell wm density "$density"
device shell settings put global animator_duration_scale 0
device shell input keyevent 82
device install -r "$apk" | grep -q Success
pkg=com.sevenmotion.novatube.tv
category=android.intent.category.LAUNCHER
if [[ "$label" == television ]]; then
    device shell pm list features > "$RUNNER_TEMP/features.txt"
    grep -q 'android.software.leanback' "$RUNNER_TEMP/features.txt"
    category=android.intent.category.LEANBACK_LAUNCHER
fi
component=$(device shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c "$category" "$pkg" | tr -d '\r' | tail -1)
[[ "$component" == "$pkg/"* ]]
device logcat -c
device shell am start -W -n "$component" > "$RUNNER_TEMP/start.txt"
grep -q 'Status: ok' "$RUNNER_TEMP/start.txt"
take() { device exec-out screencap -p > "$RUNNER_TEMP/ui.png"; tesseract "$RUNNER_TEMP/ui.png" stdout --psm 11 2>/dev/null > "$RUNNER_TEMP/ocr.txt"; }
for _ in {1..20}; do
    take
    if grep -Eiq 'M3U|Xtream' "$RUNNER_TEMP/ocr.txt"; then break; fi
    sleep 2
done
grep -Eiq 'M3U|Xtream' "$RUNNER_TEMP/ocr.txt"
device shell pidof "$pkg" > /dev/null
printf '%s\n' "app=$pkg" "version=1.0.0 (1794878682)" "avd=$profile" "image=$image" "category=$category" "signing=ephemeral emulator key" "startup=ok" > "$out/controle-$label.txt"
if [[ "$label" == television ]]; then
    device shell input keyevent KEYCODE_DPAD_CENTER
else
    tesseract "$RUNNER_TEMP/ui.png" "$RUNNER_TEMP/words" --psm 11 tsv >/dev/null 2>&1
    point=$(python3 - "$RUNNER_TEMP/words.tsv" <<'PY'
import csv,sys
for row in csv.DictReader(open(sys.argv[1]),delimiter='\t'):
    if 'M3U' in row['text'].upper():
        print(int(row['left'])+int(row['width'])//2, int(row['top'])+int(row['height'])//2)
        break
else:
    raise SystemExit('M3U button was not recognized')
PY
)
    read -r x y <<< "$point"
    device shell input tap "$x" "$y"
fi
check_form() {
    for _ in {1..14}; do
        take
        if grep -Eiq 'optional|provider|source|sign in and load|paste|coller|fournisseur' "$RUNNER_TEMP/ocr.txt" && ! grep -Eiq 'device code|welcome to|bienvenue sur|revendeur|MK[:·]' "$RUNNER_TEMP/ocr.txt"; then return 0; fi
        sleep 1
    done
    return 1
}
check_form
cp "$RUNNER_TEMP/ui.png" "$out/$label-formulaire.png"
echo 'form=open' >> "$out/controle-$label.txt"
device shell input keyevent KEYCODE_BACK
sleep 2
if check_form; then
    if ! cmp -s "$RUNNER_TEMP/ui.png" "$out/$label-formulaire.png"; then cp "$RUNNER_TEMP/ui.png" "$out/$label-formulaire-retour.png"; fi
fi
device shell pidof "$pkg" > /dev/null
if device logcat -b crash -d | grep -Eq 'FATAL EXCEPTION|Fatal signal'; then exit 1; fi
echo 'crash_buffer=empty' >> "$out/controle-$label.txt"
cat "$out/controle-$label.txt"
