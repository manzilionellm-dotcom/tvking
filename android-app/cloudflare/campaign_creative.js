// Schéma fermé : une création est une recette visuelle, jamais du HTML,
// du JavaScript ou un modèle distant exécuté dans le téléphone.
export function normalizeCreative(value) {
  if (value == null || value === '') return null;
  if (typeof value !== 'object' || Array.isArray(value)) throw new Error('Création 3D invalide.');
  const allowed = ['version', 'template', 'palette', 'image_url', 'badge', 'motion', 'duration_seconds'];
  if (Object.keys(value).some(k => !allowed.includes(k)) || value.version !== 1 ||
      !['orbit', 'prism', 'spotlight'].includes(value.template) ||
      !['ember', 'ice', 'gold'].includes(value.palette) ||
      !['gentle', 'still'].includes(value.motion) ||
      ![6, 8, 10].includes(value.duration_seconds)) throw new Error('Modèle 3D invalide.');
  if (typeof value.badge !== 'string' || value.badge.trim().length > 24 ||
      typeof value.image_url !== 'string' || value.image_url.length > 300) throw new Error('Texte ou image 3D invalide.');
  const image = value.image_url.trim();
  if (image) {
    let url;
    try { url = new URL(image); } catch { throw new Error('Image HTTPS invalide.'); }
    if (url.protocol !== 'https:' || url.username || url.password || url.hash ||
        /^(localhost|127\.|0\.|10\.|192\.168\.|169\.254\.|\[)/i.test(url.hostname) ||
        /^172\.(1[6-9]|2\d|3[01])\./.test(url.hostname) ||
        [...url.searchParams.keys()].some(k => /password|passwd|username|token|secret|api.?key|authorization/i.test(k))) {
      throw new Error('Utilise une image HTTPS publique sans identifiants.');
    }
  }
  return { version: 1, template: value.template, palette: value.palette, image_url: image,
    badge: value.badge.trim(), motion: value.motion, duration_seconds: value.duration_seconds };
}

export function readCreative(raw) {
  if (!raw) return null;
  try { return normalizeCreative(JSON.parse(raw)); } catch { return null; }
}

export function presentCampaign(row) {
  const { creative_json, ...item } = row;
  return { ...item, creative: readCreative(creative_json) };
}
