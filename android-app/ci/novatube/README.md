# Construction séparée de NOVATUBE

## REC et sauvegarde MP4 dans le téléphone

Le lecteur NOVATUBE attend la fermeture de sa connexion directe, puis partage
un seul relais entre la lecture et l'enregistrement. Le relais reconnaît les
réponses MPEG-TS et HLS, suit les variantes et recopie les segments TS sans
réencoder la vidéo. Il ne confirme le démarrage qu'après réception et écriture
de vrais paquets ; erreurs réseau, disque et fermeture sont remontées à
l'interface. Les prises portent un nom unique, y compris dans la même minute.
Les HLS chiffrés, à pistes séparées ou en fMP4 non pris en charge sont refusés
explicitement ; aucun texte de playlist n'est enregistré comme une vidéo.

Pendant la bascule du direct vers le relais, un fournisseur limité à une
connexion peut encore refuser la nouvelle lecture (401/403/458/509, 429/5xx
ou coupure). Avant le premier octet média, le relais réessaie donc pendant
toute la fenêtre du premier média (25 s), avec un délai plafonné ; après le
premier média, 401/403 redeviennent définitifs et les segments déjà écrits ne
sont jamais recopiés. Une coupure en plein REC autorise 12 reconnexions,
comme 7 MOTION.

Chaque REC terminé avec de vraies données, même interrompu par le réseau,
est **sauvegardé automatiquement** dans la galerie (même export MP4 que le
bouton ci-dessous). Les sauvegardes passent une par une, attendent un export
manuel en cours au lieu d'échouer, et ne recopient jamais un fichier déjà
exporté. Le lecteur affiche le résultat ; en cas d'échec, l'original reste
dans l'app et le bouton permet de réessayer.

Dans Réglages → Enregistrements, le bouton **Enregistrer dans la galerie
(MP4)** exporte une prise terminée vers `Movies/NOVATUBE/NOVATUBE_*.mp4`.
La progression reste visible pendant le traitement. Les doubles exports et
la suppression du fichier pendant sa conversion sont bloqués, même après
fermeture et réouverture de la liste.

Les pistes H.264/AAC compatibles sont remuxées sans perte. Sinon, les codecs
natifs effectuent une conversion H.264/AAC lorsque l'appareil la permet,
avec dimensions et cadence source conservées et un débit adapté. Il n'y a
pas d'agrandissement artificiel d'une vidéo basse définition. Un codec absent,
une source HDR non gérée, une piste audio perdue, un fichier invalide ou une
copie interrompue donnent un échec visible ; le fichier original est conservé.
L'export ne promet pas la lecture de toute résolution sur chaque téléphone.
Le nom `.mp4`, le conteneur et les pistes réels doivent tous être corrects.

La lecture du TS enregistré utilise `MediaExtractorCompat` de Media3 1.5.1,
déjà embarqué par le lecteur. Son parseur TS sait identifier les pistes HEVC ;
la conversion conserve ensuite les vrais codecs Android de l'appareil. Le MP4
final reste contrôlé par l'extracteur Android natif, et la capacité matérielle
du téléphone reste nécessaire pour décoder puis encoder le format demandé.

Avant le remux H.264, chaque séparateur Annex-B de trois octets est normalisé
en quatre octets : les NAL vidéo, leur ordre, les horodatages et la piste AAC
restent inchangés. Le parseur natif `MPEG4Writer` soustrait quatre octets entre
deux NAL ; lui transmettre les séparateurs mixtes du TS peut tronquer un NAL
ou arrêter le processus avec une taille d'écriture négative. Le run nº11 a
enregistré cet arrêt dans `addMultipleLengthPrefixedSamples_l`.
Le correctif refuse les NAL vides ou mal formés et applique la limite de
64 Mio après l'expansion, avant toute allocation ou écriture native. Des
tests JVM vérifient les octets préservés et les tampons directs/lecture seule ;
les trois tests Android et leurs exigences de durée, d'images et de son
restent obligatoires pour autoriser la publication.

Les PTS d'un TS peuvent débuter avant l'origine choisie par le parseur : dans
la mire H.264, le premier son précède la première image de 21 333 µs. Une
passe sur les métadonnées des pistes sélectionnées relève leur minimum sans
stocker toute la chronologie ni décoder la vidéo. Si ce minimum est négatif,
une translation commune remet toutes les dates à zéro ou après zéro, pour
le remux comme pour les deux décodeurs de la conversion. Les écarts entre
audio et vidéo, la cadence et l'ordre des images restent ainsi identiques.
La fin de l'entrée dépend de l'absence d'échantillon, jamais du signe du PTS.
La relecture finale continue de refuser une piste vide ou un PTS négatif,
avec un message distinct pour ces deux cas.

Android 10 et plus utilise MediaStore sans accès global à la galerie. Android
7 à 9 demande la permission d'écriture historique, limitée par `maxSdkVersion=28`.
Le REC reste désactivé dans l'espace +18 : un export public dans la galerie
ne serait plus protégé par la biométrie de l'application.

Le workflow privé exige les tests UI/REC, les règles natives sur JVM et trois
tests instrumentés sur Android 35 AOSP : sauvegarde AVC/AAC, conversion HEVC
vers AVC/AAC et refus d'une fausse vidéo. Les clips sont synthétiques (mire et
son générés par ffmpeg), réservés à l'APK de test. Les deux fichiers sont
versionnés dans `recording-test-media/` et vérifiés par SHA-256 avant copie :
la CI ne dépend pas d'une installation FFmpeg ou d'un miroir Ubuntu pour
les préparer. La commande `create_recording_test_media.py --regenerate DOSSIER`
documente leur fabrication locale à partir d'une mire et d'une sinusoïde ;
une régénération exige une revue des nouveaux fichiers et de leurs empreintes.
Un précontrôle démarre l'émulateur puis l'arrête avant de lancer la compilation
privée. Il ne constitue pas une réussite des tests d'export et ne crée pas leur
preuve. Si Android ne démarre pas, le code de sortie et la fin du journal sont
affichés, puis conservés dans un artefact de diagnostic. Cela évite d'attendre
une compilation complète pour découvrir une panne du banc de test.
L'AVD est créé et recherché dans un même dossier NOVATUBE sous `RUNNER_TEMP`,
avec un chemin absolu et `ANDROID_AVD_HOME` transmis aux deux outils. Le fichier
de déclaration `.ini` est contrôlé avant le lancement ; le répertoire personnel
du runner n'est pas déplacé.
Le runner redémarre ensuite Android, installe l'APK release exact et lie la
preuve des trois exports à son SHA-256 avant la publication. L'AVD jetable ne
contient que le banc synthétique, sans playlist utilisateur ; tous ses buffers
logcat sont vidés juste avant les tests. En cas d'échec, deux collectes
indépendantes conservent jusqu'à 3 000 lignes : tous les buffers Android dans
`recording-android-logcat.txt`, puis le buffer de crash dans
`recording-android-logcat-crash.txt`. Aucun filtre par tag ne masque les erreurs
AndroidRuntime, les signaux natifs ou une suppression par ActivityManager/LMKD.
Les valeurs sensibles de l'environnement sont masquées avant écriture et
affichage. Même si une collecte échoue, sa sortie partielle et la seconde
collecte sont conservées ; la console ne reprend que les 100 dernières lignes
de chaque buffer. L'artefact de diagnostic conserve les deux journaux complets
bornés et le `mapping.txt` R8 release pour interpréter une stack obfusquée.
Il est téléversé uniquement en cas d'échec, après suppression de la clé
temporaire, sans aucun APK non vérifié. Ces diagnostics ne valident aucun test.
Une réussite sur émulateur n'est pas un essai sur le téléphone de l'utilisateur.
Le lanceur AndroidX et l'APK de test partagent plusieurs bibliothèques avec
l'application. Gradle ne les embarque pas une seconde fois dans l'APK de test,
alors que R8 peut supprimer leurs entrées inutilisées par l'application seule.
Les règles de `android/app/proguard-rules.pro` sont obtenues par l'outil officiel
R8 `TraceReferences`, à partir du bytecode des trois tests et des dépendances
AndroidX Test figées : runner 1.6.2, monitor 1.7.2, core 1.6.1, ext-junit 1.2.1,
storage 1.5.0 et concurrent-futures-ktx 1.1.0.
Elles conservent les classes et membres effectivement référencés dans le
classpath release : Kotlin et coroutines, futures, Lifecycle, Trace et le pont
Flutter. Les façades Kotlin et leurs méthodes héritées sont traitées ensemble.
Aucune règle globale ne désactive l'optimisation, et les bibliothèques du lanceur
restent réservées à l'APK de test. Les trois critères d'export et l'identité de
l'APK release testé restent inchangés.

## Profils et APK de test avec espace +18

La demande complémentaire conserve l'identité NOVATUBE, la version `0.1.5+5`
et sa clé dédiée. Elle permet dix profils, chacun avec dix sources manuelles
Xtream ou M3U. La migration attribue les anciennes sources au profil 1.

Le build AAB Play garde `allowAdult=false` et ne reçoit aucun paramètre
`NOVATUBE_PRIVATE_APK`. L'espace +18 est réservé à une compilation APK
installée directement :

```sh
flutter build apk --release --target=lib/main_zuno_mobile.dart \
  --build-name=0.1.5 --build-number=5 \
  --dart-define=NOVATUBE_PRIVATE_APK=true
```

Dans cet APK, l'activation est désactivée au départ et propre à chaque profil.
La première ouverture demande une confirmation de majorité et une
authentification biométrique système. Chaque nouvelle visite exige cette
authentification (empreinte sur un appareil configuré) ; aucun PIN de
l'application ou de l'appareil ne sert de repli. Sans biométrie disponible et
enregistrée, après annulation ou échec, la section reste verrouillée. Les
profils enfants restent bloqués. Le changement de profil et le passage en
arrière-plan révoquent la session ; elle n'est jamais persistée.

Le tri exploite noms, catégories, marqueurs `+18`/`18+`/`🔞` et indicateurs
explicites du fournisseur, notamment `is_adult`. Le signal est conservé dans
la base, les caches, les reprises et les téléchargements sans modifier les
libellés ou URLs. Une catégorie neutre peut être ouverte dans +18 sous le
libellé « Dossier source », mais seuls ses titres classés adultes y sont
affichés. Le filtrage précède les plafonds de recherche et de récents.
Les indications découvertes dans une fiche consultée sont mémorisées par
source et par titre. Aucun scan du contenu vidéo ni de toutes les fiches
n'est effectué ; un fournisseur sans information fiable peut laisser un
contenu impossible à identifier automatiquement. L'application ne fournit
aucune source ni aucun contenu.
Le bouton REC est désactivé dans cette section : les enregistrements actuels
ne disposent pas d'un accès protégé. La lecture, le Cast et les favoris restent
disponibles après authentification.

Ce paramètre ne réactive ni les licences, ni le panel/MAC, ni Gold, ni les
promotions, ni les achats externes. Les contrôles de signature et d'identité
restent identiques. Aucun de ces builds n'est envoyé à Google automatiquement.

Les tests `test/novatube/adult_access_test.dart` couvrent les verrouillages,
les profils, la biométrie et la conservation des signaux dans la reprise.
Les tests de tri contrôlent les catégories neutres, les indicateurs explicites
et la conservation du classement après rechargement. Les tests biométriques
utilisent une plateforme simulée ; un essai sur appareil physique reste
nécessaire pour vérifier le dialogue et le capteur de ce téléphone.
Les tests d'interface de l'APK doivent aussi être exécutés avec le paramètre
`--dart-define=NOVATUBE_PRIVATE_APK=true` ; les tests Play restent exécutés sans
ce paramètre.

Ce dossier prépare **NOVATUBE**, nouvelle application Android :

| Valeur | Identité imposée |
| --- | --- |
| Branche | `feature/novatube-play-aab` |
| Base | `zuno-mobile-0.1.5-test` |
| Commit source | `93d367e501905e0bd2478d021013d93e43b5794b` |
| Package et namespace | `com.sevenmotion.novatube` |
| Nom | `NOVATUBE` |
| Entrée Flutter | `lib/main_zuno_mobile.dart` |
| Version | `0.1.5` |
| versionCode | `5` |
| Clé d'upload | Nouvelle clé `novatube-upload`, dédiée à NOVATUBE |

## Accord avant compilation

Le propriétaire doit d'abord voir les fichiers modifiés et approuver la
compilation de leur commit exact. Aucune compilation Flutter, Android ou JVM
ne doit être exécutée pour NOVATUBE avant cet accord. Les lectures, contrôles
de syntaxe et tests Python de validation de fichiers ne construisent pas l'app.

Le workflow `.github/workflows/novatube-play-aab.yml` a uniquement un événement
`workflow_dispatch`. L'entrée `reviewed_commit=<SHA complet approuvé>` reste
obligatoire. `confirme=COMPILER_NOVATUBE` construit l'AAB Play sans publication ;
`confirme=PUBLIER_NOVATUBE_APK_PRIVE` construit et publie l'APK privé vérifié.
Si la branche a changé depuis la revue, le job ne démarre pas. Aucun job ne
publie sur Google Play ou dans un environnement ZUNO/7 MOTION.

## Adresse fixe pour Downloader

**<https://novatube.zuno8k.com/novatube.apk>** est l'adresse à conserver dans
Downloader. Le Worker Cloudflare dédié `novatube-downloads` lit
`latest-download.json` sur la seule branche NOVATUBE puis redirige vers l'APK
signé et vérifié. Les métadonnées publiques sont disponibles à
<https://novatube.zuno8k.com/version.json>. Les routes `/` et `/apk` mènent
également au téléchargement.

Le premier APK disponible est celui du commit `26193f18`, hébergé dans le
stockage Blob dédié. Les prochaines publications du mode
`PUBLIER_NOVATUBE_APK_PRIVE` utilisent des releases GitHub propres à NOVATUBE :
tag `novatube-private-<SHA complet>` et fichier `NOVATUBE-<SHA complet>.apk`.
Elles ne changent pas la release « latest » globale du dépôt. Les assets
existants ne sont jamais écrasés et aucun secret d'hébergement supplémentaire
n'est nécessaire.

La publication suit cet ordre : analyse, tests Play et privés, signature,
contrôle du véritable APK, conservation de ses preuves, téléversement dans
la release dédiée, téléchargement public intégral et comparaison du SHA-256.
Le manifeste est modifié seulement après la réussite de ces contrôles, par
une écriture conditionnelle sur le SHA de son contenu courant. Un échec de
build, de tests, de téléchargement ou une modification concurrente laisse
le dernier pointeur valide en place. Un ancien run ou un commit antérieur
ou divergent ne peut pas remplacer une version plus récente.

Le job de compilation reste en lecture seule ; seul le job de publication
dispose de `contents: write`, après réussite du premier job et vérification
du propriétaire, de la branche, du mode privé et du SHA approuvé. Le Worker
refuse un manifeste d'une autre application ou d'un autre certificat et
n'accepte que les destinations NOVATUBE prévues. Il ne conserve pas la
redirection en cache ; le cache GitHub en amont peut toutefois retarder de
quelques minutes la visibilité du nouveau manifeste.

Les tests Python et Node couvrent ces comportements avec des doubles de
GitHub et du réseau. Le résultat effectif de chaque publication reste celui
du run indiqué dans le manifeste et dans les preuves de l'artefact ; des tests
du script ne constituent pas à eux seuls une publication GitHub Actions.

Les exclusions de cette branche dans `build-zuno-tv.yml` et `quality-zuno.yml`
empêchent leurs déclenchements habituels au push. Elles n'altèrent pas leurs
copies sur les autres branches. Ne pas ouvrir de PR avant l'accord : le dépôt
possède également des workflows hérités déclenchés par les PR, dont `qa-gates`.

## Enregistrement du workflow GitHub

Le workflow initial a été ajouté sur `main` par la PR autorisée pour ce seul
fichier. Les évolutions APK privé restent sur `feature/novatube-play-aab` ;
sélectionner cette branche lors du lancement manuel et garder les deux
entrées existantes `confirme` et `reviewed_commit`.

Un nouveau workflow uniquement manuel, ajouté seulement à une branche de
travail et jamais exécuté, peut être absent du registre GitHub Actions.
La documentation GitHub exige la présence du fichier sur la branche par
défaut pour son amorçage ; elle indique également qu'après une première
exécution, l'API/CLI peuvent le lancer sur une autre branche ou un tag.

La commande `gh workflow run novatube-play-aab.yml --ref
feature/novatube-play-aab` ne supprime pas cette contrainte d'enregistrement.
Ne pas modifier `main`, changer la branche par défaut, recycler le workflow
de signature ZUNO/7 MOTION ni ajouter un déclencheur automatique pour la
contourner. Si aucun point d'entrée indépendant déjà enregistré et autorisé
n'est disponible, signaler ce blocage au propriétaire et attendre sa décision.
Un fichier YAML préparé n'est pas un run réussi, ni un AAB construit.

Références officielles :

- [Événements GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch)
- [Lancement manuel d'un workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)

## Signature et sauvegarde

Les seuls secrets utilisés par cette chaîne sont :

- `NOVATUBE_UPLOAD_KEYSTORE_BASE64`
- `NOVATUBE_UPLOAD_STORE_PASSWORD`
- `NOVATUBE_UPLOAD_KEY_PASSWORD`
- `NOVATUBE_UPLOAD_KEY_ALIAS`

Ils sont attendus dans les secrets GitHub Actions du dépôt, avec une nouvelle
clé indépendante. Aucun secret `ANDROID_*`, aucun `key.properties` hérité,
aucune clé debug ni clé ZUNO/7 MOTION ne peut servir de repli.

Le certificat public `novatube-upload-cert.pem` et `fingerprint.json` sont
versionnés pour que la signature attendue soit revue avec le code. Le JSON
doit contenir `package`, `alias` et `sha256` (64 caractères hexadécimaux sans
séparateurs). Il ne contient aucune clé privée ni aucun mot de passe.

Le fichier temporaire du runner est créé hors du dépôt avec le mode `0600`,
vérifié contre l'empreinte publique, utilisé par Gradle puis supprimé même
en cas d'échec. La sauvegarde durable de la clé et des mots de passe est une
opération privée distincte, à confirmer au propriétaire lors de sa création.
Les métadonnées des secrets GitHub ne constituent pas une sauvegarde exportable.
Ce dossier et les artefacts du workflow ne doivent jamais contenir cette clé.

## Icône exacte et absence de rognage

`branding.json` lie le logo fourni et les ressources classiques/adaptatives
revues visuellement à leurs empreintes SHA-256. Format :

```json
{
  "source_path": "android-app/assets/novatube/logo-source.png",
  "source_sha256": "<empreinte exacte du fichier fourni>",
  "generated_icons": {
    "android-app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png": "<empreinte exacte>"
  }
}
```

Les chemins sont relatifs à la racine du dépôt. Le manifeste réel contient
les cinq densités classiques, le XML adaptatif et ses ressources. Le contrôle
refuse toute image absente ou modifiée depuis la revue. Le contrôle des sommes
ne remplace pas la vérification visuelle du texte dans les masques Android.

## Vérifications effectuées après accord

1. Source issue du tag exact, commit approuvé, identité Gradle/Flutter, politique
   Play immuable, icônes et certificat public.
2. Régressions Python : mauvais package/version, debug, lanceur TV, Cast absent,
   service de lecture incorrect, rapports de tests interrompus ou en échec.
3. Tests JVM existants du handoff réseau Cast avec les dépendances épinglées.
4. Analyse Flutter et tests des nouvelles exclusions Play, de l'import réel
   M3U/Xtream, du Cast, des profils/favoris, de l'EPG et de la lecture.
   Les anciens tests d'activation commerciale ne constituent pas les critères
   attendus de NOVATUBE. Les nouveaux tests vérifient leur désactivation.
5. Construction avec la commande exacte suivante, sans le mode Cast de test :

```bash
flutter build appbundle --release \
  --target=lib/main_zuno_mobile.dart \
  --build-name=0.1.5 --build-number=5
```

Les wrappers Gradle absents du tag sont extraits d'un projet Flutter temporaire.
Seuls `gradlew`, `gradlew.bat` et `gradle-wrapper.jar` manquants sont copiés :
aucune réécriture du manifeste ou de la configuration native NOVATUBE.

6. `bundletool validate`, puis lecture du manifeste du véritable AAB : package,
   nom/version, lanceur mobile, Cast et services de lecture.
7. Comparaison SHA-256 du signataire avec le certificat public approuvé, puis
   `jarsigner -verify -strict` avec un truststore ne contenant que ce certificat.
8. Présence du moteur Flutter release pour les trois architectures attendues,
   rapports de tests réellement terminés et empreinte du verrou des dépendances.

`bundletool` est épinglé à `1.18.2`, SHA-256
`378b5434cd1378bef6b2bc527b8c7f0ff2584b273830335bce54d6d0813c8584`,
fourni par l'[asset officiel Google](https://github.com/google/bundletool/releases/tag/1.18.2).

## Livrable et limites du rapport

L'artefact `NOVATUBE-0.1.5-5-verified-<commit>-<tentative>` n'est créé qu'après
la réussite de toutes les étapes. Il contient l'AAB, son SHA-256, le manifeste
extrait, le rapport de signature, les tests, la version Flutter exacte et la
provenance (commit, numéro/URL du run, versions, certificat).

Aucun AAB n'est téléversé en cas d'échec. Un résultat de tests unitaires ou de
widgets n'est pas un essai sur téléphone : la provenance distingue les tests
non exécutés sur appareil et les tests d'export du mode privé sur émulateur
Android 35. Aucun contrôle de ce workflow ne constitue une
acceptation Google Play. Les champs `googleUpload` et `published` restent
`false` : toute création de fiche ou publication attend une autorisation séparée.
