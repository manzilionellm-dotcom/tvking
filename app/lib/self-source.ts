/*
 * « Activer ma liste » — le client ajoute SON abonnement Xtream / M3U à SA box.
 *
 * Le site parle au panel Zuno (API publique /api/self-source/:mac, déjà en
 * production) via son relais serveur app/api/self-source/[mac] (les réponses
 * du panel ne sont pas lisibles directement par un navigateur : pas d'en-tête
 * CORS sur les réponses). Le panel REFUSE toute
 * MAC sans licence active (« not_entitled ») : impossible d'écrire sur une box
 * qui n'est pas cliente. La box reçoit la liste d'elle-même (vérification du
 * panel chaque minute dans l'app).
 *
 * Logique pure (testée) : normalisation de la MAC, corps de requête, lecture
 * des réponses. Le mot de passe n'est JAMAIS relu : le panel ne le renvoie pas.
 */

export const PANEL_API = "https://app.7themotion.com";

/** Format exact attendu par le panel : « MK » + 5 octets hexadécimaux. */
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/;

/**
 * Tolère la saisie approximative : minuscules, espaces, tirets, préfixe « MK »
 * oublié, séparateurs absents (« mk807860074f »). Renvoie null si impossible.
 */
export function normalizeMac(input: string): string | null {
  let s = input.trim().toUpperCase().replace(/[\s-]/g, ":");
  if (s.startsWith("MK")) s = s.slice(2);
  const hex = s.replace(/:/g, "");
  if (!/^[0-9A-F]{10}$/.test(hex)) return null;
  const mac = "MK:" + hex.match(/.{2}/g)!.join(":");
  return MAC_RX.test(mac) ? mac : null;
}

export type SourceForm =
  | { type: "xtream"; label: string; server: string; username: string; password: string }
  | { type: "m3u"; label: string; url: string };

const isHttp = (u: string) => /^https?:\/\/\S+$/i.test(u.trim());

/** Corps JSON du POST, ou null si un champ manque / une adresse est invalide. */
export function buildBody(f: SourceForm): Record<string, string> | null {
  const label = f.label.trim();
  if (f.type === "xtream") {
    const server = f.server.trim().replace(/\/+$/, "");
    if (!isHttp(server) || !f.username.trim() || !f.password.trim()) return null;
    return { type: "xtream", label, server_url: server, username: f.username.trim(), password: f.password.trim() };
  }
  if (!isHttp(f.url)) return null;
  return { type: "m3u", label, m3u_url: f.url.trim() };
}

export type ApiOutcome =
  | "ok"
  | "notEntitled"
  | "mac"
  | "fields"
  | "tooMany"
  | "generic";

/** Réponse du panel → issue affichable (traduite par la page). */
export function outcomeOf(status: number, body: unknown): ApiOutcome {
  const b = (body ?? {}) as Record<string, unknown>;
  if (b.ok === true) return "ok";
  if (b.error === "not_entitled" || b.blocked === "no_license") return "notEntitled";
  if (b.reason === "too_many" || status === 409) return "tooMany";
  if (status === 400) {
    const e = String(b.error ?? b.message ?? "");
    return /mac/i.test(e) ? "mac" : "fields";
  }
  return "generic";
}

export type PublicItem = {
  id: string | null;
  locked: boolean;
  type: "xtream" | "m3u";
  label: string;
  server_url: string | null;
  username: string | null;
  m3u_url: string | null;
};

/** Liste des sources d'une box (GET) — tolère les variantes de réponse du panel. */
export function itemsOf(body: unknown): PublicItem[] {
  const b = (body ?? {}) as Record<string, unknown>;
  const raw = Array.isArray(b.items) ? b.items : Array.isArray(b.playlists) ? b.playlists : [];
  return raw
    .filter((x): x is Record<string, unknown> => typeof x === "object" && x !== null)
    .map((x) => ({
      id: typeof x.id === "string" ? x.id : null,
      locked: x.locked === true || (x.origin !== undefined && x.origin !== "self"),
      type: x.type === "xtream" ? "xtream" : "m3u",
      label: typeof x.label === "string" ? x.label : "",
      server_url: typeof x.server_url === "string" ? x.server_url : null,
      username: typeof x.username === "string" ? x.username : null,
      m3u_url: typeof x.m3u_url === "string" ? x.m3u_url : null,
    }));
}
