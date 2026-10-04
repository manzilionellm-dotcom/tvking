# Contrat d'API « Pouvoirs clients » (panel ⇄ Worker ⇄ box)

Branche : `claude/pouvoirs-clients` (issue de la production `claude/panel-mise-en-ligne`, 0896028c).
**Rien n'est déployé.** Tout est derrière l'interrupteur Worker `CLIENT_POWERS` (coupé par défaut).

## 1. Interrupteur de repli

| Variable Worker | Valeur par défaut | Effet |
|---|---|---|
| `CLIENT_POWERS` | absente = coupé | Coupé : les routes admin répondent `404 client_powers_off` (sauf `GET …/powers` → `{enabled:false}`) et `GET /api/status/<mac>` reste **identique à avant** (aucun champ ajouté). Allumé (`1`, `true`, `on`, `yes`) : routes actives et champs ajoutés au statut. |

À poser comme *variable/secret du Worker* (tableau de bord Cloudflare ou `wrangler secret`), **pas** dans `wrangler.toml`
(le garde-fou du workflow de déploiement n'accepte déjà pas `TRIAL_ENFORCEMENT` ; garder la même discipline).

## 2. Ce que la BOX doit lire (contrat public, sans authentification)

`GET /api/status/<mac>` — champs **ajoutés** (uniquement si `CLIENT_POWERS` est allumé) :

```json
{
  "frozen": false, "banned": false,            // existants (blocage)
  "payment_request": null,                      // ou objet ci-dessous
  "client_message": null,                       // ou objet ci-dessous
  "refresh_rev": 0                              // nombre
}
```

`payment_request` (demande « merci de payer ») :
```json
{ "id": "1791145762785", "message": "Merci de régler…", "amount": "20",
  "currency": "EUR", "link": "https://…", "due_at": null }
```
`client_message` :
```json
{ "id": "1791145762788", "title": "Info", "body": "Bonjour", "expires_at": 1791149362788 }
```

Règles côté box (à implémenter dans l'app, **non fait ici**) :
1. `payment_request != null` → afficher le message (bandeau ou boîte de dialogue) avec montant/devise ; `link` (https) en option
   (QR code ou texte). **Ne bloque pas** la lecture : pour bloquer, l'admin utilise « Geler » (`frozen: true`, déjà géré).
2. `client_message != null` → afficher une fois par `id` (mémoriser le dernier `id` vu). Ignorer si `expires_at` est passé.
3. `payment_request.id` change à chaque nouvel envoi : réafficher si l'`id` diffère du dernier vu, ou à chaque ouverture tant que la demande est active (au choix produit).
4. `refresh_rev` : mémoriser la dernière valeur ; si elle change, relire **immédiatement** `/api/status/<mac>` et `/api/device-source/<mac>` (sans attendre le prochain cycle).
   C'est le « forcer la relecture » du panel ; le temps réel (WebSocket/SSE) relèvera de l'agent « Activation instantanée ».
5. Un champ absent (ancien Worker ou interrupteur coupé) = rien à afficher. Les anciennes versions de l'app ignorent ces champs.

## 3. Routes admin (JWT `super_admin` uniquement ; un revendeur reçoit 403)

Toutes sous `/api/v1/devices/:id/…` (`:id` = id de l'appareil, comme `PATCH /devices/:id`). Chaque écriture est **journalisée** dans `audit_logs`.

| Méthode + chemin | Corps | Effet | Journal (`action`) |
|---|---|---|---|
| `GET …/powers` | — | État : blocage, suspendu, à vie, demande/message actifs, `refresh_rev` | — |
| `POST …/block` | `{status:'active'\|'frozen'\|'banned', reason?}` | Bloque / débloque + relecture forcée | `client.block` |
| `PUT …/payment-request` | `{message?, amount?, currency?, link?(https), due_at?}` | Demande de paiement | `client.payment_request.set` |
| `DELETE …/payment-request` | — | Retire la demande | `client.payment_request.clear` |
| `POST …/message` | `{title?, body, expires_in_hours?}` | Message affiché dans l'app | `client.message.send` |
| `DELETE …/message` | — | Retire le message | `client.message.clear` |
| `POST …/extend` | `{days:1..365}` | Licence datée : +N jours (statut inchangé). Licence à vie : 409. Sans licence : ajout de jours d'essai (logique `trial-extend` existante) | `client.extend` / `trial.extend` |
| `POST …/suspend` | `{suspend:true\|false, reason?}` | Licence `suspended` / `active` (date de fin conservée). Sans licence : 409 | `client.suspend` / `client.resume` |
| `POST …/refresh` | — | Incrémente `refresh_rev` | `client.refresh` |
| `GET/POST …/notes`, `DELETE …/notes/:noteId` | `{body}` | Notes internes (jamais publiques) | `client.note.add` / `client.note.delete` |
| `GET …/actions?limit=` | — | Journal des actions de ce client (audit_logs : `device` + `device_source`), sans IP ni secret | — |

**Changer la liste M3U/Xtream** : route existante `PUT /api/v1/sources/:mac` (remplace l'ensemble) — déjà journalisée (`source.set`) et visible dans `…/actions`.
**Bloquer sans motif** : `PATCH /api/v1/devices/:id` existe toujours (journal `device.block`, accessible aux revendeurs sur leurs appareils).

## 4. Données (migration `010_client_powers.sql`, additive)

`client_notices (mac, kind['payment'|'message'|'refresh'], active, title, body, amount, currency, link, due_at, expires_at, rev, …)` et `client_notes`.
Le Worker crée aussi les tables à la volée (`CREATE TABLE IF NOT EXISTS`) : la migration peut être appliquée avant ou après, sans risque.

## 5. Vérification

```
cd android-app/cloudflare && node --check worker.js && node --check api_v1.js && node --check client_powers.js
node --test client_powers.test.mjs                       # 23 tests (D1 simulée)
cd ../admin-panel && npm ci && npm test && npm run build   # tests du panel (Node ≥ 22.6) + build
```
Contre un vrai moteur SQL : `android-app/cloudflare/tools/client_powers.e2e.sqljs.mjs` (voir l'en-tête du fichier ; `npm i sql.js` hors dépôt).

## 6. Points d'attention avant mise en ligne

- **Déploiement du Worker** : le run du 3/10 (`37120120412`) a échoué à « DÉPLOYER le Worker » avec l'erreur Cloudflare **10064** :
  « New version of script does not export class 'RealtimeHub' which is depended on by existing Durable Objects ».
  Le Worker en ligne (dernier déploiement manuel du 20/09) contient une classe Durable Object `RealtimeHub` que la branche de production n'exporte pas.
  **Ne jamais forcer** une migration `delete-class` : elle détruirait l'état du DO. Il faut d'abord retrouver le code de `RealtimeHub` (branche de l'agent « Activation instantanée » ?) et le déclarer dans `wrangler.toml` + le code déployé.
- Journal : `logAudit` est « au mieux » (une panne du journal n'annule pas l'action) — comportement existant, inchangé.
- Les nouvelles actions sont réservées au `super_admin` ; les revendeurs gardent uniquement ce qu'ils avaient (activation, sources, geler/bannir leurs appareils).
