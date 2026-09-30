// =========================================================
//  sessionPolicy.ts — Décisions de session, SANS réseau
// =========================================================
//  Ce module ne parle pas à l'API et ne touche pas à localStorage.
//  Il répond seulement à : « est-ce que CETTE réponse doit effacer
//  le jeton ? » et « est-ce que CE jeton a dépassé la moitié de sa
//  vie ? ». api.ts et App.tsx s'en servent pour que la règle soit
//  testable sans navigateur.
//
//  Règle :
//    - 401 « jeton invalide / expiré » (ou 401 authentifié qui n'est
//      pas un contrôle de mot de passe) → on déconnecte.
//    - 401 bad_credentials / bad_current → l'identifiant est faux,
//      la session éventuelle reste.
//    - réseau, timeout, 5xx, 429 → on GARDE le jeton et on réessaie.
// =========================================================

/// Toutes les 30 minutes le panel regarde si le jeton a passé la
/// moitié de sa vie. Ce n'est pas la durée du jeton (30 j / 7 j,
/// décidée par le Worker) : juste la fréquence du contrôle.
export const SESSION_REFRESH_POLL_MS = 30 * 60 * 1000;

/// Codes 401 qui parlent du mot de passe saisi, pas du jeton.
/// Les confondre avec une session morte déconnecterait quelqu'un
/// qui s'est trompé en se connectant ou en changeant son mot de passe.
const CREDENTIAL_CODES = new Set(['bad_credentials', 'bad_current']);

/// true seulement pour un vrai rejet de session.
export function isSessionRejection(status: number, code: string): boolean {
  if (status !== 401) return false;
  if (CREDENTIAL_CODES.has(code)) return false;
  return true;
}

export type BootDecision = 'logged_out' | 'keep';

/// Au démarrage, après /auth/me (ou /auth/refresh).
/// `status === null` = la requête n'a pas abouti (réseau, timeout).
export function decideBootOutcome(input: {
  status: number | null;
  code: string | null;
}): BootDecision {
  if (
    input.status != null
    && isSessionRejection(input.status, input.code || '')
  ) {
    return 'logged_out';
  }
  return 'keep';
}

export type HttpAuthResult =
  | { kind: 'network' }
  | { kind: 'timeout' }
  | { kind: 'http'; status: number; code: string; noAuth?: boolean };

/// Jeton à conserver après une réponse. `null` = on l'efface.
/// Une erreur réseau ou un timeout renvoie le jeton tel quel.
export function nextTokenAfterResponse(
  current: string | null,
  result: HttpAuthResult,
): string | null {
  if (result.kind === 'network' || result.kind === 'timeout') return current;
  // Le login n'envoie pas le jeton : un 401 « mauvais mot de passe »
  // ne doit pas non plus effacer une session déjà ouverte.
  if (result.noAuth) return current;
  if (isSessionRejection(result.status, result.code)) return null;
  return current;
}

/// AbortSignal.timeout lève un DOMException TimeoutError.
/// Un fetch annulé lève AbortError. Les deux ne sont PAS un 401.
export function isTimeoutError(e: unknown): boolean {
  if (!e || typeof e !== 'object') return false;
  const name = (e as { name?: string }).name;
  return name === 'TimeoutError' || name === 'AbortError';
}

/// Décode le segment payload d'un JWT (base64url) sans vérifier la
/// signature : la vérification se fait côté Worker. Ici on ne lit
/// que iat / exp pour savoir s'il faut demander un renouvellement.
function readJwtTimes(token: string): { iat: number; exp: number } | null {
  try {
    const part = token.split('.')[1];
    if (!part) return null;
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/');
    const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
    const json = JSON.parse(atob(padded)) as { iat?: unknown; exp?: unknown };
    if (typeof json.iat !== 'number' || typeof json.exp !== 'number') return null;
    return { iat: json.iat, exp: json.exp };
  } catch {
    return null;
  }
}

/// true quand au moins la moitié de la durée (exp - iat) est passée.
/// Un jeton illisible n'est PAS renouvelé ici : s'il est vraiment
/// invalide, le prochain appel authentifié renverra 401 et là,
/// seulement là, on déconnecte.
export function tokenNeedsRefresh(
  token: string,
  nowSec: number = Math.floor(Date.now() / 1000),
): boolean {
  const t = readJwtTimes(token);
  if (!t) return false;
  const life = t.exp - t.iat;
  if (life <= 0) return false;
  return nowSec >= t.iat + life / 2;
}
