// Segment config must be declared in this file: Next does not read a re-exported `dynamic`.
// force-static is required by the GitHub Pages static export (deploy-pages.yml).
export const dynamic = "force-static";

export { default, alt, size, contentType } from "./opengraph-image";
