# Atlas : temps réel et sécurité — revue avant mise en production

## Périmètre et provenance

Branche issue de `origin/release/atlas-console-20261029` (`8bf5390`), cible de la future PR brouillon. `main` est en retard : réconciliation ultérieure, sans modification de `main` ici. Travail local uniquement : aucune fusion, aucun déploiement, aucun changement de compte réel, aucun achat.

## Fonctionnement instantané

* Origine unique Flutter : `API_BASE` (`--dart-define=API_BASE=...`), défaut `https://seven-motion-backend.manzilionel-lm.workers.dev`.
* Installation : clé aléatoire en stockage sécurisé, jamais une clé admin. Heartbeat/statut signe un jeton HMAC lié à MAC + appareil + licence, valable une heure. Une MAC seule ne reçoit pas de jeton.
* Installation existante : preuve de l’Android ID déjà enregistré puis épinglage de la clé d’installation ; l’ID enregistré n’est plus remplacé par un heartbeat public. C’est une migration **TOFU**, pas une attestation matérielle. Les appareils historiques sans identité fiable et les clés perdues nécessitent une procédure d’enrôlement revue par l’owner. Les anciennes routes HTTP/WS historiques restent compatibles et ne sont pas rendues sûres rétroactivement.
* Jeton -> ticket opaque à usage unique (60 s) -> WebSocket du `RealtimeHub` existant, singleton `devices-v1`. Aucun JWT dans l’URL. Événements `{v,type,mac?,version,at}`, sans playlist, identifiant de serveur ni secret.
* Après commit réussi, invalidation globale ou ciblée MAC ; aucun événement après échec. Re-fetch ciblé, boucle dirty anti-perte d’événement, état poussé aux notifiers/streams UI.
* Heartbeat 15 s, détection socket mort 35 s, reconnexion exponentielle 1–30 s + jitter, relecture complète à chaque reconnexion et reprise de l’app. Repli 30 s uniquement socket indisponible. Les anciens sondages activation et source 24 h / 2 s sont supprimés.
* API : `Cache-Control: no-store`, requêtes Flutter anti-cache. Le dernier état local reste utilisable hors réseau.

**Latence : cible <1 s pour l’invalidation + petite ressource sur réseau sain, non mesurée sur appareil.** Import/parse d’une playlist, réseau lent, app suspendue et reconnexion peuvent dépasser ce délai. Aucun engagement sub-seconde démontré. Aucun APK publié ici ; les anciens builds ne gagnent pas le nouveau socket sans mise à jour.

## Matrice ressources

| Ressource | Diffusion / refresh | Surface UI |
| --- | --- | --- |
| Listes ajout/suppression | MAC, `/api/device-source/:mac` | Stream playlists immédiat ; suppression des listes panel, conservation des listes personnelles hors reset explicite |
| Activation / licence | MAC ou invalidation globale pour opérations multi-MAC | État abonnement et gate ; relecture sources lors activation/transfert/reset |
| Pub démarrage / vidéo | Globale, `/api/ad` | Gate mobile/TV global ; désactivation retire la vidéo ; fréquence existante respectée |
| Annonces | Globale, `/api/announcement` | Bandeau mobile/accueil TV, retrait compris ; pas une notification OS garantie en arrière-plan |
| Thème | Globale, `/api/theme` | Nom distant (mobile/titre TV), accent et fond clair/sombre ; tokens surfaces/texte/bordures mobile et TV, cache par plateforme, rebuild sans remount |
| Home layout | Globale, `/api/home-layout` | Rendu commun dans SimpleHome et le nouvel accueil TV ; ordre, visibilité, ruban, mise en avant, favoris/récents et cinéma/séries |
| Featured | Globale, `/api/featured` | Héros piloté dans SimpleHome et accueil TV ; changement/retrait immédiats, aucun raccourci adulte, lecteur TV natif |
| Version / mise à jour forcée | Globale, `/api/app-version` | Gate global mobile/TV ; règles existantes Play-build/build local conservées |
| Serveurs | Globale, `/api/servers` | Sélecteurs mobile/TV abonnés au notifier |

La palette dérive ses tokens du fond clair/sombre et de l’accent existants du panel ; pas de nouvelle API de réglage arbitraire token par token. Les couleurs sémantiques (erreur/live/succès) restent dédiées. La recette sur matériel physique et la mesure de latence restent requises.

## Comptes, sessions, 2FA et revendeurs

* Login : compteur D1 atomique persistant, IP + identifiant haché, 5 tentatives / 10 min ; plafond IP 30 / 10 min. Succès réinitialise le compteur identité. Derrière le proxy Vercel, vérifier en recette que l’IP observée correspond au scénario attendu ; ne jamais faire confiance à un X-Forwarded-For non authentifié.
* Accès JWT 15 min, session serveur révocable, refresh opaque hashé et tournant via cookie `__Host-`, Secure/HttpOnly/SameSite=Strict. Déconnexion individuelle/toutes sessions ; les sockets panel vérifient session/expiration. Les anciens JWT HTTP sans session restent valables au plus jusqu’à leur expiration historique (7 j) ou changement du mot de passe ; nouvelle connexion requise pour les tickets panel.
* Mon compte : mot de passe courant requis, nouveau >=12 caractères, majuscule/minuscule/chiffre, PBKDF2-SHA256 existant avec sel ; autres sessions révoquées. Le secours maître implicite est **désactivé par défaut** (`ADMIN_MASTER_RECOVERY_ENABLED=0`).
* Google Authenticator : TOTP SHA1/30 s/6 chiffres, QR généré localement, activation confirmée, anti-rejeu, clé AES-GCM, 10 codes de secours hashés et à usage unique ; désactivation exige mot de passe + code. Off par compte par défaut. Ne jamais perdre la clé de chiffrement.
* Owner : création de revendeurs actifs/suspendus, crédits existants, reset mot de passe, suspension, limites (nombre de licences actuellement actives, plans/durées autorisés, expiration, sous-revendeurs 0 par défaut), suppression confirmée uniquement si compte vide sans historique ; sinon suspension.
* Contraintes SQL atomiques couvrent aussi les écritures de licences hors `/activate`. Autorisation serveur et cloisonnement aux clients/appareils du revendeur. Les rôles admin/support deviennent lecture seule hors sécurité de leur propre compte.
* Audit des écritures, sessions et échecs login : acteur, action, cible, date/IP ; pas de corps sensible ajouté au journal. CORS exact Atlas, CSP, HSTS, DENY, Referrer-Policy et Permissions-Policy.

**Avant toute mise en production : faire tourner les identifiants admin par défaut, sans jamais les publier.** Fournir une clé de chiffrement dédiée forte avant le premier enrôlement 2FA. Ceci est un durcissement et une première couverture de tests, pas un audit de sécurité exhaustif de toutes les routes historiques.

## Préparation d’exploitation (non appliquée)

1. Sauvegarder D1 et vérifier les migrations existantes, particulièrement `003_reseller_hierarchy.sql`.
2. Revoir puis appliquer `010_device_session_keys.sql`, `011_account_security.sql`, `012_reseller_limits.sql` dans la procédure de release autorisée. Le runtime crée également ces nouvelles tables de façon idempotente.
3. Configurer les bindings secrets **sans valeurs dans Git** : `DEVICE_TOKEN_SECRET` (>=32 caractères aléatoires), `ACCOUNT_ENCRYPTION_KEY` (>=32 caractères, stable). Repli TOTP : `ADMIN_SECRET` seulement s’il est suffisamment fort. Variables : `PANEL_ORIGINS`, allowlist exacte ; pas de wildcard. `RT_HUB` existe déjà.
4. Recette via le même proxy `/api` que le panel. Toute origine de preview doit être explicitement autorisée ; ne pas ouvrir CORS à `*`.
5. Compiler/signer la nouvelle app avec l’identité Android de production, vérifier le stockage sécurisé et l’enrôlement, puis mesurer sur appareils réels avant déploiement.

## Recette manuelle requise

Deux appareils/MAC A et B + owner et deux revendeurs. Ajouter puis supprimer une liste sur A : seule A change ; listes personnelles conservées. Changer chaque ressource globale : observer chaque surface supportée. Désactiver une pub pendant sa lecture. Bannir/réactiver A. Changer version minimale ; tester annulation et reprise. Couper réseau/reprendre l’app : reconnexion, resync, repli uniquement hors socket. Tester jetons falsifiés/expirés et ticket réutilisé. Vérifier isolation A/B et refus de crédits/quotas/plans dépassés, suspension, reset mot de passe, ancien refresh, TOTP/rejeu/secours, logout-all. Vérifier D-pad et absence de lecture audio concurrente lors des contrôles globaux.

## Tests automatisés

Résultats locaux : Worker **43 tests OK**, WebSocket workerd réel **1 OK** (ticket unique + ciblage/global), panel **197 tests OK** (74 + 28 lifecycle + 85 MAC/UI + 10 livraison), build panel et build Worker dry-run OK ; Flutter **120 tests OK** (dont 4 nouveaux thème/accueil), analyse **0 erreur / 11 warnings / 51 infos**. SDK Flutter installé sur la box : 3.47.9. Les lints restants n’ont pas été masqués dans le dépôt.

Commandes :

```
cd android-app/cloudflare
npm ci
npm test
WRANGLER_SEND_METRICS=false npm run test:realtime  # build --dry-run puis vrai workerd local
cd ../admin-panel
npm ci && npm test && npm run build
cd ..
flutter pub get
flutter test
flutter analyze
```

Audit npm runtime panel : patch compatible **react-router-dom 6.30.4 → 6.30.6**, router 1.23.3 → 1.23.4. Les **2 alertes modérées subsistent** ; npm propose 7.18.5 (majeure), aucun correctif 6.x suffisant. Pas de migration majeure à l’aveugle. À traiter avant promotion après analyse du chemin exploitable.

`flutter analyze` a encore des warnings/lints dans le code existant ; ne pas présenter cette commande comme entièrement verte. Aucun test bout en bout sur réseau et matériel de production exécuté.

## Liens conservés et Vercel

Téléchargements connus conservés, faute de remplacement vérifié : `https://app.7themotion.com/vip` (Downloader 7988141), `https://app.7themotion.com/tv` (6248618), y compris le lien de téléchargement Flutter. Aucune API Flutter ne pointe encore vers cet ancien hôte. Les pages légales déjà servies par le Worker suivent la nouvelle origine.

Erreur preview Vercel signalée : Root Directory `android-app/admin-panel` absente sur la branche `gh-pages`. Proposition seulement, **non appliquée** : Ignored Build Step qui retourne 0 pour `gh-pages`, 1 sinon, par exemple `if [ "$VERCEL_GIT_COMMIT_REF" = "gh-pages" ]; then exit 0; else exit 1; fi`. Ne pas changer la production pour corriger une branche de publication d’artefacts.

## Complément Phase A et publication

Les contextes Flutter utilisés après await sont maintenant vérifiés (activation, cast, biométrie, enregistrements, PIN TV) ; 10 assertions null inutiles XMLTV supprimées. Les const réellement stables sont conservés après conversion des tokens dynamiques.

Runbook de mise en production et rollback : [GO_LIVE_ATLAS_REALTIME.md](GO_LIVE_ATLAS_REALTIME.md), également `/workspace/atlas-realtime-reference/GO_LIVE.md` sur la box. Aucune production, migration distante, génération de secret, signature ou publication Play exécutée. Blocage Play important : Gradle release utilise encore la clé **debug** et le package exemple ; confirmer identité Play et chaîne de signature avant tout AAB.
