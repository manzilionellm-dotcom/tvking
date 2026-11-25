# Zuno : image, listes et Windows — 2 novembre 2026

Cette révision part du candidat Android `2f1c7a9f01073249cfaa2b682720c0ba945d6f7e`.
Elle corrige des pertes de qualité et des opérations inutiles ; elle ne transforme
pas une source SD en 4K et ne constitue pas une mesure visuelle sur téléviseur.

## Image Android et Windows

- Android : sélectionner les pistes fixes à partir du mode physique de l'écran,
  même si l'interface Android TV est dessinée en 1080p sur une sortie 4K. Vérifier
  la capacité adaptative réelle du groupe et conserver le groupe HLS adaptatif
  déjà sélectionné.
- Fréquence d'écran, toujours optionnelle : conserver la résolution physique,
  comparer au mode réellement actif, éviter les bascules équivalentes et ne pas
  réduire un flux 50 images/s à 25 Hz. Restaurer la préférence antérieure.
- Windows : finir l'initialisation libmpv avant la première URL, invalider un zap
  devenu obsolète pendant ses préparatifs, appliquer réellement le choix matériel
  ou logiciel et publier les dimensions décodées. Filtrage Flutter intermédiaire
  pour les aperçus et fenêtres réduites, sans filtre de netteté artificiel.

Références : [SurfaceView et résolution physique Media3](https://developer.android.com/media/media3/ui/surface),
[modes physiques Android](https://developer.android.com/reference/android/view/Display.Mode),
[groupes de pistes Media3](https://developer.android.com/reference/kotlin/androidx/media3/common/Tracks.Group),
[FilterQuality Flutter](https://api.flutter.dev/flutter/dart-ui/FilterQuality.html),
[propriété hwdec de mpv](https://mpv.io/manual/stable/#options-hwdec).
Les signatures Android utilisées ont aussi été vérifiées dans les sources
`media3-common` 1.5.1 de cette application.

## Import et navigation

La lecture M3U s'arrête réellement au plafond sans recopier le texte ni produire
la liste entière des lignes. SQLite reçoit des insertions de 90 lignes, soit
900 paramètres, en conservant les transactions de remplacement et la progression
visible par lots de 1000. Une liste cachée ou déjà en import n'est pas relancée
par le rafraîchissement de démarrage.

Le Direct réutilise les index de noms, identifiants et groupes VIP entre deux
changements de catalogue. Une navigation rapide A → B → A annule maintenant le
changement différé vers B, pour les catégories comme pour les aperçus.

Mesures de développement Linux, HTTP simulé, SQLite FFI réel, après chauffe :

| Opération | Avant | Après | Méthode |
| --- | ---: | ---: | --- |
| Import complet de 50 000 chaînes | 1346 ms | 832 ms | Médiane de 3 passages, ordre alterné |
| Écriture SQLite de cet import | 870 ms | 432 ms | Même expérience |
| Parser 250 000 URL, plafond 50 000 | 124 ms | 38 ms | Médiane de 5 passages |
| Trois index Direct, 20 actualisations de 50 000 chaînes | 984 ms | 5 ms | Expérience synthétique, index réutilisés |

Ces mesures ne prédisent ni le débit fournisseur ni le temps d'import sur une
box. Les tests fonctionnels vérifient les données, les limites, le rollback et
l'absence de nouveaux parcours ; aucun seuil de chronométrage fragile n'est
imposé à la CI.

## Mise à jour et livraison Windows

Les manifestes sont interrogés en parallèle. L'interface distingue une
vérification impossible d'une application réellement à jour. Les téléchargements
identiques partagent le même travail ; les versions différentes sont sérialisées.
Un cache est recontrôlé avec sa taille et son SHA-256 avant installation.

Le constructeur Windows produit un installateur, un ZIP portable, `version.json`,
un manifeste de provenance et les SHA-256. Le runtime Visual C++ est embarqué
pour ne pas dépendre d'une installation de Visual Studio chez le client.

La signature exige le véritable certificat de signature de code de l'éditeur :
`WINDOWS_SIGNING_CERTIFICATE_BASE64`, son éventuel mot de passe
`WINDOWS_SIGNING_CERTIFICATE_PASSWORD`, et la variable publique d'empreinte
`WINDOWS_SIGNING_CERTIFICATE_THUMBPRINT`. Ne jamais placer ces secrets dans Git.
SignTool vérifie la chaîne Authenticode et l'horodatage. Sans certificat, seul
un artefact de revue explicitement non signé est autorisé. La publication exige
la signature, les contrôles du canal et les approbations existantes ; le gel de
production et les restrictions de branches ne sont pas modifiés.

La route du domaine `https://zuno.7themotion.com/pc` cible déjà la release Windows.
Elle ne doit être annoncée comme lien de cette nouvelle version qu'après
publication vérifiée du nouvel installateur. L'ancienne release ne vaut pas
preuve de livraison de ces corrections.

## Validation et limites

Avant envoi : 157 tests Kotlin réussis, tests ciblés d'import, d'index, de mise
à jour et de lecteur Windows réussis ; 17 catalogues de langues complets.
La suite Flutter locale a exécuté 915 tests avec succès (8 ignorés) ; deux tests
Cast réseau sont bloqués par `NetworkInterface.list` dans ce conteneur
(`Bad value for ai_flags`). Les deux tests de connexion panel passent sur le
serveur local, exécutés séparément car ils partagent le port 18789. Les 72 tests
de configuration passent. Analyse Flutter : zéro erreur, 229 diagnostics de
style/avertissement. La CI du commit final reste la preuve de compilation
Android/Windows et de la suite Flutter entière. Les résultats du run et les empreintes des artefacts
doivent être associés au SHA exact, pas à un ancien APK.

Aucun essai physique HDR, entrelacement, cadence HDMI, PC Windows ou Cast n'a été
réalisé dans cet environnement. Les mécanismes Cast et leur bouton ne sont pas
remplacés. La qualité finale reste liée au flux, au décodeur et à l'écran.
