import type { MetadataRoute } from "next";

export const dynamic = "force-static";

const paths = [
  "/",
  "/forfaits",
  "/telecharger",
  "/activer",
  "/connexion",
  "/faq",
  "/guides/installer-zuno",
  "/guides/ajouter-playlist-m3u-xtream-zuno",
  "/guides/zuno-coupures-erreurs-lecture",
  "/legal",
  "/revendeur",
  "/start",
  "/tv",
  "/films",
  "/sport",
  "/formation",
  "/search",
  "/list",
  "/reglages",
];

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return paths.map((path) => ({
    url: `https://zuno.7themotion.com${path}`,
    lastModified: now,
    changeFrequency: path === "/" || path === "/forfaits" ? "weekly" : "monthly",
    priority: path === "/" ? 1 : path === "/forfaits" || path === "/telecharger" ? 0.9 : 0.7,
  }));
}
