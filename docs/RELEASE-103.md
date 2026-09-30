# Zuno 103 — activation et effacement de liste

Compte-rendu du 30 septembre 2026. Rien n'a été publié sur la release
`zuno-tv`. Le Worker de production n'a pas été déployé. `main` n'a pas
été poussé.

Les chiffres ci-dessous sont ceux des commandes réellement exécutées
sur cette machine. Un délai mesuré en local (Worker sur
`127.0.0.1:8787`) n'est pas le délai d'une box chez un client.

## Ce qui change

- La box interroge `GET /api/status` toutes les **3 s** tant qu'elle
  attend une activation ou ses premières chaînes, puis toutes les **4 s**.
  En cas d'échecs réseau, l'attente double jusqu'à 45 s. Une lecture
  ratée ne remplace pas le dernier statut connu.
- Les codes IPTV ne sont rechargés que si `source_rev` a changé (ou si
  le Worker est encore ancien et n'envoie pas ce champ).
- Retirer une liste dans le panel (`DELETE /api/v1/sources/:mac` avec
  l'adresse et l'identifiant, ou `PUT` du lot restant) écrit une
  empreinte. La box enlève cette liste, ses chaînes, les favoris et
  l'historique de ces chaînes, et le mot de passe stocké. Une autre
  liste n'est pas touchée.
- Sans jeton : 401. Revendeur sans droit `sources` : 403. Revendeur qui
  n'a pas cette box : 403. Effacer une autre MAC ne vide pas celle-ci.
  Un second effacement de la même liste répond `already: true`.
- Hors ligne, la liste reste. Au retour du réseau, l'empreinte déjà
  écrite est appliquée.
- Message par-dessus la lecture (« Ton revendeur a retiré cette liste »).
  « Continuer » ferme le lecteur. S'il ne reste plus de liste, l'écran
  « Ajouter ma liste » s'ouvre.
- Le nom visible de l'APK TV est planché à **103** dans
  `.github/workflows/build-zuno-tv.yml` (le `pubspec.yaml` reste
  `0.3.0+11`, il sert au téléphone). Le `versionCode` doit être
  strictement au-dessus de **1790640358** (v102). Ce plancher est dans
  le script : **il n'a pas été exécuté ici** (workflow non lancé).

## Prouvé — commandes exécutées

### 1. Preuve panel → box (Worker réel + client Dart réel)

`wrangler` 4.42.1, `wrangler dev` sur `127.0.0.1:8787`, D1 locale dans
un dossier temporaire, schéma `schema.sql` plus la migration
`003_reseller_hierarchy.sql`. Côté app : `RemoteActivationWatch`,
`SubscriptionState`, `RemoteSourceRepository`, `PlaylistRepository` et
une base SQLite réelle (`sqflite_common_ffi`). Pas un faux du même code.

Commande (30 septembre 2026, sortie complète du passage vert) :

```
cd android-app
flutter test --reporter expanded \
  --dart-define=RUN_E2E=true \
  --dart-define=BACKEND_URL=http://127.0.0.1:8787 \
  test/features/subscription/panel_box_e2e_test.dart
```

```
00:00 +0: loading .../panel_box_e2e_test.dart
00:00 +0: (setUpAll)
00:02 +0: panel efface la liste, la box se vide, délais mesurés
[Flavor] init → sevenMotion (The Few)
[DB] Ouverture de la base SQLite : /tmp/zuno-box-db-CUFEZA/tv_king.db
[DB] Schéma v6 créé.
[BlackBox] 30/09 11:38:23 I [DB] lecture : 1 chaînes, 1 liste(s) en 5 ms

MESURE activation_secondes=4.048
[BlackBox] 30/09 11:38:38 I [DB] lecture : 0 chaînes, 0 liste(s) en 0 ms

MESURE effacement_secondes=3.848
[BlackBox] 30/09 11:38:38 I [DB] lecture : 2 chaînes, 2 liste(s) en 1 ms

[Subscription] getStatus error: ClientException with SocketException: Connection refused ... uri=http://127.0.0.1:8787/api/status/MK:AA:BB:CC:DD:01
[DeviceSecret] enroll: ClientException ... Connection refused ... /api/device-proof
[RemoteSource] sync error: ClientException ... Connection refused ... /api/device-source/MK:AA:BB:CC:DD:01

[BlackBox] 30/09 11:38:44 I [DB] lecture : 1 chaînes, 1 liste(s) en 1 ms

MESURE retour_reseau_secondes=3.231
00:24 +1: (tearDownAll)
00:24 +1: All tests passed!
```

Les trois lignes `Connection refused` sont le scénario hors-ligne :
le Worker a été arrêté exprès. Le test a ensuite exigé que la liste
soit encore là, puis a relancé le même dossier D1.

Délais lus sur le chronomètre du test (secondes, localhost) :

| Mesure | Secondes |
|---|---|
| Clic d'activation (`POST /api/v1/activate`, plan `lifetime`) → statut payé sur la box | **4,048** |
| `DELETE` de la liste A → playlist, chaînes, favoris, récents, session et mot de passe de A absents | **3,848** |
| Worker coupé puis relancé → A disparaît, B reste | **3,231** |

Le test a aussi exigé, et il est passé, donc ces points sont prouvés
sur cette base locale :

- sans jeton, le `DELETE` répond 401 et la liste A est encore en SQLite ;
- revendeur sans droit `sources` : 403 ;
- autre revendeur, avec le droit `sources` mais pas propriétaire de
  cette MAC : 403, liste A toujours là ;
- `DELETE` sur une autre MAC : la box de ce test garde A ;
- second `DELETE` de A : HTTP 200 et `already: true` ;
- le `GET /api/status` contient `"revoked"` et ne contient pas le mot
  de passe `secret-liste-a` ;
- l'avis local `RemovedListNotice` a `removed > 0` et `noneLeft: true`
  après le premier effacement ;
- le favori d'une chaîne qui n'appartient pas à A (`ch-other`) reste ;
- après re-semis de A et B, seul A part au retour du réseau ; le mot
  de passe de B et la chaîne `ch-b` restent.

`flutter test` sans `RUN_E2E` **ignore** ce fichier (le CI n'a pas
besoin de wrangler). Vérifié : `Skip: RUN_E2E non posé`.

### 2. Écran « Ajouter ma liste » (harnais Flutter, pas une box)

```
flutter test --reporter expanded \
  test/features/tv/removed_list_prompt_test.dart
```

```
00:00 +5: ... liste retirée, plus rien : message puis Ajouter ma liste
[DefaultServers] HTTP 400
00:01 +6: ... il reste une autre liste : retour à l'accueil, pas d'ajout
00:01 +7: All tests passed!
```

(`+5` parce que le fichier de rythme, lancé dans la même commande, a
5 tests. Les deux tests d'écran sont `+6` et `+7`.)

Ce qui est prouvé ici : un faux lecteur affiche « lecteur » ; le
message « Liste retirée » / « Ton revendeur a retiré cette liste »
s'ouvre **par-dessus** ; après « Continuer », le faux lecteur n'est
plus là et le titre « Ajouter ma liste » est affiché. S'il reste une
autre liste, on revient à l'accueil et « Ajouter ma liste » n'apparaît
pas.

Ce n'est pas l'app Android TV. Le lecteur est un `Scaffold` de test.

### 3. Rythme et empreinte (calcul pur)

5 tests dans `activation_pace_test.dart`, inclus dans la commande
ci-dessus (`All tests passed`) : 3 s / 4 s / plafond 45 s, rechargement
des codes seulement si `source_rev` change, une lecture ratée garde le
dernier statut, empreinte identique au Worker, `source_rev` absent /
zéro / nombre.

### 4. Worker (faux D1 en mémoire, pas la preuve box)

```
node android-app/cloudflare/zuno_security.test.mjs
```

```
PASS empreinte xtream identique à la box
PASS status porte source_rev et revoked, jamais le mot de passe
...
28 passed, 0 failed
```

Ce fichier ne remplace pas la preuve du §1 : il ne lance pas wrangler
et ne parle pas au client Dart.

### 5. Suite Flutter, sans la preuve réseau

```
cd android-app && flutter test --reporter compact
```

Sortie finale (30 septembre 2026) :

```
00:11 +256 ~1: All other tests passed!
```

Le `~1` est `panel_box_e2e_test.dart`, ignoré faute de `RUN_E2E`.
Les deux tests d'écran du §2 font partie des 256.

### 6. `flutter analyze`

Flutter 3.47.5, `flutter analyze` dans `android-app/` :

```
248 issues found. (ran in 14.4s)
```

Code de sortie **1**. Détail compté sur cette sortie : **0 error**,
**32 warning**, le reste en `info`. Aucune error ni warning dans les
fichiers ajoutés ou modifiés pour la 103. Les 32 warnings sont
antérieurs (champs inutilisés, etc.). Ce dépôt ne sort donc pas
« zéro problème » avec cet analyseur. Le workflow CI relance
`flutter analyze` : son résultat sur GitHub **n'a pas été lu ici**.

## Non prouvé — seulement une vraie box

- **Pas d'émulateur Android sur cette machine.** `adb` absent,
  `ANDROID_HOME` vide, binaire `emulator` absent. Aucune capture,
  aucun log logcat, aucune photo d'écran TV.
- **Pas d'APK release signé.** Le mot de passe du keystore n'est pas
  sur cette machine. Le certificat attendu
  `5145b8e0…9e61`, Leanback, `applicationId` et le `versionCode` de
  l'APK **n'ont pas été vérifiés sur un fichier APK**.
- Le workflow `build-zuno-tv.yml` **n'a pas été lancé à la main**.
  Un push de `claude/zuno-103` peut le déclencher (compilation seule :
  `PUBLIER` n'est vrai que sur `main` ou `publish=true`). Cette
  compilation, si elle part, n'est pas un résultat déjà en main au
  moment de ce document.
- Le clic dans le **navigateur du panel** n'a pas été fait. La preuve
  du §1 appelle les mêmes routes HTTP (`POST /api/v1/activate`,
  `PUT` et `DELETE /api/v1/sources/:mac`, login revendeur
  `/api/v1/auth/reseller/login`).
- La lecture d'un **vrai flux** (image qui continue derrière le
  message, puis s'arrête au « Continuer ») n'a pas été regardée.
- Le délai **Internet** jusqu'à `https://app.7themotion.com` n'a pas
  été mesuré. 4,0 s et 3,8 s sont le rythme local (veille 3 s ou 4 s
  plus le temps de réponse de wrangler sur la même machine).
- Une box déjà en **v102** n'a pas installé cet APK. Profils, listes
  et clés déjà présentes chez un client n'ont pas été migrés sur un
  appareil.
- `version.json` de la release `zuno-tv` n'a pas été réécrit.

## Procédure manuelle — 5 étapes, chronomètre

À faire sur **une seule** box, après avoir installé l'APK produit par
le workflow de la branche (artefact du run, **pas** le lien
`zuno-tv` tant que vous n'avez pas décidé de publier).

1. La box est allumée, une liste est visible, des chaînes sont en
   cache. Lancez un chronomètre à la seconde.
2. Dans le panel, ouvrez **cette** box et retirez **cette** liste
   (page Sources). Ne touchez pas la télécommande pendant l'attente.
3. Regardez l'écran. Le flux ne doit pas mourir d'un coup : le message
   « Ton revendeur a retiré cette liste » passe par-dessus. Appuyez
   sur **Continuer**.
4. S'il ne restait qu'une liste, l'écran doit afficher
   **Ajouter ma liste**. Arrêtez le chronomètre à cet instant et notez
   les secondes. Les chaînes, favoris et le code de la liste retirée
   ne doivent plus être proposés. Une autre liste, si vous en aviez
   laissé une, doit encore être là.
5. Coupez le réseau de la box (Wi-Fi ou câble). Retirez une liste dans
   le panel. La box doit **garder** la liste. Rallumez le réseau et
   relancez le chronomètre jusqu'à la disparition.

Même chronomètre pour l'activation, sur une box encore à l'écran du
code : clic « Activer » dans le panel, arrêt du chronomètre quand
l'accueil s'ouvre seul. Le chiffre local de référence est 4,048 s ;
le vôtre, sur Internet, est celui qui compte.

Critère de go : les deux chronomètres tiennent en quelques secondes,
une seule liste part, la lecture n'est pas coupée avant le message,
et l'APK s'installe par-dessus la v102 (même signature). Sinon : no-go,
on ne publie pas.

## Mise en service (quand vous le déciderez)

1. Secrets Cloudflare déjà requis par le Worker actuel :
   `ADMIN_SECRET` (signature des jetons) et `SOURCE_ENCRYPTION_KEY`
   (chiffrement au repos des mots de passe ; sans cette clé le Worker
   laisse le texte en clair, il n'invente pas une clé). **Ils n'ont
   pas été lus ni modifiés ici.**
2. Déployer le Worker **avant** l'app. Sans le nouveau Worker, la box
   ne reçoit pas `source_rev` / `revoked`.
3. Installer l'APK 103 sur **une** box et faire la procédure des
   5 étapes.
4. Seulement ensuite : push `main` ou workflow manuel avec
   `publish=true`. Jamais `publish=true` pour un essai.

Retour arrière : ne pas republier un `versionCode` plus petit que
celui déjà en ligne (la v102 est à 1790640358 ; un APK plus petit ne
s'installe pas par-dessus). Si une 103 publiée est mauvaise, on
compile la version précédente avec un `versionCode` **plus grand**.
Tant que `zuno-tv` n'est pas réécrit, les clients restent en v102.
Le Worker de production n'ayant pas été déployé par ce travail, il
n'y a rien à annuler côté Cloudflare pour l'instant.
