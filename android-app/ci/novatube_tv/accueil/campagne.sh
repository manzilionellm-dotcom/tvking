#!/usr/bin/env bash
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
: "${NOVA_WELCOME_OUT:?Dossier de preuves (chemin absolu) requis}"
case "$NOVA_WELCOME_OUT" in /*) ;; *) exit 2;; esac
# Lancer sur une COPIE de android-app : la préparation adapte les traductions et le mot-symbole.
test -f ci/novatube_tv/prepare_build.py
export DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true CI=true BOT=true
python3 ci/novatube_tv/prepare_build.py
flutter --suppress-analytics gen-l10n
cp "$here/accueil_tv_test.dart" test/novatube_tv/accueil_tv_test.dart
flutter --suppress-analytics test --no-pub --concurrency=1 --reporter expanded \
  --dart-define=NOVATUBE_TV=true test/novatube_tv/accueil_tv_test.dart
