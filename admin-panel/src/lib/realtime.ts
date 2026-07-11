// =========================================================
//  realtime.ts — Client WebSocket temps réel du panel
// =========================================================
//  Couche « en plus » du polling (cf. docs/REALTIME-PROTOCOL.md §7) :
//    - connexion après login, rôles admin uniquement (les revendeurs
//      n'ouvrent JAMAIS le socket — le serveur les refuse de toute façon)
//    - reconnexion avec backoff 3 → 6 → 15 → 30 s (plafond) + jitter ±20 %
//    - keepalive : frame texte littérale 'ping' toutes les 45 s
//    - mini pub/sub (onRt) + carte des appareils en direct
//      (snapshot + deltas device_online / device_offline / watching)
//    - envoi de commandes ciblées (sendCmd) + attente d'ack (waitForAck)
//
//  Tout est FAIL-OPEN : si le WS est indisponible, les pages retombent
//  sur leur comportement HTTP existant (polling / fetch one-shot).
// =========================================================

import { useEffect, useRef, useState } from 'react';
import { API_BASE, getToken, getCurrentUser, isOwnerRole, type RtInfo } from '@/lib/api';

// ---------------------------------------------------------
//  Types des évènements Hub → Panel (spec §3)
// ---------------------------------------------------------

/// Appareil connecté au hub (forme du snapshot et de device_online).
export interface RtDevice {
  mac: string;
  platform?: string;      // 'mobile' | 'tv'
  country?: string;       // ISO2 (Cloudflare)
  channel?: string;       // chaîne en cours ('' = rien)
  appVersion?: string;
  model?: string;
  connectedAt?: number;
  lastSeen?: number;
}

/// Confirmation qu'un appareil a appliqué une commande (sync/message).
/// latencyMs peut être null : le hub perd sa carte sentAt en mémoire
/// quand il hiberne — il envoie alors null plutôt qu'une valeur fausse.
export interface AckEvent {
  id: string;
  mac: string;
  ok: boolean;
  latencyMs: number | null;
  error?: string;
}

/// Une mutation a eu lieu ailleurs (autre onglet / autre admin).
export interface ChangedEvent {
  scope: string;
  mac?: string;
}

export type RtEventType =
  | 'snapshot'
  | 'device_online'
  | 'device_offline'
  | 'watching'
  | 'ack'
  | 'changed'
  | 'bye';

export type RtState = 'connected' | 'connecting' | 'offline';

// ---------------------------------------------------------
//  État module (pas de lib d'état : tout vit ici, comme le
//  cache utilisateur de api.ts)
// ---------------------------------------------------------

let ws: WebSocket | null = null;
let state: RtState = 'offline';
let wantConnected = false;            // true entre rtConnect() et rtDisconnect()
let attempt = 0;                      // index dans BACKOFF_MS
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let pingTimer: ReturnType<typeof setInterval> | null = null;

/// Paliers de reconnexion (ms) — plafond 30 s (spec §7).
const BACKOFF_MS = [3000, 6000, 15000, 30000];
const PING_INTERVAL_MS = 45000;

// Abonnés par type d'évènement.
const handlers = new Map<RtEventType, Set<(e: any) => void>>();
// Abonnés au changement d'état de connexion.
const stateListeners = new Set<(s: RtState) => void>();
// Carte des appareils en direct (mac → device) + abonnés.
const liveDevices = new Map<string, RtDevice>();
const liveListeners = new Set<() => void>();
let liveArrayCache: RtDevice[] = [];
// Attentes d'ack en cours (id de commande → resolve).
const ackWaiters = new Map<string, (a: AckEvent) => void>();
// Coalescence des frames « watching » (voir notifyLiveCoalesced).
const WATCHING_COALESCE_MS = 300;
let watchingFlushTimer: ReturnType<typeof setTimeout> | null = null;

function setState(s: RtState) {
  if (state === s) return;
  state = s;
  stateListeners.forEach((fn) => { try { fn(s); } catch { /* noop */ } });
}

function notifyLive() {
  // Un flush immédiat rend le flush différé inutile.
  if (watchingFlushTimer) { clearTimeout(watchingFlushTimer); watchingFlushTimer = null; }
  liveArrayCache = Array.from(liveDevices.values());
  liveListeners.forEach((fn) => { try { fn(); } catch { /* noop */ } });
}

/// Notification différée (~300 ms) des abonnés live — utilisée pour les
/// frames « watching » (changement de chaîne seul) : sur une flotte
/// occupée elles arrivent plusieurs fois par seconde, et re-rendre les
/// pages à ce rythme est inutile. Les évènements structurels (snapshot /
/// device_online / device_offline) restent notifiés immédiatement.
function notifyLiveCoalesced() {
  if (watchingFlushTimer) return; // un flush est déjà programmé
  watchingFlushTimer = setTimeout(() => {
    watchingFlushTimer = null;
    notifyLive();
  }, WATCHING_COALESCE_MS);
}

function dispatch(type: RtEventType, event: any) {
  const set = handlers.get(type);
  if (!set) return;
  set.forEach((fn) => { try { fn(event); } catch { /* noop */ } });
}

/// URL du WebSocket : dérivée de API_BASE ('' = même origin), https → wss.
function wsUrl(token: string): string {
  const base = API_BASE || window.location.origin;
  return (
    base.replace(/^http/i, 'ws') +
    `/api/v1/rt/ws?token=${encodeURIComponent(token)}`
  );
}

function clearTimers() {
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
}

/// Programme une tentative de reconnexion avec backoff + jitter ±20 %.
function scheduleReconnect() {
  if (!wantConnected || reconnectTimer) return;
  const base = BACKOFF_MS[Math.min(attempt, BACKOFF_MS.length - 1)];
  const jitter = base * 0.2 * (Math.random() * 2 - 1);
  const delay = Math.max(1000, Math.round(base + jitter));
  attempt += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    openSocket();
  }, delay);
}

function handleMessage(raw: string) {
  // Frames non-JSON ('pong' du keepalive…) : ignorées silencieusement.
  let msg: any = null;
  try { msg = JSON.parse(raw); } catch { return; }
  if (!msg || typeof msg.type !== 'string') return;

  switch (msg.type as RtEventType) {
    case 'snapshot': {
      // État complet à la connexion : on reconstruit la carte.
      liveDevices.clear();
      const devices: RtDevice[] = Array.isArray(msg.devices) ? msg.devices : [];
      for (const d of devices) {
        if (d && d.mac) liveDevices.set(d.mac, d);
      }
      notifyLive();
      break;
    }
    case 'device_online': {
      const d: RtDevice | undefined = msg.device;
      if (d && d.mac) {
        liveDevices.set(d.mac, d);
        notifyLive();
      }
      break;
    }
    case 'device_offline': {
      if (msg.mac && liveDevices.delete(msg.mac)) notifyLive();
      break;
    }
    case 'watching': {
      const d = msg.mac ? liveDevices.get(msg.mac) : undefined;
      if (d) {
        d.channel = msg.channel ?? '';
        d.lastSeen = Date.now();
        // Coalescé : seuls les abonnés à la LISTE live sont différés —
        // les handlers onRt('watching') restent notifiés immédiatement
        // via le dispatch() en fin de fonction.
        notifyLiveCoalesced();
      }
      break;
    }
    case 'ack': {
      // Réveille l'éventuel waitForAck() correspondant.
      const waiter = msg.id ? ackWaiters.get(msg.id) : undefined;
      if (waiter) {
        ackWaiters.delete(msg.id);
        waiter(msg as AckEvent);
      }
      break;
    }
    case 'bye': {
      // Le hub nous congédie (remplacé…) : ne PAS reconnecter tout de
      // suite — on force le backoff au plafond (spec §3).
      attempt = BACKOFF_MS.length - 1;
      break;
    }
    default:
      break;
  }
  dispatch(msg.type, msg);
}

function openSocket() {
  if (!wantConnected) return;
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;
  // Le token est relu à CHAQUE tentative (il peut avoir été renouvelé).
  const token = getToken();
  if (!token) { setState('offline'); return; }

  setState('connecting');
  let socket: WebSocket;
  try {
    socket = new WebSocket(wsUrl(token));
  } catch {
    setState('offline');
    scheduleReconnect();
    return;
  }
  ws = socket;

  socket.onopen = () => {
    if (ws !== socket) return;
    attempt = 0; // connexion réussie → on repart du 1er palier
    setState('connected');
    // Keepalive NAT : frame texte littérale 'ping' toutes les 45 s.
    if (pingTimer) clearInterval(pingTimer);
    pingTimer = setInterval(() => {
      if (socket.readyState === WebSocket.OPEN) {
        try { socket.send('ping'); } catch { /* noop */ }
      }
    }, PING_INTERVAL_MS);
  };

  socket.onmessage = (ev) => {
    if (ws !== socket) return;
    if (typeof ev.data === 'string') handleMessage(ev.data);
  };

  socket.onclose = () => {
    if (ws !== socket) return;
    ws = null;
    if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
    // La liste live n'est plus fiable une fois déconnecté.
    if (liveDevices.size > 0) { liveDevices.clear(); notifyLive(); }
    setState('offline');
    scheduleReconnect();
  };

  socket.onerror = () => {
    // onclose suivra et gérera la reconnexion.
    try { socket.close(); } catch { /* noop */ }
  };
}

// ---------------------------------------------------------
//  API publique
// ---------------------------------------------------------

/// Ouvre la connexion temps réel. No-op si déjà connecté / en cours, ou
/// si l'utilisateur courant n'est pas un rôle admin (les revendeurs ne
/// doivent jamais tenter la connexion — v1 spec §2).
export function rtConnect(): void {
  const user = getCurrentUser();
  if (!isOwnerRole(user?.role)) return;
  if (wantConnected && ws) return;
  wantConnected = true;
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  openSocket();
}

/// Ferme la connexion (logout / démontage) et stoppe toute reconnexion.
export function rtDisconnect(): void {
  wantConnected = false;
  attempt = 0;
  clearTimers();
  const socket = ws;
  ws = null;
  if (socket) {
    socket.onclose = null;
    try { socket.close(); } catch { /* noop */ }
  }
  if (liveDevices.size > 0) { liveDevices.clear(); notifyLive(); }
  setState('offline');
}

/// État courant de la connexion.
export function getRtState(): RtState {
  return state;
}

/// S'abonner aux changements d'état de connexion. Retourne le désabonnement.
export function onRtState(fn: (s: RtState) => void): () => void {
  stateListeners.add(fn);
  return () => { stateListeners.delete(fn); };
}

/// S'abonner à un type d'évènement Hub → Panel. Retourne le désabonnement.
export function onRt(type: RtEventType, handler: (e: any) => void): () => void {
  let set = handlers.get(type);
  if (!set) { set = new Set(); handlers.set(type, set); }
  set.add(handler);
  return () => { set!.delete(handler); };
}

/// Liste des appareils actuellement connectés au hub (copie stable).
export function getLiveDevices(): RtDevice[] {
  return liveArrayCache;
}

/// S'abonner aux changements de la liste live. Retourne le désabonnement.
export function onLiveDevices(fn: () => void): () => void {
  liveListeners.add(fn);
  return () => { liveListeners.delete(fn); };
}

/// Génère un id court unique pour une commande.
function newCmdId(): string {
  return 'cmd_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}

/// Envoie une commande ciblée à un appareil via le hub (spec §3 Panel → Hub).
/// Retourne l'id généré — à passer à waitForAck() pour la confirmation.
export function sendCmd(
  mac: string,
  action: 'sync' | 'message',
  payload: unknown,
): string {
  const id = newCmdId();
  if (ws && ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify({ type: 'cmd', id, mac, action, payload }));
    } catch { /* fail-open : l'ack n'arrivera juste pas */ }
  }
  return id;
}

/// Attend l'ack d'une commande (id renvoyé par sendCmd, ou champ rt.id
/// d'une réponse de mutation HTTP). Résout null après timeoutMs.
/// Défaut 20 s : un ack de `sync all` n'arrive qu'APRÈS que l'appareil a
/// fini ses ~7 re-fetch HTTP — 5 s expirait à tort sur les TV lentes.
export function waitForAck(id: string, timeoutMs = 20000): Promise<AckEvent | null> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      ackWaiters.delete(id);
      resolve(null);
    }, timeoutMs);
    ackWaiters.set(id, (ack) => {
      clearTimeout(timer);
      resolve(ack);
    });
  });
}

/// Issue d'un push temps réel (champ `rt` des réponses de mutation, spec §4).
export type RtOutcome = {
  status: 'acked' | 'ack_error' | 'timeout' | 'offline' | 'none';
  latencyMs?: number | null;
  error?: string;
};

/// Résout l'issue d'un push instantané — helper PARTAGÉ (Toast +
/// ActivatePage) pour ne pas dupliquer la machine à états :
///   rt absent      → 'none'    (backend sans temps réel — fail-open)
///   delivered = 0  → 'offline' (appliqué à la prochaine connexion)
///   pas d'ack      → 'timeout' (l'appareil appliquera au prochain contact)
///   ack.ok = false → 'ack_error' (+ message d'erreur de l'appareil)
///   sinon          → 'acked' (+ latence, null si le hub l'a perdue)
export async function awaitRtOutcome(rt?: RtInfo | null): Promise<RtOutcome> {
  if (!rt) return { status: 'none' };
  if (rt.delivered < 1) return { status: 'offline' };
  const ack = await waitForAck(rt.id);
  if (!ack) return { status: 'timeout' };
  if (ack.ok === false) return { status: 'ack_error', error: ack.error };
  return { status: 'acked', latencyMs: ack.latencyMs };
}

// ---------------------------------------------------------
//  Hooks React
// ---------------------------------------------------------

/// État de connexion réactif ('connected' | 'connecting' | 'offline').
export function useRtStatus(): RtState {
  const [s, setS] = useState<RtState>(getRtState());
  useEffect(() => {
    setS(getRtState());
    return onRtState(setS);
  }, []);
  return s;
}

/// Abonnement à un type d'évènement (le handler peut changer sans resouscrire).
export function useRtEvent(type: RtEventType, handler: (e: any) => void): void {
  const ref = useRef(handler);
  ref.current = handler;
  useEffect(() => onRt(type, (e) => ref.current(e)), [type]);
}

/// Liste live des appareils connectés + drapeau « WS connecté ».
export function useLiveDevices(): { devices: RtDevice[]; connected: boolean } {
  const [devices, setDevices] = useState<RtDevice[]>(getLiveDevices());
  const status = useRtStatus();
  useEffect(() => {
    setDevices(getLiveDevices());
    return onLiveDevices(() => setDevices(getLiveDevices()));
  }, []);
  return { devices, connected: status === 'connected' };
}
