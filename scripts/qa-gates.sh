#!/usr/bin/env bash
# ============================================================================
# qa-gates.sh — la porte de qualité unique (app TV web).
# Vert = exit 0 sur TOUT ; une seule rouge = REJETÉ.
#   1. lint       (eslint, 0 erreur)
#   2. typegen    (types de routes Next — requis avant tsc sur checkout frais)
#   3. typecheck  (tsc --noEmit, 0 erreur)
#   4. tests      (vitest, suite verte)
#   5. build      (next build production)
#   6. budget     (taille du JS client vs baseline commitée)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "── [1/6] lint"
npm run lint

echo "── [2/6] typegen"
npx next typegen

echo "── [3/6] typecheck"
npx tsc --noEmit

echo "── [4/6] tests"
npm test

echo "── [5/6] build"
npm run build

echo "── [6/6] budget de taille (JS client)"
node scripts/size-budget.mjs

echo "✅ qa-gates : tout est vert"
