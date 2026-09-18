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
      # Branche de travail actuelle : le sideload téléphone doit
      # recevoir CE build, signé officiel (demande 16/09).
      claude/instant-m3u-activate)                    echo 'phone-latest' ;;
      # =========================================================
      #  LE CANAL TÉLÉPHONE ÉTAIT GELÉ (18/09/2026)
      # =========================================================
      #  Mesuré, pas supposé : `phone-latest/version.json` annonçait
      #  encore 198870 pendant que la TV en était à 198875. Cinq
      #  numéros d'écart — donc cinq builds téléphone compilés, verts,
      #  et jamais arrivés sur un seul appareil.
      #
      #  La cause est cette liste-ci. Le travail a changé de branche ;
      #  personne n'a pensé à l'y réinscrire, et rien n'est prévu pour
      #  le dire. La branche est alors tombée sur « latest », un canal
      #  générique que l'app téléphone ne regarde pas. Aucune erreur,
      #  aucune alerte : exactement la règle n°2 de la maison, « vert
      #  ne veut pas dire livré ».
      #
      #  Le correctif du juge des empreintes — celui qui fait qu'une
      #  liste poussée depuis le panel arrive sur le téléphone — était
      #  dans le lot bloqué. On corrigeait la panne que le
      #  propriétaire signalait, et le correctif ne partait nulle part.
      #
      #  ⚠ CETTE LISTE RECOMMENCERA. Elle demande à un humain de se
      #  souvenir d'y revenir à chaque changement de branche, et c'est
      #  déjà arrivé deux fois. La vraie sortie serait que `phone` ait
      #  le même défaut que `tv` (un canal par défaut plutôt qu'une
      #  liste blanche) — mais ça changerait ce que reçoivent de VRAIS
      #  clients depuis n'importe quelle branche : c'est une décision
      #  du propriétaire, pas un choix de passage.
      claude/retour-13sept-notifications)            echo 'phone-latest' ;;
      *)
        # =========================================================
        #  DIRE QUAND ON NE PUBLIE NULLE PART (18/09/2026)
        # =========================================================
        #  « latest » est un canal générique : l'app téléphone ne le
        #  regarde pas. Tomber ici veut donc dire « ce build ne partira
        #  sur AUCUN appareil » — et jusqu'à aujourd'hui ça se passait
        #  sans un mot, avec un ✅ vert au bout. Cinq builds ont été
        #  perdus comme ça.
        #
        #  On l'écrit sur la SORTIE D'ERREUR : les appelants capturent
        #  `$(...)`, c'est-à-dire la sortie standard uniquement. Le
        #  canal renvoyé est donc strictement inchangé — on ajoute une
        #  phrase dans le journal, on ne touche pas à la mécanique.
        #
        #  Une branche `test/**` tombe ici elle aussi, et c'est VOULU :
        #  elle ne doit rien publier. L'avertissement confirme alors
        #  que la protection joue, au lieu de laisser deviner.
        echo "release_tag.sh : branche « $BRANCH » → canal « latest »." >&2
        echo "  ⚠ L'app TÉLÉPHONE lit « phone-latest », pas « latest »." >&2
        echo "  ⚠ Ce build ne parviendra donc à AUCUN téléphone." >&2
        echo "  Si c'est une branche de travail, inscris-la dans la" >&2
        echo "  liste « phone » de ci/release_tag.sh. Si c'est un essai," >&2
        echo "  c'est le comportement attendu." >&2
        echo 'latest'
        ;;
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
