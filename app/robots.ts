import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: ["/api/", "/ops"] },
    sitemap: "https://tvking.vercel.app/sitemap.xml",
    host: "https://tvking.vercel.app",
  };
}
