#!/usr/bin/env bash
set -euo pipefail
recipe="${1:?Recette mobile à assembler}"
production="${2:?Sources mobiles de production}"
bash "$recipe/prepare-production-video.sh" "$production"
python3 "$recipe/prepare_novatube_video.py"
bash "$recipe/free/prepare-sources.sh"
flutter create --no-pub --platforms=android --org com.manzilionellm.tvking --project-name tv_king .
cp "$recipe/novatube_video/production-pubspec.lock.fixture" pubspec.lock
flutter pub get --enforce-lockfile
flutter gen-l10n
