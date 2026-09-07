#!/usr/bin/env bash
# =========================================================
#  build_label.sh — LE NUMÉRO DE VERSION QU'ON DICTE AU TÉLÉPHONE
# =========================================================
#  Décision du propriétaire (07/09/2026), à appliquer sur TOUTES les
#  apps de la maison — téléphone, box, et celles qui viendront :
#
#      « on fait mon année de naissance plus 1 pour le premier build ;
#        quand on fera la mise à jour ce sera 19882 »
#
#  Donc : 19881, 19882, 19883… Un nombre court, qu'on lit à voix haute
#  au client sans se tromper, et qu'on compare d'un coup d'œil.
#
#  ---------------------------------------------------------
#  POURQUOI DEUX NUMÉROS, ET PAS UN SEUL
#  ---------------------------------------------------------
#  Le `versionCode` d'Android doit être STRICTEMENT CROISSANT À VIE.
#  Android refuse d'installer un paquet dont le numéro est inférieur à
#  celui déjà installé, et notre vérificateur de mise à jour conclurait
#  « déjà à jour » pour toujours. Le parc porte déjà des horodatages
#  (1788127315 et voisins) : on ne peut plus redescendre, jamais.
#
#  D'où la séparation, et elle est définitive :
#    • versionCode  → pour ANDROID. Un horodatage. Personne ne le lit.
#    • buildLabel   → pour LES HUMAINS. 1988 + compteur. Affiché en
#                     grand dans « À propos », dicté au téléphone.
#
#  ---------------------------------------------------------
#  IL MONTE À CHAQUE PUBLICATION, PAS À CHAQUE COMPILATION
#  ---------------------------------------------------------
#  Le compteur est lu depuis le dernier `version.json` RÉELLEMENT
#  publié sur le canal, pas depuis un compteur du serveur de build.
#
#  Sans ça, trois pushes sans publication feraient sauter le numéro de
#  19881 à 19884, et le client verrait des numéros manquants — il
#  croirait avoir raté des mises à jour. Corollaire utile : une
#  compilation qui ne publie rien ne consomme aucun numéro, le prochain
#  build recalcule exactement le même.
#
#  ---------------------------------------------------------
#  USAGE
#  ---------------------------------------------------------
#      NEW_LABEL=$(ci/build_label.sh <owner/repo> <tag-de-la-release>)
#
#  Exemple :
#      ci/build_label.sh manzilionellm-dotcom/tvking seventv-latest
#
#  Écrit le nouveau numéro sur la sortie standard, et RIEN d'autre
#  (les explications partent sur la sortie d'erreur, pour ne pas
#  polluer la capture). Ne échoue jamais : sans réseau ou sans
#  manifeste publié, il rend « 19881 ».
#
#  ---------------------------------------------------------
#  POUR LE PROCHAIN QUI AJOUTE UNE APP
#  ---------------------------------------------------------
#  Appelle CE script. Ne recopie pas le calcul dans ton workflow : le
#  jour où l'un des deux dérive, deux apps donneront deux numéros
#  différents pour la même version, et le support ne saura plus quoi
#  croire. Une seule implémentation, autant d'appelants qu'on veut.
# =========================================================
set -euo pipefail

REPO="${1:?usage: build_label.sh <owner/repo> <tag>}"
TAG="${2:?usage: build_label.sh <owner/repo> <tag>}"

#  Le préfixe. Changer cette valeur RENUMÉROTE toute la série : à ne
#  toucher qu'avec l'accord du propriétaire, c'est son année.
PREFIX="${BUILD_LABEL_PREFIX:-1988}"

PREV_LABEL=$(curl -fsSL --max-time 20 \
  "https://github.com/${REPO}/releases/download/${TAG}/version.json" \
  2>/dev/null | tr -d ' \n' \
  | grep -oE '"buildLabel":"[0-9]*"' | grep -oE '[0-9]+' || true)

#  On retire le préfixe pour retrouver le compteur seul. Une valeur
#  absente, vide ou non numérique repart de zéro — donc du premier
#  numéro de la série, jamais d'un nombre inventé.
PREV_N="${PREV_LABEL#"$PREFIX"}"
case "$PREV_N" in
  '' | *[!0-9]*) PREV_N=0 ;;
esac

NEW_LABEL="${PREFIX}$((PREV_N + 1))"

echo "build_label: canal=${TAG} precedent=${PREV_LABEL:-aucun} nouveau=${NEW_LABEL}" >&2
printf '%s\n' "$NEW_LABEL"
