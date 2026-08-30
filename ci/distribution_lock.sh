#!/usr/bin/env bash
# =========================================================
#  distribution_lock.sh — Le verrou de publication
# =========================================================
#  POURQUOI CE FICHIER EXISTE (30/08/2026).
#
#  Demande du propriétaire, mot pour mot : « il faut qu'on crée un code
#  qui protège tout : les liens des dernières builds, c'est moi qui
#  donne le code. N'importe qui ne peut pas changer ça. Même si c'est
#  moi qui ai donné le prompt. »
#
#  Ce dernier morceau est le plus important, et c'est celui qu'un
#  développeur oublie : la protection doit tenir MÊME CONTRE UNE
#  DEMANDE MAL FORMULÉE DU PROPRIÉTAIRE LUI-MÊME. Un assistant à qui on
#  dit « change le lien » le changera. Ce script fait qu'un tel
#  changement NE PEUT PAS ÊTRE PUBLIÉ sans la phrase secrète.
#
#  ---------------------------------------------------------
#  CE QUE CE VERROU FAIT — ET CE QU'IL NE FAIT PAS
#  ---------------------------------------------------------
#  IL FAIT : aucune release ne part si une valeur de distribution a
#  changé sans avoir été RESCELLÉE avec la phrase secrète. Le build
#  échoue, bruyamment, avant toute publication. Les box installées
#  continuent de recevoir leurs mises à jour du bon endroit.
#
#  IL NE FAIT PAS : empêcher quelqu'un ayant les droits d'écriture sur
#  le dépôt de modifier le code. Aucun script ne peut faire ça — il
#  suffirait de supprimer ce script. La seule barrière contre une
#  PERSONNE, ce sont les permissions GitHub et la protection de
#  branche. Ce sont des réglages, pas du code. Dire le contraire serait
#  vendre une serrure en carton.
#
#  Autrement dit : ce verrou arrête les ACCIDENTS et les changements
#  faits sans y penser — de loin la cause la plus fréquente d'un lien
#  cassé — pas un adversaire déterminé qui a déjà les clés du dépôt.
#
#  ---------------------------------------------------------
#  COMMENT ÇA MARCHE
#  ---------------------------------------------------------
#  `ci/distribution.lock` contient les valeurs protégées EN CLAIR (pour
#  qu'on puisse les lire et comprendre) plus une empreinte `seal=`.
#
#  L'empreinte est un HMAC-SHA256 des valeurs, calculé avec une phrase
#  secrète que SEUL le propriétaire connaît (secret GitHub
#  `DIST_LOCK_PASSPHRASE`).
#
#    • Les valeurs n'ont pas bougé  -> vérification OK, AUCUN secret
#      requis. Les builds ordinaires ne sont jamais gênés.
#    • Une valeur a changé          -> l'empreinte ne correspond plus.
#      Le build ÉCHOUE. Pour repartir, il faut resceller — donc
#      connaître la phrase.
#    • Quelqu'un modifie AUSSI le fichier .lock pour qu'il colle       ->
#      il ne peut pas recalculer `seal=` sans la phrase. Le build
#      échoue quand même.
#
#  ---------------------------------------------------------
#  UTILISATION
#  ---------------------------------------------------------
#    ci/distribution_lock.sh verify        # ce que fait la CI
#    ci/distribution_lock.sh show          # voir les valeurs actuelles
#    DIST_LOCK_PASSPHRASE='…' ci/distribution_lock.sh seal
#                                          # resceller après un
#                                          # changement VOULU
# =========================================================
set -euo pipefail

cd "$(dirname "$0")/.."
LOCK="ci/distribution.lock"

# ---------------------------------------------------------
#  Les valeurs protégées, lues À LA SOURCE
# ---------------------------------------------------------
#  On les relit dans les VRAIS fichiers à chaque fois. Recopier une
#  valeur dans le verrou aurait produit un verrou qui se vérifie
#  lui-même — et ne protège rien.
#
#  Chaque `|| echo INTROUVABLE` compte : si un jour quelqu'un renomme
#  ou supprime la ligne surveillée, la valeur devient « INTROUVABLE »,
#  l'empreinte casse, et le build s'arrête. Une valeur qui DISPARAÎT
#  est aussi grave qu'une valeur qui change.
current_values() {
  # 1. Le canal de mise à jour compilé DANS l'application (repli).
  echo -n "update_tag_code="
  grep -o "TV_UPDATE_TAG', defaultValue: '[^']*'" lib/core/update/update_service.dart \
    | sed "s/.*defaultValue: '//; s/'//" || echo INTROUVABLE

  # 2. Le canal passé par la chaîne de build.
  echo -n "update_tag_ci="
  grep -o 'TV_UPDATE_TAG=[a-zA-Z0-9._-]*' .github/workflows/build-seventv.yml \
    | head -1 | sed 's/.*=//' || echo INTROUVABLE

  # 3. L'APK que le serveur sert derrière le lien public.
  echo -n "apk_url="
  grep -o "releases/download/[a-zA-Z0-9._-]*/seven-tv.apk" cloudflare/worker.js \
    | head -1 || echo INTROUVABLE

  # 4. Le lien public lui-même. Si cette route disparaît, tous les
  #    clients perdent le téléchargement.
  echo -n "public_route="
  grep -c "segments\[0\].toLowerCase() === 'tv'" cloudflare/worker.js \
    | sed 's/^0$/INTROUVABLE/' || echo INTROUVABLE

  # 5. La clé qui signe l'app. Si elle change, Android REFUSE toutes
  #    les mises à jour des box déjà installées.
  echo -n "keystore_sha256="
  sha256sum ci/defew-debug.keystore | cut -d' ' -f1 || echo INTROUVABLE

  # 6. L'identité de l'application. La changer crée une SECONDE app au
  #    lieu de mettre à jour la première.
  echo -n "app_id_tv="
  grep -o 'com\.sevenmotion\.tv\.seven_tv' .github/workflows/build-seventv.yml \
    | head -1 || echo INTROUVABLE
}

canonical() { current_values | sed 's/[[:space:]]*$//'; }

seal_of() {
  local pass="$1"
  canonical | openssl dgst -sha256 -hmac "$pass" -r | cut -d' ' -f1
}

case "${1:-verify}" in
  show)
    canonical
    ;;

  seal)
    if [ -z "${DIST_LOCK_PASSPHRASE:-}" ]; then
      echo "ERREUR : DIST_LOCK_PASSPHRASE n'est pas fourni." >&2
      echo "Sceller sans la phrase secrète n'aurait aucun sens." >&2
      exit 2
    fi
    {
      echo "# ============================================="
      echo "#  distribution.lock — VALEURS PROTÉGÉES"
      echo "# ============================================="
      echo "#  Ne PAS modifier à la main. Toute modification"
      echo "#  d'une de ces valeurs fait ÉCHOUER la publication"
      echo "#  tant qu'elle n'a pas été rescellée avec la phrase"
      echo "#  secrète du propriétaire :"
      echo "#"
      echo "#    DIST_LOCK_PASSPHRASE='…' ci/distribution_lock.sh seal"
      echo "#"
      echo "#  Scellé le $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "# ============================================="
      canonical
      echo "seal=$(seal_of "$DIST_LOCK_PASSPHRASE")"
    } > "$LOCK"
    echo "Scellé : $LOCK"
    ;;

  verify)
    if [ ! -f "$LOCK" ]; then
      echo "::error title=Verrou absent::$LOCK n'existe pas. La publication est bloquée."
      exit 1
    fi
    #  ÉTAPE 1 — comparer les valeurs EN CLAIR. Elle ne demande AUCUN
    #  secret : c'est ce qui permet aux builds ordinaires de passer
    #  sans que la phrase traîne quelque part.
    if ! diff <(canonical) <(grep -v '^#' "$LOCK" | grep -v '^seal=' | grep -v '^$') >/dev/null; then
      echo "::error title=Valeur de distribution modifiee::Une valeur protegee a change."
      echo "--- ce que le verrou attend ---"
      grep -v '^#' "$LOCK" | grep -v '^seal=' | grep -v '^$'
      echo "--- ce qu'il y a dans le depot ---"
      canonical
      echo
      echo "Si ce changement est VOULU, resceller avec la phrase secrete :"
      echo "  DIST_LOCK_PASSPHRASE='…' ci/distribution_lock.sh seal"
      exit 1
    fi
    #  ÉTAPE 2 — vérifier l'empreinte, quand la phrase est disponible.
    #  Sans elle on ne peut pas prouver que le fichier .lock n'a pas
    #  été réécrit à la main : on le DIT, au lieu de laisser croire
    #  que tout est vérifié.
    if [ -n "${DIST_LOCK_PASSPHRASE:-}" ]; then
      expected=$(grep '^seal=' "$LOCK" | sed 's/^seal=//')
      actual=$(seal_of "$DIST_LOCK_PASSPHRASE")
      if [ "$expected" != "$actual" ]; then
        echo "::error title=Verrou falsifie::le fichier .lock a ete reecrit sans la phrase secrete."
        exit 1
      fi
      echo "Verrou VÉRIFIÉ (valeurs + empreinte)."
    else
      echo "::warning title=Empreinte non verifiee::DIST_LOCK_PASSPHRASE absent — les valeurs sont conformes, mais l'authenticite du verrou n'a pas pu etre prouvee. Poser le secret pour armer completement le verrou."
      echo "Valeurs conformes."
    fi
    ;;

  *)
    echo "usage: $0 {verify|seal|show}" >&2
    exit 2
    ;;
esac
