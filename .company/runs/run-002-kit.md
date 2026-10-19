# run-002 — kit « Metrics & Conversion Engine » (2026-10-18, branche ccr-6131f392-wjns5t)

## T0 (mesuré avant toute édition)
- `npm run build` exit 0 — 24 routes statiques (○/●), 2 dynamiques (ƒ : /api/activate, /api/auth). Aucune
  page dynamique : pas de headers()/cookies()/searchParams côté pages.
- JSON-LD (layout, toutes pages) : Organization + FAQPage + Product×2 (Annuel, À vie). Pas de WebSite,
  pas de BreadcrumbList ; FAQPage émis même sur les pages sans FAQ visible.
- og:image : fichier statique zuno.7themotion.com/social-share-v1.png déclaré dans le layout ; aucun
  `opengraph-image` généré. Canonical absent sur toutes les pages sauf /telecharger et /start.
- robots.txt : `*` seul (pas de règles IA). Pas de /api/status.

## T1 (après kit)
- Layout : Organization + WebSite une fois. PageJsonLd : Product×2 (/, /forfaits), FAQPage uniquement où
  <CitationFaq /> est rendu (/, /forfaits, /faq), BreadcrumbList sur toutes les pages > `/`.
- app/opengraph-image.tsx + twitter-image.tsx (générés au build, textes depuis aio.config.json).
- /api/status (SSE, valeurs mesurées : région, déploiement, commit, heure ; sessions = null sans KV) +
  LiveStatus dans SiteFooter (libellés FR), lien WhatsApp support.
- robots.ts : bots IA autorisés, /api/ et /ops interdits. Canonical absolu sur chaque page.
- Portes : voir message de commit (npm run qa, npm run typecheck, vérificateur kit).
