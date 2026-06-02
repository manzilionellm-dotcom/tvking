import type { NextConfig } from "next";

// Cible « APK TV » : quand on construit l'APK Android TV / Fire TV, on
// active l'EXPORT STATIQUE (out/) et on préfixe tous les assets par
// `/assets/web` — exactement le chemin servi par WebViewAssetLoader dans
// le wrapper (https://appassets.androidplatform.net/assets/web/...).
//
// En build web normal (Vercel / `npm run dev`), NOVA_TARGET n'est pas
// défini → pas de basePath, app servie normalement à la racine.
const FOR_TV_APK = process.env.NOVA_TARGET === "tv-apk";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  ...(FOR_TV_APK
    ? {
        output: "export",
        basePath: "/assets/web",
        assetPrefix: "/assets/web",
        // L'optimiseur d'images Next exige un serveur ; en export on le
        // désactive (de toute façon nos visuels sont des dégradés CSS).
        images: { unoptimized: true },
        // Les URLs se terminent par « / » → fichiers index.html par
        // dossier, simples à servir depuis les assets de l'APK.
        trailingSlash: true,
      }
    : {}),
};

export default nextConfig;
