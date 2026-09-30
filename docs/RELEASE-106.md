# Zuno 106 — stabilité, image, catalogue, émissions, panel, diagnostic son

Compte-rendu du 30 septembre 2026. Rien n'a été publié sur la release
`zuno-tv`. Le Worker de production n'a pas été déployé. `main` n'a pas
été poussé. Le lecteur 4K (binaire fermé, release `7motion-tv`) n'a
pas été modifié. L'APK n'a pas été signé avec la clé des box (elle
est dans les secrets GitHub ; elle n'est pas sur cette machine).

Cette branche assemble, dans l'ordre, les chantiers ouverts sur la
104 :

1. `claude/zuno-stabilite` (PR #60) — reconnexion 1 s, 2 s, 4 s, 8 s,
   dernière image gardée, reprise d'un film.
2. `claude/zuno-image` (PR #61) — repli décodeur matériel / logiciel /
   FFmpeg vidéo seulement s'il est dans le binaire, fréquence d'écran
   sur demande.
3. `claude/zuno-catalogue-cache` (PR #59) — dernier catalogue films
   et séries gardé sur la box.
4. `claude/zuno-intelligent` (PR #56) — émissions suivies. Cette
   branche partait de la 103 : le délai fixe de 3 s de cette base
   n'a pas été repris, il aurait annulé l'attente croissante.
5. `claude/zuno-panel-instantane` (PR #57) — le panel parle à la box
   tout de suite. Code seulement : le Worker n'est pas déployé.
6. Commit `fb784ab9` (Zuno 105 du codeur, branche
   `claude/app-admin-panel-connection-9fphfr`) — diagnostic du son
   dans la boîte noire, et retour d'écran sans capture (le zoom
   Material photographiait une image vide). Compatible : il est
   posé sur la 104, il ne refait pas le son exclusif. Un seul
   conflit, dans `setUrl` : on remet à zéro le moteur d'image et
   le diagnostic son.
7. Commit `e6f8a3fe` de `claude/zuno-image` (arrivé après la
   première fusion de `fa0d44f6`). Media3 refuse
   `setVideoFrameMetadataListener(null)`. On retire le compteur
   avec `clearVideoFrameMetadataListener` et **le même objet**
   (`frameClock`). Sans ça, le premier APK de la branche image ne
   compilait pas.
8. Imports en double laissés par la fusion (`Format` et
   `DecoderReuseEvaluation`, chacun deux fois). Kotlin les refuse
   (« ambiguous »). Ils sont retirés. Le run
   https://github.com/manzilionellm-dotcom/tvking/actions/runs/36773748899
   (commit `a6e25714`, sans le correctif d'écouteur) est **rouge**
   pour ces deux raisons. Il ne compte pas comme preuve.

Le téléphone et le PC ne sont pas la box. Le `pubspec.yaml` reste
`0.3.0+11` (téléphone). Le nom visible de l'APK TV est planché à
**106** (`FLOOR_VN` dans `.github/workflows/build-zuno-tv.yml`).
Le `versionCode` n'est pas un nombre écrit dans le dépôt : c'est
`date +%s` au moment du build, les secondes epoch. Le workflow
refuse un code inférieur ou égal à **1790642483** (dernier APK de
test déjà accepté par une box ; lui-même au-dessus du 1790640358
de la v102). Au moment de ces tests, l'horloge de la machine lisait
1790799813, donc déjà au-dessus. Le code exact de l'APK est celui
imprimé par le run GitHub, pas un nombre choisi ici.

## Conflits résolus

- `NativeVideoView.kt` (stabilité × image) : les deux jeux d'imports
  (copie de la dernière image, et surface pour la fréquence). Le
  corps a été fusionné sans perdre le jeton de session, le volume
  à 0 avant une reconnexion, l'attente 1/2/4/8 s, l'image tenue,
  le repli décodeur, ni le FFmpeg vidéo conditionnel.
- `tv_player_screen.dart` (imports image + reconnexion).
- `tv_vod_player_screen.dart` : une erreur de flux attend 1/2/4/8 s
  et garde l'image ; si le moteur d'image est épuisé, on s'arrête
  et on le dit.
- `tv_cinema_screen.dart` (stabilité × catalogue) : Git a fusionné
  seul. Le libellé « reprendre » de la stabilité
  (`sectionResumeWhereYouLeftOff`) est resté. Le cache catalogue
  (rechargement, âge, hors ligne) est resté.
- `tv_extras_screen.dart` et la barre du direct (intelligent × image)
  : voix claire, moteur Matériel/Logiciel/FFmpeg, fréquence d'écran,
  et le bouton Suivre. Suivre s'insère après Favori. Guide, REC et
  Favori ne changent pas de place. Le moteur reste le dernier bouton.
- `NativeVideoView.kt` à nouveau, pour la 105 : au changement
  d'adresse, reset du moteur d'image et du diagnostic son.

## Prouvé — commandes exécutées

Machine : Flutter 3.47.5, Dart 3.13.4, Gradle 8.10.2, Java 21.
Les tests Kotlin ne compilent pas `NativeVideoView.kt` (il est
exclu du module `logic-test`, il a besoin du SDK Android et
d'ExoPlayer).

### 1. Suite Flutter, arbre final (après les six fusions)

```
cd android-app && flutter test --reporter compact
```

Sortie finale (30 septembre 2026), code de sortie **0** :

```
00:21 +338 ~2: All other tests passed!
```

**338 tests passés, 2 ignorés, 0 échec.** Les 2 ignorés sont
`panel_box_e2e_test.dart` et `panel_instant_e2e_test.dart` : ils
demandent `RUN_E2E` et wrangler. Ils n'ont pas été lancés.

Mesures écrites par cette suite (mémoire, pas un flux) :

```
MESURE zap_20_microsecondes=123
MESURE budget_app_ms=1180
MESURE decision_reconnexion_20_microsecondes=41
```

123 microsecondes : qui a le droit de parler, 20 fois. 41
microsecondes : décider d'une reconnexion, 20 fois. 1180 ms : le
budget d'attente applicatif testé (sous 2 s). Aucun de ces chiffres
n'est un délai de zap sur une box.

### 2. La même suite, après chaque fusion

Même commande, sur chaque commit de fusion, avant le commit de
version. Code de sortie **0** à chaque fois. Le `~1` puis `~2`
sont les tests e2e ignorés faute de `RUN_E2E`.

| Fusion | Résultat |
| --- | --- |
| 1. stabilité `1a72e519` | `+282 ~1` |
| 2. image `01753708` | `+289 ~1` |
| 3. catalogue `a69e0323` | `+308 ~1` |
| 4. intelligent `a6615d6c` | `+335 ~1` |
| 5. panel `b2c863bc` | `+338 ~2` |
| 6. diagnostic 105 `2eccc171` | `+338 ~2` |

La 104 s'arrêtait à `+271 ~1`. Aucune fusion n'a fait baisser le
nombre de tests passés.

### 3. Kotlin, logique pure (sans Android)

```
gradle -p android-app/packages/native_video_player/logic-test test --rerun-tasks
```

```
BUILD SUCCESSFUL
55 tests, 0 échec, 0 ignoré
```

Détail lu dans les rapports XML du run :

| Classe | Tests |
| --- | ---: |
| PlaybackSessionTest (jeton, 20 zaps) | 3 |
| SpokenTrackChoiceTest | 7 |
| ClearVoiceGainTest | 4 |
| ReconnectPlanTest | 9 |
| DecoderFallbackTest | 11 |
| FrameRateMatchTest | 8 |
| VideoTrackChoiceTest | 8 |
| AudioDiagnosisTest (105) | 5 |
| **Total** | **55** |

```
MESURE zap_20_microsecondes=55
MESURE budget_app_ms=1180 tampon_ms=1000 zap_ms=180
MESURE decision_reconnexion_20_microsecondes=6 dernier_delai_ms=8000
```

### 4. `flutter analyze`

Même commande que le workflow
(`--no-fatal-infos --no-fatal-warnings`) :

```
242 issues found. (ran in 13.9s)
```

Code de sortie **0**. Comptage sur cette sortie : **0 error**,
**32 warning**, **210 info**. Les 32 warnings sont le même nombre
que la note 104. Le warning déjà connu `primary` inutilisé dans
`tv_player_screen.dart` est dans ce compte. Aucun error nouveau.

### 5. Décisions pures du panel (sans Worker, sans navigateur)

```
node android-app/cloudflare/box_signal_pure.test.mjs
node --experimental-strip-types android-app/admin-panel/src/lib/boxLive.test.ts
```

Les deux commandes se terminent par `PASS` (code de sortie 0).
16 contrôles dans le premier (gel, bannissement, ordre déjà vu,
expiration), 5 assertions dans le second (texte « en ligne »,
« en attente »). Ce n'est pas un appel au Worker de production.

## Pas prouvé — seulement sur une vraie box

- **Pas de box.** Pas d'`adb`, pas d'émulateur, pas de flux IPTV,
  pas de haut-parleur. Aucun des tests ci-dessus n'a ouvert une
  chaîne.
- **Pas d'APK signé.** Pas de keystore. Signature, Leanback,
  `applicationId` et le `versionCode` réel de l'APK ne sont connus
  qu'une fois le workflow GitHub terminé. S'il est rouge, on ne
  pose pas l'APK.
- `NativeVideoView.kt` (ExoPlayer, surface, FFmpeg, copie d'image,
  diagnostic son) n'est pas couvert par `logic-test`. Une compilation
  locale est tentée si le SDK Android s'installe ; le résultat est
  noté à la fin de ce fichier, ou remplacé par le run GitHub.
- Le push de `claude/zuno-106` déclenche tout seul
  `build-zuno-tv.yml` (chemins `android-app/**` et le workflow).
  `PUBLIER` n'est vrai que sur `main` ou avec `publish=true`.
  Ce run ne réécrit pas `zuno-tv`. `test_box` n'est pas lancé
  depuis ici : le déclenchement manuel n'a pas été fait (le push
  suffit pour la vérification, et il ne publie pas).
- Le Worker Cloudflare n'est pas déployé. Le code du canal
  (`box_signal.js`, migration `010_box_commands.sql`) est dans la
  branche, pas en production.
- 1080i, AC-3 vers une barre de son, HE-AAC « vieille radio »,
  fréquence 50/60 Hz : non mesurés.
- Une box déjà en v102, ou une box qui a déjà un APK de test au
  `versionCode` 1790642483, n'a pas installé cet APK.

## Procédure sur une box de test

À faire sur **une seule** box, avec l'APK produit par le workflow de
**cette branche** (artefact du run). Pas le lien `zuno-tv`.

Préparez deux chaînes dont vous reconnaissez la voix. Notez un film
déjà commencé, et coupez le réseau seulement à l'étape 4.

1. **20 zaps.** Ouvrez la chaîne A. Zappez vers B, puis A, puis B,
   **20 fois**, aussi vite que la télécommande le permet. Vous ne
   devez jamais entendre **deux voix en même temps**. Vous ne devez
   pas rester sur un **écran noir** : un flash très court sous le
   logo peut arriver, un noir de plusieurs secondes est un échec.
   Au 20e zap, une seule voix, une image.
2. **30 secondes.** Restez sur cette chaîne sans toucher. Pas de
   coupure, pas de boucle (la même phrase qui revient), pas d'image
   figée.
3. **Film avec reprise.** Ouvrez un film, avancez d'au moins une
   minute, quittez, rouvrez-le. Il reprend près de l'endroit quitté
   (quelques secondes avant, c'est voulu).
4. **Réseau coupé, liste toujours là.** Coupez le réseau de la box.
   Ouvrez Films. La liste du dernier catalogue doit s'afficher
   (elle était déjà sur la box). Sans catalogue jamais chargé, la
   liste vide est normale : ce test suppose un catalogue déjà vu
   une fois en ligne.
5. **Moteur.** Réglages → En plus → Moteur image. Le réglage
   d'origine est **Matériel**. OK passe à **Logiciel**. Revenez au
   direct : l'image doit être là (c'est le repli quand le matériel
   donne du noir). OK encore dit que FFmpeg vidéo n'est pas dans
   cette version et ne change pas de moteur. Remettez Matériel.
6. **1080i.** Ouvrez une chaîne entrelacée 1080i si vous en avez
   une. L'image ne doit pas rester noire, ni se dédoubler au point
   d'être illisible. Le désentrelacement est celui de la puce : on
   n'en a pas écrit un.

Critère : les six points tiennent. Sinon on ne publie pas.
Le chiffre de 123 microsecondes ne compte pas : c'est un test sans
flux.

## Mise en service (quand vous le déciderez)

1. Lire le run du workflow de cette branche. S'il est rouge, on ne
   pose pas l'APK.
2. Installer cet APK sur **une** box et faire les 6 étapes.
3. Seulement ensuite : push `main` ou workflow manuel avec
   `publish=true`. Jamais `publish=true` pour un essai.

Retour arrière : ne pas republier un `versionCode` plus petit que
celui déjà en ligne (v102 = 1790640358, et un APK de test peut déjà
être à 1790642483). Tant que `zuno-tv` n'est pas réécrit, les
clients restent en v102. Rien à annuler côté Cloudflare : le Worker
n'a pas été déployé.
