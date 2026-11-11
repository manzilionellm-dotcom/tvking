# CI de validation du lot 1

Cette CI est une nouvelle préparation après perte de l'environnement. Elle
ne réutilise aucun résultat antérieur et n'a pas encore été exécutée sur GitHub
au moment de ce checkpoint. L’agent responsable relit les déclencheurs, droits, scripts appelés et artefacts
avant tout push déjà autorisé par la mission ; aucune nouvelle autorisation
utilisateur n’est introduite pour cette relecture.

Les commits L1-02, L1-05 et L1-06 avaient déjà atteint GitHub et leurs sources
ont été récupérées à l'identique. Leurs documents gardent le récit des essais
de cette première session ; les anciens journaux locaux ont été perdus.
La validation du lot reconstruit repose sur les nouvelles exécutions et
empreintes du rapport final, y compris les régressions rejouées sur le vrai
116. Les résultats d'un arbre perdu ne sont pas attribués au nouvel arbre.

## Périmètre et droits

`zuno-audit-116.yml` ne répond qu'aux pushes sur `zuno/audit-116-lot1` dans
`manzilionellm-dotcom/tvking`, effectués et relancés par le propriétaire.
La branche d'intégration n'est pas une cible de publication et aucune fusion
n'est effectuée. Les droits sont `contents: read` ; aucun job n'a de droit
d'écriture GitHub. Les checkouts utilisent le SHA du push et ne conservent
pas les credentials Git.

Le constructeur existant n'est pas appelé : le nouveau workflow contient
physiquement les seules étapes nécessaires à un APK. Il ne contient aucune
commande de génération AAB, de création/modification de release, de déploiement
Worker/panel ni d'écriture sur un lien public. Les workflows historiques
restent inchangés, sauf les deux modes de tests partagés décrits plus bas.

Le build signé garde l'environnement `zuno-app-production` et le script
`.github/app-release-guard.mjs` inchangé. Ses paramètres sont fixes : opération
build, publication fausse, test_box faux, backend vide, variante box, AAB faux.
Le manifeste `.github/app-production.json` n'est ni modifié ni contourné.
Une éventuelle approbation GitHub de l'environnement reste applicable.

## Identité et signature

L'APK utilise `lib/main_tv.dart`, le package `com.sevenmotion.tv.seven_tv` et la
clé déjà existante. Le script de signature exige le secret base64 ou déchiffre
`ci/release.jks.enc` avec le secret existant. Sans clé, il échoue ; aucune clé
debug de repli n'est créée. Le certificat DER est contrôlé **avant compilation**
puis vérifié sur l'APK produit :

`5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61`

La version de validation est `116-test.<run_number>`, compatible avec le
vérificateur de démarrage existant. Le versionCode est l'epoch courant,
strictement supérieur à 1794284448 et inférieur à 2100000000. Il n'y a aucune
lecture ou écriture de version.json et aucun changement de canal de mise à
jour. Ni `ZUNO_UPDATE_CHANNEL` ni `PLAY_BUILD` ne sont ajoutés.

Les scripts durables `patch_manifest.py` et `patch_gradle.py` sont utilisés.
Après compilation, les quatre Kotlin générés du paquet zuno_cast doivent être
identiques octet par octet aux sources de `android_overlay/google_cast`.

## Résolution des dépendances

Les versions d'outils proviennent des workflows du dépôt : Flutter 3.47.7
stable, Java17 pour Android et les capacités, Java21 et Gradle8.11.1 pour la
logique native. Le compilateur du test de bridge Cast est celui déjà résolu
par le projet logique Kotlin2.0.21 ; aucune dépendance applicative n'est ajoutée.

Deux ressources doivent contenir les résolutions réellement testées :

- `ci/audit-116/app-tests.lock` pour les tests de l'application.
- `ci/audit-116/tv-apk.lock` pour le build TV après le pin existant
  `shared_preferences_android: 2.5.0`.

Chaque job copie le verrou correspondant, exécute `pub get --enforce-lockfile`
puis compare le résultat. Un fichier absent ou une résolution différente fait
échouer le job. Les résolutions ont maintenant été réellement refaites avec
le SDK exact, sans changement de dépendance hors le pin TV déjà prévu :

- application : `52b123c9a3dc9d182d91411c076551b8b50b211827ad55052d7ae23795124c92` ;
- TV : `48b594e4a393325ad413b2816aba4db5122c480b88afa03fde4f95b48cec0022`.

## Contrôles et preuves

| Job | Contrôle | Preuve conservée |
| --- | --- | --- |
| configuration | SHA, arbre116, ascendance, gardes et vérificateur startup | Logs, SHA/arbre et résultat des transformations |
| flutter | Toutes les localisations, analyse stricte séparée, gate historique sans erreur, tous les tests | Codes et logs de l'analyse, suite complète, verrou et version Flutter |
| worker | Smoke de sécurité et tous les fichiers `*.test.mjs` | Logs Node et SHA |
| player / mobile | Workflows obligatoires du code partagé, sur les sources courantes | Suites Flutter, logique JVM, capacités, matériel et bridge |
| pixels | Scripts existants API29 et API35, mire locale et contre-preuve | Images, mesures, XML et logs existants |
| build-tv | APK signé, identité, ABI, backend et quatre copies Kotlin | SHA256, taille, certificat, provenance, classpath Media3, logs et symboles |
| startup | Script original API29 et API35 sur les octets exacts uploadés | Manifestes, XML, captures, rapports et logs de chaque API |

`player-debug-test.yml` et `mobile-gestures-test.yml` reçoivent un input
`workflow_call.audit_116`, faux par défaut. Vrai, il appelle les nouveaux tests
sur `android-app` au SHA courant. Faux, leurs anciens jobs gardent leur corps
et leurs déclencheurs. Le mode audit ne reconstruit pas une ancienne base
téléphone, ne change pas de package et ne produit aucun APK.

Le contrôle des ancres extrait séparément la base téléphone réellement utilisée
par les anciens workflows et y applique les patches dans leur ordre. Il exécute
aussi `prepare.py --edition auto` sur une extraction temporaire du SHA courant,
suivi du pin SharedPreferences Android 2.5.0, sans compilation ni AAB. Cette
préparation ne participe jamais au build APK. Le checkout secondaire de
`37fdf3305c5de9d35e20fd6567df38008fc7a7ee` n'est utilisé que par ce contrôle ;
le build et les tests partagés utilisent le SHA courant.

Les jobs historiques `test-apk` sont ignorés dans ce mode et ne sont pas
comptés comme réussis. Ils visent la base mobile ancienne et créent des
identités de test distinctes. Le rapport attribue séparément les résultats
aux nouveaux jobs réellement exécutés sur le code partagé du SHA courant.

## Captures contrôlées des écrans existants

Le fichier opt-in `test/features/tv/lot1_reference_capture.dart` fonctionne
sur le 116 et le candidat sans changer leurs sources de production. Il fixe
le produit ZUNO TV, le profil adulte p1 confirmé, le contrôle parental chargé,
la langue française, Phantom Black, 1920×1080 pixels, DPR 1 et texte 1. Le
catalogue SQLite synthétique contient les mêmes six chaînes ; Alpha est en
favoris et Bravo en récent. Le Direct utilise son vrai conteneur `TvShell`.
La capture intervient après douze pas de 100 ms, avant le délai de l'aperçu
vidéo : elle n'est pas une preuve de pixels ou de qualité vidéo.

`fixed_capture_clock.c`, compilé en bibliothèque de test avec le compilateur
C du runner, fige seulement l'heure civile du processus `flutter_tester`.
Le processus Flutter outil, CLOCK_MONOTONIC et les autres horloges restent
inchangés. Aucun fichier de production ni horloge système n'est modifié.
Les variables requises sont `AUDIT116_CLOCK_PROCESS=flutter_tester`,
`AUDIT116_CLOCK_EPOCH=1794416400`, `TZ=UTC` et `LD_PRELOAD` pointant vers cette
bibliothèque. Le test refuse une date différente de 2026-11-11 17:00:00 UTC.

La sonde `capture_clock_probe.dart` a réellement confirmé la date constante
avant/après un Future de 120 ms, tandis que Stopwatch avançait de 128 ms.
Cette sonde utilise `AUDIT116_CLOCK_PROCESS=dartvm` pour le SDK installé.
Cela vérifie le dispositif de temps. Les captures de référence ont été
exécutées sur le commit exact du 116 et inspectées ; les captures candidates
et leur comparaison sont rattachées séparément au SHA final dans le rapport.

## Lecture des résultats et limites

Le code non nul de l'analyse stricte est conservé même si le gate historique
sans erreur passe. Un avertissement préexistant ne disparaît pas du rapport.
Un job sauté, annulé ou absent n'est pas un succès. Les artefacts nomment le SHA
réel ; les contrôles startup téléchargent l'ID produit par le job de build,
vérifient son SHA256 et sa taille, puis contrôlent le certificat et la version.

La CI ne prouve aucun gain de fluidité sur box physique, aucune compatibilité
Cast réelle sur téléviseur, ni une acceptation Google Play. Les émulateurs sont
des appareils de test jetables. Aucun appareil ou catalogue client n'est effacé.
