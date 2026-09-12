#!/usr/bin/env bash
# =========================================================
#  build_label_test.sh — Le numéro de maison est UNIQUE
# =========================================================
#  POURQUOI CE TEST EXISTE. Le compteur vivait par canal : publier
#  la TV lisait seventv-latest, publier le téléphone lisait
#  phone-latest, et les deux séries divergeaient (mesuré : 198818
#  vs 198827). Ce script fige la règle du propriétaire :
#
#      prochain = PREFIX + (max familial + 1)
#
#  Il ne tape PAS GitHub. Il pose des version.json factices dans un
#  dossier temporaire et demande à build_label.sh de les lire via
#  BUILD_LABEL_FIXTURE_DIR — le même chemin de code que la CI, sans
#  le réseau. Un 404 se simule en n'écrivant pas le fichier.
#
#  Exécution :
#      bash -n ci/build_label.sh && bash ci/build_label_test.sh
#
#  Dry-run réel (lecture seule, ne publie rien) :
#      ci/build_label.sh manzilionellm-dotcom/tvking seventv-latest
# =========================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/ci/build_label.sh"

pass=0
fail=0
ok() {
  if [ "$1" = 1 ]; then
    pass=$((pass + 1))
    echo "PASS  $2"
  else
    fail=$((fail + 1))
    echo "FAIL  $2"
  fi
}

#  Syntaxe d'abord : un script que bash refuse de parser ne doit
#  jamais arriver en CI, même si toutes les assertions plus bas
#  seraient vertes.
if bash -n "$SCRIPT"; then
  ok 1 "bash -n ci/build_label.sh"
else
  ok 0 "bash -n ci/build_label.sh"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

poser() {
  local canal="$1"
  local label="$2"
  mkdir -p "${WORKDIR}/${canal}"
  #  Espaces volontaires : le script doit les retirer, comme un
  #  version.json pretty-print de la CI.
  cat > "${WORKDIR}/${canal}/version.json" <<EOF
{
  "versionCode": 1,
  "buildLabel": "${label}",
  "mandatory": false
}
EOF
}

appeler() {
  local tag="$1"
  BUILD_LABEL_FIXTURE_DIR="$WORKDIR" \
    BUILD_LABEL_FAMILY="${BUILD_LABEL_FAMILY:-phone-latest seventv-latest windows-latest}" \
    "$SCRIPT" manzilionellm-dotcom/tvking "$tag" 2>/dev/null
}

# ---------------------------------------------------------
#  Cas mesuré le 12/09/2026 : TV 198818 + téléphone 198827.
#  Quel que soit le canal qu'on publie, le prochain est 198828
#  — pas 198819 (l'ancien calcul TV) ni 198828 seulement pour
#  le téléphone.
# ---------------------------------------------------------
poser phone-latest 198827
poser seventv-latest 198818
poser windows-latest 19888

got="$(appeler seventv-latest)"
ok "$([[ "$got" == 198828 ]] && echo 1 || echo 0)" \
  "TV 198818 + phone 198827 + win 19888, publish TV → 198828 (pas 198819) [got=${got}]"

got="$(appeler phone-latest)"
ok "$([[ "$got" == 198828 ]] && echo 1 || echo 0)" \
  "même famille, publish téléphone → 198828 aussi [got=${got}]"

got="$(appeler windows-latest)"
ok "$([[ "$got" == 198828 ]] && echo 1 || echo 0)" \
  "même famille, publish Windows → 198828 aussi [got=${got}]"

#  Un canal hors liste participe quand même (premier publish d'une
#  app nouvelle). Ici tizen n'a pas de manifeste : le max reste 198827.
got="$(appeler tizen-latest)"
ok "$([[ "$got" == 198828 ]] && echo 1 || echo 0)" \
  "canal hors liste sans manifeste → max familial + 1 [got=${got}]"

#  Le même canal hors liste, S'IL a un numéro plus grand, gagne.
poser tizen-latest 198830
got="$(appeler tizen-latest)"
ok "$([[ "$got" == 198831 ]] && echo 1 || echo 0)" \
  "canal hors liste plus avancé (198830) → 198831 [got=${got}]"

# ---------------------------------------------------------
#  Canal sans version.json : ignoré, comme aujourd'hui « aucun ».
# ---------------------------------------------------------
rm -rf "${WORKDIR}/windows-latest"
got="$(appeler windows-latest)"
ok "$([[ "$got" == 198831 ]] && echo 1 || echo 0)" \
  "windows sans version.json : ignore, max reste tizen 198830 → 198831 [got=${got}]"

#  Manifeste sans buildLabel (cas réel du canal `test`) : ignore.
mkdir -p "${WORKDIR}/test"
printf '%s\n' '{"versionCode":1,"url":"x"}' > "${WORKDIR}/test/version.json"
BUILD_LABEL_FIXTURE_DIR="$WORKDIR" BUILD_LABEL_FAMILY="test" \
  got_test="$("$SCRIPT" manzilionellm-dotcom/tvking test 2>/dev/null)"
ok "$([[ "$got_test" == 19881 ]] && echo 1 || echo 0)" \
  "manifeste sans buildLabel → 19881 [got=${got_test}]"

# ---------------------------------------------------------
#  Famille vide / tout absent → 19881 (fail-open historique).
# ---------------------------------------------------------
EMPTY="$(mktemp -d)"
got="$(BUILD_LABEL_FIXTURE_DIR="$EMPTY" BUILD_LABEL_FAMILY="phone-latest seventv-latest" \
  "$SCRIPT" manzilionellm-dotcom/tvking seventv-latest 2>/dev/null)"
ok "$([[ "$got" == 19881 ]] && echo 1 || echo 0)" \
  "aucun manifeste → 19881 [got=${got}]"
rmdir "$EMPTY"

# ---------------------------------------------------------
#  Fail-open réseau : une base injoignable ne doit PAS faire
#  tomber le build. Même contrat qu'avant (« Ne échoue jamais »).
# ---------------------------------------------------------
got="$(BUILD_LABEL_RELEASE_BASE="http://127.0.0.1:1" \
  BUILD_LABEL_FAMILY="seventv-latest" \
  "$SCRIPT" manzilionellm-dotcom/tvking seventv-latest 2>/dev/null)"
ok "$([[ "$got" == 19881 ]] && echo 1 || echo 0)" \
  "sans réseau → 19881 [got=${got}]"

# ---------------------------------------------------------
#  Format 1988N : on ne casse ni le préfixe, ni le passage à
#  deux chiffres (19889 → 198810, pas 19890).
# ---------------------------------------------------------
rm -rf "${WORKDIR:?}/"*
poser seventv-latest 19889
got="$(BUILD_LABEL_FIXTURE_DIR="$WORKDIR" BUILD_LABEL_FAMILY="seventv-latest" \
  "$SCRIPT" manzilionellm-dotcom/tvking seventv-latest 2>/dev/null)"
ok "$([[ "$got" == 198810 ]] && echo 1 || echo 0)" \
  "19889 + 1 = 198810 (pas 19890) [got=${got}]"

#  stdout = le numéro SEUL (une ligne), pour que $(...) des
#  workflows ne capture pas un commentaire.
stdout_lines="$(BUILD_LABEL_FIXTURE_DIR="$WORKDIR" BUILD_LABEL_FAMILY="seventv-latest" \
  "$SCRIPT" manzilionellm-dotcom/tvking seventv-latest 2>/dev/null | wc -l)"
ok "$([[ "$stdout_lines" -eq 1 ]] && echo 1 || echo 0)" \
  "stdout = une seule ligne [lines=${stdout_lines}]"

echo
echo "${pass} pass, ${fail} fail"
[ "$fail" -eq 0 ]
