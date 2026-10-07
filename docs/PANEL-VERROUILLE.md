# Panel Zuno — version de référence et verrouillage

Demande du propriétaire : conserver exactement le panel actuellement en ligne.
Les nouvelles publicités restent dans le travail local, sans publication.

## Référence conservée

Le manifeste `.github/panel-production.json` distingue le panel et le Worker :
le dernier déploiement du panel seul est le run 37469426377 ; le dernier
déploiement du Worker est le run 37439373445. Le parcours E2E de référence
37468941723 est vert. Ces trois runs ont été relus via l’API GitHub.
Aucun fichier du panel, du Worker ni de la box n’est modifié par ce verrouillage.

## PROUVÉ — contrôles de code

Avant correction : `node --test .github/panel-protection.test.mjs` donne
0/12. La vraie condition du job Worker accepte un autre auteur, une autre
branche et une relance par un autre auteur dès que DEPLOYER est présent.

Après correction : `node --test .github/panel-*.test.mjs` donne 30/30.
Le mode `frozen` refuse tout déploiement, y compris celui du propriétaire.
Pour une future version revue, l’auteur et l’auteur de la relance doivent
être le propriétaire, la branche doit être celle de production et DEPLOYER
doit être saisi. Les jobs qui reçoivent les secrets dépendent de cette
validation et des contrôles de stabilité ; ils utilisent l’environnement
`zuno-panel-production`.

Les tests prouvent aussi qu’un changement du nombre de listes fait échouer
la comparaison malgré une licence identique. Les relevés filtrent les réponses
et ne conservent aucune adresse de liste ni donnée d’accès.
Le panel seul bénéficie désormais du même relevé avant/après que le Worker.

Sur les sources exactes de référence : panel 70/70, compilation TypeScript et
Vite réussie ; injection de pannes 60/60 ; audit sécurité 47/47 ; commande
Worker `node --experimental-sqlite --test *.test.mjs` réussie, sans test ignoré.
Les contrôles locaux ne constituent pas une preuve d’application des réglages GitHub.

## NON PROUVÉ — réglages GitHub tant que non activés et relus

Le relevé initial indique `protected: false` sur la branche de production et
une liste vide de rulesets. Le connecteur ne fournit pas les écritures
d’administration. Le navigateur demande la connexion du propriétaire.

Réglages à appliquer puis relire :

- Règle active ciblant uniquement `claude/panel-mise-en-ligne` : gel des mises
  à jour, suppression interdite et poussées forcées interdites, sans exception.
- Protection après un dégel expressément autorisé : PR obligatoire, validation
  du propriétaire défini dans CODEOWNERS, approbations périmées annulées,
  conversations résolues et contrôles GitHub Actions obligatoires
  « Stabilité panel et Worker » et « wrangler local + panel + box simulée ».
- Environnement `zuno-panel-production` : approbateur unique propriétaire,
  contournement administrateur désactivé, branche de production seule autorisée.
  Le propriétaire peut approuver son lancement : interdire cette auto-validation
  empêcherait le seul approbateur de déployer une version autorisée.
- Limiter les identifiants Cloudflare à cet environnement et retirer leur
  disponibilité globale après migration vérifiée. Un secret global reste
  accessible à un autre workflow sur une autre branche : CODEOWNERS ne ferme
  pas ce chemin. Aucun secret n’a été lu, copié, changé ou supprimé ici.

Le propriétaire conserve le pouvoir de modifier les règles dans les réglages
du dépôt. Un compte administrateur partagé donne ce même pouvoir à son utilisateur.
Le gel du code ne supprime pas les pannes du réseau, de Cloudflare ou d’un fournisseur.

## Déverrouillage futur

Pas de dégel automatique ni de déploiement à la suite d’un commit.
Une demande écrite du propriétaire est nécessaire. Préparer une PR minimale,
faire passer les contrôles sur cette version, obtenir la revue du propriétaire,
puis lever le gel dans les réglages et dans le manifeste. Le déploiement reste
manuel dans le workflow existant et requiert la revue de l’environnement.
Relire une référence autorisée avant/après ; licence, plan, échéance et nombre
de listes doivent rester identiques. Ne publier aucun APK clients à cette occasion.
