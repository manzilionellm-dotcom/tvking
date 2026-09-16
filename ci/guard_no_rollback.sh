#!/usr/bin/env bash
# =========================================================
#  guard_no_rollback.sh — « on ne redescend jamais »
# =========================================================
#  POURQUOI CE FICHIER EXISTE (16/09/2026).
#
#  `deploy-worker.yml` et `deploy-admin-panel.yml` se déclenchent sur
#  `claude/**`. N'IMPORTE QUELLE branche claude/ qui touche
#  `cloudflare/` ou `admin-panel/` écrase donc la production. La
#  dernière poussée gagne. Toujours. Sans conflit, sans alerte, sans
#  la moindre ligne rouge : GitHub affiche un joli ✅ vert pendant
#  qu'il enterre le travail d'une autre branche.
#
#  C'est arrivé, et on l'a mesuré. Deux branches vivaient en
#  parallèle : `claude/7motion-android-tv-compat-e0rtyp` (déployée le
#  13/09) et `claude/instant-m3u-activate` (déployée cinq fois
#  ensuite). Le 16/09, la production tournait sur la seconde et
#  7 commits de la première n'étaient plus en ligne — dont le cockpit
#  Cmd+K et la fiche 360°. Personne ne pouvait le voir : le panel
#  marchait, il était juste... plus vieux.
#
#  C'EST EXACTEMENT LA RÈGLE DU `versionCode`, appliquée au serveur.
#  Android refuse d'installer un paquet dont le numéro est inférieur à
#  celui déjà installé, et la maison tient à ce que « les apps ne se
#  perdent pas ». Le serveur mérite la même protection : ce qui est en
#  ligne ne doit jamais reculer.
#
#  ---------------------------------------------------------
#  COMMENT ÇA MARCHE
#  ---------------------------------------------------------
#  Un tag git sert de registre : `deployed/<canal>` pointe sur le
#  commit RÉELLEMENT en ligne. Avant de déployer, on vérifie que ce
#  commit est un ANCÊTRE de celui qu'on s'apprête à publier. Si oui,
#  on avance : rien ne se perd. Si non, les deux branches ont divergé
#  et on refuse, en disant quoi faire.
#
#  Le tag n'est PAS la vérité absolue — c'est un registre qu'on tient
#  nous-mêmes. Il peut manquer (premier passage) : dans ce cas on
#  laisse passer et on le crée. Mieux vaut un garde-fou qui démarre
#  doucement qu'un garde-fou qui bloque tout le jour de sa naissance.
#
#  ---------------------------------------------------------
#  USAGE
#  ---------------------------------------------------------
#    ci/guard_no_rollback.sh check <canal> <sha>
#        Refuse (sortie 1) si <sha> ferait reculer la production.
#
#    ci/guard_no_rollback.sh mark <canal> <sha>
#        Grave <sha> comme « en ligne ». À n'appeler QU'APRÈS un
#        déploiement réussi.
#
#  Canaux utilisés aujourd'hui : `worker`, `admin-panel`.
#
#  UNE SEULE IMPLÉMENTATION, AUTANT D'APPELANTS QU'ON VEUT — même
#  raison que `ci/build_label.sh` et `cloudflare/device_profiles.js`.
#  Le jour où une copie de ce test dérive, elle dit « c'est bon »
#  pendant que l'autre dit non, et on est revenu au point de départ.
# =========================================================
set -euo pipefail

action="${1:-}"
canal="${2:-}"
sha="${3:-}"

if [ -z "$action" ] || [ -z "$canal" ] || [ -z "$sha" ]; then
  echo "usage: $0 <check|mark> <canal> <sha>" >&2
  exit 2
fi

tag="deployed/$canal"

# Le tag vit sur le remote. En CI le clone est souvent superficiel :
# sans les tags NI l'historique, `merge-base` ne peut rien conclure.
git fetch --quiet --tags origin 2>/dev/null || true

case "$action" in
  check)
    if ! git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
      echo "ℹ️  Aucun registre « $tag » : premier passage."
      echo "   On laisse passer et on le créera après le déploiement."
      exit 0
    fi

    live="$(git rev-parse "refs/tags/$tag^{commit}")"

    if [ "$live" = "$sha" ]; then
      echo "✓ Même commit que la production : redéploiement à l'identique."
      exit 0
    fi

    # L'historique peut être tronqué (fetch-depth). On tente de
    # l'approfondir plutôt que de conclure à tort.
    if ! git merge-base --is-ancestor "$live" "$sha" 2>/dev/null; then
      git fetch --quiet --unshallow origin 2>/dev/null || true
    fi

    if git merge-base --is-ancestor "$live" "$sha"; then
      echo "✓ La production ($(git rev-parse --short "$live")) est un ancêtre"
      echo "  de $(git rev-parse --short "$sha") : rien ne se perd, on avance."
      exit 0
    fi

    perdus="$(git rev-list --count "$sha..$live" 2>/dev/null || echo '?')"
    cat >&2 <<EOF

❌ DÉPLOIEMENT REFUSÉ — il ferait RECULER la production.

   En ligne aujourd'hui : $live
   Ce qu'on allait pousser : $sha

   Le commit en ligne n'est PAS un ancêtre du tien : les deux branches
   ont divergé. Publier maintenant effacerait $perdus commit(s) qui
   répondent en ce moment même à de vrais clients — sans erreur, sans
   alerte, avec un ✅ vert.

   Les commits qui seraient perdus :
$(git log --oneline "$sha..$live" 2>/dev/null | head -20 | sed 's/^/     /')

   CE QU'IL FAUT FAIRE — rapatrier avant de publier :

     git fetch origin
     git merge $live        # ou : git merge <la branche d'en face>
     # régler les conflits, relancer les tests, puis repousser

   Ce garde-fou est la règle du versionCode appliquée au serveur :
   ce qui est en ligne ne redescend jamais. Voir l'en-tête de
   ci/guard_no_rollback.sh.

EOF
    exit 1
    ;;

  mark)
    git tag -f "$tag" "$sha" >/dev/null
    git push --force origin "refs/tags/$tag" >/dev/null
    echo "✓ Registre « $tag » → $(git rev-parse --short "$sha")"
    ;;

  *)
    echo "action inconnue : $action (attendu: check | mark)" >&2
    exit 2
    ;;
esac
