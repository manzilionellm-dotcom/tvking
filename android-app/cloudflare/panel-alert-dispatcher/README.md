# Notifications du propriétaire du panneau

Ce Worker séparé envoie les événements durables créés par le Worker Atlas.
Il ne déclenche pas les anciennes tâches de maintenance et ne possède aucune
route HTTP d'envoi. Le déclenchement prévu est un cron toutes les minutes.

Le propriétaire doit activer les alertes et autoriser les notifications depuis
son téléphone. Une permission accordée au navigateur seule ne constitue pas
un abonnement serveur. La session, le rôle super_admin, les préférences et le
consentement sont relus avant chaque livraison. La déconnexion ou la révocation
de la session interdit les envois suivants.

## Dépendance de transport

@block65/webcrypto-web-push est figée en version 2.0.0. Elle réalise le
chiffrement aes128gcm de RFC 8291 et la signature VAPID de RFC 8292 avec
WebCrypto, sans le mode de compatibilité Node des Workers. Le verrou npm fixe
aussi les dépendances transitives. esbuild ne sert qu'à créer le bundle.

Le test de transport déchiffre le message avec une implémentation WebCrypto
indépendante et vérifie la signature VAPID. Aucun test n'envoie de notification
vers un service réel.

## Configuration

- Liaison D1 DB : base Atlas contenant les tables panel_alert_* et panel_push_*.
- PANEL_PUSH_ENABLED : true pour autoriser le traitement du cron.
- PANEL_PUSH_PUBLIC_KEY : clé publique VAPID, identique à celle du Worker API.
- PANEL_PUSH_PRIVATE_KEY : secret du Worker d'expédition uniquement.
- PANEL_PUSH_SUBJECT : https://atlas-console-k7q2.vercel.app/.

Ne jamais placer la clé privée dans Git, le panneau, le service worker ou l'APK.
Le Worker API ne reçoit que la clé publique.

Les services de push acceptés sont ceux de Chrome/Samsung, Firefox et Apple.
Les destinations utilisent HTTPS ; aucune redirection n'est suivie. Le contenu
visible est succinct et la fiche détaillée est chargée après authentification.

## Livraison et limites

Chaque couple événement/abonnement est unique. Un bail de deux minutes protège
les invocations simultanées. Les erreurs temporaires donnent lieu à au plus six
essais espacés ; les abonnements expirés sont désactivés. Les événements datant
de plus de 24 heures ou antérieurs au consentement ne sont pas envoyés.

Un état sent veut dire « accepté par le service Push », jamais « lu sur le
téléphone ». Le service worker déduplique les éventuels rejeux par event_id.
Un envoi déjà accepté par le service tiers peut arriver après une déconnexion.

La fréquence du cron et le réseau du téléphone influencent le délai réel.
Sur iPhone/iPad, le panneau doit être ajouté à l'écran d'accueil pour Web Push.
Les sessions Atlas actuelles expirent au bout de sept jours ; une nouvelle
connexion et un clic explicite permettent de rattacher cet appareil à nouveau.

## Vérification locale

    npm ci --ignore-scripts
    npm test
    npm run build

Les tests D1/Workerd du pipeline complètent les tests cryptographiques et
vérifient les consentements, sessions, baux et reprises.
