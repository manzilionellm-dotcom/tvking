import type { NextConfig } from "next";

/*
 * GITHUB_PAGES=true (CI deploy-pages.yml) builds a fully static export served
 * under https://<owner>.github.io/tvking — hence the basePath. The normal
 * build (dev, qa-gates) is untouched.
 */
const onPages = process.env.GITHUB_PAGES === "true";

const nextConfig: NextConfig = {
  ...(onPages && {
    output: "export" as const,
    basePath: "/tvking",
    images: { unoptimized: true },
  }),
};

export default nextConfig;
