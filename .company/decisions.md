# Décisions (run-001, 2026-07-25)
- **Périmètre TV uniquement** (instruction humaine) : zéro modification des workflows/mobile.
- **Logique pure extraite pour testabilité** : la géométrie du D-pad (`app/lib/spatial.ts`) et le
  stockage de reprise (`app/lib/resume.ts`) sont des modules purs testés en node, consommés par les
  composants client. Pas de jsdom au run-001 (coût > valeur) — les composants restent couverts par
  build + lint + tsc + usage des modules purs.
- **Stockage versionné** (loi 4) : clé `tvking.v1.resume`, enveloppe `{v:1, entries:{}}`, parse
  défensif (donnée corrompue → repart propre, jamais de crash).
- **CI qa-gates** sur push/PR : lint, typecheck, tests, build — la seule porte de merge. Pas de SBOM/
  osv-scanner au run-001 (surface deps: 3 deps runtime, lockfile commité) → backlog.
- **Pas d'auto-merge** : repo sans branch protection configurable d'ici (MODE DÉGRADÉ §0.2) ; la PR
  reste ouverte, checks verts = fin légale (a).
