/*
 * Persisted acceptance of the Conditions d'utilisation (CGU), versioned: if the
 * terms change, TERMS_VERSION is bumped and every user must accept again.
 *
 * Pure logic (testable in node); only load/save touch localStorage,
 * defensively — a corrupt or foreign value never throws, it just means
 * "not accepted yet".
 */

export const CONSENT_KEY = "tvking.v1.consent";

/** Bump when the terms text changes materially — forces re-acceptance. */
export const TERMS_VERSION = 1;

export interface Consent {
  v: 1;
  /** Version of the terms that was accepted. */
  terms: number;
  /** Acceptance timestamp (ms epoch). */
  at: number;
}

/** Defensive parse: anything unexpected → null (treated as "not accepted"). */
export function parseConsent(raw: string | null): Consent | null {
  if (!raw) return null;
  try {
    const data: unknown = JSON.parse(raw);
    if (typeof data !== "object" || data === null) return null;
    const c = data as Record<string, unknown>;
    if (c.v !== 1) return null;
    if (typeof c.terms !== "number" || !Number.isFinite(c.terms)) return null;
    if (typeof c.at !== "number" || !Number.isFinite(c.at)) return null;
    return { v: 1, terms: c.terms, at: c.at };
  } catch {
    return null;
  }
}

/** Accepted only when the stored acceptance covers the current terms version. */
export function isAccepted(consent: Consent | null, version: number = TERMS_VERSION): boolean {
  return consent !== null && consent.terms >= version;
}

/** Build the acceptance record for the current terms (pure). */
export function accept(now: number, version: number = TERMS_VERSION): Consent {
  return { v: 1, terms: version, at: now };
}

/* ------------------------- browser-side thin wrappers ---------------------- */

export function loadConsent(): Consent | null {
  if (typeof window === "undefined") return null;
  try {
    return parseConsent(window.localStorage.getItem(CONSENT_KEY));
  } catch {
    return null;
  }
}

export function saveConsent(consent: Consent): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(CONSENT_KEY, JSON.stringify(consent));
  } catch {
    // Storage unavailable — the gate will simply show again next launch.
  }
}
