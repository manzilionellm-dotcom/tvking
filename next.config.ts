import type { NextConfig } from "next";

const isPages = process.env.GITHUB_PAGES === "true";
const repo = "tvking";

const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  basePath: isPages ? `/${repo}` : undefined,
  assetPrefix: isPages ? `/${repo}/` : undefined,
};

export default nextConfig;
