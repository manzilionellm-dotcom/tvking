# Studio 3D et chat privé — proposition du 12 octobre 2026

Branche de travail basée sur la campagne de la PR #110. Aucun déploiement et aucun dégel des applications ou du panel.

## Ce qui est construit
- Un éditeur de petites publicités : Orbite, Prisme, Vitrine, trois palettes, image HTTPS facultative, badge et animation de 6/8/10 secondes. Il enregistre une recette déclarative ; il ne génère pas de vidéo 3D ni de modèle libre.
- Un écran propriétaire « Chat privé » avec historique, recherche dans les 100 conversations récentes, pagination des messages, réponses, compteurs et accusés de lecture.
- Les routes indépendantes `/api/support/<identifiant>` et `/api/v1/support`. Aucun ordre, heartbeat, curseur d’activation, source ou canal instantané existant ne passe par elles.

## Confidentialité et fonctionnement
Le téléphone crée un secret aléatoire de 256 bits. Son SHA-256 identifie la conversation ; le secret est exigé dans `X-Support-Token`. Une MAC n’ouvre pas une conversation. La MAC affichée dans le panel est déclarative et ne prouve pas l’identité du client.

Le propriétaire est autorisé via son authentification existante et le rôle `super_admin`. Les employés/revendeurs sont refusés côté serveur. Les messages sont conservés dans D1 ; ce n’est pas du chiffrement de bout en bout. Ils ne sont pas copiés dans l’audit. La perte des données locales du téléphone fait perdre l’accès à son ancien fil. Aucun compte ni récupération interappareils n’est inventé.

Texte brut uniquement, 2 000 caractères, corps HTTP limité à 10 000 octets, 20 nouveaux messages par minute par fil et par émetteur, identifiant d’envoi réutilisé en cas de reprise. Cette limite n’est pas une protection globale contre la création massive de nouveaux fils anonymes. Prévoir une politique de conservation et une limitation Cloudflare par IP avant une ouverture à grande échelle.

Le panel lit le fil ouvert toutes les 3 secondes et la liste toutes les 5 secondes, uniquement quand la page est visible. Les annonces historiques gardent leur réponse ; `creative` est ajouté uniquement aux annonces qui ont un modèle valide. Les anciennes apps continuent à montrer le texte.

## Validation
`node --test android-app/cloudflare/support_chat.test.mjs android-app/cloudflare/campaigns.test.mjs android-app/cloudflare/box_channel.test.mjs` : 31 réussis. Compilation TypeScript/Vite du panel réussie. Le parcours navigateur client → panel → client est ajouté à la suite existante, avec captures desktop/mobile.

L’exécution Wrangler locale est empêchée par `uv_interface_addresses` dans l’environnement de travail. Le workflow `Studio et chat — vérifications` exécute les tests et le parcours dans un runner GitHub, sans secret de production, déploiement ou release. Vérifier son résultat sur le dernier commit avant fusion.

## Activation ultérieure
Relire la PR #110 puis cette extension, vérifier les parcours et l’app mobile associée. Le gel de production et les contrôles existants restent en place. Le déploiement réel utilise uniquement le processus déjà protégé du dépôt.
