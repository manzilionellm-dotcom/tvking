#!/usr/bin/env bash
set -euo pipefail
mission_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Composant commun, après tous les correctifs de la dernière version mobile.
for file in \
  lib/features/subscription/data/gold_trial_backend.dart \
  lib/features/subscription/data/gold_trial_controller.dart \
  lib/features/subscription/presentation/gold_trial_card.dart \
  test/features/subscription/gold_trial_backend_test.dart \
  test/features/subscription/gold_trial_controller_test.dart \
  test/features/subscription/gold_trial_card_test.dart
do
  cp "$mission_dir/android-app/$file" "$file"
done
cp "$mission_dir/android-app/ci/mobile/gold_trial_device_test.dart.template" integration_test/gold_trial_device_test.dart
git apply --check "$mission_dir/android-app/ci/mobile/trial-source-privacy.patch"
git apply "$mission_dir/android-app/ci/mobile/trial-source-privacy.patch"
git apply --check "$mission_dir/android-app/ci/mobile/panel-delivery.patch"
git apply "$mission_dir/android-app/ci/mobile/panel-delivery.patch"

# La base téléphone possède sa propre configuration réseau : lui appliquer
# aussi le changement de domaine avant de compiler le composant d'essai commun.
git apply --check "$mission_dir/android-app/ci/mobile/backend-url.patch"
git apply "$mission_dir/android-app/ci/mobile/backend-url.patch"
mkdir -p test/core/app
cp "$mission_dir/android-app/test/core/app/backend_url_test.dart" test/core/app/backend_url_test.dart
