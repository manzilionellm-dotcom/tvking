import type { MetadataRoute } from "next";

export const dynamic = "force-static";

/** AI / answer-engine crawlers allowed to read and cite the public pages. */
const AI_BOTS = [
  "GPTBot",
  "ChatGPT-User",
  "OAI-SearchBot",
  "PerplexityBot",
  "Perplexity-User",
  "ClaudeBot",
  "anthropic-ai",
  "Claude-Web",
  "Google-Extended",
  "Applebot-Extended",
  "CCBot",
  "DuckAssistBot",
  "meta-externalagent",
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/", disallow: ["/api/", "/ops"] },
      ...AI_BOTS.map((userAgent) => ({ userAgent, allow: "/", disallow: ["/api/", "/ops"] })),
    ],
    sitemap: "https://tvking.vercel.app/sitemap.xml",
    host: "https://tvking.vercel.app",
  };
}
