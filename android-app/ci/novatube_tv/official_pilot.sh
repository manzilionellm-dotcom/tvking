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
sdkmanager platform-tools emulator 'build-tools;35.0.0' "$image" </dev/null >/dev/null
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
# Au premier démarrage, sys.boot_completed peut précéder la disponibilité de PackageManager.
for n in $(seq 1 60); do
    adb shell pm list features > "$out/features.txt" 2> "$out/features-error.txt" || true
    if grep -E 'android.software.leanback|android.hardware.type.television' "$out/features.txt" > "$out/leanback.txt"; then break; fi
    sleep 2
done
test -s "$out/leanback.txt"
adb shell wm size 1920x1080
adb shell svc power stayon true
adb shell input keyevent 82
adb reverse tcp:18471 tcp:18471
adb reverse tcp:8788 tcp:8788
adb shell cat /proc/meminfo | sed -n '1p' > "$out/client-memory.txt"
curl -fsS --max-time 6 https://www.cloudflare.com/cdn-cgi/trace | sed -nE '/^(loc|colo)=/p' > "$out/egress-country.txt" || true
export BENCH_ZAPS_ONLY=1 OMP_THREAD_LIMIT=1
IFS=- read -r first second <<< "$ORDER"
for app in "$first" "$second"; do
    version_out="$out/$app"
    mkdir -p "$version_out"
    case "$app" in
      novatube)
        root="$PWD/qa-apks/apk-candidat"
        (cd "$root" && sha256sum -c SHA256SUMS)
        test "$(cat "$root/app-commit")" = "$EXPECTED_CANDIDAT"
        cp "$root/app-commit" "$version_out/app-commit"
        apk="$root/NovaTube-TV-emulateur.apk"
        digest=$(cut -d" " -f1 "$root/SHA256SUMS")
        cp "$root/build-flags.txt" "$version_out/"
        grep -Fxq "NOVATUBE_COMPACT_ZAP=true" "$version_out/build-flags.txt"
        pkg=com.sevenmotion.novatube.tv
        ;;
      televizo)
        apk="$RUNNER_TEMP/televizo-officiel.apk"
        curl -fLsS --retry 2 --proto '=https' https://files.televizo.net/televizo-default.apk -o "$apk"
        digest=df570857cebbe7576c0619e18b390cb4171854f1b1c8677e0cb757d5fcdc18ef
        pkg=com.ottplay.ottplay
        ;;
      *) exit 2 ;;
    esac
    export BENCH_PACKAGE="$pkg"
    echo "$digest  $apk" | sha256sum -c -
    printf '%s  %s.apk\n' "$digest" "$app" > "$version_out/SHA256SUMS"
    "$toolsdir/apksigner" verify --print-certs "$apk" > "$version_out/signature.txt"
    "$toolsdir/aapt" dump badging "$apk" > "$version_out/badging.txt"
    grep -q "^package: name='$pkg'" "$version_out/badging.txt"
    if [[ "$app" == televizo ]]; then
      grep -q "versionCode='635' versionName='1.9.9.44-d'" "$version_out/badging.txt"
      grep -q 'Signer #1 certificate SHA-256 digest: 0a227be4f05784030f4ea8c9c3e0f13855f19653dfe049927a723463287c015b' "$version_out/signature.txt"
    fi
    activity=$(sed -n "s/^leanback-launchable-activity: name='\([^']*\)'.*/\1/p" "$version_out/badging.txt")
    if [[ -z "$activity" ]]; then
      activity=$(sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" "$version_out/badging.txt")
    fi
    test -n "$activity"
    adb install "$apk"
    adb logcat -c
    adb shell am start -W -n "$pkg/$activity" > "$version_out/launch.txt"
    sleep 20
    python3 "$work/${app}_pilot.py" "$version_out"
    python3 "$work/benchmark.py" "$version_out"
    adb logcat -d -s NovaTubeQA:I flutter:I > "$version_out/player.log"
    # Contrôle visuel supplémentaire après les 50 chronométrages. L'enregistrement
    # de la transition ne concurrence aucune des observations optiques classées.
    adb shell rm -f /sdcard/novatube-qa-visual.mp4
    adb shell screenrecord --bit-rate 6000000 --time-limit 6 /sdcard/novatube-qa-visual.mp4 > "$version_out/record.log" 2>&1 &
    recorder=$!
    sleep 1.2
    adb shell input keyevent KEYCODE_CHANNEL_DOWN
    if wait "$recorder"; then
      adb pull /sdcard/novatube-qa-visual.mp4 "$version_out/post-zap.mp4" > "$version_out/pull.log" 2>&1 || true
    fi
    adb shell rm -f /sdcard/novatube-qa-visual.mp4
    adb uninstall "$pkg"
done
