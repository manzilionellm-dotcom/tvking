# Image — Zuno TV

Branche `claude/zuno-image`, à partir de `claude/zuno-104` (son corrigé).
Brouillon vers `claude/zuno-104`. Rien n'est publié, la release `zuno-tv`
n'est pas modifiée, le Worker n'est pas déployé, le 4K Player n'est pas touché.

Ce texte dit ce qui est **prouvé** (un test a tourné ici) et ce qui ne l'est **pas**
(aucune box, aucune photo d'écran, aucune mesure d'image).

## Ce que fait l'image aujourd'hui

La vidéo est dessinée dans une Surface Android par Media3 (ExoPlayer).
Le décodeur de la box (MediaCodec, en matériel) écrit directement dedans.
On ne passe pas par une texture Flutter : c'est ce qui avait laissé l'image
noire avec d'autres lecteurs.

Réglages déjà en place, et **laissés tels quels** (les changer avait bloqué
des chaînes en v99–v101) :

- le matériel d'abord, un autre décodeur MediaCodec seulement si le premier
  ne démarre pas ;
- pas de tunneling audio/vidéo (écran noir fréquent) ;
- pas de changement de fréquence HDMI tout seul ;
- la surface n'est pas détachée au zapping (la détacher fait un flash noir) ;
- le carton de chaîne (fond plein écran) reste tant que la première image
  n'est pas là ;
- tampon inchangé : 5 s / 45 s, départ à 1 s, reprise à 2 s ;
- une chaîne 4K sur une TV 1080p démarre quand même ;
- H.264, HEVC et MPEG-2 passent par le décodeur que la box propose ;
- un trou de réseau est réessayé ; ce n'est pas traité comme une panne d'image ;
- HDR, Dolby Vision, HLG : on ne retire pas les infos de couleur du flux.
  On ne les force pas non plus. Rien de nouveau de ce côté ;
- le ratio est « toute l'image, bandes noires si besoin ». On ne rogne pas ;
- un flux entrelacé (1080i) n'a pas de filtre à nous. C'est le décodeur de
  la box qui désentrelace, ou pas. On ne l'a pas vu sur une TV.

## Ce qui a été ajouté

1. **Repli du décodeur**, seulement si la lecture échoue avec un code
   décodeur vidéo, ou si l'image est noire / figée alors que la lecture
   est prête (pas pendant un simple chargement). Un avertissement de
   codec que Media3 peut rattraper tout seul ne change pas de moteur :
   la doc Media3 dit que ce n'est pas un échec de lecture.
   Ordre : matériel → logiciel Android (`OMX.google` / `c2.android`) →
   FFmpeg **si** la bibliothèque dit qu'elle sait lire la vidéo.
   On ne revient pas au matériel tout seul.
   Une nouvelle chaîne repart du choix de la personne (matériel par défaut).
2. **Bouton « Matériel / Logiciel / FFmpeg »** dans le direct (barre du bas,
   après Guide, REC, Favori) et dans Films / Séries. Le choix est mémorisé.
   Réglages → En plus → « Moteur image » fait le même cycle.
3. **Fréquence d'écran**, coupée par défaut. Si on l'allume : 24 → 24 Hz,
   25 → 50 Hz, 30 → 60 Hz, 50 → 50 Hz, 60 → 60 Hz, seulement si la TV a
   ce mode. Sinon on ne change rien. On remet la fréquence d'origine en
   quittant le lecteur. Réglages → En plus → « Fréquence de l'écran ».
4. **Piste vidéo** : s'il y a plusieurs pistes fixes (pas un HLS qui
   s'adapte tout seul), on prend la plus haute qui tient sur l'écran,
   et dans le débit si on l'a mesuré. Le HLS n'est pas figé : il continue
   de monter et descendre. Une 4K seule est quand même jouée.
5. **Contraste / netteté** : pas appliqué. Le seul filtre Android quitte
   la Surface et a déjà fait des écrans noirs. La ligne « Contraste »
   dans En plus l'explique. OK ne l'allume pas.

Le chemin par défaut (matériel, fréquence coupée, pas de filtre) est celui
des versions 102, 103 et 104.

## FFmpeg

- **Son** : déjà là depuis la v104 (AAC, MP2, et le reste en secours).
  On n'y touche pas.
- **Vidéo** : le fichier téléchargé
  `org.jellyfin.media3:media3-ffmpeg-decoder:1.5.0+1` contient la classe
  `ExperimentalFfmpegVideoRenderer`, mais le `.so` n'a pas de décodeur
  h264, hevc ni mpeg2. On l'a vérifié en listant les symboles du `.so`
  arm64 (aac, ac3, eac3, mp3, dca, truehd, pas de vidéo).
  Google ne publie pas le `.so` de `androidx.media3:media3-decoder-ffmpeg`.
  On n'a pas recompilé FFmpeg : remplacer le `.so` risquerait le son de
  la v104, et on ne copie le code d'aucune autre application.
- Au lancement, l'app demande à la bibliothèque si elle sait décoder
  H.264, HEVC ou MPEG-2. Si non (c'est le cas de ce binaire), le bouton
  **saute** FFmpeg et l'écrit à l'écran. Le rendu vidéo FFmpeg n'est
  pas construit. S'il répondait oui un jour, il ne serait utilisé qu'en
  secours ou par le bouton, jamais à la place du matériel par défaut.

### Licences

- Le POM de l'archive Jellyfin déclare **GPL-3.0**
  (dépôt `jellyfin-androidx-media`).
- FFmpeg lui-même est **LGPL-2.1 ou plus**, sauf si on active `--enable-gpl`.
  Le script `build.sh` publié par Jellyfin n'active que des décodeurs
  **audio** et ne passe pas `--enable-gpl`. On n'a pas le journal de
  compilation du binaire exact 1.5.0+1 : on ne peut pas jurer qu'aucune
  option GPL n'a été ajoutée à ce tag. On ne distribue pas un nouveau
  binaire FFmpeg dans cette branche.
- Rien n'a été copié depuis une autre application IPTV.

## Taille, mémoire, CPU

- **Pas de nouvel `.so`.** L'archive Jellyfin `1.5.0+1` contient déjà
  `libffmpegJNI.so` : 1 471 232 octets (arm64), 1 370 136 (arm 32),
  1 476 784 (x86), 1 563 520 (x86_64). On ne le remplace pas.
- **Taille de l'APK : pas mesurée.** Aucun APK n'a été compilé dans
  cette session.
- **Mémoire et CPU : pas mesurés.** Le décodeur logiciel utilise le
  processeur au lieu de la puce vidéo. Sur une box faible, un flux lourd
  peut saccader. On ne l'a pas chronométré.

## Prouvé (tests lancés ici)

Commandes exécutées le 30 septembre 2026, sans box et sans APK.

- `gradle test` dans `packages/native_video_player/logic-test`
  (Gradle 8.11.1) : **41 tests, tous verts**. Ça couvre le repli, les
  pistes, la fréquence, et les tests déjà là (voix, son unique, gain).
- `flutter test` (Flutter 3.47.5) : **278 tests verts, 1 ignoré**.
- `flutter analyze --no-fatal-infos --no-fatal-warnings` (mêmes drapeaux
  que le workflow) : **sortie 0, 0 erreur**. 243 infos et avertissements
  déjà présents dans le projet (style `const`, champs inutilisés). Aucun
  n'est une erreur de ce changement.
- Le `.so` arm64 de Jellyfin `1.5.0+1` a été listé (`nm`) : décodeurs
  `aac`, `ac3`, `eac3`, `mp3`, `dca`, `truehd`. Pas de `h264`, `hevc`,
  ni `mpeg2`. Le POM de cette archive dit GPL-3.0. FFmpeg lui-même,
  sans `--enable-gpl`, reste LGPL-2.1 ou plus. On n'a pas recompilé
  le `.so`, donc on ne change pas cette licence.
- Les signatures appelées (`onVideoDecoderInitialized`,
  `onVideoInputFormatChanged`, `onBandwidthEstimate`,
  `onVideoCodecError`, constructeur de `ExperimentalFfmpegVideoRenderer`)
  ont été lues dans les sources Media3 1.5.1 et dans le `classes.jar`
  Jellyfin. **Ce n'est pas une compilation** de `NativeVideoView.kt` :
  cette machine n'a pas le SDK Android.

Ce que ces tests vérifient, en clair :

- Logique de repli : une erreur réseau ne change pas de moteur ; une
  erreur de décodeur vidéo passe au logiciel ; FFmpeg seulement s'il est
  disponible ; on ne revient pas au matériel tout seul ; l'audio ne
  déclenche pas le repli vidéo.
- Image noire : seulement si le décodeur est prêt, la lecture est prête,
  et aucune trame après 8 s. Un chargement ne compte pas.
- Image figée : seulement si des trames ont déjà été vues, que ça joue,
  et plus aucune trame depuis 8 s.
- Ordre des codecs : logiciel devant seulement si on le demande ; s'il
  n'y en a pas, on garde la liste de la box.
- Piste vidéo : la plus haute qui tient à l'écran ; le débit trop juste
  prend la plus légère ; le HLS adaptatif n'est pas écrasé ; une seule
  piste n'est pas touchée.
- Fréquence : 23,976 → 24 Hz, 25 → 50 Hz (25 n'est pas pris pour 24),
  29,97 → 60 Hz ; coupé = aucun changement ; déjà le bon mode = aucun
  changement.
- Contraste : demandé mais matériel non capable = reste coupé.
- Bouton : Matériel → Logiciel → (FFmpeg si la bibliothèque le dit) ;
  sans FFmpeg vidéo, on le signale et on revient au matériel.
- Le bouton moteur est après Guide, REC et Favori, pour ne pas les décaler.
- Un `reopen` (changement de moteur) remet le carton de chaîne et ne
  compte pas comme une erreur de flux.

## Pas prouvé

- Aucune box (v102, v103, v104 ou autre) n'a lu un flux avec ce code.
- `NativeVideoView.kt` n'a pas été compilé ici (pas de SDK Android).
  Le workflow de la branche le compilera. Tant qu'il n'est pas vert,
  on ne sait pas si l'APK se construit.
- Aucune image réelle : pas de 1080i, pas de HEVC, pas de HDR, pas de
  comparaison avant / après.
- Pas de mesure de netteté, de contraste, de cadence, de mémoire, de CPU,
  ni de taille d'APK.
- On ne sait pas si le décodeur logiciel de **ta** box sait lire le HEVC
  ou le MPEG-2. S'il ne le sait pas, le repli s'arrête et l'écran
  « Réessayer » s'affiche.
- La fréquence d'écran peut couper l'image une seconde sur certaines box.
  C'est pour ça qu'elle est coupée au départ.
- Le désentrelacement 1080i n'a pas été vérifié.

## Test à faire sur ta box

1. Installe l'APK de **cette branche** (pas celui du lien clients).
   Le lien `zuno-tv` ne doit pas avoir changé.
2. **1080i** : ouvre une chaîne que tu sais entrelacée. Regarde si les
   lignes en peigne sont là. Note le nom affiché sur le bouton
   (Matériel ou Logiciel). On ne promet pas que les peignes disparaissent.
3. **HEVC** : ouvre une chaîne HEVC. Si l'image reste noire alors que le
   son joue et que le chargement est fini, attends environ 8 secondes :
   l'app doit réouvrir toute seule et le bouton doit passer à « Logiciel ».
   Si la box n'a pas de décodeur logiciel pour ce format, tu verras
   l'écran Réessayer. Dis-le : c'est une info, pas un échec caché.
4. **Zapping** : enchaîne une dizaine de chaînes. Tu dois voir le carton
   (numéro + nom), pas un flash noir entre deux images. Le son ne doit
   pas mélanger deux chaînes (ça, c'était la v104).
5. **Moteur** : OK pour la barre, droite jusqu'à « Matériel », OK.
   Le libellé passe à « Logiciel » et la chaîne se rouvre (carton).
   OK encore : un texte dit que FFmpeg vidéo n'est pas dans cette version,
   et on revient à « Matériel ». Si un jour le libellé devient « FFmpeg »
   sans ce texte, le `.so` a vraiment un décodeur vidéo — note-le.
6. **Fréquence** : Réglages → En plus → « Fréquence de l'écran », OK
   pour allumer, puis un film à 24 ou 25 images/s. Si l'écran coupe
   ou clignote, retourne couper l'option. Elle ne se rallume pas toute seule.
7. **Contraste** : la ligne l'explique et ne change pas l'image. C'est voulu.
