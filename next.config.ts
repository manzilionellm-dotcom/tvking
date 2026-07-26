import type { NextConfig } from "next";

/*
 * L'app TV est intégralement statique (103 pages SSG) : elle peut donc être
 * exportée en fichiers et servie par n'importe quel hébergeur statique — c'est
 * ce que fait .github/workflows/deploy-tv-pages.yml.
 *
 * L'export n'est activé QUE par variables d'environnement : `npm run dev`,
 * `npm run build` et `npm start` gardent exactement le comportement d'avant.
 *   STATIC_EXPORT=1        → sortie `out/` (fichiers statiques)
 *   NEXT_BASE_PATH=/tvking → préfixe d'URL (nécessaire sous github.io/<repo>/,
 *                            à laisser vide sur un domaine dédié)
 */
const staticExport = process.env.STATIC_EXPORT === "1";
const basePath = process.env.NEXT_BASE_PATH ?? "";

const nextConfig: NextConfig = {
  ...(staticExport
    ? {
        output: "export" as const,
        // Un hébergeur statique sert /sport/football/index.html : sans le slash
        // final, l'URL /sport/football renvoie 404.
        trailingSlash: true,
      }
    : {}),
  ...(basePath ? { basePath, assetPrefix: basePath } : {}),
};

export default nextConfig;
