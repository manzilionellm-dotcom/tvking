#!/usr/bin/env bash
# ============================================================================
# qa-gates.sh — la porte de qualité unique (app TV web).
# Vert = exit 0 sur TOUT ; une seule rouge = REJETÉ.
#   1. lint       (eslint, 0 erreur)
#   2. typegen    (types de routes Next — requis avant tsc sur checkout frais)
#   3. typecheck  (tsc --noEmit, 0 erreur)
#   4. tests      (vitest, suite verte)
#   5. build      (next build production)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "── [1/5] lint"
npm run lint

echo "── [2/5] typegen"
npx next typegen

echo "── [3/5] typecheck"
npx tsc --noEmit

echo "── [4/5] tests"
npm test

echo "── [5/5] build"
npm run build

echo "✅ qa-gates : tout est vert"
