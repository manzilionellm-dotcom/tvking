// =========================================================
//  source_pair.js — Code court pour lier le téléphone à la box
// =========================================================
//  La MAC s'affiche sur la télé. Elle ne suffit plus à MODIFIER
//  la source dès que la box a enregistré son secret
//  (X-Device-Secret). Le QR de l'accueil ne peut pas contenir ce
//  secret long : n'importe qui qui photographie l'écran l'aurait
//  pour toujours.
//
//  À la place, la box tire un code COURT (6 signes, sans les
//  lettres qui se confondent) et le déclare au Worker avec son
//  secret. Le QR pointe vers /mon-espace#mac=…&pair=CODE. Le
//  téléphone renvoie ce code dans l'en-tête X-Source-Pair. Le
//  code expire (20 minutes). Ce n'est pas une adresse de flux :
//  seulement la page déjà hébergée par le Worker.
//
//  Garder l'alphabet, la longueur et le délai identiques à
//  lib/features/tv/domain/home_source_link.dart.
// =========================================================

export const SOURCE_PAIR_HEADER = 'X-Source-Pair';
export const SOURCE_PAIR_TTL_MS = 20 * 60 * 1000;
export const SOURCE_PAIR_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const SOURCE_PAIR_LENGTH = 6;

const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/;
const PAIR_RX = new RegExp(
  `^[${SOURCE_PAIR_ALPHABET}]{${SOURCE_PAIR_LENGTH}}$`,
);

/// Code affichable et saisissable, sans 0/O ni 1/I.
export function sourcePairCodeOk(code) {
  return PAIR_RX.test(String(code || '').trim().toUpperCase());
}

/// Le code stocké est-il encore dans sa fenêtre ?
export function pairCodeStillValid(expiresAt, nowMs) {
  const exp = Number(expiresAt);
  const now = Number(nowMs);
  if (!Number.isFinite(exp) || !Number.isFinite(now)) return false;
  return exp > now;
}

/// Écriture « Mon espace ».
///   - box pas encore enrôlée : la MAC suffit (logiciel déjà installé)
///   - box enrôlée : secret de la box, OU code court encore valable
export function pairWriteAllowed({ enrolled, secretOk, pairOk }) {
  if (!enrolled) return true;
  return !!(secretOk || pairOk);
}

/// Lien de la page existante. Les « : » de la MAC restent en clair :
/// le Worker rejette une MAC encodée en %3A dans le chemin, et le
/// fragment suit la même habitude. `null` si la base ou la MAC
/// n'est pas utilisable. Aucune adresse de flux n'est ajoutée.
export function homeSourcePortalUrl(baseUrl, mac, pair) {
  const base = String(baseUrl || '').trim().replace(/\/+$/, '');
  if (!/^https?:\/\//i.test(base)) return null;
  const MAC = String(mac || '').trim().toUpperCase();
  if (!MAC_RX.test(MAC)) return null;
  let hash = `#mac=${MAC}`;
  const code = String(pair || '').trim().toUpperCase();
  if (code && sourcePairCodeOk(code)) hash += `&pair=${code}`;
  return `${base}/mon-espace${hash}`;
}

/// Lit #mac= et #pair= comme le fait la page (portal.js).
export function portalHashParts(hash) {
  const text = String(hash || '');
  const macM = text.match(/mac=([^&]+)/i);
  const pairM = text.match(/pair=([^&]+)/i);
  let mac = '';
  let pair = '';
  if (macM) {
    try {
      mac = decodeURIComponent(macM[1]);
    } catch (_) {
      mac = macM[1];
    }
    mac = mac.toUpperCase().replace(/\s+/g, '').replace(/-/g, ':');
  }
  if (pairM) {
    try {
      pair = decodeURIComponent(pairM[1]);
    } catch (_) {
      pair = pairM[1];
    }
    pair = pair.toUpperCase().replace(/\s+/g, '');
  }
  if (!MAC_RX.test(mac)) mac = '';
  if (!sourcePairCodeOk(pair)) pair = '';
  return { mac, pair };
}
