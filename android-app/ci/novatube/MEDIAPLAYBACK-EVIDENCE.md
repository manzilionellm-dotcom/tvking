# Preuve Cast mediaPlayback depuis l'AAB7 immuable

Le job manuel `capture_mediaplayback` demande l'intention
`CAPTURER_NOVATUBE_MEDIAPLAYBACK` et le SHA complet relu de la branche NOVATUBE.
Il reprend exclusivement l'artefact `14115570586` du run `43597754114`, commit
`6b66f0a8302b0cb34c540bb671a4d6d7fae190c6`. Il ne compile pas l'application et
n'utilise aucune clé de livraison. L'APK d'émulateur est une conversion dont
les Dex et bibliothèques exécutées sont comparés à l'AAB d'origine.

## Parcours réellement observé

Android 35 et Rygel Playbin 0.42.5 sont placés dans un réseau TAP neuf. Le
renderer officiel est extrait sans scripts de maintenance ; ses données sont
montées en lecture seule dans un espace de montages privé. Les empreintes
officielles sont dans `rygel-official-pins.json`. ADB, X11 et le bus de session
sont privés. Le job refuse toute nouvelle acceptation interactive de licence.

La mire H.264/AAC existante est servie sur le loopback hôte 8765, puis rendue
accessible à Android par `adb reverse tcp:18765 tcp:8765`. Aucun service ne
répond sur le port 18765 du renderer. L'application doit donc observer les
échecs directs réels avant son propre repli vers son relais Android. Le banc
ne modifie ni réponses SOAP/SSDP, ni cache Cast, ni état de l'application.
Ses seules requêtes de contrôle UPnP sont des lectures d'URI et d'état.

La qualification exige la sélection du nom réellement annoncé dans l'UI, le
service `PlaybackForegroundService` type 2 et notification 1002, une requête
GET 200/206 appartenant au PID Rygel vers le relais Android, des octets TCP
uniques qui progressent, et des images décodées animées sous Xvfb. Les octets
TCP du corps HTTP peuvent inclure le découpage HTTP ; ils ne sont pas présentés
comme un décompte exact de paquets MPEG-TS. Le son est réellement décodé en PCM,
sans prétendre démontrer un haut-parleur physique.

Après Home, le service, le flux et les images doivent continuer au moins huit
secondes. Le retour dans l'app puis son bouton « Stop casting » doivent retirer
le service et la notification, arrêter réellement le renderer et sa connexion,
et rendre l'ancien jeton relais introuvable (HTTP 404). Le bouton de notification
« Arrêter » n'est pas utilisé : dans cet AAB7 il ne coupe que le service natif.

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
