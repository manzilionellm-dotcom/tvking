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

async function fetchJson(url: string, init?: RequestInit, timeoutMs = 12_000): Promise<WorkerStatus | null> {
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
