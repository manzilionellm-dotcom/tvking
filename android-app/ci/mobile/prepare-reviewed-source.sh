#!/usr/bin/env bash
# La recette mobile validée reste figée : sa branche contient aussi du code
# serveur et TV, qui ne doit pas être fusionné pour une publication téléphone.
# Le même arbre téléphone est préparé pour les tests et pour le bundle Play.
set -euo pipefail
recipe_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reviewed_dir="$(cd "${1:?dossier du code mobile revu manquant}" && pwd)"
python3 - "$recipe_dir/reviewed-source.json" "$reviewed_dir" <<'PY'
import json, subprocess, sys
expected = json.load(open(sys.argv[1]))
actual = subprocess.check_output(['git', '-C', sys.argv[2], 'rev-parse', 'HEAD'], text=True).strip()
base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
assert actual == expected['sourceSha'], 'Le code mobile diffère de la revue'
assert base == expected['mobileBaseSha'], 'La base téléphone diffère de la revue'
PY
bash "$reviewed_dir/android-app/ci/mobile/prepare-gold-trial-test.sh"
git diff --check
