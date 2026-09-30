# Zuno 104 — un seul son, une image qui ne clignote pas au zap

Compte-rendu du 30 septembre 2026. Rien n'a été publié sur la release
`zuno-tv`. Le Worker de production n'a pas été déployé. `main` n'a pas
été poussé. Le lecteur 4K (binaire fermé, release `7motion-tv`) n'a
pas été modifié.

Les chiffres ci-dessous sont ceux des commandes réellement exécutées
sur cette machine. Un test en mémoire, sans flux et sans haut-parleur,
n'est pas une box chez vous.

## Cause du double son

Elle est dans le code d'avant la 104. Elle n'a pas été entendue ici
(pas de box, pas de flux).

1. Le lecteur demandait à Android de **ne pas** gérer le focus audio
   (`handleAudioFocus = false`). L'aperçu (petite image) et le plein
   écran sont deux lecteurs ExoPlayer. Les deux pouvaient sortir du
   son en même temps : Android ne coupait ni l'un ni l'autre.
2. Un zap faisait `stop()` puis `prepare()` **sans** mettre le volume
   à 0 d'abord. Sur certaines puces, le petit tampon de sortie
   (surtout en AC-3 envoyé tel quel à la barre de son) continue
   l'ancienne chaîne pendant que la nouvelle démarre.
3. Des rappels tardifs (coupure réseau, repli du décodeur FFmpeg,
   délai de 8 secondes) relançaient `prepare()` / `play()` **sans
   jeton**. Une chaîne déjà quittée pouvait reparler.
4. L'accusé envoyé à l'écran partait **avant** le `stop()`. Une
   « première image » de l'ancienne chaîne pouvait encore passer et
   cacher le logo sur une image figée.

## Ce que le code fait maintenant

- Avant d'ouvrir une chaîne, **tous les autres lecteurs** passent
  volume 0 puis `stop()`. Un seul a le droit de parler.
- Chaque ouverture ou chaque silence prend un **nouveau numéro**.
  Un rappel qui porte l'ancien numéro ne relance plus rien.
- Le focus audio Android est demandé (`handleAudioFocus = true`).
  Un lecteur déjà coupé par un autre refuse `play()`.
- Tant qu'un plein écran (direct, film, enregistrement) est ouvert,
  l'aperçu ne crée pas un second lecteur.
- L'accusé part **après** le silence. Une première image plus vieille
  que cette ouverture est jetée.
- La piste audio automatique prend la **langue de l'app** (`fre` /
  `fra` = français). Un commentaire ou une audiodescription (mot dans
  le nom, ou drapeau Media3) ne gagne pas. Si la piste déjà choisie
  est la bonne, on ne change pas (pas de second basculement). Si
  **toutes** les pistes sont des commentaires, on ne coupe pas le son.
  Un choix à la main n'est pas écrasé.
- AAC et MP2 passent par FFmpeg quand il est là, avec le même retour
  au décodeur de la box si ça bloque (leçon v99–v101). AC-3, E-AC-3
  et DTS restent sur le décodeur de la box, pour le passthrough HDMI.
- Les tampons **réseau** ne changent pas : 5 s de base, 45 s max,
  1 s pour démarrer, 2 s pour reprendre après une coupure. Les avoir
  allongés en v99–v101 a laissé des chaînes sur le logo. Contre les
  craquements, seul le petit tampon de **sortie** AudioTrack est
  doublé, avec un plafond de +256 Ko, aligné sur la taille d'une
  frame. On ne garde pas des secondes de l'ancienne chaîne.
- La vitesse du direct reste figée à 1,0. On ne saute pas les
  silences (ça coupait le début des phrases). Sortie flottante et
  réglage de vitesse de l'AudioTrack : coupés (craquements, son
  étiré).
- Après un direct « trop en retard » ou une coupure, on **rouvre**
  le flux (stop, puis nouveau média) au lieu de seulement recaler
  la tête de lecture. Le but est de ne pas laisser le son devant
  l'image. Ce n'est pas mesuré sur un vrai flux.
- **Voix claire / mode nuit** : Réglages → En plus. **Coupée par
  défaut** (clé `zuno.player.clear_voice.v1`, pas le drapeau box qui
  vaut vrai s'il est absent). Allumée, un compresseur 3:1 baisse les
  pics au-dessus de 0,40, sans remonter les chuchotements, gain
  plancher 0,45. Ça ne s'applique qu'au son déjà décodé (PCM : AAC,
  MP2). Le passthrough AC-3 / DTS vers une barre de son n'est pas
  modifié. Ce n'est **pas** une mise à niveau EBU R128 : les flux
  IPTV n'ont en général pas de mesure de volume fiable, et un gain
  aveugle d'une chaîne à l'autre peut saturer ou assourdir. On ne
  l'a pas ajouté.
- Image, volontairement prudente : décodeur matériel, repli vers le
  suivant si l'init échoue, **pas** de décodeur vidéo FFmpeg (il a
  bloqué des chaînes). Changement de qualité HLS : on ne demande pas
  au décodeur d'attendre (temps de jointure 0, sinon image figée sur
  les puces faibles). Format : toute l'image, bandes noires, pas de
  rognage. On ne demande **pas** à la TV de changer de fréquence HDMI
  (50 Hz ↔ 60 Hz) : sur beaucoup de box ça fait un écran noir et
  décale le son. Pas de tunneling. Un flux qui change de codec vidéo
  (H.264 → HEVC) est autorisé à changer. Au zap, on **ne détache pas**
  la surface (la détacher fait un flash noir). `stop()` reste
  nécessaire pour rendre le codec : sous le logo, certaines puces
  peuvent encore montrer un court noir. Le désentrelacement reste
  celui de la puce. On n'a pas écrit de désentrelaceur logiciel.

Le téléphone et le PC ne sont pas la box. Sur PC, « se taire » met
le volume à 0 et met en pause. La voix claire n'existe pas sur PC
(pas de compresseur Media3). Le `pubspec.yaml` reste `0.3.0+11`
(téléphone). Le nom visible de l'APK TV est planché à **104** dans
`.github/workflows/build-zuno-tv.yml`. Le `versionCode` doit rester
les secondes epoch, donc au-dessus de **1790640358** (v102). Ce
script **n'a pas été exécuté ici**. La v103 n'a pas été publiée :
les clients sont encore en v102. Une 104 s'installe par-dessus si
la signature est la même et le `versionCode` plus grand. Profils,
listes et clés déjà sur la box ne sont pas migrés par ce changement
(nouvelle préférence, absente = voix claire coupée).

## Prouvé — commandes exécutées

Machine : Flutter 3.47.5, Dart 3.13.4, Gradle 8.10.2, Java pour les
tests Kotlin. Pas de SDK Android : `NativeVideoView.kt` et
`ClearVoiceProcessor.kt` **n'ont pas été compilés**. Les tests Kotlin
ne compilent que la logique pure (jeton, bail, choix de piste, gain,
taille de tampon).

### 1. Un seul propriétaire du son, et 20 zaps en mémoire

```
cd android-app && flutter test --reporter compact
```

Sortie finale (30 septembre 2026) :

```
00:15 +271 ~1: All other tests passed!
```

Le `~1` est `panel_box_e2e_test.dart`, ignoré faute de `RUN_E2E`
(il a besoin de wrangler). La 103 s'arrêtait à `+256 ~1`. Les 15
tests en plus sont le son de la 104 :

- jeton : l'ancien numéro ne compte plus ;
- prendre le son coupe les autres lecteurs ;
- 20 prises d'affilée : un seul reste audible ;
- le plein écran bloque l'aperçu, puis le libère ;
- langue (`fre` / `fra` / `en-US`), commentaire, drapeau Media3,
  piste déjà bonne, que des commentaires = on ne coupe pas,
  « Recommended » n'est pas un commentaire ;
- deux faux lecteurs : le second coupe le premier avant d'ouvrir,
  20 zaps, la première liste choisit le français et un choix manuel
  n'est pas écrasé.

Pendant cette suite, le test des 20 prises a écrit :

```
MESURE zap_20_microsecondes=127
```

**127 microsecondes.** C'est le temps de la comptabilité en mémoire
(qui a le droit de parler). Il n'y a pas de flux, pas d'AudioTrack,
pas d'image. Le plafond du test est 50 ms pour cette comptabilité,
pas un délai de zap sur une box.

### 2. La même règle, en Kotlin (sans Android)

```
gradle -p android-app/packages/native_video_player/logic-test test --rerun-tasks
```

```
BUILD SUCCESSFUL
14 tests, 0 échec
MESURE zap_20_microsecondes=68
```

14 = 3 (jeton et bail) + 7 (choix de piste) + 4 (gain voix claire
et taille du tampon AudioTrack). Le pic à pleine échelle est ramené
à un gain 0,60. Sous le seuil 0,40, le gain reste 1. Un tampon de
1 000 octets passe à 2 000. Un très gros tampon ne gagne que 256 Ko.
**68 microsecondes** : même limite que ci-dessus, toujours sans son.

### 3. `flutter analyze`

Même commande que le workflow (`--no-fatal-infos --no-fatal-warnings`) :

```
242 issues found. (ran in 1.4s)
```

Code de sortie **0** avec ces drapeaux. Détail compté sur cette
sortie : **0 error**, **32 warning**, le reste en `info`. Les 32
warnings sont le même nombre que la note 103. Aucun error. Le
warning déjà connu dans `tv_player_screen.dart` (paramètre
`primary` inutilisé) est dans ce compte. Le résultat GitHub de
cette branche **n'a pas été lu ici**.

## Non prouvé

- **Pas de box.** `adb` absent, pas d'émulateur, pas de SDK Android.
  Aucun logcat, aucune photo, aucun flux IPTV lu.
- **Pas d'APK.** Pas de keystore sur cette machine. Signature,
  Leanback, `applicationId` et `versionCode` de l'APK **non vérifiés**.
- `NativeVideoView.kt` (ExoPlayer, focus, surface, FFmpeg, repli) et
  `ClearVoiceProcessor.kt` **n'ont pas été compilés**. Un test vert
  sur la logique pure ne prouve pas que le lecteur Android démarre.
- Le workflow `build-zuno-tv.yml` **n'a pas été lancé à la main**.
  Le push de `claude/zuno-104` peut le déclencher tout seul
  (les chemins `android-app/lib`, `packages`, `pubspec.yaml` et le
  workflow lui-même sont dans la liste). `PUBLIER` n'est vrai que
  sur `main` ou avec `publish=true`. Cette compilation, si elle
  part, n'écrit pas `zuno-tv`. Son résultat n'est pas dans ce
  document.
- Pas de normalisation de volume entre chaînes (voir plus haut).
- Pas de désentrelaceur écrit par nous. Pas de bascule HDR / fréquence
  HDMI : laissées exprès, pour éviter l'écran noir.
- Le court noir sous le logo, sur certaines puces, au moment du
  `stop()`, n'est pas éliminé. On a seulement évité de détacher la
  surface en plus.
- Une box déjà en v102 n'a pas installé cet APK.

## Procédure sur votre box — chronomètre, 20 zaps

À faire sur **une seule** box, avec l'APK produit par le workflow de
**cette branche** (artefact du run). Pas le lien `zuno-tv` tant que
vous n'avez pas décidé de publier.

Préparez deux chaînes dont vous reconnaissez la voix (deux speakers
différents, ou une langue différente). Notez leurs numéros.

1. Lancez le chronomètre à la seconde. Ouvrez la chaîne A. Attendez
   que l'image et la voix soient stables.
2. Zappez vers B, puis A, puis B, **20 fois**, le plus vite que la
   télécommande le permet. Ne vous arrêtez pas pour écouter entre
   chaque zap, sauf si vous entendez **deux voix en même temps** :
   dans ce cas, arrêtez et notez à quel zap.
3. Au 20e zap, attendez que l'image soit stable et que **une seule**
   voix parle. Arrêtez le chronomètre. Notez les secondes.
4. Restez **30 secondes** sur cette chaîne, sans toucher. Vous ne
   devez pas entendre de boucle (le même bout de phrase qui revient),
   ni un craquement continu, ni voir l'image figée ou un écran noir
   qui dure.
5. Zappez encore une fois, lentement. L'ancienne voix doit disparaître
   avant que la nouvelle soit claire. Un flash très court sous le
   logo peut arriver : un écran noir de plusieurs secondes, non.
6. Réglages → En plus. **Voix claire** doit être **coupée**. Allumez-la,
   revenez au direct, zappez une fois. Les voix très fortes doivent
   être un peu moins criardes sur une chaîne en AAC. Une barre de son
   qui recevait déjà l'AC-3 tel quel doit continuer à le recevoir
   (le surround ne passe pas dans le compresseur). Recoupez l'option
   si le son vous plaît moins : c'est le réglage d'origine.

Critère de go : sur les 20 zaps, jamais deux voix ensemble ; le
chronomètre du point 3 reste de l'ordre de ce que vous jugez
acceptable (le chiffre de 127 microsecondes **ne compte pas**, c'est
un test sans flux) ; les 30 secondes du point 4 sont propres ; l'APK
s'installe par-dessus la v102 (même signature). Sinon : no-go, on ne
publie pas.

## Mise en service (quand vous le déciderez)

1. Lire le résultat du workflow de la branche (compilation seule).
   S'il est rouge, on ne pose pas l'APK.
2. Installer cet APK sur **une** box et faire les 6 étapes.
3. Seulement ensuite : push `main` ou workflow manuel avec
   `publish=true`. Jamais `publish=true` pour un essai. Pas de
   `test_box` lancé depuis ici.

Retour arrière : ne pas republier un `versionCode` plus petit que
celui déjà en ligne (la v102 est à 1790640358). Tant que `zuno-tv`
n'est pas réécrit, les clients restent en v102. Rien à annuler côté
Cloudflare : le Worker n'a pas été déployé.
