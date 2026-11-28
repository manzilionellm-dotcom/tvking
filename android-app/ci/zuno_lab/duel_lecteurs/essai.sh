#!/usr/bin/env bash
set -euo pipefail
kit="$PWD/android-app/ci/zuno_lab"
base="$PWD/resultats"
televizo=com.ottplay.ottplay
zuno=com.sevenmotion.tv.seven_tv.lab
mkdir -p "$base/appareil" "$base/source" "$RUNNER_TEMP/prive"
export OMP_THREAD_LIMIT=1 PYTHONPATH="$PWD/origine/android-app/ci/novatube_tv"
python3 "$PYTHONPATH/pilot_live_source.py" prepare "$RUNNER_TEMP/mires"
sed "s/'--duration','3300'/'--duration','8500'/" "$kit/path_trace/source.py" > "$RUNNER_TEMP/source.py"
python3 "$RUNNER_TEMP/source.py" "$PYTHONPATH/pilot_live_source.py" "$RUNNER_TEMP/mires" "$base/source" > "$RUNNER_TEMP/mire.log" 2>&1 &
source "$kit/boot_lab.sh" 'system-images;android-36;android-tv;x86_64' "$base/appareil"
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = 1
adb shell input keyevent KEYCODE_BACK
for port in 18471 18475; do adb reverse tcp:$port tcp:$port; done
adb reverse tcp:18789 tcp:18787
curl -fsSL --proto '=https' --retry 2 https://files.televizo.net/televizo-default.apk -o "$RUNNER_TEMP/Televizo.apk"
echo "df570857cebbe7576c0619e18b390cb4171854f1b1c8677e0cb757d5fcdc18ef  $RUNNER_TEMP/Televizo.apk" | sha256sum -c -
echo "ef566b3405666f6692feae771652537f6f1ee7bca760244f92bf2594a5ba51ab  AppliB/ZUNO-LAB.apk" | sha256sum -c -
for f in Z T; do
  if [[ "$f" = Z ]]; then apk=AppliB/ZUNO-LAB.apk; else apk="$RUNNER_TEMP/Televizo.apk"; fi
  "$ANDROID_HOME/build-tools/35.0.0/apksigner" verify --print-certs "$apk" > "$base/cert-$f.txt"
  "$ANDROID_HOME/build-tools/35.0.0/aapt" dump badging "$apk" | sed -n '1p' > "$base/version-$f.txt"
  adb install -g "$apk"
done
# Métadonnée de localisation seule ; un code de sortie HTTP ne localise pas le lecteur.
curl --max-time 3 --noproxy '*' -fsS -H Metadata:true 'http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text' | tr -cd 'a-zA-Z0-9-' > "$base/region-machine.txt" || true
curl --max-time 6 -fsS 'https://www.cloudflare.com/cdn-cgi/trace' | sed -nE '/^(loc|colo)=/p' > "$base/sortie-reseau.txt" || true
export ZUNO_QA_PASS ZUNO_PRELOADED_BY_PANEL=yes
ZUNO_QA_PASS=$(python3 -c 'import secrets;print(secrets.token_urlsafe(42))')
node "$kit/panel/local-worker.mjs" android-app/cloudflare android-app/cloudflare "$RUNNER_TEMP/panel.json" > "$RUNNER_TEMP/panel.log" 2>&1 &
for poll in {1..80}; do [[ -s "$RUNNER_TEMP/panel.json" ]] && break; sleep .4; done
test -s "$RUNNER_TEMP/panel.json"
rc=0
for i in 0 1; do
  which=${ORDER:i:1}
  out="$base/$i-$which"
  mkdir -p "$out/optical"
  status=0
  if [[ "$which" = Z ]]; then
    export BENCH_PACKAGE="$zuno"
    adb shell am force-stop "$televizo"
    adb shell am start -n "$zuno/com.example.tv_king.MainActivity"
  else
    export BENCH_PACKAGE="$televizo"
    adb shell am force-stop "$zuno"
  fi
  path=$(adb shell pm path "$BENCH_PACKAGE" | tr -d '\r' | sed -n 's/^package://p')
  adb shell sha256sum "$path" | awk '{print $1}' > "$out/installed-before.sha256"
  if [[ "$which" = Z ]]; then
    test "$(cat "$out/installed-before.sha256")" = ef566b3405666f6692feae771652537f6f1ee7bca760244f92bf2594a5ba51ab
    python3 "$kit/panel_device/observe.py" "$out" pixels || status=$?
    if (( status == 0 )); then
      PYTHONPATH="$kit:$PYTHONPATH" python3 -c 'from pathlib import Path; from optical_witness import open_fixture; import sys;open_fixture(Path(sys.argv[1]))' "$out/optical" || status=$?
    fi
  else
    test "$(cat "$out/installed-before.sha256")" = df570857cebbe7576c0619e18b390cb4171854f1b1c8677e0cb757d5fcdc18ef
    timeout 260 python3 "$PYTHONPATH/televizo_pilot.py" "$RUNNER_TEMP/prive/televizo" > "$RUNNER_TEMP/televizo.log" 2>&1 || status=$?
  fi
  if (( status == 0 )); then python3 "$kit/duel_lecteurs/observer.py" "$out/optical" || status=$?; fi
  if [[ -s "$out/optical/luminance.csv" ]]; then
    /usr/bin/python3 "$kit/zaps_cadences/encoder.py" "$out/optical" || status=1
  fi
  echo "$status" > "$out/statut"
  adb shell sha256sum "$path" | awk '{print $1}' > "$out/installed-after.sha256"
  cmp "$out/installed-before.sha256" "$out/installed-after.sha256"
  if (( status != 0 )); then rc=1; fi
done
exit "$rc"
