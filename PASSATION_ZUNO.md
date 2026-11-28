# Passation ZUNO LAB — 28 novembre 2026

## Point de départ
Branche `lab/zuno-119-qualification-20261128`, issue directement de `a096b2f85de082622ec232fa198069bdefbbccab` (branche officielle `ccr-b93e1afd-gwirw0`). Le [run 45710084378](https://github.com/manzilionellm-dotcom/tvking/actions/runs/45710084378) a terminé avec succès. L’AAB signé de l’édition auto a pour SHA-256 `43fcccd171434d18961a2c27aeed8064ab2f08aeffcf7364f0ae439560fa149d`. Version 119, code 1794559152, paquet `com.sevenmotion.tv.seven_tv`, minSdk 24. L’archive Actions a une empreinte différente. Dernier statut Play rapporté le 27 novembre : en cours d’examen. Distribution actuelle INCERTAINE.

| Cible | État initial |
|---|---|
| Play | Version et piste effectivement servies à relever |
| Témoin | AAB authentifié. Aucun APK installé ni chronométré à l’ouverture de la campagne |
| Candidat | Construction sous identité LAB distincte en préparation |
| Diagnostic instrumenté | Aucun binaire soumis à une mesure |
| Matériel | Aucune SHIELD, petite box ou capture de dalle connectée à cet espace |

## Prochaine vérification
Sur la machine Android du banc, exécuter `adb devices -l` puis inventorier les APK installés avec `adb shell pm path com.sevenmotion.tv.seven_tv`. Relire tous les octets avant toute attribution. Pour la preuve visuelle, consigner l’identité de la chaîne et deux compteurs croissants. Aucun classement ni livraison à ce stade.

## Campagnes de provenance, de cadrage et d’enregistrement
La console Google Play indique 117 / 1794559150 disponible à 100 % sur la production, 118 remplacée, 119 en examen. Le fichier universel 119 téléchargé depuis la console a le SHA-256 96b81d876be292f9155bc2d761e07532af15b4695fc44c829ffe27f20e8909b8. Signature Play et signature de l’AAB diffèrent normalement, voir [provenance](android-app/ci/zuno_lab/results/provenance.json). La preuve de distribution dépend aussi du pays, du compte et du device.

- [Reprise historique et pièces consultées](android-app/ci/zuno_lab/results/historique.md).
- Le [premier build LAB](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46085176385) compile le correctif de cadrage. Son résultat ne qualifie pas le candidat REC et guide.
- Le [premier essai témoin](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46085087845) s’est arrêté avant l’installation sur le service de téléphonie absent de l’image TV. [Relance](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46085495056) et [essai optique externe sur le témoin](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46085513701). Les APK universels construits par bundletool sur les runners ont des certificats de test éphémères.
- Le modèle géométrique de l’appel ZUNO sur une vue et un tampon 1920 × 1080 conserve 44,44 % de la surface et zéro des quatre coins avant correction. Après la modification, la totalité est échantillonnée. Vérification Android et dalle à compléter. [Entrées et sorties](android-app/ci/zuno_lab/results/).
- Le chemin Flutter du relais écrit 238 octets de manifeste sans image sur la mire HLS. Le relais corrigé livre les 12 162 472 octets attendus au fichier et au lecteur, avec 180 images et 283 blocs audio identiques après décodage. Seize initialisations concurrentes aboutissent à un seul port sur le candidat, contre seize sur le témoin. Le bouton REC, la fermeture du lecteur et la relecture sur box restent à qualifier.
- La [contre-épreuve du guide](.github/workflows/zuno-lab-guide.yml) doit mesurer les lectures SQLite et la commande « Suivre » pendant A → B → C. Le [constructeur dédié](.github/workflows/zuno-lab-build.yml) utilise l’édition auto, le backend d’essai en boucle locale et les identifiants publicitaires Google de test. La clé de signature est réservée à chaque construction LAB.
- Commande pour reprendre : `gh run list -R manzilionellm-dotcom/tvking --branch lab/zuno-119-qualification-20261128 --limit 20`. Attendre le succès du dernier constructeur puis installer CET APK, vérifier les octets et le rouvrir. Aucune livraison enregistrée à ce stade.

## Démarrage, guide, catalogues et panel
Le [témoin Android TV](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46085495056) porte le SHA-256 `80fcb83b2f3e402f58a47e7ac05bfdf0a8c2ea7b91d7017cd02f29be07929594` (universel re-signé du bundle, Android TV 36 émulé, MemTotal 1 503 188 Kio). 0/30 ouvertures à froid maintenues. Les 30 commandes après HOME ont été envoyées sans processus chaud éligible. Le [diagnostic PID](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46086413102) localise l'arrêt dans ActivityThread.installProvider → InitializationProvider → création de WorkDatabase. Aucun temps de dalle et aucune attribution OOM. Le correctif R8 et son contrôle de DEX font l'objet d'une campagne distincte.

Le [guide ZUNO](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46085894838) passe de cinq lectures aux deux lectures nécessaires pendant A → B → C ; le bouton « Suivre » hérité de la première destination disparaît. Onze tests ciblés passent. Candidat intermédiaire `f90de79c2a0ab177a222b12ef70a86695ec92e97`, [build signé réussi](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46085894777), sans la réparation du démarrage. Interdit de le confondre avec le dernier APK qualifié.

Le [banc catalogue/REC](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46086668262) réessaie les tailles sur le même hôte en trois blocs ABBA. Le TS HD contient 600,021 s de programme, 15 000 images et 28 126 blocs audio après lecture indépendante. Le transfert du TS a été accéléré. Le résultat de l'essai HLS temps réel se lit séparément. Le panel de laboratoire reproduit deux anomalies sur le témoin : la révision source_rev donnée par le Worker disparaît côté client et un lot comportant un 404 prend l’état applied lorsque l’ancienne liste reste lisible. Le contrôle complet du Worker, D1 et SQLite s'effectue en boucle locale. Les essais en production ne font pas partie de la campagne.

L'essai des concurrents sur TV Android émulée est le [run 46086590083](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46086590083). Le kit terrain a validé la détection d’un gel imposé de 8 s à 25 Hz et conservé les 180 requêtes sur Stockholm, Francfort, Paris, New York, Dallas et Los Angeles. Consulter leur statut en exécutant `gh run view 46086590083 -R manzilionellm-dotcom/tvking` et `gh run view 46086668262 -R manzilionellm-dotcom/tvking`. Les mesures télécommande→dalle, 4K/HDR, SHIELD et petite box physique restent sans mesure dans ces campagnes.

## Reprise du 28 novembre, qualification du dernier APK construit

Le run officiel adaptatif reste 45710084378 après contrôle des 49 exécutions du workflow. La capture de la piste montre 117 disponible, 118 remplacée et 119 en examen. Le témoin re-signé du run 46086413102, SHA-256 04702d666804d5a863bfa6bde60dfc59e2270d4e6732fc3c8cbadfdb47d8d141, échoue aux 30 départs à froid. L’APK universel signé par Play porte une autre empreinte.

Le [dernier constructeur LAB réussi](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46087049284) contient le correctif des quatre secours, à c9f0153fae358aaef2e45d83c3f2e27383d3e0a0. L’archive 15239966146 a été retéléchargée et contrôlée. SHA-256 du ZIP 95248bb4fe0ac9a203757fd4cd138b9e650daf7b6362e1b82f41c9d6e178ac70, de ZUNO-LAB.apk f3b383247f1a7783bc284355bd801b3d013f910ce94917f173179da6018955e8, du certificat v2/v3 ea2ef87b250a2e1ceb666c0f934c7495bab734076020c8751142c2e05a923e55. Paquet com.sevenmotion.tv.seven_tv.lab, version 119-lab (1794559152). Aucun canal client modifié.

Le run optique 46088357961 ciblait le constructeur antérieur 46086918229. L’installateur a répondu Success, mais le digest calculé par le pipeline qui copiait le fichier par ADB ne correspondait pas. Aucune touche de zap. Le banc lit maintenant le SHA sur l’appareil avec sha256sum et compare au fichier local. La double ouverture exige aussi que le paquet soit au premier plan. Pour reprendre, exécuter `gh run list -R manzilionellm-dotcom/tvking --branch lab/zuno-119-qualification-20261128 --limit 20` puis vérifier les deux JSON d’ouverture et les SHA avant/après dans les deux artefacts TV/téléphone. Si l’écran ou le mouvement échoue, conserver le résultat et identifier le dernier écran. Aucun temps de dalle ni classement régional établi.

### Ouverture du lecteur en présence de deux OK

Une course existe entre la libération asynchrone de l’aperçu et la réservation de la route du lecteur. La PR réserve l’ouverture avant le premier await et rend le focus dans un bloc finally. Le workflow guide confronte les deux paires d’appuis au code 119, exige deux routes sur le témoin et une seule sur le candidat, puis vérifie Retour et réouverture. Ne pas attribuer la réussite avant lecture du run. Le contrôle des bibliothèques natives a été refait directement entre l’AAB et l’APK c9f0153f : les 21 entrées comparées (7 sur chacune des 3 ABI, hors code Dart de l’application) ont des SHA-256 identiques. Campagnes précédentes TV/téléphone [46088979109](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46088979109) et vidéo [46088979081](https://github.com/manzilionellm-dotcom/tvking/actions/runs/46088979081). Elles portent uniquement sur c9f0153f.

### Instrument de capture et décision intermédiaire

Le pilote c9f0153f a relu exactement f3b383247f1a7783bc284355bd801b3d013f910ce94917f173179da6018955e8 avant et après l’essai. L’observateur a expiré sur le premier `adb exec-out screencap -p` après 12 secondes. Aucun mouvement mesuré. Sur le build suivant, le banc emploie la console de l’émulateur pour obtenir son affichage, puis le screencap Android en secours. La collecte d’un écran manquant est séparée des mesures d’activité. Deux ouvertures, deux premiers plans et deux écrans reconnus sont nécessaires sur TV et téléphone avant la préversion LAB dédiée. La CI du premier test double OK a trouvé 0 route via le clavier synthétique : échec du test, aucune preuve du correctif dans ce run. La contre-épreuve suivante applique deux sélections à la ligne réelle et observe les routes poussées.
