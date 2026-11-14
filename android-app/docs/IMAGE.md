# Image — Zuno TV

État du candidat Android au 4 novembre 2026 : image directe du décodeur par
défaut, contraste GL seulement à la demande (branche `cursor/zuno-black-screen-qa-394f`).
Cette fiche décrit le code et sépare les vérifications de logique des essais
sur un appareil. La présence du code ne prouve pas sa publication ni son
rendu sur une box cliente. Le Worker, le lecteur Windows et le binaire tiers
« 4K Player » ne sont pas modifiés par ce traitement.

## Traitement de contraste réellement ajouté

Le lecteur Android utilise Media3 / ExoPlayer 1.5.1 et une `SurfaceView` native,
sans texture vidéo Flutter. Par défaut, MediaCodec écrit directement dans la
`SurfaceView`, sans processeur GL ni `setVideoEffects` : c'est la sortie que la
page Media3 « Surface types » recommande (cadence exacte, HDR, sortie protégée,
pleine résolution de l'écran sur les TV qui agrandissent l'interface).

Quand la personne allume le contraste, pour les vidéos SDR compatibles décodées
par MediaCodec, le lecteur installe un processeur de trames OpenGL Media3 avant
la surface. `VideoContrastEffects` fournit une matrice RGB dynamique, calculée par
`androidx.media3.effect.Contrast(0.08f)`, installée dans
`ExoPlayer.setVideoEffects` avant `prepare`. Le ×2 IA ([AI-IMAGE.md](AI-IMAGE.md))
vit dans ce même graphe : il ne tourne donc que contraste allumé.

`0.08` est le paramètre de l'effet Media3, pas une promesse de « 8 % de netteté »
ou de luminosité. Le traitement modifie le contraste des pixels. Il n'ajoute
ni netteté, ni débruitage, ni désentrelacement, ni super-résolution. Il ne
reconstitue pas de détails perdus par la compression et ne transforme pas
une source SD en véritable source 4K.

Le contraste est coupé par défaut, sur installation neuve comme sur mise à
jour sans préférence. Réglages → En plus → Contraste permet de l'allumer.
La préférence `zuno.player.image.contrast.v1` n'est écrite que par ce bouton et
conserve le choix explicite. Elle est chargée avant la création des premiers lecteurs ; le canal
Flutter transmet `setContrast` avant la première URL. Direct, films/séries,
aperçus et enregistrements reprennent ce choix.

Trois états sont distincts : la préférence demandée, la capacité du chemin de
lecture courant et l'effet annoncé comme appliqué par le natif. L'état de
préférence ne suffit pas à prouver que le traitement s'applique à chaque flux.
Le lecteur Windows ne prend pas en charge ce réglage et l'indique dans l'UI.

Changer le réglage pendant une lecture rouvre la même chaîne (position VOD,
pause et focus conservés) sur un lecteur neuf, avec ou sans le graphe GL. On ne
remplace jamais la liste d'effets d'un lecteur en cours : dans Media3 1.5.1 cela
réenregistre le flux et a figé l'image lors du test Android. Chaque ouverture
avec le graphe GL repart aussi d'une surface neuve : sur API 29, un second
`prepare` du même lecteur, graphe déjà lié, ne recréait pas le décodeur et
l'image restait figée.

### Pourquoi le GL n'est plus le défaut (mesures, émulateurs)

Mesures de la v116 (graphe GL toujours installé) contre cette branche, avec
`dumpsys SurfaceFlinger --latency` et des captures d'écran, sur le flux public
Mux (H.264 1080p, 60 i/s) et une mire HLS SDR locale (H.264 720p, 25 i/s, BT.709) :

- API 29 : la v116 fige l'image après une quarantaine de trames ; la
  reconstruction du chien de garde échoue ensuite (`connect: already
  connected`, `Decoder init failed`) et la chaîne tombe en erreur. Rendu direct :
  lecture continue à 25 i/s sur la mire, sans erreur.
- API 35 : la v116 ne livre qu'environ 9 i/s du flux à 60 i/s.
- Mire SDR : `Contrast(0.08)` donne `sortie = 1,1738 × entrée − 0,0869`, donc
  tout ce qui est sous 19/255 devient noir et tout ce qui dépasse 236/255
  devient blanc (détails perdus dans les ombres et les hautes lumières). Écart
  moyen mesuré 14,2 avec la v116 ; rendu direct : gris de la mire à ±1, image
  entière, sans rognage.

Un graphe GL bloqué gardait aussi la file d'images de la `SurfaceView` après
`release()`. `rebuildPlayer` libère donc l'ancien lecteur, puis renouvelle la
surface (masquer/réafficher la vue) quand l'ancien lecteur utilisait le GL :
mesuré sur API 29, le repli direct reprend alors l'image au lieu du carton
d'erreur.

## HDR, DRM et repli sans GL

Le filtre est destiné au SDR. Lorsqu'un format HDR ou protégé par DRM est
détecté, le lecteur demande une reconstruction sans processeur GL et sans
appel à `setVideoEffects`, même avec une liste vide. Le rendu FFmpeg vidéo,
s'il devenait disponible, reste également hors de ce traitement.

Sur Android 12+ (API 31), quand l'écran n'annonce aucun type HDR, le lecteur
demande au décodeur une sortie SDR pour les flux PQ/HLG
(`MediaFormat.KEY_COLOR_TRANSFER_REQUEST`, `HdrToneMap`). C'est une demande :
un décodeur qui ne sait pas convertir l'ignore. Sur un écran HDR rien n'est
demandé. L'émulateur API 29 refuse la mire HEVC Main10 PQ
(`NO_EXCEEDS_CAPABILITIES`, avant comme après) : l'effet se vérifie sur API 31+.
Le code ne force pas du HDR sur une
source SDR et ne promet pas un rendu HDR/Dolby Vision/HLG sur tous les appareils.
Le décodage, l'écran et la chaîne HDMI doivent toujours le prendre en charge.
La protection HDR/DRM est vérifiée par sa politique de sélection ; son rendu
physique doit encore être vérifié sur des appareils compatibles.

Une erreur du traitement vidéo/GL, ou une absence persistante de trames dans
les conditions du chien de garde, essaie d'abord le rendu direct. Ce repli est
borné à une tentative par URL : le motif est conservé pour cette lecture,
les reprises de la même URL ne réactivent pas le processeur en boucle. Une
nouvelle URL peut essayer à nouveau le traitement.

La reconstruction conserve la position VOD et la pause demandée, y compris
une pause liée au focus audio. Elle est annulée si le lecteur est détruit,
si une autre session ou URL a pris sa place, si l'application n'autorise plus
la reprise ou si le Cast possède la lecture. Ce mécanisme ne doit pas être
confondu avec le repli du décodeur vidéo déjà présent.

## Film « Dolby Vision + HDR10+ » : écran d'une seule couleur, le son continue

Signalé le 14/11/2026 par un client sur une clé Amazon Fire TV branchée à
un téléviseur 4K : un film 4K démarre, puis l'écran devient uni (bleu sur
la photo) et le son continue. Le journal de sa box ne contenait aucune
ligne sur l'image.

**Cause retenue.** Beaucoup de films 4K récents sont « hybrides » : le même
flux HEVC porte Dolby Vision (unité NAL de type 62 à la fin de chaque image,
type 63 pour la seconde couche) et HDR10+ (message SEI de type 4, signature
`B5 00 3C 00 01 04`). Les appareils à puce MediaTek MT8696 (Fire TV Stick
4K Max 1re et 2e génération, Fire TV Stick 4K 2e génération, Google TV
Streamer) n'affichent pas ce mélange : écran noir ou d'une seule couleur
avec le son. Défaut du constructeur, suivi dans
[androidx/media#1895](https://github.com/androidx/media/issues/1895) ;
d'autres lecteurs le contournent en retirant l'un des deux jeux.

**Ce que fait le lecteur** (`logic/HybridHdr.kt`, branché dans le rendu
vidéo de `NativeVideoView.kt`, juste avant le décodeur) :

| Niveau | Quand | Décodeur Dolby Vision | Décodeur HEVC |
| --- | --- | --- | --- |
| Automatique | modèles `AFTKA`, `AFTKM`, `AFTKRT`, ou puce `mt8696` | HDR10+ retiré, Dolby Vision gardé | si le flux porte les deux : les deux retirés, lecture en HDR10 |
| Réglage « Compatibilité HDR » | allumé par la personne, toute box Android | HDR10+ retiré | Dolby Vision et HDR10+ retirés |
| Observation | autres appareils Amazon | rien | rien |
| Aucun | toutes les autres box | le flux n'est pas lu | le flux n'est pas lu |

Les unités d'image (« VCL ») ne sont jamais modifiées. Un flux sans Dolby
Vision ni HDR10+ n'est lu que sur ses 12 premières images puis sur les
images clés. Interrupteur de repli de l'automatique :
`zuno.player.hybrid_hdr_off` (voir `repair_flags.dart`).

**Boîte noire.** Étiquette `IMAGE`, sur toutes les box : une ligne par
lecture avec le format annoncé et le décodeur. Sur les appareils Amazon et
MT8696 : ce que le flux contient (Dolby Vision, HDR10+) et ce qui a été
retiré.

**Vérifié.** `HybridHdrTest` (logic-test) : 41 cas, dont 1 500 suites
d'images tirées au hasard comparées à une réécriture naïve. La mire
`hybrid_hdr.mkv` (x265 + HDR10+ valide + unité 62 sur les 600 images,
`ci/generate_hybrid_hdr_fixture.py`) passée dans le filtre puis relue par
ffprobe : HDR10+ et Dolby Vision absents des 600 images, sommes de contrôle
des images décodées identiques à l'original.

**À lire dans le run du commit.** `NativeHybridHdrTest` joue la même mire
dans le vrai lecteur (émulateurs API 29 et 35, workflow
`zuno-contrast-render-tests`) : niveau automatique, réglage manuel et
interrupteur de repli. Son résultat est celui du run, pas de ce document.

**Non vérifié.** L'image sur une vraie clé Amazon MT8696 : aucun émulateur
n'a sa sortie HDMI. Le film du client n'a pas été analysé ; que son flux
soit bien hybride sera lu dans sa boîte noire (ligne `HDR du flux`). Le
passage par le décodeur HEVC ordinaire, celui que son écran annonçait, n'est
pas décrit dans le ticket du constructeur : le retrait des deux jeux y est
une précaution, pas un correctif démontré.

## Résolution de la surface

Un écran peut sortir en 3840 × 2160 alors que l'interface Android est dessinée
en 1920 × 1080. Avec le processeur GL, garder un tampon de la seule taille
logique de la vue pourrait réduire l'image avant son affichage.

`VideoSurfaceSize.forContrast` calcule donc une taille de tampon à partir du
rapport entre écran physique et écran logique, tout en respectant la taille
relative de la vue : plein écran, aperçu ou mini-fenêtre. Le lecteur applique
cette taille avec `SurfaceHolder.setFixedSize`. Le chemin direct et les
situations sans agrandissement valide utilisent `setSizeFromLayout`.

Les calculs tiennent compte de l'orientation, rejettent les dimensions
invalides et bornent le tampon à 8192 pixels par côté et 7680 × 4320 pixels au
total. Ces bornes évitent une allocation aberrante ; elles ne prouvent pas une
capacité de lecture 8K. Il s'agit de préserver la résolution disponible du
chemin de rendu, pas d'un algorithme d'upscaling qui invente des détails.

Les tests JVM prouvent les dimensions calculées, notamment le cas d'une UI
1080p sur une sortie 4K. Ils ne prouvent ni l'allocation réelle du tampon sur
une TV, ni la résolution HDMI finale, ni un gain de netteté mesuré.

## Indicateur de qualité fondé sur la lecture

Les cartes et lignes du Direct ne transforment plus les mentions 4K/FHD/HD
du nom de chaîne en badges techniques. L'aperçu et les commandes de lecture
affichent les dimensions numériques reçues du lecteur courant.

- **Format source** : dimensions, codec et transfert colorimétrique du format
  sélectionné transmis par Media3. HDR/SDR reste inconnu si cette information
  manque ; ce libellé ne garantit pas un mode HDR sur la dalle.
- **Sortie lecteur** : dimensions du callback `onVideoSizeChanged` en rendu
  direct. Media3 1.5.1 supprime ce callback sur le chemin GL (b/292111083) :
  dans ce cas, le relevé vient exclusivement du format `video/raw` de sortie
  fourni par `PlaybackVideoGraphWrapper` au callback de trame. Ce format est
  construit depuis la taille de sortie mesurée par le graphe, pas depuis le
  format AVC/HEVC d'entrée. L'événement garde l'origine `gl_output` dans les
  preuves. Ces dimensions restent distinctes du format source et du HDMI ;
  un agrandissement ne prouve pas du détail 4K natif.
- **Sortie décodeur** : deltas réels de `DecoderCounters` pendant 2 à 5 secondes
  de lecture continue. La cadence déclarée par le fichier n'est jamais utilisée
  à sa place. Pause, tampon, changement de décodeur ou fenêtre invalide effacent
  la mesure. Ces compteurs ne mesurent pas les pertes après le traitement GL,
  le compositeur Android ou la dalle.

Le PC publie les dimensions déjà rapportées par `VideoParams`; codec, HDR et
cadence restent inconnus tant que son moteur ne les fournit pas. Aucun score
de qualité ni état « IA active » n'est inventé. Les données d'une ancienne
chaîne sont effacées au zap et lors d'une reconstruction du lecteur.

Les tests ajoutés couvrent source/sortie différentes, nom commercial 4K/60/IA
avec une lecture 720 et 24 images/s comptées, informations inconnues, pause,
zap et invalidation des fenêtres. Le test Android de pixels vérifie séparément
les événements source et sortie réels de la mire 256 × 144. L'exécution de
ces nouvelles assertions dépend de la CI du candidat qui les intègre.

## Autres mécanismes conservés

- Décodage matériel en premier, avec repli vidéo ciblé vers les codecs logiciels
  Android si nécessaire. Le repli FFmpeg vidéo reste conditionné aux capacités
  réellement annoncées par la bibliothèque ; le nom du moteur ne suffit pas.
- Pas de tunneling audio/vidéo et pas de changement de fréquence HDMI automatique
  par défaut. Le réglage de cadence demeure optionnel, conserve la résolution
  physique et restaure la préférence d'écran antérieure.
- Choix des pistes fixes en fonction de l'écran physique et du débit connu,
  sans figer un groupe HLS réellement adaptatif. Une piste 4K unique n'est pas
  écartée uniquement parce que l'interface ou l'écran est plus petit.
- Affichage de toute l'image avec respect du ratio ; pas de rognage volontaire.
- Reconnexion réseau, carton jusqu'à la première image et gestion des dernières
  trames restent des mécanismes de continuité, pas des filtres d'amélioration.
- Aucun filtre de désentrelacement propre à Zuno n'est ajouté. Le comportement
  des flux 1080i dépend toujours du décodeur et nécessite un essai physique.

## FFmpeg et coût du traitement

Le changement ajoute `media3-effect` 1.5.1 et utilise le traitement GL de Media3.
Il ne remplace pas le binaire Jellyfin `media3-ffmpeg-decoder:1.5.0+1` et n'ajoute
pas de nouvelle compilation FFmpeg. L'audit historique de ce binaire trouvait
des décodeurs audio, sans H.264/HEVC/MPEG-2 vidéo ; le lecteur conserve sa
vérification des capacités avant de proposer un moteur vidéo FFmpeg.

Le coût GPU, mémoire, consommation et température de l'effet n'a pas été
mesuré sur une box cliente. Le tampon physique peut augmenter le travail GL
sur un écran 4K. Le repli direct constitue une récupération après échec ; il
ne remplace pas des mesures de performance sur du matériel représentatif.

## Vérifications et limites

Résultats du candidat avant l'essai de rendu Android :

- 31 tests Dart ciblés réussis : préférence, canal, moteur et cycle de lecture/PiP.
- 165 tests JVM réussis, dont les politiques de traitement/repli et les calculs
  de taille de surface.
- Analyse Flutter complète : zéro erreur ; 228 avertissements/informations
  préexistants signalés dans le projet.

Le test de canal utilise un transport Flutter simulé : il vérifie notamment
que la préférence arrive avant l'URL, pas que les pixels changent. Les tests
JVM n'exécutent ni le décodeur Android ni OpenGL.

`NativeContrastPixelTest.defaultOff_directPixels_onChangesRealPixels_offRestoresTheSameFrame`
lit une mire synthétique. Il vérifie d'abord le rendu direct par défaut (aucun
graphe GL, taille d'origine `renderer_callback`), puis allume le contraste
(réouverture avec graphe GL, origine `gl_output`, ombres plus sombres et clairs
plus clairs), le coupe (retour direct, même image à ±2 près) et le rallume
(même image à ±2 près), sans erreur ni réouverture en trop. Ce nouveau
contrat doit passer dans la CI de la branche avant intégration.

Mesures de l'ancien contrat (contraste par défaut) : dans le
[run 41551529426](https://github.com/manzilionellm-dotcom/tvking/actions/runs/41551529426),
au commit `40f847cd`, les deux émulateurs Android API 29 et 35 ont réussi ce
premier passage. La plage sombre mesure 34,33 avec contraste et 48,33 sans ;
la plage claire mesure 241 avec contraste et 224 sans. Les retours ON et OFF
reproduisent chacun leur première image : différence RGB moyenne nulle.
Les valeurs sont celles de cette mire, pas une note de qualité universelle.

La contre-épreuve réintroduisant le refus permanent du contraste a bien
échoué sur `PIXEL_CONTRAST_NOT_APPLIED` sur les deux API. Le job complet est
cependant rouge : son vérificateur attendait `AssertionError` dans l'attribut
XML `type`, alors qu'AGP l'écrit au début du texte de `<failure>`. Le lecteur
de rapports accepte maintenant ces deux formes, exige toujours le marqueur
de pixels, refuse les erreurs différentes, les tests ignorés et les captures
absentes. Onze tests Python couvrent ce contrat. Le workflow doit être rejoué
sur le commit corrigé avant intégration ; les mesures archivées ne remplacent
pas ce nouveau contrôle.

Ces résultats d'émulateur ne valident pas toutes les box, les flux entrelacés,
les contenus HDR/DRM, les sorties HDMI ou le rendu physique 4K.

Avant de conclure sur un appareil, comparer une même source SDR fixe avec et
sans contraste, vérifier que la désactivation survit au redémarrage, puis
contrôler la fluidité, les ombres/hautes lumières, les changements de chaîne
et les reprises. Vérifier séparément les sources HDR/DRM et le comportement
de pause/reprise. Les mesures doivent identifier l'APK et l'appareil testés.
