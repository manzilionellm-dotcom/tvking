// =========================================================
//  mac.ts — La MAC d'une box, telle que le serveur l'attend
// =========================================================
//  Le serveur range chaque box sous « MK:AD:A6:98:70:6A » (MK + 5 octets).
//  La box affiche désormais seulement « AD:A6:98:70:6A » au client : le
//  revendeur peut donc taper ou coller la MAC SANS « MK: », avec des
//  tirets, des espaces ou rien du tout. On remet le format tout seul.
//
//  Fichier pur (aucune dépendance) : testé par mac.test.ts.
// =========================================================

/// Nombre de chiffres hexadécimaux d'une MAC Zuno (5 octets après « MK »).
const MAC_HEX_DIGITS = 10;

/// MAC d'appareil telle que le serveur l'attend : MK:XX:XX:XX:XX:XX.
///
/// - « AD:A6:98:70:6A », « ad-a6-98-70-6a », « ADA698706A »,
///   « mk:ad:a6:98:70:6a » ou « MK ADA6 9870 6A » → « MK:AD:A6:98:70:6A » ;
/// - une saisie incomplète ou trop longue est rendue en majuscules,
///   sans rien inventer : le contrôle isValidMac la refusera.
export function normalizeMac(raw: string): string {
  const upper = String(raw ?? '').trim().toUpperCase();
  const body = upper.replace(/^MK[:\-\s]?/, '');
  const hex = body.replace(/[^0-9A-F]/g, '');
  // Un caractère qui n'est ni hexadécimal ni séparateur : on ne devine pas.
  const strayChars = body.replace(/[0-9A-F:\-\s.]/g, '');
  if (hex.length !== MAC_HEX_DIGITS || strayChars.length > 0) return upper;
  const pairs = hex.match(/.{2}/g) ?? [];
  return `MK:${pairs.join(':')}`;
}

export function isValidMac(raw: string): boolean {
  return /^MK(?::[0-9A-F]{2}){5}$/.test(normalizeMac(raw));
}

/// Ce que le client voit sur sa box (sans « MK: »).
export function displayMac(mac: string): string {
  const n = normalizeMac(mac);
  return n.startsWith('MK:') && isValidMac(n) ? n.slice(3) : mac;
}
