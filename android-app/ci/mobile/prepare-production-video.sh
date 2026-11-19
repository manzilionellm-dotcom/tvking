#!/usr/bin/env bash
# Rejoue la recette du bundle actuellement distribué (1792467150).
# Le SHA a été lu dans libapp.so de l'AAB fourni par Google Play.
set -euo pipefail
recipe="$(cd "$(dirname "$0")" && pwd)"
source_dir="$(cd "${1:?recette Google Play requise}" && pwd)"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == 8ea5a55075d8b5ad334643b780067c486a917f61 ]]
[[ "$(git rev-parse HEAD)" == 37fdf3305c5de9d35e20fd6567df38008fc7a7ee ]]
for patch in patches/mobile-{sport-gratuit,radio,panel-sync,identity,stability}.patch \
    android-app/ci/mobile/{adult-classification,player-terminal-fallback,mobile-back-gestures,football-upcoming,player-session-handoff}.patch; do
  git apply "$source_dir/$patch"
done
git diff --check
# Le bundle de production ne doit pas résoudre de nouvelles versions de paquets.
cp "$recipe/novatube_video/production-pubspec.lock.fixture" pubspec.lock
