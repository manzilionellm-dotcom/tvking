#!/usr/bin/env bash
# Dans l'arbre mobile assemblé, avant les tests Play ou la création de l'AAB.
set -euo pipefail
recipe="$(cd "$(dirname "$0")" && pwd)"
git apply "$recipe/phone.patch"
python3 "$recipe/ads/prepare_ads.py" dart
git apply "$recipe/performance.patch"
git apply "$recipe/bootstrap-optional-diagnostics.patch"
git apply "$recipe/catalogue-scroll.patch"
git apply "$recipe/swipe-feed.patch"
