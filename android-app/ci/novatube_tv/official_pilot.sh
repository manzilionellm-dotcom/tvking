#!/usr/bin/env bash
set -euo pipefail
work="$PWD/android-app/ci/novatube_tv"
out="$PWD/pilot-results"
mkdir -p "$out"
export ANDROID_SERIAL=emulator-5554
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg libpulse0 python3-pil tesseract-ocr
(cd atlas/android-app/cloudflare && npm ci --no-audit --no-fund)
 ATLAS_PORT=8788 node "$work/atlas_local_server.mjs" atlas/android-app/cloudflare "$RUNNER_TEMP/atlas.json" > "$RUNNER_TEMP/atlas.log" 2>&1 &
 for n in $(seq 1 60); do if [[ -s "$RUNNER_TEMP/atlas.json" ]]; then break; fi; sleep 1; done
 test -s "$RUNNER_TEMP/atlas.json"
image='system-images;android-36;android-tv;x86_64'
echo "$image" > "$out/system-image.txt"
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$image" >/dev/null
toolsdir="$ANDROID_HOME/build-tools/35.0.0"
printf 'no\n' | avdmanager create avd -f -n tvpilot -k "$image" >/dev/null
python3 "$work/pilot_live_source.py" prepare "$RUNNER_TEMP/encoded-fixture"
sudo chmod a+rw /dev/kvm
mkdir -p "$HOME/.android"
if [[ ! -f "$HOME/.android/adbkey" ]]; then adb keygen "$HOME/.android/adbkey"; fi
adb start-server
"$ANDROID_HOME/emulator/emulator" -avd tvpilot -port 5554 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swiftshader -memory 1536 -cores 2 > "$out/emulator.txt" 2>&1 &
emupid=$!
python3 "$work/pilot_live_source.py" serve "$RUNNER_TEMP/encoded-fixture" --duration 6600 > "$out/source.log" 2>&1 &
srcpid=$!
cleanup(){ adb exec-out screencap -p > "$out/last.png" 2>/dev/null || true; adb emu kill >/dev/null 2>&1 || true; kill "$srcpid" "$emupid" 2>/dev/null || true; }
trap cleanup EXIT
for n in $(seq 1 180); do
 if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then break; fi
 sleep 2
done
test "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1
adb shell pm list features | grep -E 'leanback|television' > "$out/leanback.txt"
adb shell wm size 1920x1080
adb shell svc power stayon true
adb shell input keyevent 82
adb reverse tcp:18471 tcp:18471
adb reverse tcp:8788 tcp:8788
adb shell cat /proc/meminfo | head -1 > "$out/client-memory.txt"
curl -fsS --max-time 6 https://www.cloudflare.com/cdn-cgi/trace | sed -nE '/^(loc|colo)=/p' > "$out/egress-country.txt" || true
export BENCH_PACKAGE=com.sevenmotion.novatube.tv BENCH_ZAPS_ONLY=1
export OMP_THREAD_LIMIT=1
IFS=- read -r first second <<< "$ORDER"
for version in "$first" "$second"; do
    root="$PWD/qa-apks/apk-$version"
    version_out="$out/$version"
    mkdir -p "$version_out"
    (cd "$root" && sha256sum -c SHA256SUMS)
    expected="$EXPECTED_CANDIDAT"
    if [[ "$version" == temoin ]]; then expected="$EXPECTED_TEMOIN"; fi
    test "$(cat "$root/app-commit")" = "$expected"
    apk="$root/NovaTube-TV-emulateur.apk"
    cp "$root/app-commit" "$root/SHA256SUMS" "$version_out/"
    "$toolsdir/apksigner" verify --print-certs "$apk" > "$version_out/signature.txt"
    "$toolsdir/aapt" dump badging "$apk" > "$version_out/badging.txt"
    pkg=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" "$version_out/badging.txt")
    activity=$(sed -n "s/^leanback-launchable-activity: name='\([^']*\)'.*/\1/p" "$version_out/badging.txt")
    test "$pkg" = "$BENCH_PACKAGE"; test -n "$activity"
    adb install "$apk"
    adb logcat -c
    adb shell am start -W -n "$pkg/$activity" > "$version_out/launch.txt"
    sleep 20
    python3 "$work/novatube_pilot.py" "$version_out"
    python3 "$work/benchmark.py" "$version_out"
    adb logcat -d -s NovaTubeQA:I flutter:I > "$version_out/player.log"
    adb uninstall "$pkg"
done
