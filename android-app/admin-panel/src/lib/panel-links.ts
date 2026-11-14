// Une notification ne choisit jamais une origine ou un écran arbitraire.
// Les codes d'appareil ne servent qu'à relire une fiche via l'API authentifiée.
export interface PanelTarget { path: '/devices' | '/blackbox'; mac: string; url: string }

export function readPanelTarget(value: unknown, origin: string): PanelTarget | null {
  if (typeof value !== 'string' || value.length > 512 || /[\\\u0000-\u0020\u007f]/.test(value)) return null;
  try {
    const base = new URL(origin);
    const url = new URL(value, base);
    if (!['https:', 'http:'].includes(url.protocol) || url.origin !== base.origin
        || url.username || url.password || url.hash
        || (url.pathname !== '/devices' && url.pathname !== '/blackbox')) return null;
    const keys = Array.from(url.searchParams.keys());
    if (keys.length !== 1 || keys[0] !== 'mac') return null;
    const mac = (url.searchParams.get('mac') || '').toUpperCase();
    if (!/^(?:MK(?::[0-9A-F]{2}){5}|[0-9A-F]{2}(?::[0-9A-F]{2}){5})$/.test(mac)) return null;
    return { path: url.pathname, mac, url: `${url.pathname}?mac=${encodeURIComponent(mac)}` };
  } catch { return null; }
}

/** Destination conservée dans l'état du routeur, sans stocker de jeton. */
export function loginDestination(value: unknown, origin: string): string {
  if (value === '/' || value === '/account') return value;
  return readPanelTarget(value, origin)?.url || '/';
}
