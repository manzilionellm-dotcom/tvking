// Règles d'URL pour une source IPTV (M3U, serveur Xtream, EPG).
// Partagées par le panel (/api/v1/sources) et « Mon espace »
// (/api/self-source) pour qu'un lien invalide soit refusé partout.

export const MAX_SOURCE_URL = 2048;

/// `null` si l'URL est un http(s) avec un hôte, sinon un message court.
export function httpUrlError(value, label) {
  const s = String(value || '').trim();
  if (!s) return `${label} requis`;
  if (s.length > MAX_SOURCE_URL) return `${label} trop long`;
  let u;
  try {
    u = new URL(s);
  } catch (_) {
    return `${label} invalide`;
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') {
    return `${label} doit commencer par http:// ou https://`;
  }
  if (!u.hostname) return `${label} invalide`;
  return null;
}
