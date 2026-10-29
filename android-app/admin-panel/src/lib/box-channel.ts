// Canal du panel. Un seul WebSocket pour tout le panneau.
// S'il ne s'ouvre pas (Worker ancien, interrupteur de repli,
// réseau), les pages continuent de sonder toutes les 2 s.
// Le jeton est dans la query : le navigateur ne peut pas poser
// Authorization sur un WebSocket. On ne l'écrit nulle part.

import { getToken } from '@/lib/api';
import { parseChannelEvent, type ChannelEvent } from '@/lib/box-channel-core';
import { panelPollInterval, REALTIME_POLL_LEGACY } from '@/lib/live-sync';

type Listener = (event: ChannelEvent) => void;
type StateListener = (up: boolean) => void;

let socket: WebSocket | null = null;
let up = false;
let attempt = 0;
let timer = 0;
let stopped = true;
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

function wsUrl(token: string): string {
  const http = apiBase();
  const ws = http.replace(/^http/i, 'ws');
  const url = new URL(`${ws}/api/v1/rt/ws`);
  url.searchParams.set('token', token);
  return url.toString();
}

function setUp(next: boolean) {
  if (up === next) return;
  up = next;
  for (const fn of states) fn(up);
}

export function panelChannelUp(): boolean {
  return up && !REALTIME_POLL_LEGACY;
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

function schedule(owner: number) {
  if (!isActive(owner)) return;
  const wait = Math.min(30_000, 1000 * (2 ** Math.min(attempt, 5)));
  window.clearTimeout(timer);
  timer = window.setTimeout(() => connect(owner), wait);
}

function connect(owner: number) {
  if (!isActive(owner) || REALTIME_POLL_LEGACY) return;
  const token = getToken();
  if (!token) return;
  let opened: WebSocket;
  try {
    opened = new WebSocket(wsUrl(token));
  } catch {
    attempt += 1;
    schedule(owner);
    return;
  }
  socket = opened;
  const isCurrent = () => isActive(owner) && socket === opened;
  opened.onopen = () => {
    if (!isCurrent()) return;
    attempt = 0;
    setUp(true);
  };
  opened.onmessage = (ev) => {
    if (!isCurrent()) return;
    const event = parseChannelEvent(String(ev.data ?? ''));
    if (!event) return;
    for (const fn of listeners) fn(event);
  };
  opened.onclose = () => {
    if (!isCurrent()) return;
    socket = null;
    setUp(false);
    attempt += 1;
    schedule(owner);
  };
  opened.onerror = () => {
    if (!isCurrent()) return;
    try { opened.close(); } catch { /* déjà fermé */ }
  };
}

/// À appeler une fois la session ouverte. Le retour ferme le socket
/// (déconnexion).
export function startPanelChannel(): () => void {
  const owner = ++generation;
  stopped = false;
  attempt = 0;
  window.clearTimeout(timer);
  const previous = socket;
  socket = null;
  setUp(false);
  try { previous?.close(); } catch { /* déjà fermé */ }
  connect(owner);
  return () => {
    // Le cleanup d'un ancien effet React ne doit jamais arrêter la
    // session créée entre-temps par un nouvel appel à startPanelChannel.
    if (!isActive(owner)) return;
    stopped = true;
    window.clearTimeout(timer);
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
