import type { NextConfig } from "next";

/*
 * NOVA+ ships as a fully static export bundled inside the Android-TV APK's
 * WebView. The wrapper serves the bundle via WebViewAssetLoader under
 * `https://appassets.androidplatform.net/assets/web/…`, so for the APK build we
 * MUST prefix every asset/route with `/assets/web` — otherwise Next emits
 * absolute `/_next/…` URLs that resolve outside the AssetLoader's `/assets/`
 * handler and 404 (white, unstyled, stuck screen).
 *
 * The APK build sets NOVA_TARGET=tv-apk (see build-nova-tv.yml). A plain
 * `npm run build` (dev/preview) still exports to `out/` but at the root.
 *
 * - output: "export"  → emit static HTML/JS to `out/`
 * - images.unoptimized → required for export (and we use plain <img> anyway)
 * - trailingSlash      → emit `path/index.html` so subpath routing resolves
 * - basePath/assetPrefix (tv-apk only) → match the WebView's `/assets/web` mount
 */
const FOR_TV_APK = process.env.NOVA_TARGET === "tv-apk";

const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  ...(FOR_TV_APK ? { basePath: "/assets/web", assetPrefix: "/assets/web" } : {}),
};

export default nextConfig;
