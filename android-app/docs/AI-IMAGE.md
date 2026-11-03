# Traitement neuronal facultatif de l'image

## Calcul réellement exécuté

Le plugin native_video_player embarque le modèle **ArtCNN_C4F16 neutre**, ses poids entraînés et une traduction reproductible de ses opérateurs ONNX en fragments GLES. La chaîne contient neuf passes GPU : débruitage spatial léger, sept convolutions avec connexion résiduelle, puis reconstruction de la luminance et composition couleur à deux fois la largeur et la hauteur.

Le réseau a été entraîné principalement pour l'anime. Son exécution correcte ne prouve pas une amélioration perceptuelle universelle pour le sport, les visages ou les sources déjà propres. La reconstruction ne transforme pas la source en vidéo native 4K. Le score de performance n'est jamais un score de qualité.

- Source : [Artoriuz/ArtCNN, version 1.6.2](https://github.com/Artoriuz/ArtCNN/tree/f606e1f0ba7e6f0ab55049f33dac4d854819b00b).
- Modèle ONNX : 51 559 octets, SHA256 7a6436299b8c757dbb7084ac39a25c310db1941133e73d1ee3e74c8b3bddc1ca.
- Licence MIT originale dans assets/zuno_ai/LICENSE-ArtCNN.txt.
- Aucun LiteRT, NNAPI, composant natif supplémentaire ni téléchargement à l'exécution. Le minSdk 21 et les ABI existantes sont conservés.

## Couleurs et fidélité du port

Le [constructeur concret DefaultVideoFrameProcessor.Factory.Builder de Media3 1.5.1](https://github.com/androidx/media/blob/1.5.1/libraries/effect/src/main/java/androidx/media3/effect/DefaultVideoFrameProcessor.java) utilise WORKING_COLOR_SPACE_DEFAULT, donc BT.709 électrique pour le SDR. Certaines Javadocs de cette version disent encore « linéaire »; le constructeur et le choix de intermediateColorInfo dans cette source font autorité pour cette intégration. Les fragments ne font pas une deuxième OETF/EOTF. Réexaminer ce contrat si le lecteur change de version ou d'espace de travail.

Le débruitage opère avant le réseau sur R'G'B'. La luminance Y' utilise les coefficients BT.709; les chromas sont conservées et interpolées. Le dernier opérateur applique le DepthToSpace DCR x2 du modèle, puis son clamp de sortie. Les convolutions utilisent le padding zéro ONNX, des textures **RGBA16F signées**, et des samplers highp. Les features négatives ne sont pas tronquées en RGBA8. Les ReLU sont limitées aux quatre couches qui en possèdent dans le graphe d'origine.

Le générateur packages/native_video_player/tools/generate_artcnn.py vérifie le hash ONNX, génère les sept fragments et produit une référence CPU via ONNX Runtime. La fixture mélange couleurs, zones sombres, bruit et bords. Le manifeste couvre tous les fragments et les deux fixtures; Android vérifie leurs hashes avant compilation. Après régénération intentionnelle, mettre à jour la constante PIPELINE_SHA de ArtCnnAssets.kt avec le fingerprint imprimé, puis refaire les vérifications.

## Admission, benchmark et repli

Le contexte privé de préflight reproduit le choix Media3 : GLES3, puis GLES2 si création du contexte, de la surface ou makeCurrent échoue. Le contexte du lecteur ne change pas. Les capacités sont relues dans ce dernier; un pilote ou une version différents invalident le rapport.

Le préflight exige au moins un moteur Flutter attaché, une première image reçue pour chacun et aucun bail de lecture. Chaque décodeur possède un bail indépendant : fermer un aperçu ne libère pas le plein écran. Une génération monotone détecte même acquire/close entre deux checkpoints. L'annulation est contrôlée avant compilation, link, allocation et chaque passe. La deadline de 2,5 s est **coopérative** : Android ne permet pas d'interrompre un appel pilote déjà entré dans glCompileShader ou glFinish. Deux tentatives bornées permettent une reprise au prochain vrai idle. Les refus matériel, modèle ou numériques permanents ne bouclent pas.

Avant la vitesse, le vrai GPU doit réussir la comparaison des pixels avec la référence ONNX. Une taille doit ensuite terminer cinq warmups et vingt frames entières. Le chrono englobe débruitage, toutes les convolutions, composition et glFinish. Une seule frame de préflight dépassant 16,67 ms arrête immédiatement ce benchmark. Les rapports ne sont jamais extrapolés depuis une tuile, une marque de GPU ou une autre résolution.

Le catalogue couvre 640×360, 720×480, 720×576, 960×540, 1280×720 et 1920×1080. Au plus quatre autres tailles réellement rencontrées, limitées à 1920×1080, sont mémorisées et deviennent prioritaires au prochain idle après libération de tous les baux. Leur lecture initiale reste native. Une taille jamais mesurée porte BENCHMARK_MISSING, pas un verdict inventé sur la box.

Le score vaut floor(100 × budget_frame / p95_traitement). L'admission demande au moins 200, sans pic au-delà du budget entier. Cette marge de 50 % n'est pas une promesse de 60 fps : décodage, composition, chauffe et autres applications utilisent aussi le matériel. La première allocation de textures en lecture est incluse dans le chrono réel.

La première frame fige la décision. Source inconnue, HDR, DRM, source native 4K, absence de gain utile pour l'écran, mémoire insuffisante, float non rendable, modèle invalide ou référence échouée gardent la texture native. Une hausse de cadence, une perte des métadonnées, une erreur GLES ou une perte de marge désactive le traitement jusqu'au prochain flush. Le repli transfère **le même objet texture d'entrée, ses dimensions et son timestamp**, sans reopen/prepare ni commande réseau.

La VRAM dédiée reste inconnue; elle n'est pas déduite de la RAM système. Le diagnostic indique séparément si Android annonce une fonction NPU. Ce moteur utilise le GPU et ne prétend jamais utiliser ce NPU.

## Contrat d'intégration

Le plugin enregistre chaque moteur avec `AiPictureEngine.get(context).attachFlutterUi()`, puis poste `firstFrameDisplayed()` sur le fil principal après `onFlutterUiDisplayed`. Le préflight attend la première image de tous les moteurs encore attachés et l'absence de bail de lecture. Un moteur sans interface maintient cette attente tant qu'il reste attaché ; un callback reçu après fermeture de son inscription est ignoré. Chaque vue conserve acquirePlayback(aiLeaseOwner), avec un propriétaire opaque indépendant de la vue, avant tout prepare et ferme son bail après libération confirmée du décodeur. Un échec de release ne doit ni autoriser un benchmark concurrent ni retenir la vue et son contexte Android dans le registre des baux. newEffect accepte les providers hdrOrDrm, framesPerSecond, allowUpscale(width,height), sessionId et sourceKnown, plus onStatus. Ils doivent être sûrs sur le fil GL; allowUpscale utilise les dimensions physiques de l'écran.

L'effet se place avant le contraste SDR sans modification globale du contexte ou des couleurs. Le callback est posté au fil UI et un sessionId ancien est rejeté. active=true exige une vraie frame neuronale terminée dans son budget. Un statut inchangé est répété au plus une fois par seconde après une nouvelle frame, pour rétablir l'indicateur après hold/reconnecting sans rejouer une ancienne preuve. Les dimensions de source et de sortie sont séparées. p95Ms et score décrivent le benchmark, pas les détails réels de la source ni les fps affichés.

## Vérifications et portée des preuves

- AiFrameGateTest et AiPlaybackLeasesTest : 17 tests JVM sur admission, refus persistants, absence d'activation tardive, 30→60 fps, première allocation et propriétaires indépendants.
- verify_artcnn_egl.py : fragments livrés exécutés sur EGL/Mesa et comparés à ONNX Runtime CPU. Un réseau neutralisé doit échouer. Sur llvmpipe ES3.2 de développement : erreur maximale 1/255, moyenne 0,124/255. Ceci prouve le calcul logiciel, pas la vitesse d'une Android TV.
- AiPictureGpuTest.realModelAndNativeFallbacksAreVerified : référence sur le pilote Android, actif→erreur→natif, deadline, source inconnue, taille exacte, native 4K/HDR, flush/session et heartbeat. Admission et horloge sont injectées uniquement dans le test, aucune performance de box n'en découle. Les convolutions et les pixels sont réels. Si floatRT manque, les preuves de repli sont sauvegardées, la référence est déclarée non exécutée, et le test échoue explicitement au lieu d'un skip vert.

Les preuves Android sont dans files/ai-picture/measurements.json et les PNG voisins. Une compilation, une référence logicielle ou un émulateur ne suffisent pas à annoncer une classe de box compatible. Il faut le rapport du GPU client pour sa taille et sa cadence, puis vérifier lecture réelle, chauffe, son et changements de chaîne.
