import type { MetadataRoute } from "next";
import { SITE_URL } from "./lib/app-downloads";

export const dynamic = "force-static";

const paths = ["/", "/start", "/tv", "/films", "/sport", "/formation", "/search", "/list", "/reglages", "/telecharger"];

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  return paths.map((path) => ({
    url: `${SITE_URL}${path}`,
    lastModified: now,
    changeFrequency: path === "/" ? "weekly" : "monthly",
    priority: path === "/" ? 1 : 0.7,
  }));
}
