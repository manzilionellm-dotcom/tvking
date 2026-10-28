import { API_BASE, boxesApi, getToken, type BoxLiveRow } from './api';
import { deliveryConfirmed, type DeliveryOrder } from './deliveryStatus';

export interface PanelEvent extends Partial<DeliveryOrder> {
  type: string;
  mac?: string;
  online?: boolean;
  last_seen_at?: number;
  at?: number;
  elapsed_ms?: number | null;
}
type Listener = (event: PanelEvent) => void;
const listeners = new Set<Listener>();
let socket: WebSocket | undefined;
let retry: ReturnType<typeof setTimeout> | undefined;
let heartbeat: ReturnType<typeof setInterval> | undefined;
let attempt = 0;
let generation = 0;
let lastSeen = 0;

function emit(event: PanelEvent) { for (const listener of listeners) listener(event); }
export function panelConnected() { return socket?.readyState === WebSocket.OPEN; }

async function connect(gen: number) {
  if (!listeners.size || gen !== generation || !getToken()) return;
  try {
    const { ticket } = await boxesApi.ticket();
    if (!listeners.size || gen !== generation) return;
    const url = new URL(`${API_BASE}/api/v1/rt/ws`, window.location.origin);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    url.searchParams.set('ticket', ticket);
    const ws = new WebSocket(url);
    socket = ws;
    const opening = setTimeout(() => ws.close(), 8000);
    ws.onopen = () => {
      clearTimeout(opening);
      if (gen !== generation || !listeners.size) { ws.close(); return; }
      lastSeen = Date.now();
      emit({ type: 'connection', online: true });
      ws.send(JSON.stringify({ type: 'hello' }));
      heartbeat = setInterval(() => {
        if (Date.now() - lastSeen > 25_000) { ws.close(); return; }
        if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'hello' }));
      }, 10_000);
    };
    ws.onmessage = message => {
      if (gen !== generation) return;
      try {
        const event: PanelEvent = JSON.parse(message.data);
        lastSeen = Date.now();
        attempt = 0;
        if (event.type !== 'hello') emit(event);
      } catch { /* Une trame invalide ne modifie jamais l'affichage. */ }
    };
    ws.onerror = () => ws.close();
    ws.onclose = () => {
      clearTimeout(opening);
      if (gen !== generation) return;
      clearInterval(heartbeat);
      socket = undefined;
      emit({ type: 'connection', online: false });
      schedule(gen);
    };
  } catch { schedule(gen); }
}

function schedule(gen: number) {
  if (gen !== generation || !listeners.size) return;
  clearTimeout(retry);
  const delay = Math.min(30_000, 1000 * 2 ** Math.min(attempt++, 5));
  retry = setTimeout(() => { void connect(gen); }, delay);
}

export function subscribePanel(listener: Listener) {
  listeners.add(listener);
  if (listeners.size === 1) { attempt = 0; void connect(++generation); }
  return () => {
    listeners.delete(listener);
    if (listeners.size) return;
    generation++;
    clearTimeout(retry);
    clearInterval(heartbeat);
    socket?.close();
    socket = undefined;
  };
}

export function mergeLiveEvent(previous: Record<string, BoxLiveRow>, event: PanelEvent): Record<string, BoxLiveRow> {
  const mac = event.mac;
  if (!mac) return previous;
  const row: BoxLiveRow = previous[mac] || { id: mac, mac, online: false, last_seen_at: 0,
    pending: [], last_applied: null, fleet_pending: [], fleet_last_applied: null };
  if (event.type === 'presence') return { ...previous, [mac]: { ...row,
    online: event.online === true, last_seen_at: event.last_seen_at || event.at || 0 } };
  if (!event.order_id) return previous;
  const pending = row.pending.filter(order => order.id !== event.order_id);
  const order = { id: event.order_id, kind: event.kind || event.type,
    created_at: event.at, applied_at: event.applied_srv || undefined };
  const applied = event.state === 'applied' && deliveryConfirmed(event as DeliveryOrder);
  if (event.type !== 'receipt' || (!applied && !['failed', 'expired'].includes(event.state || ''))) pending.push(order);
  return { ...previous, [mac]: { ...row, pending,
    last_applied: applied ? order : row.last_applied } };
}
