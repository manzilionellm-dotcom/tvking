# Zuno — définition vidéo et proportions

Cette révision prolonge la PR #145. Elle conserve le rendu direct sur SurfaceView,
le HDR transmis par Media3, les décodeurs et le traitement audio existants.
Elle ne transforme pas une source SD en véritable HD ou 4K.

## Ce qui change

- **Réglages → En plus → Qualité vidéo** : Auto par défaut, ou Définition maximale.
  Le choix est mémorisé. Maximum sélectionne la meilleure piste vidéo annoncée
  comme décodable par Media3 ; il peut demander davantage de débit. Revenir à
  Auto rend la sélection adaptative au lecteur, sans rouvrir l'URL ni changer
  les pistes audio/sous-titres. Une source à piste unique conserve sa définition.
- Les lecteurs Direct, Films, Séries et Enregistrements appliquent la préférence.
  Les petits aperçus gardent Auto. Le réglage est proposé sur Android ; le lecteur
  Windows conserve son comportement.
- La sélection fixe utilise la définition physique de la sortie, via l'API
  Media3 `Util.getCurrentDisplayModeSize`, au lieu de la hauteur de la vue UI.
  Une interface Android à 1080p ne plafonne donc plus à elle seule une TV 4K.
- Un groupe réellement adaptatif est reconnu par `isAdaptiveSupported`, et non
  par son seul nombre de pistes. Auto ne remplace pas un ladder adaptatif par
  des pistes fixes annexes. Les overrides vidéo et mesures réseau précédentes
  sont nettoyés à la nouvelle ouverture ; les choix postés sont invalidés lors
  d'un changement de qualité, de session, de lecteur ou d'un passage au Cast.
- La Surface et l'image de reprise respectent le ratio vidéo et les pixels non
  carrés. Les sources 4:3, cinéma large ou portrait ne sont pas étirées ni rognées.
- L'option existante de fréquence HDMI ne choisit plus un mode de résolution
  inférieure pour atteindre 24/50/60 Hz. Elle reste désactivée par défaut.
- Le bandeau Direct/Films/Séries affiche les dimensions du format reçu du
  décodeur, sans déduire « 4K » du nom commercial de la chaîne.

Le filtre de contraste expérimental reste indisponible : aucun effet OpenGL,
upscaler artificiel, bibliothèque vidéo supplémentaire ou second lecteur n'est ajouté.

## Validation automatisée

- Logique Kotlin : 4K avec UI 1080p, ratio 4:3 et cinéma, pixels anamorphiques,
  dimensions invalides, sélection Maximum/Auto, source SD, coexistence de pistes
  adaptatives et fixes, conservation de la résolution HDMI.
- Flutter : persistance, ordre des appuis rapides, indépendance du moteur et de
  la cadence, absence de réouverture lors du changement de qualité, dimensions
  filtrées pendant un zap, choix Maximum/Auto à la télécommande.
- Les seize catalogues sont complets. Le workflow Quality Zuno exécute maintenant
  la suite Kotlin pure en plus de Flutter. L'APK de revue exécute les tests du
  nouveau réglage avant compilation.
- Résultats et APK exacts : voir les workflows du commit dans la PR #145.

## Recette sur matériel

1. TV 4K avec interface Android 1080p : source de test HLS multi-définition,
   connexion suffisante. Comparer Auto puis Maximum et relever la définition
   affichée ; vérifier le retour à Auto si la connexion ralentit.
2. Même test sur une box 1080p et un téléphone, puis source à piste SD unique :
   les dimensions affichées doivent rester celles de la source.
3. Vidéo 4:3, 1920×800 et 720×576 anamorphique : vérifier les proportions et les
   bandes noires, puis le plein écran, le retour et la reprise après interruption.
4. Changer rapidement Maximum/Auto, zapper et quitter le lecteur : pas de flux
   supplémentaire, de seconde voix ou de choix périmé appliqué à la chaîne suivante.
5. Avec l'option de cadence activée, lire un film 24 fps sur une sortie HDMI 4K :
   conserver cette résolution, ou garder le mode d'origine si aucun 4K/24 n'existe.
6. Vérifier HDR/HLG, HEVC, 1080i et Cast sur le matériel réel. Une compilation et
   des tests de logique ne mesurent pas la netteté, le désentrelacement ou les FPS.

Référence primaire : [Media3 — Surface types](https://developer.android.com/media/media3/ui/surface),
sur la résolution physique des TV dont l'interface est mise à l'échelle.

Le raccordement de l'essai fournisseur reste indépendant de cette amélioration
vidéo et nécessite toujours le véritable `gold-export.zip`.
