# Le panel arrive sur la box tout de suite

Compte-rendu du 30 septembre 2026. Rien n'a été publié sur la release
`zuno-tv`. Le Worker de production n'a pas été déployé. Le panel
n'a pas été déployé. `main` n'a pas été poussé. `ADMIN_SECRET` et
`SOURCE_ENCRYPTION_KEY` n'ont pas été changés.

Les chiffres ci-dessous sont ceux des commandes réellement exécutées
sur cette machine. Un délai mesuré en local (Worker sur
`127.0.0.1:8787`) n'est pas le délai d'une box chez un client, ni le
délai d'Internet.

## Avant (version 103)

La box apprenait **seulement** la licence, le gel, le bannissement et
le numéro de liste en lisant `GET /api/status` :

- toutes les **3 s** tant qu'elle attend une activation ou ses
  premières chaînes ;
- toutes les **4 s** ensuite ;
- jusqu'à **45 s** si le réseau ne répond plus.

Mesuré dans `docs/RELEASE-103.md` : activation 4,048 s, effacement
3,848 s, retour réseau 3,231 s (même type de machine locale).

Le message, le thème, l'accueil, le favori, la pub, les tarifs,
l'avis, les serveurs et la mise à jour forcée étaient lus **au
démarrage** de l'app. Pas de canal pour les pousser après. Le
heartbeat sert à dire « je suis là », pas à recevoir un ordre.

## Maintenant

Chaque action du panel qui concerne une box écrit **un ordre**
(un nom, jamais un mot de passe). La box garde une connexion ouverte
(`GET /api/box/wait`, 20 s, le serveur regarde toutes les 300 ms).
Dès que l'ordre est là, elle relit l'état qu'elle connaît déjà
(`/api/status`, annonce, thème, etc.) puis elle accuse réception
(`POST /api/box/ack`). Le panel affiche « appliqué à HH:MM:SS ».

Si le canal ne s'ouvre pas (ancien Worker, secret refusé, trop de
connexions, Wi-Fi coupé), la box revient au rythme 3 s / 4 s de la
103. Quand le canal tient, elle ne relit le statut qu'en filet,
toutes les **25 s**, pour ne pas doubler le trafic.

Un même numéro d'ordre n'est pas rejoué. Un second accusé ne change
pas l'heure. Limite : **30** attentes par minute et par box, **120**
par adresse IP. La 31e répond 429.

Le tableau du panel ne se recharge pas tout seul par magie : la page
demande `GET /api/v1/boxes/live` **toutes les 2,5 s**. L'ordre arrive
sur la box en une fraction de seconde (chiffres plus bas). La colonne
« Direct » peut mettre jusqu'à 2,5 s de plus à l'afficher.

Les box v102 et v103 n'appellent pas `/api/box/wait`. `GET /api/status`
reste public. Ce n'est pas un APK 102 ou 103 qui a été lancé ici.

## Inventaire

| Action dans le panel | Avant | Maintenant | Mesuré ici |
| --- | --- | --- | --- |
| Activation | statut, 3–4 s | ordre `activate` | 0,232 s |
| Suspension (gel) | statut, 3–4 s | ordre `suspend` | 0,423 s |
| Réactivation après gel | statut, 3–4 s | ordre `resume` | 0,421 s |
| Blocage (banni) | statut, 3–4 s | ordre `block` | 0,432 s |
| Réactivation après ban | statut, 3–4 s | ordre `resume` | 0,417 s |
| Expiration (date déjà passée) | statut, 3–4 s | ordre `expire` | 0,130 s |
| Renouvellement | statut, 3–4 s | ordre `renew` | 0,436 s |
| Changement de liste | statut + `source_rev`, 3–4 s | ordre `source` | 0,430 s |
| Effacement de liste | empreinte + statut, 3–4 s | ordre `source_clear` | 0,420 s |
| Message au client | seulement au démarrage | ordre `message` (tout le parc) | 0,336 s |
| Thème | seulement au démarrage | ordre `theme` | 0,131 s |
| Mise à jour forcée | pas relue sur la TV après le boot | ordre `force_update` | 0,322 s |
| Favori du jour | seulement au démarrage | ordre `featured` | 0,137 s |
| Publicité | seulement au démarrage | ordre `ad` | 0,332 s |
| Tarifs | seulement au démarrage | ordre `pricing` | 0,140 s |
| Invitation à laisser un avis | seulement au démarrage | ordre `feedback` | 0,428 s |
| Disposition de l'accueil | seulement au démarrage | ordre `home` | 0,360 s |
| Serveur proposé dans l'app | seulement au démarrage | ordre `servers` | 0,419 s |
| +7 jours à tous | statut, au prochain passage | ordre `license` | 0,317 s |
| Box éteinte, puis rallumée | l'ordre attend le prochain statut | l'ordre part à l'ouverture du canal | 0,219 s |
| Worker coupé, puis rallumé | le dernier statut reste | l'ordre part au retour | 1,036 s |
| Transfert vers une autre MAC | statut, 3–4 s | ordre `transfer` | 0,260 s |

L'heure gravée pour l'activation de cet essai est
`applied_at = 1790787454832`, soit **16:57:34 UTC** le 30 septembre
2026. Le panel écrit « appliqué à HH:MM:SS » avec **l'horloge du
navigateur**, pas en UTC. Cette phrase a été vérifiée par un test
du texte (`en ligne · v103 · appliqué à 12:03:04 · activation`),
pas en ouvrant la page dans un navigateur.

Câblé de la même façon, **pas chronométré** dans cet essai :
suppression d'une MAC, ajout ou retrait d'un membre de famille
(activation, liste, ou effacement), les autres boutons qui écrivent
le même type d'ordre (effacer une annonce, couper un serveur,
automatisation du thème). L'ancien formulaire HTML
(geler / bannir / marquer payé) écrit aussi un ordre : le nom a été
vérifié sans réseau (`freeze` → suspension, `note` → rien). Ces
boutons n'ont pas été cliqués contre wrangler.

Ne part **pas** sur la box, et ce n'est pas un oubli :

- la note interne du client ;
- le nom du client, les crédits, le mot de passe du revendeur ;
- les liens M3U d'une famille (ce sont des jetons, pas un ordre
  vers une box) ;
- les profils de l'app (Enfants, etc.) : ils vivent sur la box,
  le panel ne les règle pas.

## Prouvé — commandes exécutées

Machine : Flutter 3.47.5, Dart 3.13.4, Node 22.14.0, wrangler 4.145.0.
`wrangler dev` sur `127.0.0.1:8787`, D1 locale dans un dossier
temporaire. Secret d'essai seulement, dans `cloudflare/.dev.vars`
(fichier ignoré par git) : ce n'est pas le secret de production.

### 1. Preuve panel → box

Worker réel et code client réel (`RemoteActivationWatch`,
`BoxSignalClient`, `SubscriptionState`). Pas un faux du même code.

```
cd android-app
flutter test --reporter expanded \
  --dart-define=RUN_E2E=true \
  --dart-define=BACKEND_URL=http://127.0.0.1:8787 \
  test/features/subscription/panel_instant_e2e_test.dart
```

Sortie du passage vert (30 septembre 2026). Les lignes `MESURE`
sont le chronomètre. Le résumé JSON ne garde qu'une fois
« resume » (la dernière, 0,417 s) ; les deux réactivations sont
dans les lignes au-dessus.

```
MESURE activate_secondes=0.232
MESURE applique_a_epoch_ms=1790787454832
MESURE suspend_secondes=0.423
MESURE resume_secondes=0.421
MESURE block_secondes=0.432
MESURE resume_secondes=0.417
MESURE expire_secondes=0.13
MESURE renew_secondes=0.436
MESURE source_secondes=0.43
MESURE source_clear_secondes=0.42
MESURE message_secondes=0.336
MESURE theme_secondes=0.131
MESURE force_update_secondes=0.322
MESURE featured_secondes=0.137
MESURE ad_secondes=0.332
MESURE pricing_secondes=0.14
MESURE feedback_secondes=0.428
MESURE home_secondes=0.36
MESURE servers_secondes=0.419
MESURE license_secondes=0.317
MESURE reprise_secondes=0.219
MESURE retour_reseau_secondes=1.036
MESURE transfer_secondes=0.26
00:27 +1: All tests passed!
```

Ce que cet essai a aussi vérifié, parce qu'il a fini vert :

- sans jeton, l'état en direct répond **401** ;
- attente sans secret de box : **401** ; mauvais secret : **401** ;
- `GET /api/status` sans secret : **200** (une box ancienne peut
  encore lire). Sur une base neuve, le corps contient `revoked`
  et **pas** encore `source_rev` (la table des listes n'existe
  pas tant qu'on n'a pas posé une liste : c'est déjà le cas en 103) ;
- un revendeur ne voit pas la box d'un autre : **403** sur l'état
  en direct, sur l'effacement de liste et sur le renouvellement.
  Sa liste à lui ne contient pas la MAC de l'autre ;
- la 31e attente en une minute répond **429** ;
- la version envoyée par la box (`103-test`) revient dans l'état
  en direct, et la box est marquée en ligne ;
- le corps de l'attente ne contient pas le mot de passe de la liste ;
- un second accusé répond `already: true` et l'heure ne change pas ;
- box arrêtée : l'ordre de gel reste en file, il part au rallumage
  (0,219 s) et la box passe gelée ;
- Worker tué : l'état « gelé » déjà connu reste. Au retour, la
  réactivation part en 1,036 s. Ce chiffre part du clic (le test
  réessaie si le fichier SQLite local répond « database is locked »,
  ce qui est un à-coup de wrangler, pas un refus de l'API).

La console de ce test affiche aussi un échec Xtream vers
`127.0.0.1:9` (rien n'écoute). En mode debug, l'app écrit l'adresse
complète, et cette adresse de test contient le mot de passe. Ce
n'est pas le canal : le test vérifie que le corps de l'attente ne
le contient pas. Rien de tout cela n'est allé sur Internet.

### 2. Décisions sans réseau

```
cd android-app/cloudflare && node box_signal_pure.test.mjs
```

16 contrôles, dont : la note interne ne part pas, une date déjà
passée est une expiration même si le statut dit encore « actif »,
un ordre déjà vu ne se rejoue pas, une box muette depuis plus de
45 s est hors ligne.

```
cd android-app/cloudflare && node zuno_security.test.mjs
```

`33 passed, 0 failed`. Dedans : état en direct sans jeton 401,
attente sans secret 401, mauvais secret 401, accusé sans secret 401,
attente vide sans mot de passe. Cette base est **en mémoire** : elle
prouve les refus, pas la livraison d'un ordre (ça, c'est le §1).

```
cd android-app/admin-panel
node --experimental-strip-types src/lib/boxLive.test.ts
```

`PASS panel boxLive`. La ligne attendue est
`en ligne · v103 · appliqué à 12:03:04 · activation`, et
`hors ligne · en attente : suspension`.

```
cd android-app && flutter test test/features/subscription/box_signal_test.dart
```

3 tests verts : filet à 25 s quand le canal tient, rythme 103
quand il est coupé, le même numéro une seule fois, chaque action
a une relecture et aucun secret dans l'ordre.

### 3. Toute la suite Flutter, sans la preuve réseau

```
cd android-app && flutter test --reporter compact
```

```
00:13 +259 ~2: All other tests passed!
```

Les deux ignorés (`~2`) sont les preuves wrangler
(`panel_box_e2e_test.dart` de la 103 et
`panel_instant_e2e_test.dart`). Sans `RUN_E2E`, elles ne lancent
pas le Worker. La 103 en comptait 256 verts et 1 ignoré : les
3 tests du §2 expliquent le passage à 259.

### 4. `flutter analyze`

Flutter 3.47.5, dans `android-app/` :

```
242 issues found. (ran in 15.1s)
```

Code de sortie **1**. Compté sur cette sortie : **0 error**,
**32 warning**, **210 info**. Même nombre de warnings que le
compte-rendu 103. Aucune error ni warning dans les fichiers de
ce changement. Ce dépôt ne sort donc pas « zéro problème ».

## Non prouvé

- **Pas de vraie box.** Pas d'émulateur, pas de `adb`, pas
  d'APK installé. Le code Dart a tourné dans `flutter test`.
- **Pas de délai Internet.** Tout est sur `127.0.0.1`. Le chiffre
  chez un client sera plus grand (le réseau, plus jusqu'à 2,5 s
  pour que la colonne du panel se rafraîchisse).
- **Pas de navigateur.** La page Appareils n'a pas été ouverte.
  Seul le texte de la colonne a été testé.
- **Pas d'écran « mets à jour ».** Le numéro de build local est 0,
  donc l'app ne se bloque pas. L'ordre `force_update` est bien
  arrivé (0,322 s) ; un vieil APK bloqué, non.
- **Pas d'APK publié.** Le workflow `Build Zuno TV` s'est lancé
  tout seul au premier push de cette branche, puis il a été
  annulé avant tout job
  (run `36747041037`, conclusion `cancelled`). Il n'a rien écrit
  sur `zuno-tv`. Le lancement manuel `test_box=true` et
  `publish=false` n'a pas été fait : l'outil GitHub de cette
  machine ne peut pas démarrer un workflow.
- **Pas de déploiement** du Worker Cloudflare ni du panel.
- Les boutons listés « pas chronométrés » plus haut n'ont pas
  leur propre ligne `MESURE`.
- La batterie d'une box n'a pas été mesurée. Ce qui est prouvé :
  le rythme (25 s au lieu de 4 s tant que le canal tient) et le
  plafond 429.

## Essai chronométré pour le propriétaire

Sur un ordinateur qui a Flutter, Node et le dépôt :

```
cd android-app
flutter test --reporter expanded \
  --dart-define=RUN_E2E=true \
  --dart-define=BACKEND_URL=http://127.0.0.1:8787 \
  test/features/subscription/panel_instant_e2e_test.dart
```

Le port 8787 doit être libre. Chaque ligne `MESURE` est un délai
en secondes, sur la machine qui lance la commande. Ce n'est pas
le délai d'une box à la maison.

Pour voir la colonne dans le panel, il faut cette version du
Worker **et** cette version de l'app sur la box. Tant que le
Worker de production n'est pas mis à jour, les box continuent
comme en 103 (3–4 s pour la licence et la liste, le reste au
démarrage).
