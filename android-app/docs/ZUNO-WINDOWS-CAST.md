# ZUNO Windows — Cast réutilisé de 7 MOTION

Le point d'entrée reste `main_windows.dart` → `bootstrapZunoTv` : les écrans,
le catalogue, la MAC, les listes et la licence sont ceux de ZUNO. Le bouton Cast
est ajouté aux lecteurs du direct et de la VOD sur Windows uniquement.

## Utilisation

1. Installer ZUNO sur un PC Windows 10/11 64 bits et ajouter sa propre liste.
2. Connecter le PC et la TV au même réseau privé, par Wi-Fi ou Ethernet.
3. Activer le récepteur DLNA de la TV ou le contrôle réseau de Roku.
4. Lancer une vidéo dans ZUNO, cliquer sur Cast, puis choisir la TV.
5. Pause/reprise et Stop se trouvent dans la barre Cast. Stop revient au PC.
   Les pistes audio et le déplacement dans la vidéo se règlent sur la TV.

La lecture locale est fermée avant l'envoi : pause seule garderait parfois une
deuxième connexion ouverte chez le fournisseur. Annuler le sélecteur revient
au PC et invalide toute connexion Cast encore en attente. Le retour d'une VOD
sur le PC reprend à la position locale précédant le Cast ; la progression de
lecture sur la TV n'est pas synchronisée dans cette version.

## Réutilisation du moteur

Les transports DLNA/Roku, SSDP, les sondes de flux, le relais HTTP/HLS,
le remuxage MPEG-TS/fMP4, les stratégies de repli et les protections contre les
réponses tardives proviennent de la branche 7 MOTION corrigée le 19 octobre
2026 (PR 129). Leurs tests de réseau et de concurrence sont repris.

Adaptations propres à ZUNO : le catalogue fournit directement l'URL de lecture,
sans importer la table de préférences Xtream spécifique à 7 MOTION ; le relais
PC n'appelle pas le service Android de notification. L'ouverture et la fermeture
du lecteur local libmpv passent par une file qui invalide les anciens zaps.

## Limites vérifiées dans le code

- DLNA et Roku : transports réseau disponibles sur Windows, à valider sur chaque
  modèle réel de TV. Aucune compatibilité universelle n'est revendiquée.
- Google Cast : le transport existant utilise un pont natif Android. Les
  récepteurs uniquement Google Cast sont donc masqués sur Windows. Aucun
  remplacement expérimental du moteur n'est ajouté.
- Pas d'AirPlay, de transcodage, ni d'envoi de fichiers VOD locaux dans cette
  version. Les codecs doivent être acceptés par la TV.
- Le PC doit rester allumé et connecté lorsqu'il sert de relais. Aucun réglage
  système de pare-feu ou d'alimentation n'est changé automatiquement.
- La barre de temps et les pistes locales sont masquées pendant une VOD Cast
  pour ne pas faire croire qu'elles commandent le récepteur.

## Validation et distribution

La CI exécute l'analyse Dart, les tests Cast et la file de lecture, puis construit
l'installateur et le ZIP sur Windows. Le build est distinct de la publication.
Les protections `zuno-app-production` et `.github/app-production.json` restent
en place : un artefact de CI n'est pas une mise à jour client publiée.

Avant une diffusion client, il reste à vérifier sur un PC et une TV : découverte,
M3U/Xtream direct et VOD, pause/reprise, Stop, annulation pendant une connexion,
retour PC, perte réseau et fermeture de ZUNO. Aucun résultat de test matériel
n'est déduit de la réussite de la compilation. Le workflow actuel ne dispose pas
d'une signature Authenticode de l'éditeur.
