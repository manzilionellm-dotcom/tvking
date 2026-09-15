import type { MetadataRoute } from "next";

export const dynamic = "force-static";

const paths = ["/", "/start", "/tv", "/films", "/sport", "/formation", "/search", "/list", "/reglages"];

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return paths.map((path) => ({
    url: `https://tvking.vercel.app${path}`,
    lastModified: now,
    changeFrequency: path === "/" ? "weekly" : "monthly",
    priority: path === "/" ? 1 : 0.7,
  }));
}
