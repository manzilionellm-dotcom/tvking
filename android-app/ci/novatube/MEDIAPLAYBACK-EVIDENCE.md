# Preuve Cast mediaPlayback et arrêt depuis la notification

Le job manuel `capture_mediaplayback` demande l'intention
`CAPTURER_NOVATUBE_MEDIAPLAYBACK` et le SHA complet relu de la branche NOVATUBE.
Il reprend exclusivement l'archive AAB immuable épinglée dans le contrôleur et
le workflow. Il ne compile pas l'application et n'utilise aucune clé de
livraison. L'APK d'émulateur est une conversion dont
les Dex et bibliothèques exécutées sont comparés à l'AAB d'origine.

Ce scénario utilise NOVATUBE **0.1.8 (8)**, dont l'AAB signé a été vérifié
localement le 14 novembre 2026 : commit `1610073a902acb922d1ea1bc394eebef2273efb3`,
run `43608872429`, tentative `1`, artefact `14120095100`.

| Élément immuable | Valeur vérifiée |
| --- | --- |
| Nom d'artefact | `NOVATUBE-0.1.8-8-verified-1610073a902acb922d1ea1bc394eebef2273efb3-1` |
| Archive ZIP | 96 493 953 octets ; SHA-256 `5bfaa2a6e74e3594ea7bb377e038b266e7b2014c8c5dbc66c407273231f598ee` |
| AAB | 97 127 777 octets ; SHA-256 `4de381b8bcc7898bf96d038945f4b2047586aad08cd990630404d345c7cceb60` |
| Certificat d'upload | SHA-256 `38d6dabe9a73e5ab94a56491e4da6638f5da09ef1eaa77d0eb892d5f0478824b` |

La signature stricte, le manifeste et la provenance ont été vérifiés. Les
608 tests Flutter, 10 tests Cast JVM et 42 tests d'enregistrement JVM passent
dans le build. Les premiers essais Android restent des diagnostics :
le second découvre le vrai renderer et atteint son relais, mais Rygel refuse
le MIME MPEG-TS avant décodage. Le troisième révèle une configuration AAC
incomplète dans le MP4, refusée par ExoPlayer avant le Cast. Le contrôle
d'arrêt par notification reste donc à observer réellement. Les corrections
ciblées passent 17 tests Python.
Les trois contrôleurs vérifient les mêmes octets de workflow ; les empreintes
des deux jobs vidéo sont recalculées sans changement de leurs gardes.
Le runtime charge le scénario du banc avant les helpers du binaire : leur
second checkout contient déjà un ancien scénario, qui ne doit pas remplacer
celui approuvé pour la preuve. Une régression dans un processus Python neuf
vérifie cette séparation sans ouvrir Android.

## Parcours exigé pour la qualification

Android 35 et Rygel Playbin 0.42.5 sont placés dans un réseau TAP neuf. Le
renderer officiel est extrait sans scripts de maintenance ; ses données sont
montées en lecture seule dans un espace de montages privé. Les empreintes
officielles sont dans `rygel-official-pins.json`. ADB, X11 et le bus de session
sont privés. Le job refuse toute nouvelle acceptation interactive de licence.

La mire H.264/AAC existante, dont l'empreinte reste vérifiée, est remuxée sans
transcodage en vrai MP4 fragmenté continu. Rygel Playbin0.42.5 annonce une
liste statique incluant `video/mp4` mais pas `video/mp2t` : aucun plugin ou
MIME fictif ne remplace ce choix. Le serveur utilise `/vod/pattern.mp4`, le
vrai type `video/mp4` et ne promet aucun Range. L'échantillon de contrôle du
même muxer est entièrement décodé ; sa provenance et son empreinte restent
dans les diagnostics. Le démultiplexeur officiel `qtdemux` est vérifié.
Le muxer utilise `delay_moov`, disponible dans FFmpeg6.1 : l'en-tête initial
attend les informations des premiers paquets. Avant d'ouvrir le serveur, le
banc exige l'AudioSpecificConfig réelle `1188` (deux octets), le profil AAC-LC,
48 000 Hz et un canal. Cette garde refuse le MP4 de média3 même lorsque FFmpeg
parvient à le décoder. Les deux pistes restent copiées sans transcodage.

Ce flux est servi sur le loopback hôte 8765, puis rendu accessible à Android
par `adb reverse tcp:18765 tcp:8765`. Aucun service ne
répond sur le port 18765 du renderer. L'application doit donc observer les
échecs directs réels avant son propre repli vers son relais Android. Le banc
ne modifie ni réponses SOAP/SSDP, ni cache Cast, ni état de l'application.
Ses seules requêtes de contrôle UPnP sont des lectures d'URI et d'état.
La capture passive exige le vrai `SetAVTransportURI` envoyé par Android,
le refus HTTP500/UPnP716 correspondant et le SYN/RST loopback survenu pendant
cet échange. Le journal Rygel et un relevé STOPPED doivent les corroborer.
Cette validation HEAD précède l'installation de l'URI dans Playbin : une URI
vide est conservée comme telle, sans inventer d'erreur GStreamer.

Dans l'AAB8, l'import M3U conserve cette entrée dans Live, même pour `.mp4`.
La feuille Cast reste ouverte après la sélection : elle doit montrer le vrai
nom, `castConnected` et son bouton `castStop`. Cela ne prouve pas la lecture ;
les contrôles média et FGS suivants restent tous indispensables.

La qualification exige la sélection du nom réellement annoncé dans l'UI, le
service `PlaybackForegroundService` type 2 et notification 1002, une requête
GET 200/206 appartenant au PID Rygel vers le relais Android `.mp4`, des octets TCP
uniques qui progressent, et des images décodées animées sous Xvfb. Les octets
TCP du corps HTTP peuvent inclure le découpage HTTP ; ils ne sont pas présentés
comme un décompte exact d'échantillons vidéo. Le son est réellement décodé en PCM,
sans prétendre démontrer un haut-parleur physique.

Après Home, le service, le flux et les images doivent continuer au moins huit
secondes. Le téléphone reste ensuite en arrière-plan. Le banc ouvre le volet
SystemUI et reconnaît l'unique ligne NOVATUBE portant le titre de la chaîne et
le texte traduit `castConnected` suivi du vrai nom du renderer. Les lectures
Android `cmd notification list/get` doivent confirmer le même contenu, le
package, l'id 1002, le canal `cast_playback_channel` et l'action traduite
`castStopTooltip`. Aucune commande ne déclenche le PendingIntent.

Si nécessaire, seul le bouton d'expansion observé dans cette ligne est touché.
Le banc relit ensuite l'UI et touche le bouton `android:id/action0` activé de
cette notification. Il enregistre le geste « user-cast-notification-stop »,
l'identité native et les images avant/après ; il ne revient pas dans l'app.
Le service et la notification doivent disparaître, le renderer et sa connexion
doivent s'arrêter, et l'ancien jeton relais doit répondre HTTP 404. L'activité
doit rester en arrière-plan après l'arrêt. Des GET de reprise locale distincts
ne remplacent ni n'invalident la vérification de cet ancien relais.

Les deux vidéos Android/Xvfb sont entièrement décodées avant qualification.
Seules les sorties qualifiées vont dans `mediaplayback-evidence`. Tous les
relevés XML, PCAP, images, logs et résultats restent séparément dans l'artefact
`DIAGNOSTIC-NOT-PLAY`, y compris lors d'un échec. Une revue humaine des vidéos
reste nécessaire avant toute utilisation dans Google Play ; ce job ne publie
rien et ne soumet aucun formulaire Google.

Sources du renderer :

- <https://archive.ubuntu.com/ubuntu/pool/main/r/rygel/rygel_0.42.5.orig.tar.xz>
- <https://packages.ubuntu.com/noble/rygel>
- <https://packages.ubuntu.com/noble/rygel-playbin>
- <https://docs.kernel.org/filesystems/overlayfs.html>
- <https://dbus.freedesktop.org/doc/dbus-run-session.1.html>
- <https://ffmpeg.org/ffmpeg-formats.html#Fragmentation>
- <https://ffmpeg.org/doxygen/6.1/movenc_8c_source.html>
- <https://gstreamer.freedesktop.org/documentation/isomp4/qtdemux.html>

Formats de lecture Android 15 utilisés pour identifier la notification :

- <https://github.com/aosp-mirror/platform_frameworks_base/blob/android15-release/services/core/java/com/android/server/notification/NotificationShellCmd.java>
- <https://github.com/aosp-mirror/platform_frameworks_base/blob/android15-release/services/core/java/com/android/server/notification/NotificationRecord.java>
- <https://github.com/aosp-mirror/platform_frameworks_base/blob/android15-release/core/java/android/service/notification/StatusBarNotification.java>
- <https://github.com/aosp-mirror/platform_frameworks_base/blob/android15-release/core/java/android/app/NotificationChannel.java>
