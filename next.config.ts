import type { NextConfig } from "next";

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
