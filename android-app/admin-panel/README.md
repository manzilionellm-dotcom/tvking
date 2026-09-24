# Admin Panel — App Licensing Platform

Panel de gestion **Super Admin** pour la plateforme de licensing. React +
Vite + Tailwind, déployable sur **Cloudflare Pages** en `git push`.

## Stack

- **Vite** + **React 18** + **TypeScript**
- **Tailwind CSS** (palette alignée sur les apps Flutter — `app_colors.dart`)
- **React Router** (routes login / dashboard / pages)
- API : Worker Cloudflare via `/api/v1/*` (voir `cloudflare/api_v1.js`)
- Auth : JWT HS256 signé avec `ADMIN_SECRET` du Worker

## Pages (Phase 1.A)

| Route | Statut |
|---|---|
| `/login` | ✅ |
| `/` (Dashboard, KPIs) | ✅ |
| `/customers` (lecture + recherche) | ✅ |
| `/devices` (lecture + recherche) | ✅ |
| `/apps` (lecture) | ✅ |
| `/activations` (lecture) | ✅ |
| `/playlists`, `/renewals`, `/payments`, `/resellers`, … | Phase 1.B+ |

## Setup local (une seule fois)

```bash
cd admin-panel
npm install
npm run dev
# → http://localhost:5173
```

Pendant le dev, les requêtes `/api/*` sont proxy vers
`http://127.0.0.1:8787` (le Worker en `wrangler dev`). Lance le Worker en
parallèle dans un autre terminal :

```bash
cd ../cloudflare
wrangler dev --local --persist
```

## Premier login

Au tout premier `POST /api/v1/auth/login`, si la table `admin_users`
de D1 est vide, le Worker crée automatiquement un compte :

- **email** : `admin`
- **password** : la valeur de ton `ADMIN_SECRET` Worker (le même secret
  que celui que tu utilisais déjà sur l'ancien panel)

Tu peux changer ce mot de passe plus tard via une page Settings (Phase 2).

## Build et déploiement Cloudflare Pages

```bash
npm run build
# → dist/ (à uploader sur Pages)
```

### Connecter le repo à Cloudflare Pages (one-time, 5 min)

1. Cloudflare Dashboard → **Pages** → **Create application** → **Connect to Git**
2. Sélectionner `manzilionellm-dotcom/tvking`
3. **Build settings** :
   - Framework preset : `Vite`
   - Build command : `cd admin-panel && npm install && npm run build`
   - Build output directory : `admin-panel/dist`
   - Root directory : `/` (laisser vide)
4. **Environment variables** (Production) :
   - `VITE_API_BASE` = `https://seven-motion-backend.<ton-pseudo>.workers.dev`
     (ou ton domaine custom Worker si configuré)
5. Save and deploy

À chaque push sur `main`, Pages re-build et déploie sur
`https://<ton-projet>.pages.dev` (et le custom domain si configuré).

### Custom domain (recommandé)

- Pages → Custom domains → `admin.7themotion.com` (ou autre)
- Cloudflare ajoute automatiquement le CNAME + cert HTTPS

## Liens code → API

| Composant | Endpoint Worker |
|---|---|
| `LoginPage.tsx` | `POST /api/v1/auth/login` |
| `DashboardPage.tsx` | `GET /api/v1/stats/overview` |
| `CustomersPage.tsx` | `GET /api/v1/customers?q=` |
| `DevicesPage.tsx` | `GET /api/v1/devices?q=` |
| `AppsPage.tsx` | `GET /api/v1/apps` |
| `ActivationsPage.tsx` | `GET /api/v1/licenses` |

## Phase 1.B (next session)

- Création/édition complète (Customers, Devices, Apps)
- Formulaire d'activation (MAC + App + durée → 1 clic)
- Renouvellement 1 an / 1 mois / 6 mois / lifetime
- Push playlist Xtream à distance
- Filtres avancés sur licenses (status, app, expirant dans 7j)
- Audit logs en lecture
