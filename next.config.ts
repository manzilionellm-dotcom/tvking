import type { NextConfig } from "next";

/*
 * NOVA+ ships as a fully static export bundled inside the Android-TV APK's
 * WebView (file:///android_asset/www). No Node server runs on the device — all
 * IPTV fetching/parsing happens client-side (see app/lib/client-source.ts).
 *
 * - output: "export"  → emit static HTML/JS to `out/`
 * - images.unoptimized → required for export (and we use plain <img> anyway)
 * - trailingSlash      → emit `path/index.html` so file:// routing resolves
 */
const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
