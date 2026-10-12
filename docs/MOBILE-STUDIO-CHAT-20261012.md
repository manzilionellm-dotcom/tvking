# 7MOTION — studio, chat et confort mobile

Proposition sur une branche distincte du 12 octobre 2026. Aucun APK client remplacé, aucune publication, aucun dégel.

## Livré dans le code
- Petite bulle de chat sur l’accueil seulement, visage dessiné dans Flutter, badge discret, aucune ouverture automatique, aucun son. Feuille de conversation privée : historique, pagination, envoi/réessai sans doublon, états Envoyé/Lu. Le fil ouvert lit toutes les 3 secondes ; le badge toutes les 60 secondes au premier plan. Pas de notification hors app. Aucun WhatsApp.
- Cartes publicitaires en relief, trois modèles avec animation native finie de 6/8/10 secondes ; aucun HTML ni moteur vidéo. Respect de la réduction des animations et bouton de fermeture. Le texte ancien reste lisible si le modèle est inconnu.
- Téléchargements natifs via background_downloader (Android/iOS), reprise et progression persistées. Les fichiers partiels antérieurs gardent leur moteur historique. Un serveur doit accepter la reprise ; Android/iOS décident de l’exécution en arrière-plan. Validation physique encore nécessaire.
- Réglages « Confort mobile » : Wi-Fi pour les nouveaux téléchargements, animations, préparation facultative du guide via Workmanager (Android, six heures au mieux, réseau non limité, batterie suffisante, pas de lancement lorsque l’app est au premier plan).

## Six SDK libres, services facultatifs
Versions explicites documentées dans pubspec.yaml. Les SDK sont du code libre ; l’hébergement et les offres commerciales ne sont pas nécessairement gratuits.

| Brique | Configuration / état |
| --- | --- |
| Background Downloader | Moteur de téléchargement ajouté ; nécessite les permissions de construction mobile. |
| Workmanager | Guide désactivé par défaut, activation par le client. Android uniquement. |
| GrowthBook | `GROWTHBOOK_CLIENT_KEY`, `GROWTHBOOK_HOST` HTTPS. Seul `motion_ads_3d` pilote une animation ; aucun droit/source/ordre. |
| PostHog | `POSTHOG_PROJECT_KEY`, `POSTHOG_HOST` HTTPS. Consentement obligatoire, pas de rejeu de session ni capture automatique ; seulement événements de fonctions autorisées. Aucun chat, lien de lecture, MAC ou identifiant de licence. |
| RevenueCat | `REVENUECAT_PUBLIC_KEY` : adaptateur offres/client/restauration préparé. Aucun achat ni déblocage commercial avant correspondance vérifiée avec les droits existants. Pas encore de parcours d’achat utilisable. |
| LiveKit | `LIVEKIT_INVITATION_ENDPOINT` HTTPS : écran de salon à invitation, micro initialement coupé. Nécessite un serveur d’invitation et LiveKit configurés ; aucun serveur existant présumé. |

Les clés SDK sont publiques et facultatives ; aucun secret serveur dans l’APK. L’endpoint LiveKit doit vérifier une invitation expirante côté serveur et répondre `{ "url": "wss://…", "token": "…" }` avec des droits limités au salon concerné. Sans configuration, les écrans externes restent masqués et les SDK ne s’initialisent pas.

## Chat privé
API distincte de la synchronisation. Secret aléatoire de 256 bits local, empreinte SHA-256 en chemin, secret seulement en en-tête. La suppression des données de l’app perd l’accès à l’ancien fil. MAC affichée dans le panel = indication déclarative, pas preuve d’identité. Serveur D1 accessible au propriétaire via son rôle ; ce n’est pas du chiffrement de bout en bout. Pas de publicité ni de mesure d’usage dans le chat.

Le Worker/panel correspondant doit être déployé par le processus existant avant utilisation. Tant qu’il manque, le chat affiche une indisponibilité et l’accueil reste utilisable.

## Construction et vérification
Les fichiers du canal instantané, des ordres, des accusés d’activation et de récupération des sources restent inchangés. Ajouts UI sur l’accueil et les réglages seulement ; les dépendances doivent toutefois être validées dans un APK, elles ne sont pas sans impact binaire.

Le contrôle automatique local a refusé Flutter après une tentative d’accès à une adresse de métadonnées de l’environnement. Aucun contournement. Syntaxe formatée hors ligne ; tests Flutter et analyse confiés au workflow existant `Quality Zuno` sur la branche de proposition. Lire le résultat du dernier commit avant de déclarer la compilation validée. Le workflow `Studio mobile — compilation Android` construit un APK debug au nom de paquet distinct `com.sevenmotion.studio.preview`, sans secrets ni publication.

Le script `android-app/ci/mobile/prepare_studio.py` complète seulement un projet Android mobile généré (permissions de téléchargement et micro facultatif). Ne pas l’appliquer à la box. iOS nécessite encore sa configuration native et une validation sur appareil. La mise en production et un parcours d’achat complet restent hors de cette proposition.
