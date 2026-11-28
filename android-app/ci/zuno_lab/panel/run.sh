#!/usr/bin/env bash
# Banc local, à lancer sur une copie de travail temporaire de la révision à qualifier.
set -euo pipefail
app=$(realpath "$1")
modules=$(realpath "$2")
result=$(realpath -m "$3")
here=$(cd "$(dirname "$0")" && pwd)
stage=$(mktemp -d)
testfile="$app/test/zuno_isolated_panel_campaign_offline_test.dart"
if [[ -e "$testfile" || -e "$result" ]]; then exit 2; fi
export ZUNO_QA_PASS
ZUNO_QA_PASS=$(python3 -c 'import secrets; print(secrets.token_urlsafe(40))')
export ZUNO_QA_PROOF="$result"
node "$here/local-worker.mjs" "$app/cloudflare" "$modules" "$stage/ready.json" > "$stage/worker.log" 2>&1 &
worker_pid=$!
cleanup() {
  kill "$worker_pid" 2>/dev/null || true
  wait "$worker_pid" 2>/dev/null || true
  rm -f "$testfile"
}
trap cleanup EXIT
for check in $(seq 1 120); do
  if [[ -s "$stage/ready.json" ]]; then break; fi
  if ! kill -0 "$worker_pid" 2>/dev/null; then cat "$stage/worker.log"; exit 1; fi
  sleep .25
done
[[ -s "$stage/ready.json" ]]
cp "$stage/ready.json" "$result.worker.json"
cp "$here/panel_campaign_test.dart" "$testfile"
cd "$app"
flutter --suppress-analytics test --no-pub --concurrency=1 --reporter expanded --dart-define=BACKEND_URL=http://127.0.0.1:18787 --dart-define=PLAY_BUILD=true --dart-define=ZUNO_FREE_PLAYER=true --dart-define=ZUNO_EDITION=auto "$testfile"
