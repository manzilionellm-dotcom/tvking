// L'URL est ouverte par l'utilisateur, jamais exécutée ni chargée ici.
export function validAnnouncementUrl(body) {
  if (body?.url == null || body.url === '') return true;
  if (typeof body.url !== 'string') return false;
  const raw = body.url.trim();
  if (!raw) return true;
  if (raw.length > 300 || !/^https?:\/\/[^/\\\s?#]/i.test(raw) || /[\\\u0000-\u0020\u007f]/.test(raw)) return false;
  try {
    const url = new URL(raw);
    return ['http:', 'https:'].includes(url.protocol) && !!url.hostname && !url.username && !url.password;
  } catch { return false; }
}
