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
const listeners = new Set<Listener>();
const states = new Set<StateListener>();

function apiBase(): string {
  const configured = (import.meta.env.VITE_API_BASE as string | undefined) || '';
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

function schedule() {
  if (stopped) return;
  const wait = Math.min(30_000, 1000 * (2 ** Math.min(attempt, 5)));
  window.clearTimeout(timer);
  timer = window.setTimeout(connect, wait);
}

function connect() {
  if (stopped || REALTIME_POLL_LEGACY) return;
  const token = getToken();
  if (!token) return;
  let opened: WebSocket;
  try {
    opened = new WebSocket(wsUrl(token));
  } catch {
    attempt += 1;
    schedule();
    return;
  }
  socket = opened;
  opened.onopen = () => {
    attempt = 0;
    setUp(true);
  };
  opened.onmessage = (ev) => {
    const event = parseChannelEvent(String(ev.data ?? ''));
    if (!event) return;
    for (const fn of listeners) fn(event);
  };
  opened.onclose = () => {
    if (socket === opened) socket = null;
    setUp(false);
    attempt += 1;
    schedule();
  };
  opened.onerror = () => {
    try { opened.close(); } catch { /* déjà fermé */ }
  };
}

/// À appeler une fois la session ouverte. Le retour ferme le socket
/// (déconnexion).
export function startPanelChannel(): () => void {
  stopped = false;
  attempt = 0;
  connect();
  return () => {
    stopped = true;
    window.clearTimeout(timer);
    setUp(false);
    try { socket?.close(); } catch { /* déjà fermé */ }
    socket = null;
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
  const offState = onPanelChannelState(() => arm());
  return () => {
    dead = true;
    window.clearTimeout(timerId);
    offEvent();
    offState();
  };
}
