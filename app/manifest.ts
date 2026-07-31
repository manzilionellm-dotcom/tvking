import type { MetadataRoute } from "next";

/* Required for the static export (GitHub Pages) build. */
export const dynamic = "force-static";

/*
 * Web app manifest — makes TV King installable on a phone ("Ajouter à
 * l'écran d'accueil"): it opens plein écran, avec son icône, comme une
 * application native.
 */
/* Metadata routes are not basePath-prefixed automatically — do it by hand for
   the GitHub Pages build (served under /tvking). */
const base = process.env.GITHUB_PAGES === "true" ? "/tvking" : "";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "TV King — IPTV, Films, Sport & Formation",
    short_name: "TV King",
    description:
      "TV en direct (vos playlists M3U, liens vérifiés), films en lecture instantanée, sport et formation.",
    start_url: `${base}/`,
    display: "standalone",
    orientation: "portrait",
    background_color: "#121212",
    theme_color: "#121212",
    icons: [
      { src: `${base}/icon.svg`, sizes: "any", type: "image/svg+xml", purpose: "any" },
      { src: `${base}/icon.svg`, sizes: "any", type: "image/svg+xml", purpose: "maskable" },
    ],
  };
}
