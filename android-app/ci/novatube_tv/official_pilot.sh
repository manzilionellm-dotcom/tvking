#!/usr/bin/env bash
set -euo pipefail
work="$PWD/android-app/ci/novatube_tv"
out="$PWD/pilot-results"
mkdir -p "$out"
export ANDROID_SERIAL=emulator-5554
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg libpulse0 python3-pil tesseract-ocr
case "$APP" in
 tivimate) uri='https://tivimate.com/apk'; digest=beaebb25bf818450bf496d4cefb16885b190f156815dea280c31eaae0909ee6c ;;
 televizo) uri='https://files.televizo.net/televizo-default.apk'; digest=df570857cebbe7576c0619e18b390cb4171854f1b1c8677e0cb757d5fcdc18ef ;;
 novatube) uri=''; cp qa-apks/NovaTube-TV-emulateur.apk "$RUNNER_TEMP/pilot.apk" ;;
esac
if [[ -n "$uri" ]]; then
 curl -fLsS --retry 2 "$uri" -o "$RUNNER_TEMP/pilot.apk"
 echo "$digest  $RUNNER_TEMP/pilot.apk" | sha256sum -c -
fi
sha256sum "$RUNNER_TEMP/pilot.apk" | cut -d' ' -f1 > "$out/apk.sha256"
if [[ "$APP" == novatube ]]; then
 (cd atlas/android-app/cloudflare && npm ci --no-audit --no-fund)
 ATLAS_PORT=8788 node "$work/atlas_local_server.mjs" atlas/android-app/cloudflare "$RUNNER_TEMP/atlas.json" > "$RUNNER_TEMP/atlas.log" 2>&1 &
 for n in $(seq 1 60); do if [[ -s "$RUNNER_TEMP/atlas.json" ]]; then break; fi; sleep 1; done
 test -s "$RUNNER_TEMP/atlas.json"
fi
sdkmanager --list > "$RUNNER_TEMP/sdk-list"
image=$(sed -nE 's@^[[:space:]]*(system-images;android-(30|31|32|33|34|35|36);(android-tv|google-tv);x86_64)[[:space:]]*\|.*@\1@p' "$RUNNER_TEMP/sdk-list" | sort -u | sed -n '1p')
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
if [[ "$APP" == novatube ]]; then adb reverse tcp:8788 tcp:8788; fi
adb install -r "$RUNNER_TEMP/pilot.apk"
adb shell am start -W -n "$pkg/$pkgactivity" | tee "$out/launch.txt"
sleep 20
adb shell cat /proc/meminfo | head -1 > "$out/client-memory.txt"
# Métadonnée Azure strictement limitée à la région du coureur. Aucun jeton.
REGION_OBS=$(curl -fsS --noproxy '*' -H 'Metadata: true' --max-time 2 'http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text' 2>/dev/null || true)
export REGION_OBS="${REGION_OBS:-unknown}"
printf '%s\n' "$REGION_OBS" > "$out/runner-region.txt"
curl -fsS --max-time 6 https://www.cloudflare.com/cdn-cgi/trace | sed -nE '/^(loc|colo)=/p' > "$out/egress-country.txt" || true
export BENCH_PACKAGE="$pkg"
if [[ "$APP" == novatube ]]; then
  export BENCH_SKIP_VERIFIED_ZAPS=1 BENCH_PRIOR_ZAPS_RUN=46004506404
fi
python3 "$work/${APP}_pilot.py" "$out"
python3 "$work/benchmark.py" "$out"
