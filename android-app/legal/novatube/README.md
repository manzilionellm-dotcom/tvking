# Politique de confidentialité NOVATUBE

La politique décrit la distribution Google Play de `com.sevenmotion.novatube`.

- Français : https://novatube-legal.manzilionel-lm.workers.dev/privacy/fr
- English : https://novatube-legal.manzilionel-lm.workers.dev/privacy/en
- URL de la Console : https://novatube-legal.manzilionel-lm.workers.dev/privacy

`privacy.fr.md` et `privacy.en.md` sont les sources éditoriales. Les fichiers HTML correspondants sont intégrés dans `worker.mjs`. Toute modification doit conserver ces trois représentations synchronisées.

Le Worker Cloudflare `novatube-legal` est indépendant du serveur de diffusion et ne possède aucun binding de base de données, secret, formulaire, cookie ou appel réseau sortant. La configuration de déploiement est dans `cloudflare_upload_metadata.json`. Les logs applicatifs se limitent à une catégorie de page et un statut ; l'échantillonnage des logs et des traces est de 1 %, les logs d'invocation sont désactivés et les paramètres de requête sont masqués dans les traces de la plateforme.

Déploiement initial : 14 novembre 2026. Les deux pages publiques ont été ouvertes et vérifiées. La rétention actuelle du relais partagé est décrite telle qu'elle existe ; aucune purge ni nouvelle durée de conservation n'a été appliquée par ce changement.

Le lien des réglages est réservé à la distribution Play et masqué lorsque `NOVATUBE_PRIVATE_APK=true`.
