#!/usr/bin/env bash
set -euo pipefail
work="$PWD/android-app/ci/novatube_tv"
out="$PWD/pilot-results"
mkdir -p "$out"
export ANDROID_SERIAL=emulator-5554
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg libpulse0 python3-pil tesseract-ocr
cp qa-apks/NovaTube-TV-emulateur.apk "$RUNNER_TEMP/pilot.apk"
ram=1536
test "$(cat qa-apks/app-commit)" = "$EXPECTED_COMMIT"
(cd qa-apks && sha256sum -c SHA256SUMS)
expected=$(cut -d' ' -f1 qa-apks/SHA256SUMS)
if [[ "$VARIANT" == 'reference' ]]; then test "$expected" = aa93b4b959bb93d0e863d338be98445254f3412100302870a6c58a4d52662b34; fi
cp qa-apks/{build-flags.txt,app-commit} "$out/"
export FREEZE_ROUTE=10.0.2.2
export CUT_OUTPUT="$out"
echo "$expected  $RUNNER_TEMP/pilot.apk" | sha256sum -c -
sha256sum "$RUNNER_TEMP/pilot.apk" | cut -d' ' -f1 > "$out/apk.sha256"
if [[ "$APP" == novatube ]]; then
 (cd atlas/android-app/cloudflare && npm ci --no-audit --no-fund)
 ATLAS_PORT=8788 node "$work/atlas_local_server.mjs" atlas/android-app/cloudflare "$RUNNER_TEMP/atlas.json" > "$RUNNER_TEMP/atlas.log" 2>&1 &
 for n in $(seq 1 60); do if [[ -s "$RUNNER_TEMP/atlas.json" ]]; then break; fi; sleep 1; done
 test -s "$RUNNER_TEMP/atlas.json"
fi
image='system-images;android-36;android-tv;x86_64'
test -n "$image"
echo "$image" > "$out/system-image.txt"
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$image" >/dev/null
toolsdir="$ANDROID_HOME/build-tools/35.0.0"
"$toolsdir/apksigner" verify --print-certs "$RUNNER_TEMP/pilot.apk" > "$out/signature.txt"
"$toolsdir/aapt" dump badging "$RUNNER_TEMP/pilot.apk" > "$out/badging.txt"
pkg=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" "$out/badging.txt")
pkgactivity=$(sed -n "s/^leanback-launchable-activity: name='\([^']*\)'.*/\1/p" "$out/badging.txt")
if [[ -z "$pkgactivity" ]]; then pkgactivity=$(sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" "$out/badging.txt"); fi
test -n "$pkg"; test -n "$pkgactivity"
printf 'no\n' | avdmanager create avd -f -n tvpilot -k "$image" >/dev/null
python3 "$work/pilot_live_source.py" prepare "$RUNNER_TEMP/encoded-fixture"
sudo chmod a+rw /dev/kvm
mkdir -p "$HOME/.android"
if [[ ! -f "$HOME/.android/adbkey" ]]; then adb keygen "$HOME/.android/adbkey"; fi
adb start-server
"$ANDROID_HOME/emulator/emulator" -avd tvpilot -port 5554 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader -memory "$ram" -cores 2 > "$out/emulator.txt" 2>&1 &
emupid=$!
python3 "$work/cut_source.py" serve "$RUNNER_TEMP/encoded-fixture" --duration 6600 > "$out/source.log" 2>&1 &
srcpid=$!
workers=()
cleanup(){
 for worker in "${workers[@]}"; do kill -TERM "$worker" 2>/dev/null || true; done
 for worker in "${workers[@]}"; do wait "$worker" 2>/dev/null || true; done
 adb exec-out screencap -p > "$out/last.png" 2>/dev/null || true; adb emu kill >/dev/null 2>&1 || true; kill "$srcpid" "$emupid" 2>/dev/null || true; }
trap cleanup EXIT
for n in $(seq 1 180); do
 if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then break; fi
 sleep 2
done
test "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1
adb shell id > "$out/adb-root.txt" 2>&1 || true
timeout 30 adb wait-for-device
adb shell 'id; getprop ro.build.fingerprint; getprop ro.debuggable; getprop ro.build.version.sdk' > "$out/android-runtime.txt"
adb shell pm list features | grep -E 'leanback|television' > "$out/leanback.txt"
adb shell wm size 1920x1080
adb shell svc power stayon true
adb shell input keyevent 82
# Hash a shell-readable staging file on this guest before installing those same bytes.
stage=/data/local/tmp/novatube-framing.apk
adb push "$RUNNER_TEMP/pilot.apk" "$stage" > "$out/install.txt" 2>&1
adb shell toybox sha256sum "$stage" | tr -d '\r' | tee "$out/guest-staged-sha256.txt"
test "$(cut -d' ' -f1 "$out/guest-staged-sha256.txt")" = "$expected"
timeout 100 adb shell pm install -r "$stage" | tr -d '\r' | tee -a "$out/install.txt"
grep -qx 'Success' "$out/install.txt"
installed_path=$(adb shell pm path "$pkg" | tr -d '\r' | sed -n 's/^package://p' | head -1)
test -n "$installed_path"
printf '%s\n' "$installed_path" > "$out/installed-path.txt"
adb shell toybox sha256sum "$installed_path" > "$out/installed-hash-check.txt" 2>&1 || true
# A retail system image can deny reads from /data/app. The verified staged installation
# and the package manager success are retained even when the post-install read is denied.
if grep -qE '^[0-9a-f]{64} ' "$out/installed-hash-check.txt"; then
  test "$(cut -d' ' -f1 "$out/installed-hash-check.txt")" = "$expected"
fi
adb reverse tcp:8788 tcp:8788
adb reverse --list > "$out/ports-before-playback.txt"
adb shell am start -W -n "$pkg/$pkgactivity" | tee "$out/launch.txt"
sleep 20
adb shell cat /proc/meminfo | head -1 > "$out/client-memory.txt"
python3 "$work/cut_witness.py" "$out" > "$out/witness.log" 2>&1 &
workers+=("$!")
python3 "$work/cut_onboard.py" "$out"
python3 "$work/cut_observe.py" "$out" "$CUT_SECONDS"
adb logcat -d --pid="$(adb shell pidof "$pkg" | tr -d '\r')" -v monotonic > "$out/player.log" || true
