#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "public-hour failed during Android preparation at line $LINENO, status $?"' ERR
work="$PWD/android-app/ci/novatube_tv"
out="$PWD/hourly-public"
mkdir -p "$out"
export ANDROID_SERIAL=emulator-5554
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg libpulse0 python3-pil tesseract-ocr
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
retry_shell() {
  for attempt in $(seq 1 20); do
    if timeout 12 adb -s emulator-5554 shell "$@"; then return 0; fi
    timeout 6 adb reconnect offline || true
    sleep 3
  done
  return 1
}
echo 'Waiting for package, activity and window services'
for svc in package activity window; do
  for attempt in $(seq 1 50); do
    if timeout 8 adb shell service check "$svc" | grep -q ': found'; then break; fi
    sleep 2
  done
done
retry_shell wm size 1920x1080
retry_shell svc power stayon true
retry_shell input keyevent 82
test -z "$(adb reverse --list)"

adb shell cat /proc/meminfo | sed -n '1p' > "$out/client-memory.txt"
curl -fsS --max-time 6 https://www.cloudflare.com/cdn-cgi/trace | sed -nE '/^(loc|colo)=/p' > "$out/egress-country.txt" || true
curl -sS --max-time 3 -H Metadata:true --noproxy '*' 'http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text' > "$out/runner-region.txt" || true

app="$APP"
    version_out="$out"
    mkdir -p "$version_out"
    case "$app" in
      novatube)
        apk="$RUNNER_TEMP/NovaTube-LAB.apk"
        curl -fLsS --retry 2 --proto '=https' https://github.com/manzilionellm-dotcom/tvking/releases/download/novatube-tv-lab-caf2209b/NovaTube-LAB.apk -o "$apk"
        digest=410bc89ecc396704218311f7053c91df4e3efd30aa52e84e9fe20934fb33f54b
        pkg=com.sevenmotion.novatube.tv.lab
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
    # Avant le premier chronométrage : vérifier les octets réellement installés.
    match=0
    for attempt in 1 2 3; do
      timeout 40 adb wait-for-device || continue
      timeout 90 adb install --no-streaming -r "$apk" >> "$version_out/install.log" 2>&1 || true
      device_path=$(adb shell pm path "$pkg" 2>/dev/null | tr -d '\r' | sed -n 's/^package:\(.*\/base\.apk\)$/\1/p')
      if [[ -n "$device_path" ]] && timeout 90 adb pull "$device_path" "$RUNNER_TEMP/base-verified.apk" >> "$version_out/install.log" 2>&1; then
        installed=$(sha256sum "$RUNNER_TEMP/base-verified.apk" | cut -d' ' -f1)
        printf '%s\n' "$installed" > "$version_out/installed.sha256"
        if [[ "$installed" == "$digest" ]]; then match=1; break; fi
      fi
      sleep 2
    done
    test "$match" -eq 1
    

    export OMP_THREAD_LIMIT=1
    test -z "$(adb reverse --list)"
    retry_shell am start -W -n "$pkg/$activity" > "$RUNNER_TEMP/launch.txt"
    sleep 17
    private="$RUNNER_TEMP/public-onboarding"
    mkdir -p "$private"
    if ! python3 "$work/${app}_pilot.py" "$private" > "$RUNNER_TEMP/onboarding-console.log" 2>&1; then
        python3 - "$private" <<'STATUS'
from pathlib import Path
import sys
items=Path(sys.argv[1]).glob('*.png')
stages=sorted(f.stem for f in items if f.stem.startswith(('nova-', 'televizo-')))
print('Incomplete onboarding, stages: '+', '.join(stages))
STATUS
        exit 1
    fi
    touch "$out/onboarding-complete"
    printf '%s\n' "$pkg" > "$out/package.txt"
    # The runner retains these processes across steps of this same job.
    nohup bash -c 'python3 "$1" "$2"; echo "$?" > "$2/endurance.rc"' _ "$work/public_hour_observer.py" "$out" > "$RUNNER_TEMP/public-hour.log" 2>&1 </dev/null &
    echo "$!" > "$RUNNER_TEMP/hourly-observer.pid"
