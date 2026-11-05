// =========================================================
//  banners.js — Bannières image du panel (contrat box)
// =========================================================
//  La box lit déjà GET /api/banners (promo_banner_repository.dart).
//  Tant que cette route répondait 404, l'accueil restait vide.
//  Ici : on ne garde qu'une image https, un id, et les champs
//  déjà lus par PromoBanner.fromJson. Rien d'autre n'est stocké.
// =========================================================

export const BANNERS_KEY = 'banners_json';
export const BANNER_MAX = 20;

function clip(value, max) {
  const s = String(value == null ? '' : value).trim();
  return s.length > max ? s.slice(0, max) : s;
}

function httpsOrEmpty(value) {
  const s = String(value == null ? '' : value).trim();
  if (!s) return '';
  try {
    const url = new URL(s);
    if (url.protocol !== 'https:' || !url.host) return '';
    return s;
  } catch (_) {
    return '';
  }
}

function ms(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.floor(n);
}

/// Liste publiable. Les images qui ne sont pas en https sont écartées :
/// la box les ignore de toute façon. [now] devient le numéro de version
/// quand on enregistre (la box remplace toute la liste).
export function sanitizeBanners(raw, now = 0) {
  let parsed = raw;
  if (typeof raw === 'string') {
    try { parsed = JSON.parse(raw); } catch (_) { parsed = null; }
  }
  const itemsIn = parsed && Array.isArray(parsed.items)
    ? parsed.items
    : (Array.isArray(parsed) ? parsed : []);
  const items = [];
  const seen = new Set();
  let dropped = 0;
  for (const item of itemsIn) {
    if (!item || typeof item !== 'object') { dropped += 1; continue; }
    const id = clip(item.id, 64);
    const image = httpsOrEmpty(item.image);
    if (!id || !image || seen.has(id)) { dropped += 1; continue; }
    seen.add(id);
    const label = clip(item.label, 24);
    items.push({
      id,
      image,
      title: clip(item.title, 80),
      subtitle: clip(item.subtitle, 120),
      label: label || 'Publicité',
      cta: clip(item.cta, 24),
      channel: clip(item.channel, 80),
      url: httpsOrEmpty(item.url),
      from: ms(item.from),
      until: ms(item.until),
      kids: item.kids === true,
    });
    if (items.length >= BANNER_MAX) break;
  }
  const version = Math.floor(Number(now) || 0);
  return { version: version > 0 ? version : 0, items, dropped };
}
