// Une seule cible pour les écritures HTTP et les tickets temps réel.
// En production, /api est relayé par Vercel vers ce même domaine.
export const PRODUCTION_BACKEND = 'https://api.zuno8k.com';
export const API_BASE = ((import.meta.env.VITE_API_BASE as string | undefined) || '').replace(/\/+$/, '');

export function realtimeBackend(): string {
  if (API_BASE) return API_BASE;
  // Vite relaie aussi les WebSockets vers le Worker local : un test local
  // ne doit jamais ouvrir par inadvertance une socket de production.
  if (import.meta.env.DEV && typeof window !== 'undefined') return window.location.origin;
  return PRODUCTION_BACKEND;
}
