"use client";

/*
 * Activation à distance de NOVA+.
 *
 * Chaque appareil possède un identifiant stable — son "MAC virtuel" (device.ts).
 * Au lancement, l'app le signale au Worker (POST /api/heartbeat) qui ouvre un
 * essai gratuit puis renvoie l'état courant ; ensuite tu actives l'appareil à
 * distance depuis le panel admin et l'écran de NOVA+ se déverrouille tout seul
 * (l'app re-vérifie en continu tant qu'elle est bloquée).
 *
 * Le backend est le Worker Cloudflare DÉJÀ déployé (mêmes endpoints publics que
 * l'app Flutter 7 MOTION) — aucune modification serveur n'est requise :
 *   POST /api/heartbeat   { mac }   → { paid, expired, frozen, banned, days_left, … }
 *   GET  /api/status/:mac            → idem
 *
 * Modèle choisi : essai gratuit (durée fixée côté serveur) puis BLOCAGE tant que
 * l'admin n'a pas activé l'appareil.
 *
 * Réseau indisponible : on retombe sur le dernier état connu (cache local) ; si
 * on n'a jamais réussi à joindre le serveur, on laisse passer (fail-open) pour
 * ne jamais bloquer l'app sur une simple coupure — l'IPTV exige de toute façon
 * une connexion, donc un appareil hors-ligne ne diffuse rien.
 */

import { useSyncExternalStore } from "react";
import { getDeviceMac } from "./device";
import { getConfig, setConfig, type SourceConfig } from "./client-source";

// Domaine du Worker (surchargeable au build via NEXT_PUBLIC_NOVA_LICENSE_API).
const API_BASE = (process.env.NEXT_PUBLIC_NOVA_LICENSE_API ?? "https://99999.7themotion.com").replace(
  /\/+$/,
  "",
);
// NEXT_PUBLIC_NOVA_ACTIVATION=off → désactive complètement la porte (dev/démo).
const GATE_ENABLED = API_BASE.length > 0 && process.env.NEXT_PUBLIC_NOVA_ACTIVATION !== "off";

const K_CACHE = "nova:activation";
const POLL_MS = 30_000; // re-vérifie vite tant que BLOQUÉ (activation quasi-immédiate)
const REFRESH_MS = 5 * 60_000; // re-vérifie de loin quand débloqué (capte gel/ban/expiration)

export type ActivationState =
  | "active" // payé / licence active
  | "trial" // essai en cours
  | "expired" // essai terminé, pas payé
  | "frozen" // gelé par l'admin (rappel de paiement)
  | "banned" // banni
  | "unknown"; // serveur jamais joint

export interface Activation {
  mac: string;
  state: ActivationState;
  locked: boolean;
  paid: boolean;
  daysLeft: number;
  trialUntil: number;
  checkedAt: number;
  offline: boolean;
}

export type GatePhase = "checking" | "unlocked" | "locked";

let current: Activation | null = null;
let inflight: Promise<void> | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;

const listeners = new Set<() => void>();
function emit() {
  for (const l of listeners) l();
}

/* ------------------------------------------------------------------ *
 * Pont natif (Android TV) : requêtes API DIRECTES côté natif.
 *
 * Le proxy WebView (shouldInterceptRequest) n'a pas accès au corps des POST :
 * le heartbeat `{mac, app}` y perdait son corps → serveur sans MAC → appareil
 * jamais enregistré (absent du panel). On route donc l'API d'activation par
 * window.NovaNative.apiFetch (asynchrone, corps préservé). En navigateur/dev
 * (pas de pont), on retombe sur window.fetch.
 * ------------------------------------------------------------------ */
interface NovaNativeApi {
  apiFetch?: (method: string, url: string, body: string | null, callbackId: string) => void;
}
const apiPending = new Map<string, (text: string) => void>();
let apiSeq = 0;

function getNativeApiFetch(): NonNullable<NovaNativeApi["apiFetch"]> | null {
  if (typeof window === "undefined") return null;
  const n = (window as unknown as { NovaNative?: NovaNativeApi }).NovaNative;
  return n && typeof n.apiFetch === "function" ? n.apiFetch.bind(n) : null;
}

if (typeof window !== "undefined") {
  (window as unknown as { __novaApiResolve: (id: string, text: string) => void }).__novaApiResolve = (
    id,
    text,
  ) => {
    const r = apiPending.get(id);
    if (r) r(text);
  };
}

/** Appel API via le pont natif (corps POST garanti). Résout "" sur échec/timeout. */
function nativeApiFetch(method: string, url: string, body: string | null, timeoutMs: number): Promise<string> {
  const apiFetch = getNativeApiFetch();
  if (!apiFetch) return Promise.resolve("");
  return new Promise((resolve) => {
    const id = `a${++apiSeq}`;
    let done = false;
    const finish = (t: string) => {
      if (done) return;
      done = true;
      apiPending.delete(id);
      clearTimeout(to);
      resolve(t);
    };
    const to = setTimeout(() => finish(""), timeoutMs);
    apiPending.set(id, finish);
    try {
      apiFetch(method, url, body, id);
    } catch {
      finish("");
    }
  });
}

function readCache(): Activation | null {
  try {
    const raw = window.localStorage.getItem(K_CACHE);
    return raw ? (JSON.parse(raw) as Activation) : null;
  } catch {
    return null;
  }
}
function writeCache(a: Activation) {
  try {
    window.localStorage.setItem(K_CACHE, JSON.stringify(a));
  } catch {
    /* quota / mode privé — sans gravité */
  }
}

/** Forme (partielle) de la réponse du Worker — on ne lit que ce qui décide. */
interface WorkerStatus {
  paid?: boolean;
  expired?: boolean;
  frozen?: boolean;
  banned?: boolean;
  days_left?: number;
  trial_until?: number;
}

function normalize(mac: string, d: WorkerStatus, offline: boolean): Activation {
  const banned = !!d.banned;
  const frozen = !!d.frozen;
  const paid = !!d.paid;
  const expired = !!d.expired;
  const state: ActivationState = banned
    ? "banned"
    : frozen
      ? "frozen"
      : expired
        ? "expired"
        : paid
          ? "active"
          : "trial";
  return {
    mac,
    state,
    // Le serveur ne marque jamais `expired` quand `paid` est vrai, mais on reste
    // défensif : un appareil payé n'est jamais verrouillé.
    locked: !paid && (banned || frozen || expired),
    paid,
    daysLeft: Math.max(0, Number(d.days_left) || 0),
    trialUntil: Number(d.trial_until) || 0,
    checkedAt: Date.now(),
    offline,
  };
}

/* ------------------------------------------------------------------ *
 * Source POUSSÉE par le panel (« source du client, chargée automatiquement »).
 *
 * En activant un appareil, l'admin lui assigne une source (M3U ou Xtream) :
 * l'app doit la CHARGER toute seule — le client ne tape rien sur sa TV. La
 * réponse de l'API de licence porte donc (selon le backend) des champs de
 * source dont les NOMS exacts varient. On les lit de façon défensive (objet
 * `source` OU champs à plat ; type m3u/xtream) et on mémorise les clés reçues
 * pour diagnostic (DeviceCard) afin de confirmer le format réel.
 * ------------------------------------------------------------------ */
let lastDiagKeys: string[] = [];
let lastAppliedSource = "";
let lastSourceRaw = ""; // valeur brute du champ `source` renvoyé (diagnostic à l'écran)
// Empreinte de la dernière source POUSSÉE par le serveur. Persistée pour ne
// réappliquer la source que lorsque le PANEL en change — et ainsi ne jamais
// écraser, à chaque poll, une source que l'utilisateur aurait saisie à la main.
const K_SERVER_SOURCE = "nova:serverSource";

/** Diagnostic : clés renvoyées + valeur brute de `source` + source appliquée. */
export function getSourceDiag(): { keys: string[]; applied: string; raw: string } {
  return { keys: lastDiagKeys, applied: lastAppliedSource, raw: lastSourceRaw };
}

/** Xtream (serveur + identifiants) → URLs get.php (HLS) + xmltv.php. */
function xtreamToUrls(server: string, user: string, pass: string): SourceConfig {
  const base = server.replace(/\/+$/, "");
  const u = encodeURIComponent(user);
  const p = encodeURIComponent(pass);
  return {
    playlistUrl: `${base}/get.php?username=${u}&password=${p}&type=m3u_plus&output=m3u8`,
    epgUrl: `${base}/xmltv.php?username=${u}&password=${p}`,
  };
}

/** Extrait une source chargeable de la réponse serveur, sinon null. */
function extractSource(d: WorkerStatus): SourceConfig | null {
  const root = d as unknown as Record<string, unknown>;
  const srcObj =
    root.source && typeof root.source === "object" ? (root.source as Record<string, unknown>) : root;
  const get = (...keys: string[]): string => {
    for (const k of keys) {
      const v = srcObj[k] ?? root[k];
      if (typeof v === "string" && v.trim()) return v.trim();
    }
    return "";
  };

  const type = get("type", "source_type").toLowerCase();
  const server = get("server", "host", "xtream_server", "dns");
  const user = get("username", "user", "xtream_username", "login");
  const pass = get("password", "pass", "xtream_password");
  if ((type === "xtream" || (server && user && pass)) && server && user && pass) {
    return xtreamToUrls(server, user, pass);
  }

  // `source` peut aussi être DIRECTEMENT l'URL M3U (ex. { source: "http://.../get.php..." }).
  const m3u = get(
    "url", "m3u_url", "m3u", "playlist_url", "playlistUrl", "source_url", "playlist", "source",
  );
  const epg = get("epg_url", "epgUrl", "xmltv_url", "xmltv", "epg");
  if (/^https?:\/\//i.test(m3u)) return { playlistUrl: m3u, epgUrl: epg };

  // Sinon (ex. source = "d1", une simple étiquette non résoluble côté app) : rien
  // à charger. On retourne null → l'app garde la saisie manuelle en secours et le
  // diagnostic « Mon appareil » montre la valeur reçue.
  return null;
}

/** Applique la source poussée par le serveur (si présente) — charge la playlist. */
function applyServerSource(d: WorkerStatus, act: Activation): void {
  try {
    const root = (d as unknown as Record<string, unknown>) ?? {};
    lastDiagKeys = Object.keys(root);
    const s = root.source;
    lastSourceRaw = s == null ? "" : typeof s === "string" ? s : JSON.stringify(s);
  } catch {
    lastDiagKeys = [];
    lastSourceRaw = "";
  }
  if (act.state === "banned") return; // appareil bloqué : on ne charge rien

  const src = extractSource(d);
  if (!src || !/^https?:\/\//i.test(src.playlistUrl)) {
    // « Aucune » source poussée : on n'efface rien — la saisie manuelle reste le
    // secours. On oublie juste l'empreinte serveur pour qu'une source repoussée
    // plus tard (même identique) soit bien (ré)appliquée.
    lastAppliedSource = "";
    try {
      window.localStorage.removeItem(K_SERVER_SOURCE);
    } catch {
      /* sans gravité */
    }
    return;
  }
  lastAppliedSource = src.playlistUrl;

  // On n'agit que si le SERVEUR a changé de source depuis la dernière fois
  // (empreinte persistée) : anti-boucle ET respect d'un choix manuel ultérieur.
  // Tant que le panel pousse la même source, on laisse l'utilisateur libre de la
  // remplacer dans Réglages ; seul un CHANGEMENT côté panel reprend la main.
  const key = `${src.playlistUrl}\n${src.epgUrl || ""}`;
  let prev = "";
  try {
    prev = window.localStorage.getItem(K_SERVER_SOURCE) || "";
  } catch {
    /* mode privé — on retombe sur la comparaison de config ci-dessous */
  }
  if (key === prev) return;
  try {
    window.localStorage.setItem(K_SERVER_SOURCE, key);
  } catch {
    /* sans gravité */
  }

  // Déjà exactement en place → inutile de relancer un chargement.
  const cur = getConfig();
  if (cur.playlistUrl === src.playlistUrl && cur.epgUrl === (src.epgUrl || "")) return;

  setConfig({ playlistUrl: src.playlistUrl, epgUrl: src.epgUrl || "" });
}

async function fetchJson(url: string, init?: RequestInit, timeoutMs = 12_000): Promise<WorkerStatus | null> {
  // Android TV : pont natif (corps POST préservé). Sinon (dev) : window.fetch.
  if (getNativeApiFetch()) {
    const method = (init?.method ?? "GET").toUpperCase();
    const body = typeof init?.body === "string" ? init.body : null;
    const txt = await nativeApiFetch(method, url, body, timeoutMs + 3_000);
    if (!txt) return null;
    try {
      return JSON.parse(txt) as WorkerStatus;
    } catch {
      return null;
    }
  }

  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...init, signal: ctrl.signal });
    if (!res.ok) return null;
    return (await res.json()) as WorkerStatus;
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

/** Interroge le Worker et met à jour l'état d'activation (puis reprogramme). */
export async function refreshActivation(): Promise<void> {
  if (typeof window === "undefined" || !GATE_ENABLED) return;
  if (inflight) return inflight;
  inflight = (async () => {
    const mac = getDeviceMac();
    // 1) heartbeat : ouvre l'essai au 1er lancement ET renvoie l'état courant.
    // 2) repli sur /status si le POST échoue (ex. préflight bloqué).
    let data = await fetchJson(`${API_BASE}/api/heartbeat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mac, app: "nova" }),
    });
    // MAC envoyé brut : ses ':' sont des caractères de path valides et le Worker
    // découpe pathname par '/' (encoder casserait MAC_RX côté serveur).
    if (!data) data = await fetchJson(`${API_BASE}/api/status/${mac}`);

    if (data) {
      current = normalize(mac, data, false);
      writeCache(current);
      // Source poussée par le panel → chargement automatique (zéro saisie).
      applyServerSource(data, current);
    } else {
      // Hors-ligne : on garde le dernier état connu ; sinon on laisse passer.
      const cached = readCache();
      current = cached
        ? { ...cached, mac, offline: true }
        : {
            mac,
            state: "unknown",
            locked: false,
            paid: false,
            daysLeft: 0,
            trialUntil: 0,
            checkedAt: Date.now(),
            offline: true,
          };
    }
    emit();
  })().finally(() => {
    inflight = null;
    scheduleNext();
  });
  return inflight;
}

function scheduleNext() {
  if (typeof window === "undefined" || !GATE_ENABLED) return;
  if (timer) clearTimeout(timer);
  const delay = current?.locked ? POLL_MS : REFRESH_MS;
  timer = setTimeout(() => void refreshActivation(), delay);
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

function phaseOf(a: Activation | null): GatePhase {
  if (!GATE_ENABLED) return "unlocked";
  if (!a) return "checking";
  return a.locked ? "locked" : "unlocked";
}

/** État d'activation réactif ; déclenche la 1re vérification à la 1re lecture. */
export function useActivation(): { phase: GatePhase; activation: Activation | null } {
  const a = useSyncExternalStore(
    subscribe,
    () => current,
    () => null,
  );
  if (typeof window !== "undefined" && GATE_ENABLED && current === null && !inflight) {
    void refreshActivation();
  }
  return { phase: phaseOf(a), activation: a };
}

export function activationEnabled(): boolean {
  return GATE_ENABLED;
}
