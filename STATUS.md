# 7 MOTION — État du projet et mémoire persistante

> Ce fichier est ma mémoire entre les sessions Claude. Quand tu
> ouvres une nouvelle conversation, dis-moi simplement
> **"lis STATUS.md et continue"** et je reprendrai exactement
> là où on s'est arrêtés.

---

## Qui je suis (toi, Lionel)

- Fournisseur et revendeur IPTV qui veut son propre lecteur premium
- Domaine : **7themotion.com** (acheté chez Hostinger, géré par Cloudflare)
- Repo GitHub : `manzilionellm-dotcom/tvking` (branche `claude/premium-iptv-redesign-xYNVd`)
- Mon support officiel = numéro WhatsApp `+44 7307 410512` MAIS jamais nommé
  "WhatsApp" dans l'UI — branding "Concierge / Support" uniquement

---

## Identité des produits

Deux apps dans le MÊME repo (flavors Flutter) :

### 7 MOTION (flavor principal, grand public)
- **Tagline** : "THE FEW · NOT FOR EVERYONE"
- **Branding** : Maison Noir — fond charbon `#0A0A0C`, accent ember
  rouge `#D63A30`, texte ivoire `#F0EDE9`. Jamais Netflix-red ni néon.
- **Logo** : 7 rouge sur noir + badge bleu vérifié à côté du wordmark
- **Modèle commercial** : 13 €/an sur 7themotion.com, paiement EXTERNE
- **Package Android** : `com.manzilionellm.tvking`
- **Entrypoint** : `lib/main.dart`
- **Téléchargement** : `99999.7themotion.com/dl`

### Red Room (flavor adulte 18+)
- **Tagline** : "STRICTLY 18+ · AFTER HOURS"
- **Branding** : R rouge sang sur velours noir
- **Restrictions** : seules les chaînes [ChannelGenre.adult]
  apparaissent (filtre au niveau `PlaylistRepository.getAllChannels`).
  Biométrie OBLIGATOIRE à chaque cold start. Gate "j'ai 18+" au
  premier lancement. Pas de Play Store (politique Google).
  Pas d'iOS (politique Apple).
- **Package Android** : `com.redroom.player` (différent → cohabite
  avec 7 MOTION sans collision sur le téléphone)
- **Entrypoint** : `lib/main_redroom.dart`
- **Téléchargement** : `99999.7themotion.com/redroom`
- **Aiguillage** : `lib/core/flavor/flavor.dart` →
  `FlavorConfig.current.{adultOnly, biometricMandatory, requireAgeGate}`

---

## Architecture en place

### Backend (Cloudflare)
- **Worker** `lively-voice-7cb0` sur dash.cloudflare.com
- **Custom Domains** actifs : `99999.7themotion.com` (le domaine
  racine `7themotion.com` n'est pas encore branché à cause de
  DNS records Hostinger résiduels à supprimer)
- **KV namespace** : `KV_7MOTION` — stocke `client:<MAC>` avec
  `{name, playlists, status, paid, trial_until, note, last_seen_at,
  added_at, updated_at}`
- **ADMIN_SECRET** : variable env du Worker (set via wrangler)

### Endpoints publics
- `GET /` → landing page (téléchargement APK)
- `GET /dl` → 302 vers APK GitHub release `latest`
- `GET /1`, `/666666`, `/leo`, etc. → 302 vers APK (codes vanity)
- `POST /api/heartbeat` → l'app pingue avec son MAC, crée fiche
  trial 10 j si nouveau
- `GET /api/status/:mac` → l'app lit son statut courant
- `GET /config/:mac` → playlists assignées par l'admin

### Endpoints admin (auth X-Admin-Secret)
- `GET/POST /admin/clients` → CRUD
- `GET/PUT/DELETE /admin/clients/:mac`
- `POST /admin/clients/:mac/action` (freeze, unfreeze, ban,
  mark_paid, mark_unpaid, renew, note)
- `GET /admin/panel` → HTML autonome du panel web

### App Flutter
- **Player** : media_kit (libmpv)
- **Repos** : SQLite via `sqflite`
- **Identité device** : MAC virtuel `MK:XX:XX:XX:XX:XX` généré au
  1er boot, persisté en SharedPreferences
- **Trial** : SubscriptionState ping le backend au boot,
  fallback local 10 j si serveur down
- **Cast** : DLNA + Chromecast + QR (retiré du player) — clé
  Chromecast prévue à l'achat
- **PiP natif** : MainActivity.kt + MethodChannel `tvking/pip` +
  WakeLock + WifiLock pour enregistrement en background

---

## Décisions UX importantes

1. **WhatsApp est INVISIBLE** — le bouton VIP ouvre un sheet à
   2 choix ("Message instantané" / "Appel téléphonique"). Au tap
   sur Message, WhatsApp s'ouvre en silence. Pas de vert WhatsApp,
   pas du mot "WhatsApp" dans l'UI.

2. **Rotation auto SUIT le téléphone** — pas de forçage paysage.
   Style YouTube/Netflix : tel en portrait = vidéo portrait avec
   bandes, tel en horizontal = paysage plein cadre. Ça marche
   même si auto-rotate système OFF.

3. **PiP au BACK** — appuyer sur BACK pendant la lecture met la
   vidéo en mini-fenêtre flottante au lieu de fermer le player.
   YouTube canonique.

4. **Enregistrement continue en background** — WakeLock + WifiLock
   acquis par le ForegroundService AVANT le download HTTP.

5. **Section 'Mes sources IPTV' dans Réglages** — l'user peut
   ajouter ses propres playlists M3U/Xtream en plus du système
   revendeur (push à distance).

6. **Système revendeur intégré** — Toi tu pushes les playlists
   depuis le panel admin, le client reçoit auto via heartbeat.
   En parallèle, le client peut ajouter ses propres URLs.

---

## Bugs résolus récemment

- ✅ Overflow header player (badge LIVE) → `FittedBox(scaleDown)`
- ✅ Rotation auto qui suivait pas le téléphone
- ✅ Cast par QR ne marchait pas sur navigateur ordi → page HTML5
  du LocalCastServer joue le flux via hls.js / mpegts.js
- ✅ Enregistrement s'arrêtait quand on quittait l'app → WakeLock
  + WifiLock dans le service Kotlin
- ✅ PiP n'existait pas → implémentation native via MainActivity.kt
- ✅ Bouton QR retiré du header player (preference user)
- ✅ Mentions WhatsApp retirées partout
- ✅ **Enregistrement s'arrêtait après ~2 min** → cause : les CDN/Xtream
  ferment périodiquement la socket HTTP (`onDone`), l'ancien code
  nettoyait le job au lieu de reconnecter. Fix dans
  `http_recording_downloader.dart` : reconnexion auto sur coupure
  (raw + HLS, back-off progressif), plafond max **6 h**
  (`kMaxRecordingDuration`), callback `onAutoStopped` +
  `finishRecordingByPath` pour finaliser proprement la fiche en base.

## Bugs connus / pas encore résolus

- ⚠️ Domaine racine `7themotion.com` pas encore Custom Domain
  du Worker (DNS records Hostinger à supprimer)
- ⚠️ APK 207 Mo en debug — release sera plus petit mais à optimiser
- ⚠️ Pas encore de panel admin Flutter étendu (le web suffit)
- ⚠️ Cast officiel Chromecast pas encore testé (attente clé)

---

## App Licensing Platform (Phase 1.A — démarrée)

Nouvelle plateforme centrale pour gérer toutes les apps du portfolio
(7 MOTION, Red Room, futures). Cf. brief utilisateur "SaaS App
Licensing Platform" — Shopify/Stripe/Firebase pour ses apps.

### Stack
- **Backend** : Cloudflare Worker existant + nouveau module
  `cloudflare/api_v1.js` (namespace `/api/v1/*` parallèle aux endpoints
  legacy `/admin/*` et `/api/*` qui restent intacts pour compat ascendante).
- **Base de données** : nouvelle Cloudflare **D1** (`tvking_licensing`).
  Schéma complet dans `cloudflare/schema.sql` (apps, customers, devices,
  licenses, playlists, payments, audit_logs, notifications, resellers,
  admin_users).
- **Migration KV → D1** : `cloudflare/migrate_kv_to_d1.js` exposé via
  `POST /admin/migrate-to-d1` (idempotent, supporte `{dry_run: true}`).
- **Frontend admin** : `admin-panel/` — React + Vite + Tailwind à
  déployer sur Cloudflare Pages (build command : `cd admin-panel &&
  npm install && npm run build`, output : `admin-panel/dist`).

### Setup user one-time (à faire dès que tu installes Node + Wrangler)
1. `cd cloudflare && wrangler d1 create tvking_licensing`
2. Paste l'`id` retourné dans `wrangler.toml` à la place de
   `REMPLACE_MOI_PAR_L_ID_D1`
3. `wrangler d1 execute tvking_licensing --remote --file=schema.sql`
4. `wrangler deploy` (deploy le Worker avec les nouveaux endpoints)
5. `curl -X POST https://<worker>/admin/migrate-to-d1
        -H "X-Admin-Secret: <secret>"
        -d '{"dry_run":true}'` pour simuler
6. Si OK → re-curl sans `dry_run` → la migration écrit dans D1
7. Connecter Cloudflare Pages au repo (cf. `admin-panel/README.md`)

### Pages disponibles Phase 1.A
- `/login` — auth JWT (bootstrap : email=`admin`, password=`ADMIN_SECRET`)
- `/` Dashboard — KPIs lus en direct de D1
- `/customers` — liste + recherche (lecture seule en 1.A)
- `/devices` — liste + recherche (lecture seule en 1.A)
- `/apps` — liste (lecture seule en 1.A)
- `/activations` — liste licenses (lecture seule en 1.A)
- `/playlists` `/renewals` `/payments` `/resellers` `/notifications`
  `/logs` `/settings` → stubs marqués "Soon" en sidebar

### Phase 1.B (prochaine session)
- Création/édition Customers/Devices/Apps complète (boutons "Nouveau")
- Formulaire **Activer un MAC** (MAC + App + durée 1m/3m/6m/1y/lifetime → 1 clic)
- Renouvellement de license (cumule les jours si renouvelé avant expiration)
- Push playlist Xtream à distance (chiffrement creds via Web Crypto AES-GCM)
- Filtres avancés sur licenses (status, app, expirant dans 7j)
- Audit logs en lecture

### Phases ultérieures (non démarrées)
- 1.C — Resellers (portal séparé + crédits + stats)
- 2 — Paiements Stripe/PayPal + webhook auto-create license + invoice PDF
- 3 — Customer self-service portal (account.7themotion.com)
- 4 — Cron auto-expire + auto-renew + notifs email via Resend
- 5 — Analytics avancées (revenue, top apps, top resellers, renewal rate)

---

## Anciennes étapes mobiles (gardées en backlog)
1. Cast Chromecast natif à tester (attente clé)
2. QA pass complet sur Fire TV / Android TV / téléphone
3. Bug enregistrement "stop à 1 min" à diagnostiquer (probablement
   limite 1 connexion par provider IPTV — cf. message user)

---

## Conventions de code (rappel — voir aussi AGENTS.md)

- **Pas de print()** — `debugPrint()`
- **Pas de couleurs hardcodées** — `AppColors.*` ou `LumiereColors.of()`
- **Commentaires en français, abondants** — projet pédagogique aussi
- **Pas de URL IPTV en dur** dans le code de prod
- **Tokens design** : `lib/core/theme/lumiere_tokens.dart`

---

## Comment ME briefer à la prochaine session

Tape juste :

> **"Lis STATUS.md et reprends. On en était à [ce que tu veux faire]."**

Et je relirai ce fichier, les derniers commits, et on continuera
sans perdre de temps en re-contexte.
