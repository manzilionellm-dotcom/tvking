// =========================================================
//  clientRow.ts — Ce qu'on lit d'un coup d'œil sur une ligne client
// =========================================================
//  Demande du 13/11/2026 : dans la liste, voir pour chaque client son
//  pays (drapeau), l'appareil qu'il utilise, la version de l'app et
//  depuis quand on ne l'a plus vu. Logique pure (pas de React) : testée
//  dans clientRow.test.ts.
//
//  Rien n'est inventé : un pays inconnu reste vide, un modèle inconnu
//  donne un libellé prudent (« Android TV » / « Mobile »).
// =========================================================

/// Au-delà de 15 minutes sans signe de vie, la box n'est plus « en ligne »
/// (même fenêtre que l'écran « En ligne » du panel).
export const ONLINE_WINDOW_MS = 15 * 60 * 1000;

/// Code pays ISO2 propre (« se » → « SE »), ou '' si ce n'en est pas un.
export function countryCode(raw: unknown): string {
  const c = typeof raw === 'string' ? raw.trim().toUpperCase() : '';
  // « XX » et « T1 » sont des codes techniques de Cloudflare (inconnu, Tor).
  return /^[A-Z]{2}$/.test(c) && c !== 'XX' ? c : '';
}

/// Nom du pays en français (« SE » → « Suède »). Code seul si le
/// navigateur ne connaît pas le nom ; '' si le code est vide.
export function countryName(raw: unknown): string {
  const code = countryCode(raw);
  if (!code) return '';
  try {
    const name = new Intl.DisplayNames(['fr'], { type: 'region' }).of(code);
    return name && name !== code ? name : code;
  } catch {
    return code;
  }
}

export interface DeviceKindInput {
  platform?: string | null;
  device_model?: string | null;
}

/// Famille d'appareil, d'après le modèle remonté par l'app.
/// Ordre : du plus précis au plus général.
export function deviceKind(d: DeviceKindInput): string {
  const m = (d.device_model || '').toLowerCase();
  if (/\baft[a-z0-9]+|fire\s*tv|firetv|amazon/.test(m)) return 'Fire TV';
  if (/shield|nvidia/.test(m)) return 'NVIDIA Shield';
  if (/chromecast|google\s*tv|\bgtv\b/.test(m)) return 'Google TV';
  if (/mi\s*box|mibox|mitv|xiaomi\s*tv/.test(m)) return 'Xiaomi TV';
  if (/formuler/.test(m)) return 'Formuler';
  if (/bravia|sony/.test(m) && d.platform !== 'mobile') return 'Sony TV';
  if (/windows/.test(m)) return 'Windows';
  if (d.platform === 'tv' || /\btv\b|adt-|homatics|dune|box/.test(m)) return 'Android TV';
  if (d.platform === 'mobile') return 'Mobile';
  return m ? 'Android' : '';
}

export interface SeenInfo {
  /// Vrai si la box a donné signe de vie dans les 15 dernières minutes.
  online: boolean;
  /// « En ligne », « il y a 3 h », « il y a 5 j », « il y a 2 mois », « — ».
  label: string;
}

function toMs(value: unknown): number | null {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  // Les vieilles lignes sont en secondes.
  return n < 1e11 ? n * 1000 : n;
}

/// Dernière fois que la box a contacté le serveur, en clair.
export function seenInfo(lastSeen: unknown, now = Date.now()): SeenInfo {
  const ts = toMs(lastSeen);
  if (ts == null) return { online: false, label: '—' };
  const diff = Math.max(0, now - ts);
  if (diff < ONLINE_WINDOW_MS) return { online: true, label: 'En ligne' };
  const min = Math.floor(diff / 60000);
  if (min < 60) return { online: false, label: `il y a ${min} min` };
  const h = Math.floor(min / 60);
  if (h < 24) return { online: false, label: `il y a ${h} h` };
  const d = Math.floor(h / 24);
  if (d < 60) return { online: false, label: `il y a ${d} j` };
  const mo = Math.floor(d / 30);
  if (mo < 24) return { online: false, label: `il y a ${mo} mois` };
  return { online: false, label: `il y a ${Math.floor(d / 365)} ans` };
}

/// Version de l'app à afficher : le nom (« 117 ») si l'app l'envoie,
/// sinon le numéro de build, sinon ''.
export function appVersionLabel(version: unknown, build: unknown): string {
  const v = typeof version === 'string' ? version.trim() : '';
  if (v) return `v${v}`;
  const b = typeof build === 'number' ? build : Number(build);
  return Number.isFinite(b) && b > 0 ? `build ${b}` : '';
}
