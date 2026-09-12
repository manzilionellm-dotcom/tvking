#!/usr/bin/env bash
# =========================================================
#  release_tag.sh — SUR QUEL CANAL CETTE BRANCHE PUBLIE-T-ELLE ?
# =========================================================
#  Compagnon de ci/build_label.sh. Il répond à une seule question :
#  « la branche X publie sur quelle release ? »
#
#  POURQUOI IL EXISTE (07/09/2026). Le numéro lisible (buildLabel) se
#  calcule AVANT de compiler, pour le graver dans l'APK. Il faut donc
#  connaître le canal (où l'on publie) dès le début. Le précédent, lui,
#  n'est plus « le numéro de CE canal » : ci/build_label.sh prend le
#  max de toute la famille (12/09/2026). Or la correspondance
#  branche → canal vivait au milieu de l'étape de publication, tout à
#  la fin du workflow.
#
#  La recopier au début aurait créé deux vérités : le jour où l'une
#  change et pas l'autre, l'app afficherait un numéro et le serveur en
#  publierait un autre. Le support ne saurait plus quoi croire. Une
#  seule implémentation, deux appelants.
#
#  USAGE :
#      TAG=$(ci/release_tag.sh phone <nom-de-branche>)
#      TAG=$(ci/release_tag.sh tv    <nom-de-branche>)
#
#  ---------------------------------------------------------
#  LA RÈGLE, ET POURQUOI ELLE EST AINSI
#  ---------------------------------------------------------
#  « prod » et « tv-prod » sont les canaux que le lien CLIENT sert. Ils
#  ne sont publiés QUE par la branche maison mère : aucune autre branche
#  ne peut les écraser. Les branches de correctif ont leur propre canal
#  dédié, pour qu'un essai ne parte jamais chez un client. Tout le reste
#  atterrit sur le canal générique.
# =========================================================
set -euo pipefail

KIND="${1:?usage: release_tag.sh <phone|tv> <branche>}"
BRANCH="${2:?usage: release_tag.sh <phone|tv> <branche>}"

case "$KIND" in
  phone)
    case "$BRANCH" in
      claude/maison-mere-phone)                      echo 'prod' ;;
      claude/iptv-chromecast-cast-WeAyo)             echo 'cast-fix-latest' ;;
      claude/phone-app-language-translation-ornt8n)  echo 'phone-i18n-latest' ;;
      # CANAL DE TÉLÉCHARGEMENT DIRECT (07/09/2026). Le propriétaire veut
      # un lien téléphone qui TÉLÉCHARGE, au lieu de renvoyer au Play
      # Store : « le lien va sur Play Store, je veux un qui télécharge ».
      # Cette branche est celle qui porte le travail réel, donc c'est
      # elle qui alimente ce canal. Il est SÉPARÉ de « prod » : le lien
      # client historique continue de mener au magasin, seul le nouveau
      # /apk sert ce canal-ci.
      claude/7motion-android-tv-compat-e0rtyp)       echo 'phone-latest' ;;
      *)                                             echo 'latest' ;;
    esac
    ;;
  tv)
    case "$BRANCH" in
      claude/maison-mere-phone)                      echo 'tv-prod' ;;
      claude/iptv-chromecast-cast-WeAyo)             echo 'cast-fix-tv-latest' ;;
      *)                                             echo 'tv-latest' ;;
    esac
    ;;
  *)
    echo "release_tag.sh : type inconnu « $KIND » (attendu phone ou tv)" >&2
    exit 1
    ;;
esac
