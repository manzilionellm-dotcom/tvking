# Banc de démonstration dataSync NOVATUBE

## Statut et portée

Ce dossier prépare un job de preuves séparé, dans le workflow NOVATUBE déjà
enregistré. Neuf essais Android ont été exécutés sur l'ancien AAB7 ; les plus
avancés ont affiché le lecteur avec la mire réelle. Aucun MP4 de l'interface
n'est encore qualifié. Les bancs sont maintenant épinglés sur l'AAB8 vérifié ;
aucun parcours FGS de cette version n'a encore été exécuté.
Le scénario est destiné à une revue humaine avant toute utilisation dans
Google Play Console ; une réussite machine ne vaut pas approbation de Google.

Le binaire de référence est NOVATUBE **0.1.8 (8)**, vérifié localement le
14 novembre 2026 : commit `1610073a902acb922d1ea1bc394eebef2273efb3`,
run `43608872429`, tentative `1`, artefact `14120095100`.

| Élément immuable | Valeur vérifiée |
| --- | --- |
| Nom d'artefact | `NOVATUBE-0.1.8-8-verified-1610073a902acb922d1ea1bc394eebef2273efb3-1` |
| Archive ZIP | 96 493 953 octets ; SHA-256 `5bfaa2a6e74e3594ea7bb377e038b266e7b2014c8c5dbc66c407273231f598ee` |
| AAB | 97 127 777 octets ; SHA-256 `4de381b8bcc7898bf96d038945f4b2047586aad08cd990630404d345c7cceb60` |
| Certificat d'upload | SHA-256 `38d6dabe9a73e5ab94a56491e4da6638f5da09ef1eaa77d0eb892d5f0478824b` |

Les contrôles locaux ont confirmé la provenance, le manifeste, la validation
bundletool et la signature JAR stricte. Les rapports du build attestent
608 tests Flutter, 10 tests Cast JVM et 42 tests d'enregistrement JVM.
Ces résultats ne prouvent pas l'exécution Android de ce nouveau banc vidéo.

Le repin local du 14 novembre 2026 sur la base `1610073a902acb922d1ea1bc394eebef2273efb3`
passe les 140 tests Python. Les quatre jobs hors preuves vidéo sont identiques
à cette base. Les conditions, permissions, actions et commandes des deux jobs
vidéo restent identiques ; leurs identités de binaire et empreintes sont mises
à jour ensemble. Ce contrôle local n'exécute ni émulateur ni parcours FGS.

## Deux provenances explicites

Le SHA saisi dans `reviewed_commit` approuve le script de démonstration. Le
binaire est fixé séparément par le bloc de constantes en tête de
`run_datasync_evidence.py` : commit original, run, tentative, artefact,
SHA-256 ZIP et SHA-256 AAB. Le workflow ne propose pas d'URL de binaire libre.

Les gardes exigent un lancement manuel sur
`feature/novatube-play-aab`, dans `manzilionellm-dotcom/tvking`, par le
propriétaire et le même propriétaire comme acteur déclencheur, avec le SHA
complet du script et l'intention `CAPTURER_NOVATUBE_DATASYNC`.
Le script vérifie aussi `GITHUB_WORKFLOW_REF`, `GITHUB_WORKFLOW_SHA` et
`GITHUB_JOB` : seul `capture_datasync`, dans le fichier de workflow enregistré
et au même SHA approuvé, peut exécuter le banc.

Le job `capture_datasync` est en lecture seule (`contents: read`, `actions: read`).
`github.token` sert uniquement à l'action de téléchargement d'un artefact
d'un autre run. Aucun secret de signature ni droit d'écriture n'est fourni.
Les octets exacts du workflow sont vérifiés par une empreinte dans le script.
Toute modification du YAML, même un changement de nom, exige de mettre à
jour cette empreinte après revue. Une seconde empreinte porte sur l'objet
`capture_datasync` après lecture YAML ; `verify_source.py` vérifie ainsi
l'intégralité de ce job sans relâcher les gardes des trois jobs existants.

Le second checkout fournit les helpers et traductions du commit exact de
l'application. Ils restent inchangés : validation de provenance, signature
publique réelle, manifeste réel, bundletool 1.18.2 épinglé, conversion en APK
avec une clé éphémère, comparaison DEX/libapp et émulateur Android 35.
L'application n'est jamais recompilée. L'APK dérivé et sa clé ne sont jamais
inclus dans les artefacts de preuves.

## Scénario réel

1. Installer l'APK dérivé sur un téléphone AOSP neuf.
2. Accorder uniquement `POST_NOTIFICATIONS` par `adb pm grant` sur cet
   appareil jetable, puis vérifier le résultat Android. Cette préparation
   est enregistrée dans les preuves ; aucun dialogue de permission au clic
   REC n'est prétendu. Le parcours REC actuel ne présente pas ce dialogue.
3. Ajouter volontairement une M3U par l'interface : Serveur, Ajouter M3U,
   champ URL M3U, Valider et charger ma liste. Aucun préremplissage de la base
   ou changement de préférences n'est effectué.
4. Ouvrir Direct et la chaîne synthétique `NOVATUBE_TEST_PATTERN`.
5. Vérifier une vraie image animée dans une surface vidéo observée, puis
   commencer la capture d'écran MP4 avant le tap REC.
6. Taper REC, vérifier le service `dataSync` (type 1, notification 1001),
   passer Home et observer une croissance du fichier pendant huit secondes.
7. Ouvrir le volet Android et taper l'action `Arrêter` de la notification
   `Enregistrement en cours`. Vérifier retrait du service, de la notification
   et stabilisation du fichier.
8. Récupérer et vérifier le fichier `.ts`, arrêter le serveur source, puis
   ouvrir Mes enregistrements et relire le fichier dans l'application.
9. Vérifier une image animée en relecture et que la vidéo MP4 contient toute
   la séquence des actions. Conserver les relevés, XML UI et sommes de contrôle.

Les coordonnées de chaque action proviennent des rectangles des éléments
effectivement observés. Une surface vidéo non accessible, un libellé absent,
une notification ambiguë ou un fichier inaccessible entraîne un échec. Le
script n'invente pas de sélecteur réussi ni d'image à la place d'un échec.

Le run `43599920601` expose la vidéo via un `FrameLayout` NOVATUBE et une
unique `View` feuille ayant les mêmes bounds, non interactifs et sans libellé.
La capture et le XML montrent ce conteneur autour de la mire réelle. Le banc
reconnaît strictement cette structure et son aspect 16:9, puis lit ses bounds
à chaque observation ; il ne prétend pas que `SurfaceView` est accessible
sous son nom. Les vues Flutter globales, les conteneurs plein écran et les
candidats ambigus restent refusés. Le contrôle de mouvement et tous les
contrôles FGS, fichier, arrêt, relecture et vidéo restent obligatoires.

La relecture possède un locator distinct : le code de
`TvRecordingPlayerScreen` place le même `NativeVideoView` dans un
`StackFit.expand` et affiche en permanence le titre du canal. Seulement
après l'ouverture depuis Mes enregistrements et l'arrêt vérifié du serveur,
de son thread et de ses processus média, `motion("replay")` accepte un
unique wrapper natif portrait de cette même structure. Le titre CHANNEL
doit être présent dans le XML frais ; les bounds sont ceux du conteneur,
jamais ceux d'une vue Flutter globale. Le direct reste limité au 16:9.
Cette géométrie de relecture reste à observer sur Android. Le calcul de
mouvement centré et la revue humaine de la mire ne changent pas.

Le run `43601114877` atteint la mire, mais sa barre de commandes est masquée
avant l'attente initiale du canal et de REC. Le banc révèle cette barre par
un tap sur le conteneur vidéo observé seulement lorsque les deux libellés
sont absents. Il exige ensuite canal et REC dans le même XML ; l'action REC
emploie directement les bounds de ce vrai bouton, sans deuxième dump. La
barre du lecteur se masque après six secondes. L'attente du canal et de
Stop après le tap REC peut aussi révéler la barre ; elle ne retouche jamais
REC. Le quatrième essai observe le mouvement réel de la mire et envoie le
tap REC, mais ne valide pas Stop ni le démarrage de l'enregistrement.

Le run `43602519391` retourne le XML de REC 6,081 secondes après la
révélation. La vidéo montre la barre en train de descendre au moment du
tap, cohérent avec l'expiration des six secondes. La nouvelle observation
après révélation est immédiate, sans la pause générique d'une seconde.
Avant REC, le XML doit avoir moins de cinq secondes depuis ce tap de
révélation, avec une nouvelle vérification juste avant l'envoi ; la marge
restante est réservée au transport de la commande. Un XML expiré n'autorise
aucun tap REC, et une attente après REC ne retente jamais cette action.

Le diagnostic global précédent perdait l'instant REC sous les messages
audio de l'émulateur. Le PID NOVATUBE est désormais suivi par logcat durant
le scénario ; un fichier séparé indique si ce suivi s'est arrêté trop tôt.
En cas d'échec, l'état brut des services et la liste des fichiers enregistrés
sont aussi conservés. Ces diagnostics ne remplacent aucune preuve requise.

Le run `43603905492` envoie REC 3,582 secondes après la révélation des commandes, observe
Stop et révèle un vrai `RecordingForegroundService` NOVATUBE au premier
plan, notification 1001, type numérique `0x00000001`, avec un fichier TS de
765 912 octets. Le relevé Android 35 nomme ce champ `types=`. Le parseur
accepte désormais ce nom ou `foregroundServiceType=`, sur l'unique ligne
foreground du service identifié, avec un seul champ de type. Seul le type
dataSync exact reste accepté ; mediaPlayback, types combinés, champs
absents/ambigus et notification différente restent refusés. La croissance
en arrière-plan, l'arrêt par notification et la relecture ne sont pas
encore démontrés par cet essai.

Le run `43604691531` échoue avant REC sur une première image quasi noire.
Le XML désigne bien le conteneur `(0,656)-(1079,1263)` ; le crop centré
`647×364` à `(215,777)`, ramené en gris à `64×36`, présente un contraste de
2. Le banc attend désormais au maximum trente secondes un contraste
strictement supérieur à 25 avant le contrôle live. Chaque XML et PNG
`live-readiness-*`, son délai et son contraste restent dans les observations.
Cette préparation n'est pas une preuve de mouvement : les trois nouvelles
images de `motion("live")` et tous leurs seuils restent inchangés. Aucun
nouveau tap REC ni redémarrage de l'app n'est ajouté ; une image toujours
noire ou arrivée après le délai provoque encore l'échec.

Le run `43605556714` confirme la mire animée, REC, Stop, le service dataSync
et un fichier TS de 223 720 octets. Il échoue sur le premier relevé Activity
immédiatement après Home ; le diagnostic final montre ensuite réellement
le launcher Android, NOVATUBE invisible et hors PiP. Le banc attend donc
au maximum quinze secondes après un seul Home, avec le même critère :
une activité resumed doit être observée et aucune ne doit être NOVATUBE.
Chaque relevé `home-activity-*`, son délai et son état sont conservés, même
en cas d'échec. Les huit secondes de mesure du fichier commencent seulement
après ce constat. Le service en arrière-plan, l'arrêt et la relecture restent
obligatoires ; ils n'ont pas encore été atteints dans cet essai.

Le run `43606350793` atteint Home après 1,668 seconde. Le fichier passe de
292 152 à 609 308 octets pendant huit secondes avec dataSync toujours actif.
L'action Arrêter de la notification retire le service et sa notification ;
le TS se stabilise à 1 051 484 octets et ses 25,690944 secondes utiles sont
décodées strictement. Le serveur est arrêté avant la tentative de relecture.
Le retour ouvre bien l'accueil, mais défilé sur RESUME : Series, Server,
Settings et le canal sont visibles dans un unique ScrollView NOVATUBE.
Le banc utilise seulement cette structure observée pour remonter vers les
tuiles hautes, puis exige le recognizer complet initial inchangé avant
d'ouvrir les réglages. Les XML de ce retour sont désormais conservés.
La relecture réelle reste obligatoire et n'est pas encore démontrée.

Le run `43607218714` réalise ensuite tout le parcours, y compris une
relecture animée réelle avec le serveur source arrêté. Le TS est stable à
987 000 octets et ses 24,0456 secondes utiles se décodent strictement. Le
MP4 de 92,029189 secondes se décode intégralement, mais échoue au dernier
contrôle : le marqueur de mouvement en relecture est à 91,334 secondes
dans l'horloge externe, ce qui laisse 0,695 seconde contre la seconde
exigée. La fenêtre video-start→video-stop dure 94,482 secondes ; elle
encadre aussi le démarrage et l'arrêt de screenrecord, contrairement à la
durée du média. Les dernières images du MP4 montrent bien la mire locale.
Le banc garde désormais cinq secondes de relecture après le contrôle de
mouvement au lieu de deux. Les trois nouvelles images, leurs seuils et
l'exigence d'une seconde finale dans `qualify()` restent inchangés. Aucun
MP4 de cet essai n'est promu rétroactivement en preuve qualifiée.

## Média contrôlé

Seule la fixture H.264/AAC versionnée
`recording-test-media/novatube-h264-aac.ts` est utilisée, avec le SHA-256
`81724394c63e0b5294ba57e47c0e2c631ded3c28e0b0589610c768a64c019694`.
Le serveur local écoute sur `127.0.0.1:8765`; Android y accède par `10.0.2.2`.
FFmpeg boucle et remuxe les mêmes octets média à débit réel, sans réencoder
l'application ni contacter un fournisseur de contenu. La fixture est une
mire et une tonalité synthétiques. Les connexions et octets transmis sont
journalisés. Le serveur est arrêté avant la relecture du fichier enregistré.

La capture `screenrecord` est une vraie capture de l'écran, sans audio. Les
PNG de vérification sont bruts ; aucune image de remplacement n'est générée.

Le TS brut est conservé. Son décodage strict porte sur toute la durée, sauf
la dernière seconde : une coupure réseau volontaire peut interrompre la
dernière image TS. Il faut au moins six secondes de contenu décodable, puis
une relecture animée réelle dans l'app avec le serveur source arrêté. Cette
tolérance bornée ne s'applique pas au MP4 de démonstration, qui doit décoder
intégralement. Le rapport donne la durée exacte vérifiée et la seconde exclue.

## Ce qui n'est pas démontré

- `mediaPlayback` : le service garde un relais Cast/DLNA vivant lorsque le
  téléphone alimente un récepteur réel. Aucun récepteur n'est disponible
  dans ce banc. Une simple lecture locale n'est pas présentée comme preuve.
- PiP ou mode Écouteurs : aucun parcours Play correspondant n'est utilisé.
- Conversion/export MP4 sous dataSync : le service est arrêté avant cette
  opération. Après un arrêt par notification, le fichier reste disponible
  dans Mes enregistrements ; aucune conversion automatique n'est prétendue.
- Délai Android de six heures : ce scénario court ne le teste pas.

## Validation et résultats

Tests locaux sans Android :

```bash
python3 -m unittest discover -s android-app/ci/novatube -p test_datasync_evidence.py -v
```

Les tests couvrent refus des mauvaises autorités/provenances, archive
modifiée, chemins ZIP dangereux, mauvais type FGS, éléments hors écran ou
d'une autre application, croissance absente, arrêt incomplet et vidéo tronquée.
Ils ne constituent aucune preuve d'exécution réelle du scénario Android.

Validation historique du 14 novembre 2026 sur l'AAB7 : les vingt-trois tests
passaient. L'archive originale 0.1.7 et son AAB avaient passé leurs empreintes
et la validation de provenance.
Un client HTTP réel a reçu 357 200 octets de mire ; FFprobe a reconnu H.264,
AAC, 160 × 90 et 9,101333 secondes. FFmpeg a décodé strictement les 8,101333
secondes utiles. La fixture n'a pas changé et aucun processus de diffusion
n'est resté actif après l'arrêt du serveur. Ce test de composants n'a pas
ouvert NOVATUBE ni produit une vidéo de son interface.

Les essais jusqu'à REC9 ont observé sur Android le conteneur de relecture,
la notification `expandableNotificationRow`, les libellés après REC, l'accès
ADB au fichier externe et le maintien du portrait 1080 × 1920. La nouvelle
marge finale de cinq secondes reste à exécuter ; toute exécution doit
toujours satisfaire l'ensemble des contrôles, sinon elle produit uniquement
des diagnostics, sans vidéo qualifiée.

Seule une séquence complète crée `datasync-evidence/` avec `datasync-demo.mp4`
et `evidence.json`. Toute observation partielle, y compris un MP4 éventuel,
reste dans `datasync-diagnostic/unqualified-observations/`. Le rapport de
succès exige encore une revue humaine et indique `mediaPlayback` non démontré.
La variation de pixels ne prouve pas à elle seule l'identité visuelle de la
mire. Le rapport exige explicitement la confirmation humaine de la mire
animée en direct, de sa relecture locale et de la lisibilité des actions.
La surface Flutter globale est exclue des surfaces vidéo acceptées.

## Remplacement par l'AAB final suivant

Après validation du prochain AAB, mettre à jour le bloc des six constantes
de provenance, le ref du checkout original, `run-id`, `artifact-ids` et le
nom d'artefact de sortie du YAML. Recalculer `WORKFLOW_SHA256` et
`DATASYNC_JOB_SHA256` (JSON canonique de `jobs.capture_datasync` lu par
`WorkflowLoader`), puis refaire
les tests et la revue. La version affichée dans les preuves provient de la
provenance et du manifeste vérifiés par les helpers de ce nouveau commit.
Ne pas substituer le SHA du script à celui de l'application.

## Chemin de dispatch autorisé

Le nouveau fichier autonome `novatube-datasync-evidence.yml` ne serait pas
déclenchable légitimement tant qu'il n'existe pas sur la branche par défaut.
La lecture GitHub du 14 novembre 2026 a confirmé `default_branch=main`,
l'absence de ce nouveau fichier sur `main` et la présence du workflow
`novatube-play-aab.yml` avec `workflow_dispatch`. Ce workflow est déjà
enregistré sous l'identifiant `414377516` : le run `43597754114` l'utilise
sur `feature/novatube-play-aab`.

Cette variante remplace donc le précédent patch autonome : ne pas appliquer
les deux. Elle ajoute uniquement `capture_datasync` au fichier déjà enregistré
sur la branche NOVATUBE. Aucun nouveau workflow n'est créé sur `main`.

Les deux inputs existants restent des chaînes obligatoires. Après revue et
épinglage du binaire final, sélectionner le workflow NOVATUBE existant dans
Actions, choisir `feature/novatube-play-aab`, saisir
`confirme=CAPTURER_NOVATUBE_DATASYNC` et le SHA complet du script approuvé dans
`reviewed_commit`. Il n'est pas nécessaire de modifier la branche par défaut.

Les trois anciens jobs restent identiques et refusent cette intention :
`release` accepte seulement compilation Play ou publication privée ;
`publish_private` exige la réussite de `release` et l'intention privée ;
`capture_play` exige la réussite de `release` et l'intention de compilation.
Le nouveau job n'a aucune dépendance `needs: release`, ne reçoit aucun secret
de signature, ne compile pas l'app et ne dispose d'aucun droit d'écriture.
Les permissions globales, la concurrence et les événements restent inchangés.

Les tests de workflow supplémentaires refusent l'élargissement d'une ancienne
garde à l'intention REC, toute dépendance au build, toute suppression des
contrôles d'acteur/SHA/branche, un secret de signature, un droit d'écriture,
une recompilation et la promotion de diagnostics en preuve.
Lors de la validation historique REC9, les 28 tests de workflow et les
23 tests du banc passaient ensemble, soit 51 tests ciblés, sur la tête
incluant le diagnostic réseau séparé
`f8467063651072095c2125adca973b7dbd9bbcaf`. La comparaison des objets YAML confirme que les trois
anciens jobs et les permissions globales sont identiques à la base
`6b66f0a8302b0cb34c540bb671a4d6d7fae190c6`.

Ce dossier n'effectue aucun changement distant, aucun commit, aucun dispatch
et aucun envoi à Google Play. Les références actives désignent exclusivement l'AAB8
vérifié du run `43608872429`. Les neuf essais Android cités ci-dessus concernent
l'ancien AAB7. Le run `43597097197` ayant échoué,
ses métadonnées ne servent pas de provenance d'un binaire.

Sources GitHub :

- [Déclenchement manuel et choix de branche](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [Workflow enregistré sur main](https://github.com/manzilionellm-dotcom/tvking/blob/main/.github/workflows/novatube-play-aab.yml)
- [Run du workflow existant sur la branche NOVATUBE](https://github.com/manzilionellm-dotcom/tvking/actions/runs/43597754114)

## Faisabilité du second service, hors de ce banc

`gmrender-resurrect` est un vrai récepteur UPnP utilisant GStreamer ; une
lecture vidéo réelle est possible avec une sortie vidéo et les bons codecs.
Le picker NOVATUBE relu ne propose cependant pas de saisie IP manuelle : il
attend la découverte SSDP. Le relais publie ensuite l'IP locale du téléphone
avec un port dynamique. Un processus Linux hôte ne constitue donc pas à lui
seul un récepteur utilisable depuis le banc actuel : découverte et route
inverse du relais doivent être observées avant de tenter la démonstration.

Android Emulator 36.5 a ajouté un réseau Wi-Fi commun entre émulateurs. Cela
ouvre une autre piste avec un véritable récepteur Android, mais ne prouve pas
le fonctionnement automatique d'un récepteur Linux hôte. Aucun récepteur
factice, aucune réponse SOAP simulée et aucun banc Cast supplémentaire n'ont
été ajoutés. La preuve `mediaPlayback` reste à faire séparément.

Sources techniques :

- [Sortie GStreamer du récepteur](https://github.com/hzeller/gmrender-resurrect/blob/master/src/output_gstreamer.c)
- [Réseau entre émulateurs](https://developer.android.com/studio/run/emulator-networking-interconnect)
- [Adresses et limites du réseau Android Emulator](https://developer.android.com/studio/run/emulator-networking-address)
