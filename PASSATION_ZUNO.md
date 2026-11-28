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
