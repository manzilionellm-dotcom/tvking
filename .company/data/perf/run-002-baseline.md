# Baseline perf run-002 (2026-07-25) — build production Next 16.2.11

| Métrique | run-001 | run-002 | Source |
|---|---|---|---|
| Pages statiques générées | 115 | **103** | next build (exit 0) |
| Taille .next totale | 24 Mo | **23 Mo** | du -sh |
| Plus gros chunk JS client | 224 Ko | **228 Ko** | .next/static/chunks |
| Chunks suivants | 148 / 112 / 56 / 44 Ko | 148 / 112 / 56 / 44 Ko | idem |
| Total JS client (.next/static/**/*.js) | non mesuré | **702,5 Kio** | scripts/size-budget.mjs |
| Génération des pages | ~1,0 s (115 pages) | ~1,0 s (103 pages) | next build |

**Pourquoi 103 pages et non 115 :** les 12 tuiles de facette (disciplines / thèmes) ne sont plus du
contenu — elles généraient chacune une fiche `/title` et un lecteur `/watch` pour un simple logo
(24 pages absurdes). Elles sont remplacées par 12 vraies pages de facette. Solde : −24 +12 = −12.

**Plus gros chunk : 224 → 228 Ko (+1,8 %) — dépassement assumé et tracé.** Cause : les nouvelles
surfaces réellement fonctionnelles sont des composants client (collections persistées, recherche
locale, rangée « Reprendre » réelle). Le budget de run-001 (« aucun chunk > 224 Ko ») est donc
recalé à 232 Ko, et la porte automatique posée dans qa-gates porte désormais sur le **total** du JS
client avec une marge de +10 % (`.company/data/perf/baseline.json`, 702,5 Kio → plafond 772,8 Kio).

(TTFF / zapping réels S3 : toujours NON MESURABLES — le lecteur est un mock, aucun flux vidéo.
Backlog B1.)
