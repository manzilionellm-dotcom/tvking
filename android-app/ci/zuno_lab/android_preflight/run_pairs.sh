#!/usr/bin/env bash
# Deux AVD indépendants et des ordres ABBA/BAAB définis avant l'observation.
set -euo pipefail
out=${1:?dossier}; order=${2:?ordre}; bits=${3:?apk}
[[ "$order" == abba || "$order" == baab ]]
base=$(pwd)
pkg=com.sevenmotion.tv.seven_tv.lab.catalog
source ci/zuno_lab/android_catalog_boot/boot1g.sh "$out"
cp ci/zuno_lab/android_catalog_fixture/mire.ts "$RUNNER_TEMP/catalog.ts"
echo "52d6a4710795551895241b407e183127b573b012be1e0594a50f2d89c911e3f4  $RUNNER_TEMP/catalog.ts" | sha256sum -c -
python3 ci/zuno_lab/android_catalog_raster/prepare_driver.py wait-1080-refus
# Le pilote injecte l'intent uniquement au premier lancement d'un processus neuf.
python3 - <<'PY'
from pathlib import Path
p=Path('ci/zuno_lab/android_catalog_cycles/run.py')
s=p.read_text()
old="adb('shell','am','start','-W','-n',activity)"
assert s.count(old)==1
s="import os\n"+s if not s.startswith('"""') else s
s=s.replace(old, "adb('shell','am','start','-W','-n',activity,'--ez','disable_lab_gl_preflight',__import__('os').environ['DISABLE_LAB_PREFLIGHT'])")
compile(s,str(p),'exec')
p.write_text(s)
PY
rc=0
for idx in 0 1 2 3; do
  arm=${order:idx:1}
  dest=$out/$((idx+1))-$arm
  mkdir -p "$dest"
  adb uninstall "$pkg" >/dev/null 2>&1 || true
  # Le vidage des données entre essais doit être confirmé avant la nouvelle installation.
  test -z "$(adb shell pm path "$pkg" | tr -d '\r')"
  if [[ "$arm" == a ]]; then export DISABLE_LAB_PREFLIGHT=false; else export DISABLE_LAB_PREFLIGHT=true; fi
  echo "$DISABLE_LAB_PREFLIGHT" > "$dest/skip-requested.txt"
  python3 ci/zuno_lab/android_catalog_anr/observe.py "$dest" "$bits" "$RUNNER_TEMP/catalog.ts" wait-light || rc=1
  adb logcat -d -v epoch ZunoStartup:I '*:S' | grep -E 'lab\.ai\.|ai\.preflight\.(begin|end)' > "$dest/preflight-times.log" || true
  grep -F "lab.ai.skip=$DISABLE_LAB_PREFLIGHT" "$dest/preflight-times.log" >/dev/null || rc=1
  if [[ "$arm" == b ]]; then
    grep -F "lab.ai.preflight.skipped" "$dest/preflight-times.log" >/dev/null || rc=1
    if grep -F "ai.preflight.begin" "$dest/preflight-times.log" >/dev/null; then rc=1; fi
  else
    grep -F "ai.preflight.begin" "$dest/preflight-times.log" >/dev/null || rc=1
  fi
  adb shell am force-stop "$pkg"
  sleep 3
done
exit "$rc"
