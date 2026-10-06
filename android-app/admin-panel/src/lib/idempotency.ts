// =========================================================
//  idempotency.ts — Clé d'idempotence des écritures critiques
// =========================================================
//  Une clé par INTENTION (clic sur « Activer »). Le Worker garde la
//  réponse de la première exécution 24 h : la même clé renvoyée rejoue
//  cette réponse au lieu de réactiver et de redébiter.
//
//  Règle de vie de la clé (testée par idempotency.test.ts) :
//    • réponse reçue (succès, ou refus métier 4xx) → clé abandonnée, le
//      clic suivant est une nouvelle intention ;
//    • pas de réponse (coupure réseau, status 0) ou erreur serveur (5xx)
//      → la requête a PU s'exécuter : on garde la clé, le prochain envoi
//      rejoue au lieu de doubler.
//  Module pur : aucune dépendance au navigateur ni à `import.meta`.
// =========================================================

export function newIdempotencyKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `k-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
}

/// Garde-t-on la même clé pour la prochaine tentative après [e] ?
/// Toute erreur sans statut HTTP lisible est traitée comme une coupure.
export function keepIdempotencyKeyAfter(e: unknown): boolean {
  const status = typeof e === 'object' && e !== null && 'status' in e
    ? Number((e as { status: unknown }).status)
    : NaN;
  if (!Number.isFinite(status)) return true;
  return status === 0 || status >= 500;
}
