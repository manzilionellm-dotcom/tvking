/**
 * Canonical host = metadataBase (app/layout.tsx) = sitemap host. Every indexable page
 * declares its own absolute canonical so none inherits another page's URL.
 */
export const CANONICAL_BASE = "https://zuno.7themotion.com";

export function canonicalUrl(path: string): string {
  return path === "/" ? `${CANONICAL_BASE}/` : `${CANONICAL_BASE}${path}`;
}

export function canonicalFor(path: string) {
  return { alternates: { canonical: canonicalUrl(path) } } as const;
}
