# Image — Zuno TV

État du candidat Android au 3 novembre 2026, après la révision `c3809be4`.
Cette fiche décrit le code et sépare les vérifications de logique des essais
sur un appareil. La présence du code ne prouve pas sa publication ni son
rendu sur une box cliente. Le Worker, le lecteur Windows et le binaire tiers
« 4K Player » ne sont pas modifiés par ce traitement.

## Traitement de contraste réellement ajouté

Le lecteur Android utilise Media3 / ExoPlayer 1.5.1 et une `SurfaceView` native,
sans texture vidéo Flutter. Pour les vidéos SDR compatibles décodées par
MediaCodec, il installe maintenant un processeur de trames OpenGL Media3 avant
la surface. `VideoContrastEffects` fournit une matrice RGB dynamique, calculée par
`androidx.media3.effect.Contrast(0.08f)`, installée une seule fois dans
`ExoPlayer.setVideoEffects` avant `prepare`. Ce n'est donc plus uniquement un réglage d'interface.

`0.08` est le paramètre de l'effet Media3, pas une promesse de « 8 % de netteté »
ou de luminosité. Le traitement modifie le contraste des pixels. Il n'ajoute
ni netteté, ni débruitage, ni désentrelacement, ni super-résolution. Il ne
reconstitue pas de détails perdus par la compression et ne transforme pas
une source SD en véritable source 4K.

Le contraste est demandé par défaut, sur installation neuve comme sur mise à
jour sans préférence. Réglages → En plus → Contraste permet de le couper.
La préférence `zuno.player.image.contrast.v1` conserve une désactivation
explicite. Elle est chargée avant la création des premiers lecteurs ; le canal
Flutter transmet `setContrast` avant la première URL. Direct, films/séries,
aperçus et enregistrements reprennent ce choix.

Trois états sont distincts : la préférence demandée, la capacité du chemin de
lecture courant et l'effet annoncé comme appliqué par le natif. L'état de
préférence ne suffit pas à prouver que le traitement s'applique à chaque flux.
Le lecteur Windows ne prend pas en charge ce réglage et l'indique dans l'UI.

Couper le réglage choisit une matrice identité exacte, relue à chaque trame.
La liste d'effets reste identique : remplacer cette liste pendant la lecture
réenregistre le flux dans Media3 1.5.1 et a figé l'image lors du test Android.
Le processeur GL reste installé ; ce n'est pas un retour au rendu direct.

## HDR, DRM et repli sans GL

Le filtre est destiné au SDR. Lorsqu'un format HDR ou protégé par DRM est
détecté, le lecteur demande une reconstruction sans processeur GL et sans
appel à `setVideoEffects`, même avec une liste vide. Le rendu FFmpeg vidéo,
s'il devenait disponible, reste également hors de ce traitement.

Le code n'ajoute pas de conversion HDR vers SDR, ne force pas du HDR sur une
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

`NativeContrastPixelTest` et le workflow de rendu de la PR 183 sont prévus pour
lire une mire synthétique, comparer les pixels avec et sans contraste et
vérifier le retour au rendu sans effet. À la rédaction de cette fiche, cet
essai Android est en cours : aucun résultat de pixels réussi n'est annoncé.
Même un résultat sur émulateur ne validerait pas toutes les box, les flux
entrelacés, les contenus HDR/DRM, les sorties HDMI ou le rendu physique 4K.

Avant de conclure sur un appareil, comparer une même source SDR fixe avec et
sans contraste, vérifier que la désactivation survit au redémarrage, puis
contrôler la fluidité, les ombres/hautes lumières, les changements de chaîne
et les reprises. Vérifier séparément les sources HDR/DRM et le comportement
de pause/reprise. Les mesures doivent identifier l'APK et l'appareil testés.
