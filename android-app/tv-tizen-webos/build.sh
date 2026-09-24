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
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
SHARED="$ROOT/shared"
BUILD="$ROOT/build"

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
