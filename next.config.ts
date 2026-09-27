import type { NextConfig } from "next";
import { SHORT_LINKS } from "./app/lib/app-downloads";

const onPages = process.env.GITHUB_PAGES === "true";

const CSP_REPORT_ONLY =
  "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self' data:; connect-src 'self' https://wa.me; media-src 'self' blob: https: http:; frame-ancestors 'self'; base-uri 'self'; form-action 'self'; object-src 'none'";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  ...(onPages && {
    output: "export" as const,
    basePath: "/tvking",
    images: { unoptimized: true },
  }),
  // Raccourcis de téléchargement (/apk, /pc) : courts à taper sur une
  // télécommande (app « Downloader »). Temporaires (307) : la destination
  // est toujours la dernière version publiée. Absents de l'export statique
  // (GitHub Pages ne sait pas rediriger).
  async redirects() {
    if (onPages) return [];
    return Object.entries(SHORT_LINKS).map(([source, destination]) => ({
      source,
      destination,
      permanent: false,
    }));
  },
  async headers() {
    if (onPages) return [];
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "SAMEORIGIN" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
          { key: "Strict-Transport-Security", value: "max-age=63072000" },
          { key: "Content-Security-Policy-Report-Only", value: CSP_REPORT_ONLY },
        ],
      },
    ];
  },
};

export default nextConfig;
