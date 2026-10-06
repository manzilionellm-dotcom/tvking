# Déploiement du panel et du Worker

Ce fichier prépare le déploiement. Il ne le lance pas.
Aucun secret n’est écrit ici. Ne pas fusionner ce brouillon tant
qu’on n’a pas décidé de mettre en ligne. Ne pas publier d’APK,
ne pas toucher aux releases `zuno-tv` et `phone-latest`,
ni au 4K Player.

La branche `claude/essai-7-jours` (brouillon #91) n’est pas dans
cette livraison.

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
| `ADMIN_SECRET` | Oui, déjà en production | Signature des jetons du panel et mot de passe du premier compte `admin`. Le code refuse une valeur vide, `dev-secret` ou `change-me`. Sans secret valable, plus personne ne se connecte. **Ne pas le changer** le jour de ce déploiement : les jetons déjà ouverts seraient invalidés. |
| `SOURCE_ENCRYPTION_KEY` | Non | Chiffre les mots de passe Xtream et les URL M3U **au moment d’une écriture**. 16 caractères minimum. C’est le nom à utiliser. |
| `SECRETS_KEY` | Non, ancien nom | Lu seulement si `SOURCE_ENCRYPTION_KEY` est absent. Même règle (16 caractères minimum). Ne pas poser les deux avec des valeurs différentes. |
| `PANEL_ORIGINS` | Non | Origines CORS en plus, séparées par des virgules. Déjà acceptées sans cette variable : `https://tvking-admin.pages.dev`, `https://admin.7themotion.com`, `http://localhost:5173`, `http://127.0.0.1:5173`. |
| `DEFAULT_SERVERS` | Déjà dans `wrangler.toml` | Texte `[]`. La liste réelle des serveurs est dans D1 (`default_servers`), pas dans cette variable. Ne pas y remettre d’URL. |
| Liaison D1 `DB` | Déjà en place | Base `tvking_licensing`. Le panel ne démarre pas sans elle. Ne pas changer l’identifiant. |

`CAST_PROXY_SECRET` sert au cast, pas à ce panel. Ne pas y toucher.
`KV_7MOTION` n’est pas branché dans `wrangler.toml`. Ne pas le créer
pour cette mise en ligne.

`HONOR_REMOTE_LIST_CLEAR` n’est **pas** une variable Cloudflare.
C’est un interrupteur de compilation de l’application
(`--dart-define`), coupé par défaut. Ne pas recompiler l’app.

Côté panel, `VITE_API_BASE` est optionnelle (vide = même origine,
le dev passe par le proxy Vite). Ne la changer que si le panel
doit appeler un autre domaine que celui déjà configuré sur Pages.

### Chiffrement : le laisser éteint pour cette mise en ligne

Tant que `SOURCE_ENCRYPTION_KEY` et `SECRETS_KEY` sont absents ou
font moins de 16 caractères, les liens restent en clair, comme
aujourd’hui. Les lignes déjà en base restent lisibles. On pourra
poser la clé **après**, dans un second temps : les nouvelles
écritures passeront au format `enc1.`, les anciennes restent
lisibles. Ne pas poser la clé puis revenir à l’ancien Worker :
l’ancien code ne sait pas lire `enc1.`.

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
- Les `ALTER TABLE ... ADD COLUMN` déjà dans le code
  (`sources_json`, `origin`, `reseller_id`, `password_changed_at`,
  `permissions`, `channel`) sont ignorés si la colonne existe.
  SQLite ne retire pas une colonne proprement. Ces ajouts ne
  modifient aucune licence.

## Retour arrière

1. Dashboard Cloudflare → Worker `seven-motion-backend` →
   Deployments → redeployer la version d’avant. Le faire **seulement
   si la clé de chiffrement n’a pas encore écrit de ligne `enc1.`**.
2. Dashboard Cloudflare → Pages `tvking-admin` → redeployer le
   déploiement d’avant.
3. Ne pas vider D1. Ne pas supprimer `licenses`, `devices`,
   `device_sources`, ni `device_source_clears`.
4. Ne pas publier d’application.

Les licences, les dates de fin et les MAC ne sont pas réécrites
par le déploiement lui-même. Revenir en arrière ne les restaure
pas si quelqu’un les a modifiées dans le panel entre-temps.

## Clients déjà activés

Une activation déjà en place ne doit pas casser.

- Le déploiement ne gèle pas, ne désactive pas et ne raccourcit
  aucune licence.
- Une box déjà payée continue de recevoir son statut.
- Les listes déjà enregistrées restent. Sans clé de chiffrement,
  elles restent lisibles comme avant.
- L’application installée chez les clients a l’interrupteur
  d’effacement **coupé**. Si le serveur répond `source: null`
  (liste jamais posée, licence gelée, ou liste effacée), l’app
  déjà en place **ne vide pas** la liste locale. Seul un futur
  build compilé avec `HONOR_REMOTE_LIST_CLEAR=true` le ferait,
  et seulement pour les listes que le panel avait poussées.
- « Désactiver » dans le panel gèle la box. Ça ne retire pas le
  lien et ça n’efface pas la date de fin. Ce n’est pas un effet
  du déploiement : il faut cliquer.

Pour le contrôle, prendre **une MAC de test**, jamais la MAC d’un
client, pour l’activation, le gel, l’effacement et l’échéance.

## Vérifications sur le vrai site

À faire seulement après le déploiement réel. Cocher dans l’ordre.
La box de test est une MAC que l’on crée pour l’occasion.

1. **Connexion.** Un mauvais mot de passe reste sur l’écran de
   login. Le bon mot de passe ouvre le tableau de bord.
2. **Activation.** Écran « Activer l'application ». Poser la MAC
   de test, durée 1 mois, sans liste. Le résultat affiche
   « Application activée » et une date de fin. La licence est
   active. La box de test n’a pas encore de lien.
3. **Ajout M3U.** Écran « Liste de chaînes » (pas l’écran
   d’activation). Envoyer un lien de test. La box de test reçoit
   ce lien. Changer le lien ne prolonge pas la date de fin.
4. **Désactivation.** Geler cette box de test. Elle est bloquée.
   La date de fin est toujours là. La liste n’a pas été retirée
   par le gel. Réactiver ensuite.
5. **Effacement de liste.** Effacer les listes de la MAC de test.
   La box ne reçoit plus le lien. L’abonnement reste payé
   (`paid` vrai, pas expiré).
6. **Message.** Publier une annonce de test. La box lit le titre
   et le texte.
7. **État de la box.** Après un heartbeat, la page « En ligne »
   montre la MAC de test.
8. **Délai 1 à 2 secondes.** Modifier le lien ou l’état, puis
   recharger côté box / côté panel : le changement est visible
   au plus tard au bout d’environ 2 secondes, pas au bout de
   30 secondes.
9. **Client réel, en lecture seule.** Ouvrir la fiche d’une MAC
   déjà activée avant le déploiement. La licence est toujours
   active, la date de fin est la même, la liste est la même,
   la box n’est pas gelée. Ne rien enregistrer sur cette fiche.
