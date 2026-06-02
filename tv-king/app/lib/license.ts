// =========================================================
//  license.ts — Licence / essai (branchement au panel 7 MOTION)
// =========================================================
//  NOVA+ est une app web : elle n'a pas de vraie adresse MAC. On
//  génère donc, comme les apps mobiles du projet, un MAC VIRTUEL stable
//  par installation (format MK:XX:XX:XX:XX:XX), persisté en localStorage.
//
//  Au démarrage l'app fait un « heartbeat » sur le même backend que les
//  apps mobiles (Worker Cloudflare). Le serveur :
//    - enregistre AUTOMATIQUEMENT l'appareil (il apparaît dans le panel
//      admin, onglet Clients / Appareils) ;
//    - démarre un essai de 7 jours ;
//    - renvoie l'état (essai restant, payé, gelé, banni…).
//  Après l'essai, l'app se bloque jusqu'à activation par crédits depuis
//  le panel (par MAC). C'est de l'infrastructure de LICENCE / ACCÈS —
//  aucun flux ni identifiant de contenu n'est distribué ici.
//
//  Repli hors-ligne : si le serveur est injoignable, on NE bloque PAS
//  (on ne punit pas un utilisateur légitime pour une coupure réseau).
// =========================================================

/// Base de l'API de licence. Endpoint PUBLIC (pas de secret). Configurable
/// via NEXT_PUBLIC_LICENSE_BASE (ex. pour pointer un autre domaine).
export const LICENSE_BASE: string =
  process.env.NEXT_PUBLIC_LICENSE_BASE || "https://99999.7themotion.com";

const MAC_KEY = "tvking.mac.v1";

/// Format attendu par le backend : MK suivi de 5 octets hex (majuscules).
export const MAC_REGEX = /^MK(?::[0-9A-F]{2}){5}$/;

/// Génère un MAC virtuel aléatoire MK:XX:XX:XX:XX:XX (hex majuscules).
export function randomMac(): string {
  const bytes = new Uint8Array(5);
  if (typeof crypto !== "undefined" && crypto.getRandomValues) {
    crypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < bytes.length; i++)
      bytes[i] = Math.floor(Math.random() * 256);
  }
  const hex = Array.from(bytes, (b) =>
    b.toString(16).padStart(2, "0").toUpperCase(),
  );
  return `MK:${hex.join(":")}`;
}

/// Récupère le MAC de cette installation, en le créant au besoin.
export function getOrCreateMac(): string {
  if (typeof window === "undefined") return randomMac();
  try {
    const existing = localStorage.getItem(MAC_KEY);
    if (existing && MAC_REGEX.test(existing)) return existing;
    const mac = randomMac();
    localStorage.setItem(MAC_KEY, mac);
    return mac;
  } catch {
    return randomMac();
  }
}

/// État de licence normalisé (camelCase) côté app.
export interface LicenseStatus {
  exists: boolean;
  status: string; // 'active' | 'frozen' | 'banned' | 'unknown'
  paid: boolean;
  daysLeft: number;
  expired: boolean;
  frozen: boolean;
  banned: boolean;
  trialUntil: number;
  /// false si le serveur n'a pas pu être joint (→ on ne bloque pas).
  reachable: boolean;
}

/// État « injoignable » : sert de repli hors-ligne (fail-open).
export const UNKNOWN_STATUS: LicenseStatus = {
  exists: false,
  status: "unknown",
  paid: false,
  daysLeft: 0,
  expired: false,
  frozen: false,
  banned: false,
  trialUntil: 0,
  reachable: false,
};

/// Convertit la réponse JSON du serveur (snake_case) en LicenseStatus.
export function parseStatus(
  json: Record<string, unknown> | null,
  reachable: boolean,
): LicenseStatus {
  if (!json) return { ...UNKNOWN_STATUS, reachable };
  const num = (v: unknown) => (typeof v === "number" ? v : 0);
  return {
    exists: json.exists === true,
    status: typeof json.status === "string" ? json.status : "unknown",
    paid: json.paid === true,
    daysLeft: num(json.days_left),
    expired: json.expired === true,
    frozen: json.frozen === true,
    banned: json.banned === true,
    trialUntil: num(json.trial_until),
    reachable,
  };
}

/// Faut-il afficher l'écran bloquant ? (banni / gelé / essai fini non payé).
/// Hors-ligne (reachable=false) → on ne bloque jamais.
export function shouldBlock(s: LicenseStatus): boolean {
  if (!s.reachable) return false;
  return s.banned || s.frozen || (s.expired && !s.paid);
}

export type GateReason = "banned" | "frozen" | "trial-expired" | null;

/// Raison du blocage (pour choisir le bon message), ou null si pas bloqué.
export function gateReason(s: LicenseStatus): GateReason {
  if (!shouldBlock(s)) return null;
  if (s.banned) return "banned";
  if (s.frozen) return "frozen";
  return "trial-expired";
}

/// True si l'app est en période d'essai en cours (ni payée, ni bloquée).
export function isOnTrial(s: LicenseStatus): boolean {
  return s.reachable && s.exists && !s.paid && !shouldBlock(s);
}

/// Heartbeat : enregistre/rafraîchit l'appareil et renvoie son état.
/// Ne jette jamais — en cas d'échec réseau, renvoie l'état « injoignable ».
export async function heartbeat(mac: string): Promise<LicenseStatus> {
  try {
    const resp = await fetch(`${LICENSE_BASE}/api/heartbeat`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ mac }),
    });
    if (!resp.ok) return { ...UNKNOWN_STATUS, reachable: true };
    const json = (await resp.json()) as Record<string, unknown>;
    return parseStatus(json, true);
  } catch {
    return { ...UNKNOWN_STATUS, reachable: false };
  }
}

/// Lecture seule de l'état (sans toucher au last_seen). Utilisé par le
/// bouton « J'ai payé — rafraîchir » de l'écran bloquant.
export async function fetchStatus(mac: string): Promise<LicenseStatus> {
  try {
    const resp = await fetch(
      `${LICENSE_BASE}/api/status/${encodeURIComponent(mac)}`,
      { headers: { Accept: "application/json" } },
    );
    if (!resp.ok) return { ...UNKNOWN_STATUS, reachable: true };
    const json = (await resp.json()) as Record<string, unknown>;
    return parseStatus(json, true);
  } catch {
    return { ...UNKNOWN_STATUS, reachable: false };
  }
}
