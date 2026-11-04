#!/usr/bin/env bash
# =========================================================
#  build.sh — Assemble les paquets Tizen (.wgt) et webOS (.ipk)
# =========================================================
#  On garde UN SEUL code (shared/). Ce script copie shared/ dans deux dossiers
#  de build, y ajoute le manifeste de chaque plateforme, puis appelle les SDK :
#    • Samsung : tizen   (Tizen Studio CLI)  → .wgt
#    • LG      : ares-package (webOS CLI)    → .ipk
#  Les SDK ne sont PAS inclus ici (voir README pour l'installation).
# =========================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SHARED="$ROOT/shared"
BUILD="$ROOT/build"

# Une icône absente est une erreur de construction, pas un paquet publiable.
test -s "$ROOT/platform/tizen/icon.png"
for script in "$SHARED"/js/*.js; do node --check "$script"; done
echo "==> Nettoyage"
rm -rf "$BUILD"
mkdir -p "$BUILD/tizen" "$BUILD/webos"

echo "==> Tizen (Samsung)"
cp -r "$SHARED/." "$BUILD/tizen/"
cp "$ROOT/platform/tizen/config.xml" "$BUILD/tizen/config.xml"
[ -f "$ROOT/platform/tizen/icon.png" ] && cp "$ROOT/platform/tizen/icon.png" "$BUILD/tizen/icon.png" || true

echo "==> webOS (LG)"
cp -r "$SHARED/." "$BUILD/webos/"
cp "$ROOT/platform/webos/appinfo.json" "$BUILD/webos/appinfo.json"
[ -f "$ROOT/platform/webos/icon.png" ] && cp "$ROOT/platform/webos/icon.png" "$BUILD/webos/icon.png" || true
[ -f "$ROOT/platform/webos/largeIcon.png" ] && cp "$ROOT/platform/webos/largeIcon.png" "$BUILD/webos/largeIcon.png" || true

echo
echo "Dossiers prêts :"
echo "  Tizen : $BUILD/tizen   → packager :  tizen package -t wgt -s <profil> -- $BUILD/tizen"
echo "  webOS : $BUILD/webos   → packager :  ares-package $BUILD/webos"
echo
echo "(Voir README.md pour signer et soumettre aux stores.)"

# La signature reste explicite et locale : ne jamais commiter le certificat.
if [ -n "${TIZEN_PROFILE:-}" ]; then
  command -v tizen >/dev/null || { echo "Tizen CLI absent" >&2; exit 1; }
  tizen package -t wgt -s "$TIZEN_PROFILE" -- "$BUILD/tizen"
fi
