#!/usr/bin/env bash
# Reproduit la dernière chaîne mobile ; ne fusionne et ne publie rien.
set -euo pipefail
mission_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
test "$(git rev-parse HEAD)" = 37fdf3305c5de9d35e20fd6567df38008fc7a7ee
for patch in \
  patches/mobile-sport-gratuit.patch \
  patches/mobile-radio.patch \
  patches/mobile-panel-sync.patch \
  patches/mobile-identity.patch \
  patches/mobile-stability.patch \
  android-app/ci/mobile/adult-classification.patch \
  android-app/ci/mobile/player-terminal-fallback.patch \
  android-app/ci/mobile/mobile-back-gestures.patch \
  android-app/ci/mobile/football-upcoming.patch \
  android-app/ci/mobile/player-session-handoff.patch \
  android-app/ci/mobile/library-user-actions.patch \
  android-app/ci/mobile/gold-trial.patch
do
  git apply --check "$mission_dir/$patch"
  git apply "$mission_dir/$patch"
done
git diff --check
