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

// ---------------------------------------------------------
//  Défauts de saisie VUS en production (5–6 octobre 2026)
// ---------------------------------------------------------
//  • lien collé deux fois : « …output=tshttp://fournisseur.example… » (liste « 6 ») ;
//  • typographie du clavier du téléphone dans le mot de passe :
//    apostrophe courbe ’ (%E2%80%99) et accent flottant (%CC%81) — le
//    fournisseur refusait la liste, la box attendait 90 s pour rien ;
//  • espace ou caractère de contrôle au milieu de l'adresse.
//  Refusée AVANT d'être écrite : la dernière liste saine reste en place.
const TYPOGRAPHIC_RX = /[‘’‚‛“”«»̀-ͯ –—]/;
const TYPOGRAPHIC_ENC_RX = /%E2%80%9[89ABCD]|%CC%8[0-9A-F]|%CD%[8-9A-F][0-9A-F]|%C2%A0|%E2%80%9[34]/i;

/// `null` si la valeur est saine, sinon un message court (pur, testé).
export function sourceTextProblem(value, label) {
  const s = String(value || '');
  if (/[\s\u0000-\u001f]/.test(s.trim())) return `${label} contient un espace ou un caractère invisible`;
  if (TYPOGRAPHIC_RX.test(s) || TYPOGRAPHIC_ENC_RX.test(s)) {
    return `${label} contient un caractère de clavier de téléphone (’ ou accent) : retape-le à la main`;
  }
  return null;
}

/// Contrôles en plus de httpUrlError pour une adresse de liste.
export function sourceUrlProblem(value, label) {
  const s = String(value || '').trim();
  const base = httpUrlError(s, label);
  if (base) return base;
  if ((s.match(/https?:\/\//gi) || []).length > 1) return `${label} : lien collé deux fois`;
  return sourceTextProblem(s, label);
}
