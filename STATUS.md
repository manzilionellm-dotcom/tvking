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

## Identité du produit

- **Nom** : 7 MOTION
- **Tagline** : "THE FEW · NOT FOR EVERYONE"
- **Branding** : Maison Noir — fond charbon `#0A0A0C`, accent ember
  rouge `#D63A30`, texte ivoire `#F0EDE9`. Jamais Netflix-red ni néon.
- **Logo** : 7 rouge sur noir + badge bleu vérifié à côté du wordmark
- **Modèle commercial** : 13 €/an sur 7themotion.com, paiement EXTERNE
  (pas d'in-app Google Play, bypass commission 30%)

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

## Bugs connus / pas encore résolus

- ⚠️ Domaine racine `7themotion.com` pas encore Custom Domain
  du Worker (DNS records Hostinger à supprimer)
- ⚠️ APK 207 Mo en debug — release sera plus petit mais à optimiser
- ⚠️ Pas encore de panel admin Flutter étendu (le web suffit)
- ⚠️ Cast officiel Chromecast pas encore testé (attente clé)

---

## Prochaines étapes prévues

1. **Tester en conditions réelles** sur Fire TV / Android TV /
   téléphone : enregistrement background, PiP, rotation auto,
   panel admin web
2. **Panel admin Flutter** : étendre l'écran existant pour afficher
   colonnes trial/paid/status (Phase 3 prévue)
3. **Webhook paiement** : auto-marquer payé sans intervention manuelle
4. **Notifications client j-3 avant expiration** : push notif "Ton
   essai expire dans 3 jours"
5. **Acheter clé Chromecast** pour tester le cast natif Google
6. **QA pass complet** : suivre les bugs et tester avant lancement
   public

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
