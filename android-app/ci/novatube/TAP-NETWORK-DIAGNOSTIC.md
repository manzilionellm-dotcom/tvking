# Diagnostic réseau Cast NOVATUBE, isolé et non destiné à Play

État : TAP1 a été exécuté le 14 novembre 2026 sur le commit
`02ea2633f8e9de66fb6ab7d74d9f8cc4a63fbd4b`, run `43604492220`. Le diagnostic
s'est arrêté avant le lancement d'Android : l'adresse numérique donnée à
l'écoute ADB n'était pas prise en charge. Le correctif ci-dessous est préparé
localement sur REC6 pour revue ; il n'a pas encore été exécuté en CI.
Aucune vidéo FGS n'est produite.

## Périmètre du job

Le job `diagnose_cast_network` appartient au workflow NOVATUBE déjà enregistré.
Il demande exclusivement `DIAGNOSTIQUER_NOVATUBE_CAST_RESEAU`, un lancement manuel,
le propriétaire comme acteur initial et déclencheur, la branche NOVATUBE et le SHA
complet exactement revu. Il ne dépend d'aucun job de compilation ou publication.
Ses permissions GitHub sont limitées à `contents: read` ; aucun secret de livraison,
aucune archive AAB/APK et aucune commande d'installation d'application ne lui sont transmis.

Les quatre jobs préexistants sont conservés. La seule adaptation du banc REC est
l'empreinte du workflow complet. Son job canonique, son AAB épinglé et tous ses
critères de qualification restent identiques à la base finale fournie par root.

`run_tap_diagnostic.py` contrôle une seconde fois l'événement, le job, le propriétaire,
la branche, le contexte de run, le checkout propre et le SHA. Il vérifie également
l'empreinte du YAML relu. `verify_source.py` vérifie l'empreinte du nouveau job complet,
ce qui ferme ses étapes, arguments, permissions et chemins d'artefacts.

## Préparation avant le namespace

Les actions GitHub sont épinglées par SHA. Java 17 et les outils Android proviennent
des mêmes fournisseurs que le workflow existant. L'action Android utilise explicitement
`accept-android-sdk-licenses: false`, puis sdkmanager est exécuté avec son entrée
fermée. Une licence manquante doit bloquer l'installation ; aucun accord nouveau
n'est validé automatiquement par ce job.

Les outils réseau et les bibliothèques proviennent des dépôts Ubuntu déjà configurés
sur le runner `ubuntu-24.04`, sans ajout de dépôt. Le paquet officiel gmediarender
est téléchargé puis extrait sous `RUNNER_TEMP`, sans installation et sans scripts
de maintenance. Cette distinction évite que ses hooks d'init soient exécutés sur
le réseau hôte. Le paquet et l'exécutable extraits sont vérifiés par SHA-256.

| Élément Ubuntu Noble amd64 | Taille | SHA-256 |
|---|---:|---|
| `gmediarender_0.1-1build3_amd64.deb` | 71 318 octets | `3560d817eaedb453a3fb2dcc69c1388994df9d1658877f4b5523e15cfb2ad395` |
| `usr/bin/gmediarender` extrait | 98 272 octets | `22a18fa5d813e21ad7fdbf5fcf1f172dfdda8f4389a9aa4c15975079e16793f6` |

Les bibliothèques UPnP sont fournies par `libixml11t64` et `libupnp17t64` de Noble.
Le contrôle de l'exécutable est répété dans le probe avant de créer le TAP.

Le moteur attendu est celui observé dans REC3 : Emulator **37.2.13.0**, build
**16740729**. L'image est `system-images;android-35;default;x86_64`. Les métadonnées
Google de référence sont dans `tap-sdk-candidate-pins.json` : ce sont les tailles
et SHA-1 publiés, pas des SHA-256 d'archives mesurés localement. Le diagnostic relève
les empreintes SHA-256 des exécutables réellement présents. Un moteur différent
est refusé avant création du TAP, même si sdkmanager a terminé.

## Isolation et nettoyage

Le contrôleur ouvre un namespace réseau **neuf**, un namespace PID et un namespace
privé pour `/proc`, avec `unshare --net --pid --fork --mount-proc --kill-child=KILL`.
Le processus privilégié reçoit un environnement vide puis une liste fermée de
chemins et variables d'outils ; aucun environnement GitHub ou jeton n'est conservé.

Le probe exige que son namespace réseau diffère de celui de l'appelant et ne
contienne que `lo`. Aucune interface, règle de pare-feu, route ou configuration de
sécurité du réseau hôte n'est modifiée. Tous les fichiers AVD appartiennent à un
répertoire temporaire propre au diagnostic.

La capture PCAP est ouverte par le contrôleur avant de lancer tcpdump avec
`-w -`. Son abandon de privilèges reste actif ; les erreurs sont écrites dans un
fichier séparé pour ne pas corrompre les octets de capture.

Les variables ADB héritées sont retirées. Après validation de l'isolation seulement,
le probe démarre et suit `adb -L tcp:localhost:5037 server nodaemon`. Les clients
conservent `ADB_SERVER_SOCKET=tcp:127.0.0.1:5037`. Le manuel AOSP utilise le nom
`localhost` pour l'écoute ; son implémentation refuse ici l'adresse numérique
`127.0.0.1`, pourtant acceptée pour la connexion des clients. Aucune option `-a`
d'écoute sur toutes les interfaces n'est ajoutée. L'émulateur utilise
la console 5582 et le port invité 5583, dans la plage normalement détectée par ADB.
Ce serveur et tous ses clients restent dans le même namespace. Un indicateur de
propriété initialement faux empêche tout `logcat`, `emu kill` ou `kill-server` avant
que le serveur privé ait réellement été démarré.

La collecte logcat et chaque arrêt sont indépendants. Une erreur de logcat ne doit
pas interrompre les arrêts suivants. Les groupes de processus suivis sont arrêtés
avec des délais bornés, y compris s'ils disparaissent entre TERM et KILL. Le TAP
n'est supprimé que s'il a été créé dans le namespace validé. Les fichiers temporaires
sont retirés après l'arrêt des processus. Le rapport conserve les erreurs éventuelles
de nettoyage et refuse un succès complet s'il en subsiste.

En sortie normale, `finally` assure ce nettoyage. En arrêt forcé du parent unshare,
`--kill-child=KILL` supprime le PID initial et ses descendants : TERM seul n'est pas
présenté comme une garantie d'arrêt de PID1. Le contrôleur et le job ont aussi un
délai maximal. Aucun `pkill`, redémarrage ADB global ou arrêt d'un service hôte n'est utilisé.

## Observations réellement recherchées

1. Un TAP `ntprobe0` sur `192.0.2.0/24` et un DHCP fonctionnent dans le namespace.
2. Le véritable gmediarender/GStreamer s'annonce sous le nom
   **NOVATUBE TAP network diagnostic**. Aucun répondeur SSDP ou SOAP n'est fabriqué.
3. Un AVD Android 35 jetable démarre avec `VirtioWifi,-WiFiPacketStream` et
   `-wifi-tap ntprobe0`. Les données cellulaires de cet AVD sont désactivées pour
   rendre observable la route Wi-Fi attendue.
4. Android émet un véritable M-SEARCH multicast. La réponse du renderer est capturée
   passivement sur le TAP et fournit son URL LOCATION.
5. Android effectue un véritable GET HTTP de cette description UPnP. Son type,
   son nom et son service AVTransport doivent identifier notre renderer réel.
6. Un client HTTP de diagnostic sur l'hôte effectue un véritable GET vers un petit
   endpoint Android. La requête reçue et les octets de réponse sont vérifiés.

Le dernier endpoint est un simple contrôle de route retour, **pas le relais NOVATUBE**.
Le client de ce GET est le contrôleur de diagnostic, **pas GStreamer**. Ce job
n'installe ni ne lance NOVATUBE et ne tente aucun scénario média futur.

Le netcat Toybox d'Android 35 utilise un socket UDP connecté. Il peut donc écarter
les réponses SSDP unicast à une requête multicast. La capture passive évite de
confondre ce comportement avec une panne réseau. Le diagnostic ne prétend jamais
que NOVATUBE a reçu cette réponse ni que son interface a découvert le renderer.

## Résultats et limites

TAP1 a validé les versions et empreintes des outils, créé le namespace et le TAP,
démarré dnsmasq sur cette seule interface, ouvert la capture PCAP et démarré le
vrai renderer jusqu'à `Ready for rendering`. ADB a ensuite refusé son argument
d'écoute avec `listening on specified hostname currently unsupported`.
Le nettoyage ne rapporte aucune erreur. Le PCAP ne contient que son en-tête :
aucun DHCP Android, échange SSDP ou GET entre Android et le renderer n'est prouvé.

Le renderer a aussi signalé deux icônes absentes dans `/usr/share/gmediarender`,
car son paquet est extrait en privé. Il a néanmoins atteint son état prêt ; ces
avertissements ne sont pas la cause observée de l'arrêt TAP1.

L'artefact porte toujours le nom `NOVATUBE-Cast-network-DIAGNOSTIC-NOT-PLAY-…`.
Il contient le contexte de provenance, les versions, les logs, les échanges HTTP,
les réponses SSDP observées et la capture PCAP. Il est conservé également en cas
d'échec, pendant sept jours. Rien n'est envoyé à une release, une fiche Play ou un service tiers.

Les rapports conservent toujours ces indicateurs à faux :

```json
{
  "playEvidence": false,
  "foregroundServiceEvidence": false,
  "novatubeInstalled": false,
  "receiverMediaPlaybackObserved": false,
  "aabModified": false
}
```

Un succès ne prouve que les observations réseau listées. La découverte par
NOVATUBE, son relais, un GET média par le renderer, le décodage effectif et les
critères mediaPlayback demandent une étape séparée et ne font pas partie de ce patch.

## Sources primaires relues

- [Backend QEMU de l'émulateur](https://android.googlesource.com/platform/external/qemu/+/emu-master-dev/android-qemu2-glue/main.cpp) :
  `-wifi-tap` construit le vrai backend `tap,id=virtio-wifi`. Blob observé :
  `ce784d98404839425c58a29efd7f4d727ea66388`.
- [Aide des options TAP](https://android.googlesource.com/platform/external/qemu/+/emu-master-dev/android/emu/cmdline/src/android/help.c) :
  connexion directe et DHCP ; cette option historique est distincte du TAP netsimd expérimental.
- [Manuel AOSP ADB](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md) et
  [serveur ADB au premier plan](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/debugging.md).
- [Écoute des sockets ADB](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/socket_spec.cpp) :
  `socket_spec_listen` et `tcp_host_is_local` expliquent le refus observé dans TAP1
  et l'emploi de `localhost` pour l'écoute, avec les clients sur `127.0.0.1`.
- [Toybox Android 35](https://android.googlesource.com/platform/external/toybox/+/android-15.0.0_r1/toys/net/netcat.c).
- [Manuel tcpdump 4.99.4](https://github.com/the-tcpdump-group/tcpdump/blob/tcpdump-4.99.4/tcpdump.1.in) :
  l'abandon de privilèges peut précéder l'ouverture du fichier de capture.
- [gmrender-resurrect](https://github.com/hzeller/gmrender-resurrect),
  [sortie GStreamer](https://github.com/hzeller/gmrender-resurrect/blob/master/src/output_gstreamer.c) et
  [paquet Ubuntu Noble](https://packages.ubuntu.com/noble/gmediarender).
- [SDK Google](https://dl.google.com/android/repository/repository2-3.xml) et
  [images système Google](https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml).
- [Action Android épinglée](https://github.com/android-actions/setup-android/blob/be39fa834029ff78f1a44aa3bb0819b8fc2bd8fd/action.yml).
- [Namespaces PID Linux](https://man7.org/linux/man-pages/man7/pid_namespaces.7.html) et
  [unshare](https://man7.org/linux/man-pages/man1/unshare.1.html).
