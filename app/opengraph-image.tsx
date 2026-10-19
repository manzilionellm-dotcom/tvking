/**
 * Dynamic share card, generated at build time (no request-time API, no `runtime = 'edge'`).
 * Text comes from aio.config.json — the same constants the pages render. No ratings, no counters.
 */
import { ImageResponse } from "next/og";
import { aio } from "../lib/aio";

// Required by the GitHub Pages static export (deploy-pages.yml, output: "export"),
// same as app/robots.ts and app/sitemap.ts. On Vercel the card is built once either way.
export const dynamic = "force-static";

export const alt = `${aio.siteName} — L'app IPTV, pas les chaînes`;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const CLAIM = "L'app IPTV, pas les chaînes";
const ENTRY = aio.plans.map((p) => `${p.name.fr} ${p.priceLabel}`).join(" · ");
const DOMAIN = "zuno.7themotion.com";
const ACCENT = "#3b82f6";

export default function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: 72,
          background: "linear-gradient(135deg, #0a0a0c 0%, #111827 60%, #0a0a0c 100%)",
          color: "#f8fafc",
          fontFamily: "system-ui, Segoe UI, Roboto, sans-serif",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <div style={{ width: 18, height: 18, borderRadius: 9999, background: ACCENT, display: "flex" }} />
          <div style={{ fontSize: 34, fontWeight: 700, letterSpacing: -0.5, display: "flex" }}>{aio.siteName}</div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
          <div style={{ fontSize: 68, fontWeight: 800, lineHeight: 1.08, letterSpacing: -1.5, display: "flex", maxWidth: 1000 }}>
            {CLAIM}
          </div>
          <div style={{ fontSize: 30, color: "#93c5fd", fontWeight: 600, display: "flex" }}>Licence app : {ENTRY}</div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 24, color: "#94a3b8" }}>
          <div style={{ display: "flex" }}>{DOMAIN}</div>
          <div style={{ display: "flex" }}>Nous ne vendons pas de chaînes</div>
        </div>
      </div>
    ),
    { ...size },
  );
}
