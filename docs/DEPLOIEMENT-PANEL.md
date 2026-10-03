# Déploiement du panel et du Worker

Ce fichier prépare le déploiement. Il ne le lance pas.
Aucun secret n’est écrit ici. Ne pas fusionner ce brouillon tant
qu’on n’a pas décidé de mettre en ligne. Ne pas publier d’APK,
ne pas toucher aux releases `zuno-tv` et `phone-latest`,
ni au 4K Player.

Cette livraison réunit le panel tout-en-un, l’essai de 7 jours
(interrupteur coupé) et l’activation 1 an / à vie avec l’ajout
de jours. Les écrans `/activate` et `/chaines` restent séparés.

## Ordre

1. **D’abord le Worker** (`android-app/cloudflare`, nom
   `seven-motion-backend`, domaine `app.7themotion.com`).
2. **Ensuite le panel** (Cloudflare Pages, projet `tvking-admin`,
   site `https://tvking-admin.pages.dev`).

Les deux peuvent partir dans la même fenêtre, mais le Worker doit
répondre avec le nouveau code avant d’ouvrir le nouveau panel.
Le panel déjà en ligne appelle déjà l’activation **sans** lien M3U,
puis envoie la liste à part. Le nouveau Worker refuse une activation
qui contiendrait encore un lien (`source` ou `sources`) : il répond
400 et **n’écrit rien**. L’ordre « Worker puis panel » ne casse donc
pas les activations faites avec le panel actuel.

Le nouveau panel appelle aussi `POST /api/v1/trial-extend`. Tant que
l’ancien Worker est en face, cet appel n’existe pas. D’où le Worker
en premier.

Le site vitrine Next.js (GitHub Pages) n’est pas ce panel. Un push
sur `main` relance quand même `.github/workflows/deploy-pages.yml`.
Les fichiers `android-app/.github/workflows/deploy-worker.yml` et
`deploy-admin-panel.yml` ne sont pas des workflows GitHub actifs
(ils ne sont pas à la racine `.github/workflows`). Le Worker et le
panel se publient à la main, quand on le décide.

## Variables Cloudflare

À poser sur le Worker avec `wrangler secret put` (ou le tableau
Secrets du dashboard). Ne jamais les coller dans Git, dans ce
fichier, ni dans `wrangler.toml`.

| Nom | Obligatoire ? | Rôle |
| --- | --- | --- |
| `ADMIN_SECRET` | Oui, déjà en production | Signature des jetons du panel et mot de passe du premier compte `admin`. Le code refuse une valeur vide, `dev-secret` ou `change-me`. Sans secret valable, plus personne ne se connecte. **Ne pas le changer** le jour de ce déploiement : les jetons déjà ouverts seraient invalidés. C’est aussi le secret de l’en-tête `X-Admin-Secret` pour `POST /api/v1/trial-extend`. |
| `PANEL_ORIGINS` | Non | Origines CORS en plus, séparées par des virgules. Déjà acceptées sans cette variable : `https://tvking-admin.pages.dev`, `https://admin.7themotion.com`, `http://localhost:5173`, `http://127.0.0.1:5173`. |
| `DEFAULT_SERVERS` | Déjà dans `wrangler.toml` | Texte `[]`. La liste réelle des serveurs est dans D1 (`default_servers`), pas dans cette variable. Ne pas y remettre d’URL. |
| Liaison D1 `DB` | Déjà en place | Base `tvking_licensing`. Le panel ne démarre pas sans elle. Ne pas changer l’identifiant. |

### À ne pas poser

- **`SOURCE_ENCRYPTION_KEY`** : ne pas créer cette variable.
- **`SECRETS_KEY`** : ne pas créer cette variable non plus.
  Tant qu’elles sont absentes, les liens restent en clair, comme
  aujourd’hui, et un retour à l’ancien Worker sait encore les lire.
- **`TRIAL_ENFORCEMENT`** : la laisser **absente**, ou à `0`.
  Valeurs qui allumeraient le verrou : `1`, `true`, `on`, `yes`.
  Tout le reste, y compris l’absence, reste coupé. Coupé, aucun
  client actuel n’est bloqué par la règle des 7 jours. Les ancres
  s’écrivent quand même.

`CAST_PROXY_SECRET` sert au cast, pas à ce panel. Ne pas y toucher.
`KV_7MOTION` n’est pas branché dans `wrangler.toml`. Ne pas le créer
pour cette mise en ligne.

`HONOR_REMOTE_LIST_CLEAR` n’est **pas** une variable Cloudflare.
C’est un interrupteur de compilation de l’application
(`--dart-define`), coupé par défaut. Ne pas recompiler l’app.

Côté panel, `VITE_API_BASE` est optionnelle (vide = même origine,
le dev passe par le proxy Vite). Ne la changer que si le panel
doit appeler un autre domaine que celui déjà configuré sur Pages.

## Ce que le nouveau code ajoute, sans l’allumer

- Écran `/activate` : MAC, nom optionnel, **Activation 1 an** ou
  **Activation à vie**, puis un bloc « Ajouter des jours d’essai »
  (administrateur seulement). Pas de prix en euros sur les boutons.
  Le coût en crédits déjà configuré s’affiche pour un revendeur
  (1 = 1 an, 2 = à vie).
- Écran `/chaines` : le lien M3U, à part. L’activation n’écrit pas
  de liste.
- `POST /api/v1/trial-extend` avec `{ mac, days }`. Autorisé par
  `X-Admin-Secret` (la valeur actuelle de `ADMIN_SECRET`) ou par
  un jeton `super_admin`. Un revendeur reçoit 403. Jours : entier
  de 1 à 365. La MAC doit déjà être connue. La fin devient
  max(fin actuelle, maintenant) + N jours. Une licence payée encore
  en cours prime. Un gel ou un bannissement n’est pas levé.
- Familles : on ne crée plus de famille, de membre, ni de lien
  (réponse `403 family_clone_disabled`). Les lignes déjà en base
  restent. Un appareil déjà activé en famille reste payé. La
  lecture (liste, fiche) continue.
- Une seconde activation « à vie » ne redébite pas et ne raccourcit
  pas la licence, que l’interrupteur d’essai soit coupé ou allumé.

## Base de données

Aucune migration à lancer à la main.

- `migrations/008_device_sources.sql` ne change qu’un commentaire.
  La table `device_sources` existe déjà. Rien à rejouer, rien à
  annuler.
- Le Worker crée tout seul, au premier effacement de liste, la
  table `device_source_clears` (`mac`, `cleared_at`). C’est un
  ajout. L’ancien Worker l’ignore. On peut la supprimer avec
  `DROP TABLE device_source_clears` : le schéma revient en arrière,
  mais on perd la mémoire des listes effacées. **Ne pas la
  supprimer.** Une liste effacée doit le rester.
- Au premier contact ou au premier ajout de jours, le Worker crée
  `trial_anchors` (début d’essai, et `extended_until` si des jours
  ont été ajoutés) et `trial_extensions` (qui, quand, combien).
  Ce sont des ajouts. L’ancien Worker les ignore. **Ne pas les
  supprimer** : sinon, le jour où l’on allume `TRIAL_ENFORCEMENT`,
  l’essai repartirait de zéro.
- Les `ALTER TABLE ... ADD COLUMN` déjà dans le code
  (`sources_json`, `origin`, `reseller_id`, `password_changed_at`,
  `permissions`, `channel`, `extended_until`) sont ignorés si la
  colonne existe. SQLite ne retire pas une colonne proprement.
  Ces ajouts ne modifient aucune licence.

## Retour arrière

1. Dashboard Cloudflare → Worker `seven-motion-backend` →
   Deployments → redéployer la version d’avant.
   C’est possible tant que `SOURCE_ENCRYPTION_KEY` et `SECRETS_KEY`
   n’ont pas été posées (ce déploiement ne les pose pas).
2. Dashboard Cloudflare → Pages `tvking-admin` → redéployer le
   déploiement d’avant.
3. Ne pas changer `ADMIN_SECRET`.
4. Ne pas vider D1. Ne pas supprimer `licenses`, `devices`,
   `device_sources`, `device_source_clears`, `trial_anchors`,
   `trial_extensions`, ni les lignes de familles déjà créées.
5. Ne pas publier d’application. Laisser `TRIAL_ENFORCEMENT`
   absente ou à `0`.

Les licences, les dates de fin et les MAC ne sont pas réécrites
par le déploiement lui-même. Revenir en arrière ne les restaure
pas si quelqu’un les a modifiées dans le panel entre-temps.
Un ajout de jours fait après la mise en ligne ne sera plus honoré
par l’ancien Worker : la date reste en base, l’ancien code ne la
lit pas.

## Clients déjà activés

Une activation déjà en place ne doit pas casser.

- Le déploiement ne gèle pas, ne désactive pas et ne raccourcit
  aucune licence.
- Une box déjà payée continue de recevoir son statut.
- Les listes déjà enregistrées restent, en clair.
- L’application installée chez les clients a l’interrupteur
  d’effacement **coupé**. Si le serveur répond `source: null`
  (liste jamais posée, licence gelée, ou liste effacée), l’app
  déjà en place **ne vide pas** la liste locale. Seul un futur
  build compilé avec `HONOR_REMOTE_LIST_CLEAR=true` le ferait,
  et seulement pour les listes que le panel avait poussées.
- « Désactiver » dans le panel gèle la box. Ça ne retire pas le
  lien et ça n’efface pas la date de fin. Ce n’est pas un effet
  du déploiement : il faut cliquer.
- Un appareil déjà dans une famille reste valable. On ne peut
  plus en créer un nouveau depuis le panel.
- Tant que `TRIAL_ENFORCEMENT` est absente ou à `0`, un client
  vu depuis plus de 7 jours **sans** licence n’est pas bloqué
  par ce verrou. Il suit la durée d’essai du panel, comme avant.

Pour le contrôle, prendre **une MAC de test**, jamais la MAC d’un
client, pour l’activation, le gel, l’effacement, l’ajout de jours
et l’échéance.

## Vérifications sur le vrai site

À faire seulement après le déploiement réel. Cocher dans l’ordre.
La box de test est une MAC que l’on crée pour l’occasion.
Ne rien enregistrer sur la fiche d’un client réel.

1. **Variables.** Sur le Worker : `ADMIN_SECRET` est celui d’avant
   (on ne le relit pas, on vérifie qu’on ne l’a pas remplacé).
   `SOURCE_ENCRYPTION_KEY` et `SECRETS_KEY` sont absentes.
   `TRIAL_ENFORCEMENT` est absente ou vaut `0`.
2. **Connexion.** Un mauvais mot de passe reste sur l’écran de
   login. Le bon mot de passe ouvre le tableau de bord.
3. **Activation 1 an.** Écran « Activation » (`/activate`), pas
   l’écran des chaînes. Poser la MAC de test, **Activation 1 an**,
   sans liste. Le résultat affiche une date de fin. La licence
   est active, plan `yearly`. La box de test n’a pas encore de lien.
4. **Activation à vie, sur une autre MAC de test.** Le résultat
   dit « Activé à vie ». Une seconde fois sur la même MAC ne
   redébite pas les crédits.
5. **Ajout M3U.** Écran « Liste de chaînes » (`/chaines`). Envoyer
   un lien de test. La box de test reçoit ce lien. Changer le lien
   ne prolonge pas la date de fin.
6. **Ajout de jours.** Sur une MAC de test déjà vue par l’app,
   écran Activation, « Ajouter des jours d’essai », 7 jours.
   La réponse donne une date de fin. La vérification suivante de
   la box (`/api/status`) n’est pas expirée. Un compte revendeur
   ne peut pas appeler cet ajout.
7. **Désactivation.** Geler la box de test. Elle est bloquée.
   La date de fin est toujours là. La liste n’a pas été retirée
   par le gel. Réactiver ensuite.
8. **Effacement de liste.** Effacer les listes de la MAC de test.
   La box ne reçoit plus le lien. L’abonnement reste payé
   (`paid` vrai, pas expiré).
9. **Message.** Publier une annonce de test. La box lit le titre
   et le texte.
10. **État de la box.** Après un heartbeat, la page « En ligne »
    montre la MAC de test.
11. **Délai 1 à 2 secondes.** Modifier le lien ou l’état, puis
    recharger côté box / côté panel : le changement est visible
    au plus tard au bout d’environ 2 secondes, pas au bout de
    30 secondes.
12. **Client réel, en lecture seule.** Ouvrir la fiche d’une MAC
    déjà activée avant le déploiement. La licence est toujours
    active, la date de fin est la même, la liste est la même,
    la box n’est pas gelée. Ne rien enregistrer sur cette fiche.
13. **Famille déjà créée, en lecture seule.** Ouvrir « Familles
    déjà créées ». Les appareils déjà dedans sont encore listés.
    Il n’y a pas de bouton pour en créer une nouvelle. Ne rien
    supprimer.
