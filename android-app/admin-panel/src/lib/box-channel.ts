// Canal du panel. Un seul WebSocket pour tout le panneau.
// S'il ne s'ouvre pas (Worker ancien, interrupteur de repli,
// réseau), les pages continuent de sonder toutes les 2 s.
// Le JWT sert uniquement à demander un ticket HTTP à usage unique.
// Un Worker sans endpoint ticket conserve le sondage de secours.

import { getToken } from '@/lib/api';
import { isChannelHello, parseChannelEvent, type ChannelEvent } from '@/lib/box-channel-core';
import { panelPollInterval, REALTIME_POLL_LEGACY } from '@/lib/live-sync';

type Listener = (event: ChannelEvent) => void;
type StateListener = (up: boolean) => void;

let socket: WebSocket | null = null;
let up = false;
let attempt = 0;
let timer = 0;
let stopped = true;
let sessionToken: string | null = null;
let pendingTicket: { controller: AbortController; timeout: number } | null = null;
let heartbeatTimer = 0;
let socketDeadline = 0;
const TICKET_TIMEOUT_MS = 10_000;
const TICKET_LIFETIME_MS = 60_000;
const HELLO_TIMEOUT_MS = 10_000;
// Le Worker ferme les connexions sans hello depuis 35 s.
const HEARTBEAT_MS = 15_000;
const HEARTBEAT_TIMEOUT_MS = 30_000;
// Chaque ouverture de session possède ses callbacks et son arrêt. Une
// fermeture réseau peut arriver après la connexion de la session suivante.
let generation = 0;
const listeners = new Set<Listener>();
const states = new Set<StateListener>();

function apiBase(): string {
  const configured = "https://seven-motion-backend.manzilionel-lm.workers.dev";
  if (configured) return configured.replace(/\/$/, '');
  if (typeof window !== 'undefined') return window.location.origin;
  return '';
}

function wsUrl(ticket: string): string {
  const http = apiBase();
  const ws = http.replace(/^http/i, 'ws');
  const url = new URL(`${ws}/api/v1/rt/ws`);
  url.searchParams.set('ticket', ticket);
  return url.toString();
}

function setUp(next: boolean) {
  if (up === next) return;
  up = next;
  for (const fn of states) fn(up);
}

export function panelChannelUp(): boolean {
  return up && sessionToken === getToken() && !REALTIME_POLL_LEGACY;
}

export function onPanelChannel(fn: Listener): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function onPanelChannelState(fn: StateListener): () => void {
  states.add(fn);
  return () => states.delete(fn);
}

function isActive(owner: number): boolean {
  return !stopped && owner === generation;
}

function ownsSession(owner: number): boolean {
  return isActive(owner) && !!sessionToken && sessionToken === getToken();
}

function cancelTicket() {
  const pending = pendingTicket;
  pendingTicket = null;
  if (!pending) return;
  window.clearTimeout(pending.timeout);
  pending.controller.abort();
}

function clearSocketTimers() {
  window.clearInterval(heartbeatTimer);
  window.clearTimeout(socketDeadline);
  heartbeatTimer = 0;
  socketDeadline = 0;
}

function schedule(owner: number, delay?: number) {
  if (!ownsSession(owner)) return;
  const wait = delay ?? Math.min(30_000, 1000 * (2 ** Math.min(attempt, 5)));
  window.clearTimeout(timer);
  timer = window.setTimeout(() => { timer = 0; void connect(owner); }, wait);
}

async function connect(owner: number) {
  if (!ownsSession(owner) || REALTIME_POLL_LEGACY || socket || pendingTicket) return;
  const token = sessionToken!;
  const requestedAt = Date.now();
  const pending = { controller: new AbortController(), timeout: 0 };
  pendingTicket = pending;
  pending.timeout = window.setTimeout(() => pending.controller.abort(), TICKET_TIMEOUT_MS);
  const isCurrentRequest = () => ownsSession(owner) && pendingTicket === pending;
  let ticket: string;
  try {
    // Même proxy HTTP que les pages du panel, même Worker que wsUrl.
    // Aucun cache ni redirection de la requête Authorization.
    const response = await fetch('/api/v1/rt/ticket', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      signal: pending.controller.signal,
    });
    if (!isCurrentRequest()) return;
    if (pending.controller.signal.aborted) throw new Error('ticket_timeout');
    // Un refus de la session attend le prochain login. Jamais de
    // tentative avec le JWT en URL, quel que soit le statut HTTP.
    if (response.status === 401 || response.status === 403) return;
    if (response.status === 404 || response.status === 405) {
      schedule(owner, 30_000);
      return;
    }
    if (!response.ok || response.redirected) throw new Error('ticket_unavailable');
    const result: unknown = await response.json();
    if (!isCurrentRequest()) return;
    if (pending.controller.signal.aborted || Date.now() - requestedAt >= TICKET_LIFETIME_MS) {
      throw new Error('ticket_expired');
    }
    const value = result && typeof result === 'object'
      ? (result as Record<string, unknown>).ticket : null;
    if (typeof value !== 'string' || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value)) {
      throw new Error('ticket_invalid');
    }
    ticket = value;
  } catch {
    if (isCurrentRequest()) {
      attempt += 1;
      schedule(owner);
    }
    return;
  } finally {
    window.clearTimeout(pending.timeout);
    if (pendingTicket === pending) pendingTicket = null;
  }
  if (!ownsSession(owner)) return;
  openSocket(owner, ticket);
}

function openSocket(owner: number, ticket: string) {
  let opened: WebSocket;
  try {
    // Le ticket n'est jamais mémorisé : chaque reconnexion le renouvelle.
    opened = new WebSocket(wsUrl(ticket));
  } catch {
    attempt += 1;
    schedule(owner);
    return;
  }
  socket = opened;
  let ready = false;
  let greeted = false;
  const ownsSocket = () => isActive(owner) && socket === opened;
  const isCurrent = () => ownsSocket() && ownsSession(owner);
  const disconnect = (close = true) => {
    if (!ownsSocket()) return;
    socket = null;
    clearSocketTimers();
    setUp(false);
    if (close) { try { opened.close(); } catch { /* déjà fermé */ } }
    attempt += 1;
    schedule(owner);
  };
  const sayHello = () => {
    if (!isCurrent()) { disconnect(); return; }
    try { opened.send(JSON.stringify({ v: 1, type: 'hello' })); }
    catch { disconnect(); }
  };
  socketDeadline = window.setTimeout(() => disconnect(), HELLO_TIMEOUT_MS);
  opened.onopen = () => {
    if (!isCurrent()) { disconnect(); return; }
    ready = true;
    sayHello();
  };
  opened.onmessage = (ev) => {
    if (!isCurrent()) { disconnect(); return; }
    if (!ready || typeof ev.data !== 'string') return;
    if (isChannelHello(ev.data)) {
      greeted = true;
      attempt = 0;
      window.clearTimeout(socketDeadline);
      socketDeadline = window.setTimeout(() => disconnect(), HEARTBEAT_TIMEOUT_MS);
      if (!heartbeatTimer) heartbeatTimer = window.setInterval(sayHello, HEARTBEAT_MS);
      setUp(true);
      return;
    }
    if (!greeted) return;
    const event = parseChannelEvent(ev.data);
    if (!event) return;
    for (const fn of listeners) fn(event);
  };
  opened.onclose = () => disconnect(false);
  opened.onerror = () => disconnect();
}

/// À appeler une fois la session ouverte. Le retour ferme le socket
/// (déconnexion).
export function startPanelChannel(): () => void {
  const owner = ++generation;
  stopped = false;
  sessionToken = getToken();
  attempt = 0;
  window.clearTimeout(timer);
  cancelTicket();
  clearSocketTimers();
  const previous = socket;
  socket = null;
  setUp(false);
  try { previous?.close(); } catch { /* déjà fermé */ }
  void connect(owner);
  return () => {
    // Le cleanup d'un ancien effet React ne doit jamais arrêter la
    // session créée entre-temps par un nouvel appel à startPanelChannel.
    if (!isActive(owner)) return;
    stopped = true;
    sessionToken = null;
    window.clearTimeout(timer);
    cancelTicket();
    clearSocketTimers();
    const closing = socket;
    socket = null;
    setUp(false);
    try { closing?.close(); } catch { /* déjà fermé */ }
  };
}

/// Lecture immédiate sur événement, et sondage de secours.
/// Le délai s'allonge quand le canal est ouvert.
export function bindPanelRefresh(refresh: () => void): () => void {
  let timerId = 0;
  let dead = false;
  const arm = () => {
    if (dead) return;
    window.clearTimeout(timerId);
    timerId = window.setTimeout(() => {
      refresh();
      arm();
    }, panelPollInterval(panelChannelUp()));
  };
  arm();
  const offEvent = onPanelChannel(() => refresh());
  const offState = onPanelChannelState((connected) => {
    arm();
    // Le canal ne rejoue pas ici les événements manqués. Dès la première
    // ouverture et chaque reconnexion, on relit donc l'état du serveur.
    if (connected && !dead) refresh();
  });
  return () => {
    dead = true;
    window.clearTimeout(timerId);
    offEvent();
    offState();
  };
}
