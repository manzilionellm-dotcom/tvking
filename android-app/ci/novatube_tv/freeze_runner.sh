#!/usr/bin/env bash
set -euo pipefail
work="$PWD/android-app/ci/novatube_tv"
out="$PWD/pilot-results"
mkdir -p "$out"
export ANDROID_SERIAL=emulator-5554
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg libpulse0 python3-pil tesseract-ocr
cp qa-apks/NovaTube-TV-emulateur.apk "$RUNNER_TEMP/pilot.apk"
expected=9239c20e5bbb77b7d9636eccef7511c41f5319dbb7a8e72aceb4633d1fc650af
ram=1536
if [[ "$FREEZE_SCENARIO" == temoin-passif ]]; then expected=d8d4a1b316f4b407342181c17e8cfc1cb73130d13b6a92ec95cd48be117cb145; fi
if [[ "$FREEZE_SCENARIO" == candidat ]]; then expected=3dc5440dd3edd2ab057dc355ac0d35ea5ac8fbd6435546f9991233c201493dd5; fi
if [[ "$FREEZE_SCENARIO" == memoire ]]; then ram=1024; fi
export FREEZE_ROUTE=127.0.0.1
if [[ "$FREEZE_SCENARIO" == direct ]]; then export FREEZE_ROUTE=10.0.2.2; fi
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
export FREEZE_TUNNEL_GATE="$out/tunnel-arm-gate.txt"
printf "HOLD\n" > "$FREEZE_TUNNEL_GATE"
python3 "$work/freeze_live_source.py" serve "$RUNNER_TEMP/encoded-fixture" --duration 6600 > "$out/source.log" 2>&1 &
srcpid=$!
workers=()
python3 "$work/freeze_witness.py" "$out" --channels AB --seconds 6600 > "$out/origin-witness.log" 2>&1 &
workers+=("$!")
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
# Bootstrap only. Once observation starts the reverse mapping is never repaired.
installed=0
for attempt in 1 2 3; do
 timeout 50 adb wait-for-device || true
 for ready in $(seq 1 30); do
   if timeout 4 adb shell cmd package path android 2>/dev/null | grep -q '^package:'; then break; fi
   sleep 1
 done
 if timeout 65 adb install --no-streaming -r "$RUNNER_TEMP/pilot.apk" >> "$out/install-attempts.txt" 2>&1 || timeout 6 adb shell pm path "$pkg" 2>/dev/null | grep -q '^package:'; then installed=1; break; fi
 adb reconnect offline >> "$out/install-attempts.txt" 2>&1 || true
 sleep 3
done
test "$installed" = 1
timeout 35 adb wait-for-device
adb reverse tcp:18471 tcp:18471
adb reverse tcp:8788 tcp:8788
adb reverse --list > "$out/ports-before-playback.txt"
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
python3 "$work/freeze_onboard.py" "$out"
python3 "$work/freeze_android.py" "$out" "$pkg" --duration 6500 --arm-file "$out/observation-start.json" > "$out/android-observer.log" 2>&1 &
workers+=("$!")
tunnel_args=()
if [[ "$FREEZE_SCENARIO" == temoin-passif ]]; then tunnel_args+=(--passive-reverse); fi
python3 "$work/freeze_tunnel.py" "$out" "${tunnel_args[@]}" --seconds 6300 --interval 6 > "$out/tunnel-witness.log" 2>&1 &
workers+=("$!")

for i in $(seq 1 40); do
 if [[ -s "$out/guest-tunnel-ready.json" ]]; then break; fi
 sleep 1
done
if [[ ! -s "$out/guest-tunnel-ready.json" ]]; then echo "Témoin Android direct non confirmé à l’ouverture" > "$out/temoin-initial.txt"; fi
python3 "$work/freeze_benchmark.py" "$out"

python3 "$work/freeze_android.py" capture --out "$out/inspection-finale" --package "$pkg" --reason session_end
