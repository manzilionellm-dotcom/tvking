# Baseline perf run-001 (2026-07-25) — build production Next 16.2.11
| Métrique | Valeur | Source |
|---|---|---|
| Pages statiques générées | 115 | next build (exit 0) |
| Taille .next totale | 24 Mo | du -sh |
| Plus gros chunk JS client | 224 Ko | .next/static/chunks |
| Chunks suivants | 148 / 112 / 56 / 44 Ko | idem |
| Génération des pages | ~1,0 s (115 pages, 3 workers) | next build |
Budget loi 10 pour les runs suivants : aucun chunk > 224 Ko, .next ≤ 24 Mo, build vert.
(TTFF/zapping réels S3 : NON MESURABLES au run-001 — lecteur mock, pas de flux vidéo. Vit au backlog B1.)
