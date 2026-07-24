# Décisions (journal)

## Run 001 — 2026-07-23

### D1 — Bump Next.js 16.2.4 → 16.2.11 (sécurité)
`npm audit` (prod) signalait 3 highs sur Next 16.2.4 : DoS Server Components,
bypass Middleware/Proxy (segment-prefetch), cache-poisoning redirects, XSS CSP nonces,
cache-poisoning RSC. Toutes corrigées en 16.2.x. Bump patch (même mineure) → risque faible.
Revalidé : `npm run build` vert après bump. eslint-config-next aligné sur 16.2.11.

### D2 — Vulnérabilités transitives NON corrigées (consignées, pas contournées)
Restent 2 highs après le bump, non corrigeables sans casse (Loi 3 / §5 — jamais
`npm audit fix --force` qui downgrade Next → 9.3.3) :
- **postcss** (`node_modules/next/node_modules/postcss`) : bundlé DANS Next ; dépend d'un
  correctif amont de Next. Hors de notre contrôle direct. À revoir au prochain bump Next.
- **sharp** (libvips CVEs) : dépendance image OPTIONNELLE de Next. L'app n'utilise que des
  dégradés CSS (aucun `next/image` sur asset binaire) → non sollicitée au runtime.
Bilan `npm audit` : 6 → 3 highs (dev `brace-expansion`/`js-yaml` corrigés via `audit fix`).

### D3 — Pas de fabrication de la surface streaming native
Le MODULE S du prompt (Media3/ExoPlayer, matrice codec, passthrough audio, ABR, AAB/rollout)
n'a pas de surface dans ce dépôt (lecteur = mock, pas de moteur natif, pas de back-end).
On n'invente rien. On traite les vrais manques TV-UX du code existant (focus, RETOUR, play/pause)
et les fondations qualité manquantes (tests, CI, observabilité, budgets).
