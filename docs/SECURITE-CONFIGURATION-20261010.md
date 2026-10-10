# Configurations protégées — audit du 10 octobre 2026

## État réel avant correction

PROUVÉ par relecture GitHub : les règles « Zuno - panel gele » et « Zuno - revue
et tests obligatoires » sont actives sur `claude/panel-mise-en-ligne` uniquement.
La règle de gel interdit mise à jour, suppression et réécriture, sans contournement.
La production reste au commit `2b7d1ea5ff3fdad144dfc660f39b093c15020243`.
Le formulaire M3U/Xtream de la PR #104 n'est pas encore déployé.

PROUVÉ par tests avant correction : dix contrôles panel et neuf contrôles app
échouent sur les vrais workflows. Un contrôle supplémentaire reproduit le
`git push -f` du snapshot. Commande :
`node --test --test-reporter=tap .github/security-config.test.mjs`.
Les fichiers de départ proviennent des branches actuelles, sans fusion des
branches divergentes et sans données IPTV dans les fixtures.

Causes observées :
- L'ancien workflow de secret administrateur prend le secret comme entrée et
  n'utilise ni la garde de déploiement ni l'environnement protégé.
- Les actions sont désignées par des tags déplaçables, le SDK Flutter par `stable`.
- Les jobs de compilation TV et téléphone possèdent un jeton d'écriture des releases.
- Le workflow Windows peut publier sur un push de branche `claude/**`.
- Le nettoyage insère directement la saisie des tags dans un script shell ;
  la liste d'exclusions ne protège pas les canaux Zuno actuels.
- Le snapshot réécrit une branche partagée et réutilise le jeton Cloudflare de déploiement.

## Correctifs préparés

PROUVÉ localement : 82 contrôles panel et 59 contrôles apps réussis, sans test
ignoré. Les assertions de régression sont conservées, avec la correction
documentée ci-dessous du contrôle de secret historique. Des contre-preuves
exécutent la vraie garde avec gel, autre auteur, autre relance, PR étrangère,
option client ou entrée de dégel falsifiée. Le parcours autorisé du propriétaire
et celui de la PR exacte de test restent acceptés.

- Les builds TV, téléphone et Windows utilisent `contents: read`. Les publishers
  sont des jobs distincts après succès du build ; eux seuls reçoivent l'écriture.
- `.github/app-production.json` est `frozen`. Un client ou un nettoyage exige
  un dégel revu, le propriétaire, sa propre relance, la branche de travail et
  une confirmation explicite. La preuve TV garde `test_box=true`, `publish=false`.
- Les anciens publishers sont manuels, gardés et gelés ; aucun ancien workflow
  n'est exécuté pour livrer la TV. Le seul constructeur TV reste `build-zuno-tv.yml`.
- Le workflow historique de mot de passe est neutralisé : il ne reçoit aucun
  secret et ne peut appeler Cloudflare. La validation de branche, auteur et gel
  précède un refus explicite. Toute future mutation du Worker doit passer par
  `deploy-panel-cloudflare.yml`, avec ses contrôles avant et après.
- Le nettoyage accepte uniquement les anciens tags numérotés `build-N` ou
  `cast-N`. Toute la liste est validée avant le premier appel, sans shell.
  Un tag actif ou une tentative d'injection refuse toute la demande.
- Le snapshot crée une nouvelle branche par run et tentative, sans force,
  avec un accès Cloudflare distinct `CLOUDFLARE_READ_TOKEN`.
- `CODEOWNERS` couvre `.github/`, toute l'app et ses configurations.
- Les actions du périmètre sont figées par SHA complet. Les caches internes
  de l'action Flutter sont coupés dans les builds signés.

Une vérification supplémentaire a reproduit un mauvais chemin de récupération
des artefacts après séparation des jobs : rouge, puis vert au bon chemin.
Deux autres contrôles ont reproduit les droits du build mobile et la publication
Windows au push avant leur séparation. Ils restent dans la suite finale.

PROUVÉ : GitHub a refusé le workflow mobile avant tout job au run `38057301728`,
puis son appel par la qualité au run `38057385813`. `pub-cache` était au niveau
de l'étape, hors de `with`. Un nouveau test échoue avec `6 !== 8`, puis les
57 contrôles passent après la correction de deux espaces. Le run qualité
`38057803889` accepte ensuite la définition et lance les vrais jobs.
Un contrôle supplémentaire prouve avant correction l'absence de garde exécutée
dans le build mobile ; elle est maintenant appelée avant les étapes de signature.

PROUVÉ par la documentation Cloudflare : `wrangler secret put` crée une version
et la déploie immédiatement. Le premier durcissement du workflow historique
gardait donc une voie de déploiement parallèle interdite par le propriétaire.
Les nouveaux contrôles reproduisent deux échecs panel et un échec app avant
neutralisation. Le contrôle initial qui imposait un secret d'environnement à
cette voie était incorrect : il validait une opération interdite. Il est remplacé
par une assertion plus stricte, qui interdit tout accès à un secret dans ce
workflow. Les autres assertions sont inchangées. Aucune clé n'est remplacée.

## Versions relevées auprès des dépôts officiels

La liste complète, avec SHA, est dans `.github/toolchain.json`.

| Outil | Version relevée |
| --- | --- |
| Node LTS | 24.21.0 |
| Flutter stable | 3.47.7 |
| actions/checkout | v7.0.1 |
| actions/setup-node | v7.1.0 |
| actions/setup-java | v6.0.1 |
| actions/upload-artifact | v7.0.2 |
| actions/download-artifact | v8.0.2 |
| subosito/flutter-action | v2.23.0 |
| android-actions/setup-android | v4.0.4 |
| cloudflare/wrangler-action | v4.1.3 |
| Wrangler | 4.149.0 |

La tête `stable` officielle de Flutter et son tag 3.47.7 désignent le même
commit `abaf9c523780a608bd46686fd5e53740a07077f8`. Cette version est également
celle du build Zuno vert `37949476085` du 9 octobre. Les versions des paquets
React, du site Next.js et la date de compatibilité du Worker ne sont pas modifiées.
Le banc E2E existant garde son lockfile Wrangler 3.90.0 ; un contrôle séparé
compile le Worker avec Wrangler 4.149.0 en `--dry-run`, sans déploiement.

## Preuves CI déjà obtenues

PROUVÉ, branche panel `ccr-securite-panel-20261010`, commit `eea193f0` :
- [Configuration, 81 contrôles et Worker sans déploiement](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38057390959) : succès ;
  journal `tests 81`, `pass 81`, `fail 0`, `wrangler 4.149.0`,
  `--dry-run: exiting now.`
- [Stabilité panel et Worker](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38057390925) : succès ;
  les trois jobs d'autorisation et déploiement sont ignorés par les conditions de PR.
- [E2E réel Miniflare](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38057390922) : succès.

PROUVÉ, branche apps, commit `c4211da6` :
[Windows natif](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38057302440)
compile, vérifie le binaire, crée l'installateur et téléverse l'artefact avec succès.
Le job de publication Windows est ignoré. Ce run ne publie aucune release.

PROUVÉ, apps au commit `93310101`,
[qualité et canaux de test](https://github.com/manzilionellm-dotcom/tvking/actions/runs/38058107294) :
les 58 contrôles de configuration, la sécurité Worker et les 550 tests Flutter
réussissent (deux tests historiquement ignorés). Les jobs natifs TV et mobile
sont lancés après ces barrières, avec gardes acceptées et SDK fixe.

## Vérifications restant à obtenir

NON PROUVÉ à cette étape : fin des builds natifs TV et mobile après séparation
des publishers, livraison des versions test et CI du dernier contrôle de secret.
L'installation sur SHIELD et téléphone nécessite une preuve matérielle distincte.

NON PROUVÉ : protection administrative des branches app, des environnements
`zuno-app-test`, `zuno-app-production`, `zuno-panel-audit`, et disponibilité limitée
des anciens secrets globaux. Un nom d'environnement dans un fichier YAML ne
prouve pas que ses règles sont configurées. Le connecteur GitHub disponible ne
permet pas d'administrer ces réglages ; aucune valeur de secret n'a été consultée.

À appliquer puis relire dans les réglages GitHub :
1. Après la preuve native, geler la branche app validée comme le panel.
   Le corps API prêt à relire est `.github/protection-proposals/app-frozen.ruleset.json` :
   seules les mises à jour, suppressions et réécritures de cette branche sont
   bloquées, sans contournement. Ce fichier n'applique aucune règle à lui seul.
   Les nouveaux développements restent possibles sur une branche distincte ;
   la branche validée exige une ouverture décidée par le propriétaire.
2. Environnements de publication : seul propriétaire approbateur, branches
   autorisées limitées et contournement administrateur désactivé. Le canal clients
   reste gelé ; le canal test suit sa procédure propre.
3. Jetons Cloudflare et clé de signature : accès limité aux environnements
   correspondants, après migration vérifiée. Aucun retrait ou remplacement de
   clé n'est exécuté par ces correctifs. Ne pas révoquer une clé de chiffrement
   des sources : les données existantes doivent rester lisibles.
4. Actions : permissions par défaut en lecture, actions autorisées limitées,
   exigence de SHA et approbations automatiques de PR désactivées. Le corps API
   des permissions est `.github/protection-proposals/workflow-permissions.json`.
   La restriction globale des actions attend l'inventaire des workflows du site :
   leur configuration, hors mission, comporte encore des tags déplaçables.
   Activer cette restriction immédiatement pourrait interrompre ces workflows.

L'accès en écriture d'un autre codeur lui permet de créer son propre workflow
et de demander un jeton d'écriture ; les gardes de ces fichiers ne suffisent pas
à arrêter ce contournement. Les droits des collaborateurs, environnements et
secrets globaux doivent donc être relus ensemble. Le propriétaire reste le seul
à ouvrir les branches validées et approuver l'accès aux secrets de livraison.

La connexion app/Worker possède un header `X-Device-Secret` dans le code app,
et l'updater contrôle taille et SHA-256. La présence de ces fonctions dans le
code ne prouve pas l'enrôlement d'un client précis ni l'import de sa liste.
Le refus M3U observé le 9 octobre reste un diagnostic distinct.

## Sources primaires

- GitHub, permissions minimales, environnements, SHA, risques des secrets globaux :
  https://docs.github.com/en/actions/reference/security/secure-use
- GitHub, approbations et branches autorisées des environnements :
  https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- GitHub, permissions et restrictions des actions au niveau du dépôt :
  https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- Cloudflare, une mutation de secret peut publier une nouvelle version :
  https://developers.cloudflare.com/workers/configuration/secrets/
- Releases officielles des actions : dépôts référencés dans le manifeste.
- Flutter stable : https://github.com/flutter/flutter/tree/stable
- Node LTS : https://github.com/nodejs/node/releases/tag/v24.21.0
- Wrangler : https://github.com/cloudflare/workers-sdk/releases/tag/wrangler%404.149.0

Ces protections portent sur le code et la livraison. La disponibilité réelle
dépend aussi du réseau, de Cloudflare et des fournisseurs ; aucun fonctionnement
permanent ni aucun taux d'incident nul n'est déduit des tests.
