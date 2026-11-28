#!/usr/bin/env bash
set -euo pipefail
obs="$PWD/observations"
mkdir -p "$obs"
localtools="$PWD/android-app/ci/zuno_lab"
runtime="$RUNNER_TEMP/endurance-signee"
python3 "$localtools/endurance_signee/preparer.py" "$runtime"
export PYTHONPATH="$runtime:$localtools:$PWD/original/android-app/ci/novatube_tv"
export BENCH_PACKAGE=com.sevenmotion.tv.seven_tv.lab OMP_THREAD_LIMIT=1
expected=ef566b3405666f6692feae771652537f6f1ee7bca760244f92bf2594a5ba51ab
(cd apk && sha256sum -c SHA256SUMS)
echo "$expected  apk/ZUNO-LAB.apk" | sha256sum -c -
python3 "$runtime/calibrate.py" "$obs/calibration.json"
ram=1536
if [[ "$SCENARIO" == lowram ]]; then ram=1024; fi
python3 - "$ram" "$localtools/android_catalog_boot/boot1g.sh" "$RUNNER_TEMP/boot-final.sh" <<'PYCODE'
import sys
from pathlib import Path
p=Path(sys.argv[2]);s=p.read_text()
for old,new in [('-http-proxy http://127.0.0.1:9','-dns-server 127.0.0.1'),('-memory 1024','-memory '+sys.argv[1]),('1024 MiB demandés',sys.argv[1]+' MiB demandés')]:
 assert s.count(old)==1;s=s.replace(old,new)
Path(sys.argv[3]).write_text(s)
PYCODE
source "$RUNNER_TEMP/boot-final.sh" "$obs"
(cd apk && cp SHA256SUMS signature.txt badging.txt "$obs/" )
adb shell input keyevent KEYCODE_BACK
adb reverse tcp:18471 tcp:18471
adb reverse tcp:18789 tcp:18789
if [[ "$ROUTE" == tunnel ]]; then adb reverse tcp:18472 tcp:18472; fi
adb reverse --list | awk 'NF>=2 {print $(NF-1),$NF}' > "$obs/reverse.txt"
adb install apk/ZUNO-LAB.apk
verify() {
  local stage=$1 paths
  paths=$(adb shell pm path "$BENCH_PACKAGE" | tr -d '\r' | sed -n 's/^package://p' | sort)
  test -n "$paths" || return 1
  while IFS= read -r path; do
    local name=${path##*/};[[ "$name" =~ ^[A-Za-z0-9._-]+\.apk$ ]] || return 1
    adb shell sha256sum "$path" | awk -v n="$name" '{print $1"  "n}'
  done <<<"$paths" > "$obs/$stage.sha256"
  grep -Fx "$expected  base.apk" "$obs/$stage.sha256" >/dev/null
}
verify before
finish(){
  local status=$?;set +e
  if verify after && cmp --silent "$obs/before.sha256" "$obs/after.sha256"; then echo match > "$obs/hash-status.txt";else echo failure > "$obs/hash-status.txt";status=1;fi
  adb shell dumpsys activity exit-info "$BENCH_PACKAGE" | grep -oE 'reason=[0-9]+ \([^)]+\)|timestamp=[0-9: .-]+|pid=[0-9]+' > "$obs/exit-info-final.txt" || true
  kill "${encoder_a:-}" "${encoder_b:-}" "${origin:-}" "${worker:-}" "${gateway:-}" 2>/dev/null || true
  adb emu kill >/dev/null 2>&1 || true
  exit "$status"
}
trap finish EXIT
printf '%s\n' "$BUILD_SHA" "$BUILD_RUN" "$GITHUB_SHA" "$ROUTE" "$SCENARIO" "$DURATION" > "$obs/conditions.txt"
adb shell cat /proc/meminfo | sed -n '/^MemTotal:/p' > "$obs/ram-android.txt"
python3 "$runtime/fixture.py" "$RUNNER_TEMP/flux/A" A > "$RUNNER_TEMP/encoder-a.log" 2>&1 & encoder_a=$!
python3 "$runtime/fixture.py" "$RUNNER_TEMP/flux/B" B > "$RUNNER_TEMP/encoder-b.log" 2>&1 & encoder_b=$!
python3 "$runtime/origin.py" "$RUNNER_TEMP/flux" "$obs/http.jsonl" "$ROUTE" "$SCENARIO" > "$RUNNER_TEMP/serveur.log" 2>&1 & origin=$!
export ZUNO_ACK_ARM="$RUNNER_TEMP/ack-test"
python3 "$localtools/panel_device/gateway.py" "$obs" "$ZUNO_ACK_ARM" > "$RUNNER_TEMP/gateway.log" 2>&1 & gateway=$!
export ZUNO_QA_PASS
ZUNO_QA_PASS=$(python3 -c 'import secrets;print(secrets.token_urlsafe(42))')
node "$localtools/panel/local-worker.mjs" android-app/cloudflare android-app/cloudflare "$RUNNER_TEMP/ready.json" > "$RUNNER_TEMP/workerd.log" 2>&1 & worker=$!
for _ in {1..100};do if [[ -s "$RUNNER_TEMP/ready.json" && -s "$RUNNER_TEMP/flux/A/index.m3u8" && -s "$RUNNER_TEMP/flux/B/index.m3u8" ]]; then break;fi;sleep 1;done
test -s "$RUNNER_TEMP/ready.json"
cp "$RUNNER_TEMP/ready.json" "$obs/worker.json"
for ch in A B; do curl -fsS "http://127.0.0.1:18471/$ch/index.m3u8" | grep -q '^s';done
curl -fsS http://127.0.0.1:18471/channels.m3u > "$obs/mire-autorisee.m3u"
python3 "$localtools/endurance_signee/entrer.py" "$obs/entree"
python3 "$runtime/observe.py" "$obs" --seconds "$DURATION"
python3 "$runtime/verify_run.py" "$obs" "$ROUTE" "$SCENARIO" "$DURATION"
