#!/usr/bin/env bash
set -euo pipefail
here="$PWD/android-app/ci/zuno_lab/endurance"
out="$PWD/observations"
mkdir "$out"
export PYTHONPATH="$PWD/original/android-app/ci/novatube_tv:$here:$PWD/android-app/ci/zuno_lab"
export BENCH_PACKAGE=com.sevenmotion.tv.seven_tv.lab.diagnostic
ram=1536
if [[ "$SCENARIO" == lowram ]]; then ram=1024; fi
python3 "$here/calibrate.py" "$out/calibration.json"
# Copie du harnais seulement. La TV doit joindre 10.0.2.2 pour le trajet
# direct, et les noms DNS Internet ne sont pas nécessaires au test local.
python3 - "$ram" <<'PY'
import os,sys
from pathlib import Path
src=Path('android-app/ci/zuno_lab/boot_lab.sh').read_text()
for old,new in [('-http-proxy http://127.0.0.1:9','-dns-server 127.0.0.1'),('-memory 1536','-memory '+sys.argv[1])]:
    assert src.count(old)==1
    src=src.replace(old,new)
(Path(os.environ['RUNNER_TEMP'])/'boot-diag.sh').write_text(src)
PY
source "$RUNNER_TEMP/boot-diag.sh" 'system-images;android-36;android-tv;x86_64' "$out"
(cd apk && sha256sum -c SHA256SUMS)
adb shell input keyevent KEYCODE_BACK
adb reverse tcp:18470 tcp:18470
if [[ "$ROUTE" == tunnel ]]; then adb reverse tcp:18472 tcp:18472; fi
adb install apk/ZUNO-DIAGNOSTIC.apk
verify_bytes() {
  local stage="$1" path name
  adb shell pm path "$BENCH_PACKAGE" | tr -d '\r' | sed -n 's/^package://p' | sort > "$RUNNER_TEMP/paths"
  test -s "$RUNNER_TEMP/paths"
  while IFS= read -r path; do
    name=${path##*/}
    [[ "$name" =~ ^[A-Za-z0-9._-]+\.apk$ ]]
    adb shell sha256sum "$path" | awk -v n="$name" '{print $1"  "n}'
  done < "$RUNNER_TEMP/paths" > "$out/$stage.sha256"
  grep -Fx "$(sha256sum apk/ZUNO-DIAGNOSTIC.apk | cut -d' ' -f1)  base.apk" "$out/$stage.sha256"
}
verify_bytes before
if [[ "$DIAG_RUN" == 46089992515 ]]; then
  grep -Fx '8b7e166b9f59f59ecb006a45a023883ddfb953aa05b30389eed99d43f43bc29e  base.apk' "$out/before.sha256"
fi
# La vérification de fin reste indépendante des exceptions et du verdict
# optique. Un échec de hachage conserve les données de l'écran et est signalé.
finish() {
  local rc=$?
  set +e
  (set -e;verify_bytes after;cmp "$out/before.sha256" "$out/after.sha256") || { echo failure > "$out/hash-status.txt";rc=1; }
  kill "${server:-}" "${encoder:-}" 2>/dev/null || true
  adb emu kill >/dev/null 2>&1 || true
  exit "$rc"
}
trap finish EXIT
adb shell cat /proc/meminfo | head -1 > "$out/ram-android.txt"
adb shell wm size > "$out/resolution.txt"
adb reverse --list | awk 'NF>=2 {print $(NF-1),$NF}' > "$out/reverse.txt"
printf '%s\n' "$GITHUB_SHA" "$DIAG_RUN" "$ROUTE" "$SCENARIO" "$DURATION" > "$out/conditions.txt"
python3 "$here/fixture.py" "$RUNNER_TEMP/hls" > "$RUNNER_TEMP/encode.log" 2>&1 & encoder=$!
python3 "$here/origin.py" "$RUNNER_TEMP/hls" "$out/http.jsonl" "$ROUTE" "$SCENARIO" > "$RUNNER_TEMP/origin.log" 2>&1 & server=$!
for _ in {1..80}; do
  if [[ $(curl -fsS http://127.0.0.1:18471/A/index.m3u8 2>/dev/null | grep -c '^s' || true) -ge 2 ]]; then break; fi
  sleep 1
done
test "$(curl -fsS http://127.0.0.1:18471/A/index.m3u8 | grep -c '^s')" -ge 2
component="$BENCH_PACKAGE/com.example.tv_king.MainActivity"
adb shell am start -n "$component"
python3 "$here/observe.py" "$out" --seconds "$DURATION"
python3 "$here/verify_run.py" "$out" "$ROUTE" "$SCENARIO" "$DURATION"
