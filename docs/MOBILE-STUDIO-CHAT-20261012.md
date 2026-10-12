# 7MOTION — studio, chat et confort mobile

Proposition sur une branche distincte du 12 octobre 2026. Aucun APK client remplacé, aucune publication, aucun dégel.

## Livré dans le code
- Petite bulle de chat sur l’accueil seulement, visage dessiné dans Flutter, badge discret, aucune ouverture automatique, aucun son. Feuille de conversation privée : historique, pagination, envoi/réessai sans doublon, états Envoyé/Lu. Le fil ouvert lit toutes les 3 secondes ; le badge toutes les 60 secondes au premier plan. Pas de notification hors app. Aucun WhatsApp.
- Cartes publicitaires en relief, trois modèles avec animation native finie de 6/8/10 secondes ; aucun HTML ni moteur vidéo. Respect de la réduction des animations et bouton de fermeture. Le texte ancien reste lisible si le modèle est inconnu.
- Adaptateur de téléchargement natif préparé, mais pas raccordé au moteur Cinéma `VodDownloadService` de cette base téléphone. Le moteur existant, sa file sérielle, ses fichiers et sa priorité à la lecture sont conservés. Aucun réglage Wi-Fi sans effet n’est affiché. Ce raccordement est une fonction distincte qui nécessite un essai de la priorité réseau et de la reprise sur téléphone.
- Réglages « Confort mobile » : animations, préparation facultative du guide via Workmanager (Android, six heures au mieux, réseau non limité, batterie suffisante, pas de lancement lorsque l’app est au premier plan).

## Six SDK libres, services facultatifs
Versions explicites documentées dans pubspec.yaml. Les SDK sont du code libre ; l’hébergement et les offres commerciales ne sont pas nécessairement gratuits.

| Brique | Configuration / état |
| --- | --- |
| Background Downloader | SDK 9.6.4 et adaptateur préparés ; moteur Cinéma existant conservé, raccordement natif non livré. |
| Workmanager | Guide désactivé par défaut, activation par le client. Android uniquement. |
| GrowthBook | SDK 4.3.0, compatible avec encrypt/pointycastle 3 existants. `GROWTHBOOK_CLIENT_KEY`, `GROWTHBOOK_HOST` HTTPS. Seul `motion_ads_3d` pilote une animation ; aucun droit/source/ordre. |
| PostHog | `POSTHOG_PROJECT_KEY`, `POSTHOG_HOST` HTTPS. Consentement obligatoire, pas de rejeu de session ni capture automatique ; seulement événements de fonctions autorisées. Aucun chat, lien de lecture, MAC ou identifiant de licence. |
| RevenueCat | `REVENUECAT_PUBLIC_KEY` : adaptateur offres/client/restauration préparé. Aucun achat ni déblocage commercial avant correspondance vérifiée avec les droits existants. Pas encore de parcours d’achat utilisable. |
| LiveKit | SDK 2.5.3 compatible avec le chiffrement mobile existant ; correction ciblée de cinq assertions non-null pour Dart 3.13. Réévaluer la version avant activation du service. `LIVEKIT_INVITATION_ENDPOINT` HTTPS : écran de salon à invitation, micro initialement coupé. Nécessite un serveur d’invitation et LiveKit configurés ; aucun serveur existant présumé. |

Les clés SDK sont publiques et facultatives ; aucun secret serveur dans l’APK. L’endpoint LiveKit doit vérifier une invitation expirante côté serveur et répondre `{ "url": "wss://…", "token": "…" }` avec des droits limités au salon concerné. Sans configuration, les écrans externes restent masqués et les SDK ne s’initialisent pas.

## Chat privé
API distincte de la synchronisation. Secret aléatoire de 256 bits local, empreinte SHA-256 en chemin, secret seulement en en-tête. La suppression des données de l’app perd l’accès à l’ancien fil. MAC affichée dans le panel = indication déclarative, pas preuve d’identité. Serveur D1 accessible au propriétaire via son rôle ; ce n’est pas du chiffrement de bout en bout. Pas de publicité ni de mesure d’usage dans le chat.

Le Worker/panel correspondant doit être déployé par le processus existant avant utilisation. Tant qu’il manque, le chat affiche une indisponibilité et l’accueil reste utilisable.

## Construction et vérification
Le livrable mobile est maintenant `patches/mobile-studio-chat.patch`, appliqué à la vraie base téléphone `37fdf3305c5de9d35e20fd6567df38008fc7a7ee` après Sport et Radio. Le code partagé `android-app/lib`, ses tests et son `pubspec.yaml` sont revenus exactement à la base de PR #112 : aucun SDK mobile n'entre dans une future compilation TV par cette PR.

`android-app/ci/mobile/apply_studio.py` applique le même patch dans le constructeur téléphone protégé et dans la compilation de revue. Il compare les octets de main.dart, des souscriptions, sources, hôtes backend, radios et transports temps réel avant/après. Le patch n'ajoute que le chat, les cartes et les services mobiles. Le guide utilise les alias EPG déjà présents dans la base téléphone, sans recharger les sources.

Le workflow `Studio mobile — compilation Android` analyse et teste cette vraie application téléphone, conserve l'overlay Cast, PiP et les composants de notification, puis construit un APK debug ARM64 distinct `com.sevenmotion.studio.preview`. Il fournit l'APK, son SHA-256 et les versions résolues. Ni clé de production, ni modification d'un canal clients. L'ancienne compilation du code partagé ne constituait pas une preuve de cette base téléphone : consulter la nouvelle exécution avant de conclure.

Après `flutter pub get`, `ci/mobile/prepare_studio_sdk.py` vérifie l’empreinte du fichier officiel LiveKit 2.5.3 et rend cinq assertions non-null explicites dans sa fermeture vidéo. Aucun override de dépendance ni modification du chiffrement historique. Le script refuse toute autre source et accepte une seconde application identique. Les deux constructeurs l’appellent avant compilation.

Le constructeur signé existant reçoit le patch et ses permissions, sous les mêmes conditions, environnement, contrôles de signature et canaux de test qu'avant. Les gardes, manifestes de gel et règles GitHub ne sont pas assouplis. La compilation de revue ne remplace pas cette signature ni un essai physique.

Le contrôle automatique local avait refusé Flutter après une tentative d'accès à une adresse de métadonnées de l'environnement. Aucun contournement : formatage Dart hors ligne seulement ; analyse, tests et compilation sont confiés aux runners GitHub.

## Mise en service
1. Relire puis intégrer PR #110 et #111 selon la procédure protégée du panel. Activer le Worker avant le chat mobile ; comparer la référence autorisée avant/après.
2. Après validation du téléphone, intégrer PR #112 puis utiliser le constructeur signé existant. Vérifier la bulle, un échange client/propriétaire, Lu, la reprise après coupure, les radios et une action instantanée du panel.
3. Publier une version clients uniquement après l'ouverture autorisée et la validation prévues par les protections ; rétablir le gel.

L'essai sur un téléphone physique et le déploiement ne sont pas prouvés par les tests. iOS nécessite sa configuration native. Les services externes du tableau restent facultatifs, non activés sans leurs paramètres ; le chat et le studio n'en ont pas besoin.
