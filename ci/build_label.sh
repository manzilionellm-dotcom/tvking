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
#  POURQUOI UNE FAMILLE UNIQUE, PAS UN COMPTEUR PAR CANAL
#  ---------------------------------------------------------
#  Demande du propriétaire (12/09/2026), mot pour mot :
#
#      « Code que toutes les apps suivent CE numéro »
#
#  Téléphone, box 7 MOTION TV, DeFew TV, Windows, Samsung, LG : ce sont
#  des frères. Le support dicte UN numéro au client. Si chaque canal
#  comptait tout seul, on se retrouvait avec une TV à 198818 et un
#  téléphone à 198827 — deux « dernières versions » qui n'ont plus rien
#  à voir. Personne ne sait plus lequel croire.
#
#  Donc le nouveau label n'est PAS « le numéro de CE canal + 1 ».
#  C'est :
#
#      PREFIX + (max(buildLabel connus sur TOUS les canaux famille) + 1)
#
#  Le TAG passé en argument reste le canal qu'on PUBLIE (pour les logs,
#  pour que l'appelant sache où il écrit). Le précédent, lui, vient du
#  MAX familial. Publier la TV après un téléphone plus avancé reprend
#  la série là où le téléphone l'a laissée — et inversement.
#
#  Le verdict « à jour ? » du panel (cloudflare/app_versions.js) continue
#  de comparer CANAL PAR CANAL : chaque appareil lit SON manifeste. Ce
#  qui change ici, ce sont uniquement les NUMÉROS qu'on grave : ils
#  suivent la même série croissante. Une box à 198828 et un téléphone
#  à 198828 portent le même numéro de maison, même s'ils n'ont pas
#  le même paquet.
#
#  ---------------------------------------------------------
#  IL MONTE À CHAQUE PUBLICATION, PAS À CHAQUE COMPILATION
#  ---------------------------------------------------------
#  Le max est lu depuis les `version.json` RÉELLEMENT publiés, pas
#  depuis un compteur du serveur de build.
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
#  Vérifier (rien n'est publié — lecture seule) :
#      bash -n ci/build_label.sh
#      bash ci/build_label_test.sh
#      ci/build_label.sh manzilionellm-dotcom/tvking seventv-latest
#
#  Variables d'environnement (tests / urgence, pas la CI normale) :
#      BUILD_LABEL_PREFIX        préfixe, défaut 1988
#      BUILD_LABEL_FAMILY        liste d'espaces qui remplace la famille
#      BUILD_LABEL_FIXTURE_DIR   lit <dir>/<canal>/version.json sans réseau
#      BUILD_LABEL_RELEASE_BASE  base d'URL, défaut GitHub releases/download
#
#  ---------------------------------------------------------
#  POUR LE PROCHAIN QUI AJOUTE UNE APP
#  ---------------------------------------------------------
#  1. Appelle CE script. Ne recopie pas le calcul dans ton workflow :
#     le jour où l'un des deux dérive, deux apps donneront deux numéros
#     différents pour la même version, et le support ne saura plus quoi
#     croire. Une seule implémentation, autant d'appelants qu'on veut.
#  2. Ajoute le canal dans FAMILLE_CANAUX ci-dessous. Sinon son numéro
#     ne participe pas au max, et les apps divergent à nouveau — c'est
#     exactement le bug que ce script existe pour empêcher.
# =========================================================
set -euo pipefail

REPO="${1:?usage: build_label.sh <owner/repo> <tag>}"
TAG="${2:?usage: build_label.sh <owner/repo> <tag>}"

#  Le préfixe. Changer cette valeur RENUMÉROTE toute la série : à ne
#  toucher qu'avec l'accord du propriétaire, c'est son année.
PREFIX="${BUILD_LABEL_PREFIX:-1988}"

# ---------------------------------------------------------
#  LA FAMILLE — UNE liste, lue par TOUS les publish
# ---------------------------------------------------------
#  POURQUOI elle existe : le propriétaire veut qu'un seul numéro
#  traverse toute la maison. Si on ne lisait que le TAG passé, chaque
#  workflow redeviendrait un compteur isolé (TV 198818, téléphone
#  198827, Windows 19888 — mesuré le 12/09/2026).
#
#  D'où viennent ces noms, pour ne pas en inventer :
#    • AGENTS.md « La famille, et qui suit quoi »
#    • ci/release_tag.sh (tous les echo de canal)
#    • cloudflare/app_versions.js → VERSION_CHANNELS
#    • build-*.yml (tags réellement publiés)
#
#  Un canal SANS version.json est ignoré, comme aujourd'hui « aucun ».
#  On n'échoue pas : un frère pas encore né ne doit pas bloquer les
#  autres. `prod` est gardé même s'il a été vidé : c'est encore le
#  canal que le téléphone interroge (update_service.dart) — le jour
#  où un manifeste y revient, il rentre dans le max tout seul.
#
#  tv-fix-latest n'est plus publié comme app neuve, mais le pont de
#  migration de build-tv.yml peut encore y poser un version.json :
#  s'il porte un buildLabel, il fait partie de la série.
#
#  cinema-test / prive-latest / play-aab / phone-compare ne sont PAS
#  la famille : ce sont des essais ou des paquets magasin. Les y
#  mettre ferait monter le numéro du client pour un build que
#  personne n'installera.
# ---------------------------------------------------------
FAMILLE_CANAUX=(
  phone-latest          # Téléphone — sideload /7motion (AGENTS.md)
  prod                  # Téléphone — canal lu par l'app (VERSION_CHANNELS.mobile)
  latest                # Téléphone — repli release_tag.sh (branche inconnue)
  cast-fix-latest       # Téléphone — correctif Cast (release_tag.sh)
  phone-i18n-latest     # Téléphone — branche i18n (release_tag.sh)
  seventv-latest        # Box 7 MOTION TV (AGENTS.md + VERSION_CHANNELS.tv)
  tv-latest             # DeFew TV — canal générique (release_tag.sh)
  tv-prod               # DeFew TV — maison mère (release_tag.sh)
  cast-fix-tv-latest    # DeFew TV — correctif Cast (release_tag.sh)
  tv-fix-latest         # DeFew TV — ancien canal, pont de migration
  windows-latest        # Windows (AGENTS.md + VERSION_CHANNELS.windows)
  tizen-latest          # Samsung / Tizen (AGENTS.md)
  webos-latest          # LG / webOS (AGENTS.md)
)

#  Surcharge de test : une famille courte, sans toucher à la liste
#  ci-dessus. La CI de production ne définit JAMAIS cette variable.
if [ -n "${BUILD_LABEL_FAMILY:-}" ]; then
  #  word-splitting voulu : la variable est une liste d'espaces.
  #  shellcheck disable=SC2206
  FAMILLE_CANAUX=( ${BUILD_LABEL_FAMILY} )
fi

#  Le canal qu'on publie entre TOUJOURS dans le max, même s'il n'est
#  pas encore dans la liste. Sinon le premier publish d'une app
#  nouvelle ignorerait son propre précédent — et pourrait republier
#  le même numéro par-dessus.
deja_dans_famille=0
for canal in "${FAMILLE_CANAUX[@]}"; do
  if [ "$canal" = "$TAG" ]; then
    deja_dans_famille=1
    break
  fi
done
if [ "$deja_dans_famille" -eq 0 ]; then
  FAMILLE_CANAUX+=("$TAG")
fi

RELEASE_BASE="${BUILD_LABEL_RELEASE_BASE:-https://github.com/${REPO}/releases/download}"

# ---------------------------------------------------------
#  Lire le buildLabel d'UN manifeste, ou rien.
# ---------------------------------------------------------
#  POURQUOI on ne parse pas en JSON « vrai » : jq n'est pas garanti
#  sur le runner, et le format est le nôtre (champ entre guillemets).
#  On garde EXACTEMENT le même grep qu'avant, pour ne pas changer ce
#  qu'on accepte. Un fichier absent, un 404, un manifeste sans
#  buildLabel (ex. l'ancien canal `test`) : on rend vide — « aucun ».
# ---------------------------------------------------------
extraire_label() {
  local brut="$1"
  printf '%s' "$brut" \
    | grep -oE '"buildLabel":"[0-9]*"' \
    | grep -oE '[0-9]+' \
    | head -n1 \
    || true
}

lire_manifeste() {
  local canal="$1"
  if [ -n "${BUILD_LABEL_FIXTURE_DIR:-}" ]; then
    local fichier="${BUILD_LABEL_FIXTURE_DIR}/${canal}/version.json"
    if [ -f "$fichier" ]; then
      tr -d ' \n' < "$fichier" || true
    fi
    return 0
  fi
  curl -fsSL --max-time 12 --connect-timeout 5 \
    "${RELEASE_BASE}/${canal}/version.json" \
    2>/dev/null | tr -d ' \n' \
    || true
}

#  On retire le préfixe pour retrouver le compteur seul. Une valeur
#  absente, vide ou non numérique repart de zéro — donc du premier
#  numéro de la série, jamais d'un nombre inventé.
compteur_depuis_label() {
  local label="$1"
  local n="${label#"$PREFIX"}"
  case "$n" in
    '' | *[!0-9]*) printf '0' ;;
    *)             printf '%s' "$n" ;;
  esac
}

# ---------------------------------------------------------
#  MAX familial. Lecture séquentielle : plus lisible qu'un
#  parallel, et les 404 GitHub répondent en une fraction de
#  seconde. Un canal muet ne bloque pas les autres.
# ---------------------------------------------------------
max_n=0
max_label=""
max_canal=""
resume_famille=""

for canal in "${FAMILLE_CANAUX[@]}"; do
  label="$(extraire_label "$(lire_manifeste "$canal")")"
  if [ -z "$label" ]; then
    echo "build_label:   canal=${canal} precedent=aucun (ignore)" >&2
    continue
  fi
  n="$(compteur_depuis_label "$label")"
  echo "build_label:   canal=${canal} precedent=${label} (compteur=${n})" >&2
  resume_famille="${resume_famille}${resume_famille:+ }${canal}=${label}"
  if [ "$n" -gt "$max_n" ]; then
    max_n="$n"
    max_label="$label"
    max_canal="$canal"
  fi
done

NEW_LABEL="${PREFIX}$((max_n + 1))"

echo "build_label: publie=${TAG} famille_max=${max_label:-aucun} (via ${max_canal:-aucun}) nouveau=${NEW_LABEL}" >&2
if [ -n "$resume_famille" ]; then
  echo "build_label: connus ${resume_famille}" >&2
fi
printf '%s\n' "$NEW_LABEL"
