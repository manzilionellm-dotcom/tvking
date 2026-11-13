// @vitest-environment jsdom
// Régressions du vrai canal : aucun réseau, mais les mêmes callbacks et
// minuteries que le navigateur. close() reste volontairement asynchrone :
// un événement de l'ancienne socket peut arriver après le prochain login.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PANEL_POLL_MS, PANEL_POLL_SLOW_MS } from './live-sync';

const auth = vi.hoisted(() => ({ token: 'jeton-de-test' as string | null }));
vi.mock('@/lib/api', () => ({ getToken: () => auth.token }));

class ControlledWebSocket {
  static instances: ControlledWebSocket[] = [];
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  close = vi.fn();
  replyToHello = true;
  send = vi.fn((raw: string) => {
    if (this.replyToHello && JSON.parse(raw).type === 'hello') this.hello();
  });

  constructor(readonly url: string) {
    ControlledWebSocket.instances.push(this);
  }

  open() { this.onopen?.(); }
  finishClose() { this.onclose?.(); }
  hello() { this.message({ v: 1, type: 'hello' }); }
  message(payload: unknown = {
      v: 1, seq: 1, type: 'source', mac: 'MK:AA:BB:CC:DD:EE', at: 1,
  }) {
    this.onmessage?.({ data: JSON.stringify(payload) });
  }
}

let channel: typeof import('./box-channel');
let cleanups: Array<() => void>;
let fetchTicket: ReturnType<typeof vi.fn>;
let ticketNumber: number;

function ticketResponse() {
  ticketNumber += 1;
  return Response.json({ ticket: `00000000-0000-4000-8000-${String(ticketNumber).padStart(12, '0')}` });
}

function begin() {
  const stop = channel.startPanelChannel();
  cleanups.push(stop);
  return stop;
}

async function settle() { await vi.advanceTimersByTimeAsync(0); }

async function start() {
  const stop = begin();
  await settle();
  return { stop, socket: ControlledWebSocket.instances.at(-1)! };
}

function deferredResponse() {
  let resolve!: (response: Response) => void;
  const promise = new Promise<Response>((done) => { resolve = done; });
  return { promise, resolve };
}

beforeEach(async () => {
  vi.resetModules();
  vi.useFakeTimers();
  vi.stubGlobal('WebSocket', ControlledWebSocket);
  ControlledWebSocket.instances = [];
  auth.token = 'jeton-de-test';
  ticketNumber = 0;
  fetchTicket = vi.fn(async () => ticketResponse());
  vi.stubGlobal('fetch', fetchTicket);
  cleanups = [];
  channel = await import('./box-channel');
});

afterEach(() => {
  for (const cleanup of cleanups.reverse()) cleanup();
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('cycle de vie du canal panel', () => {
  it('une fermeture tardive après stop/start ne perturbe pas la nouvelle socket', async () => {
    const old = await start();
    old.socket.open();
    old.stop();
    const current = await start();
    current.socket.open();

    // Le navigateur livre maintenant la fermeture demandée au logout.
    old.socket.finishClose();
    expect(channel.panelChannelUp()).toBe(true);
    await vi.advanceTimersByTimeAsync(PANEL_POLL_SLOW_MS);
    expect(ControlledWebSocket.instances).toHaveLength(2);
    expect(current.socket.close).not.toHaveBeenCalled();
  });

  it('les ouvertures et messages obsolètes restent sans effet', async () => {
    const received = vi.fn();
    cleanups.push(channel.onPanelChannel(received));
    const old = await start();
    old.stop();
    const current = await start();

    old.socket.open();
    old.socket.message();
    expect(channel.panelChannelUp()).toBe(false);
    expect(received).not.toHaveBeenCalled();

    current.socket.open();
    current.socket.message();
    expect(channel.panelChannelUp()).toBe(true);
    expect(received).toHaveBeenCalledTimes(1);
  });

  it('chaque arrêt appartient à sa session et ne ferme pas une session plus récente', async () => {
    const old = await start();
    old.socket.open();
    const current = await start();
    expect(old.socket.close).toHaveBeenCalledTimes(1);
    current.socket.open();

    old.stop();
    old.stop();
    expect(channel.panelChannelUp()).toBe(true);
    expect(current.socket.close).not.toHaveBeenCalled();

    current.stop();
    expect(channel.panelChannelUp()).toBe(false);
    expect(current.socket.close).toHaveBeenCalledTimes(1);
  });

  it('un arrêt définitif ignore les callbacks tardifs et annule toute reconnexion', async () => {
    const received = vi.fn();
    cleanups.push(channel.onPanelChannel(received));
    const current = await start();
    current.socket.open();
    current.socket.finishClose();
    current.stop();

    current.socket.open();
    current.socket.message();
    current.socket.finishClose();
    await vi.advanceTimersByTimeAsync(PANEL_POLL_SLOW_MS);
    expect(channel.panelChannelUp()).toBe(false);
    expect(received).not.toHaveBeenCalled();
    expect(ControlledWebSocket.instances).toHaveLength(1);
  });

  it('relit dès la première ouverture et la reconnexion, en conservant les deux cadences', async () => {
    const refresh = vi.fn();
    const stopRefresh = channel.bindPanelRefresh(refresh);
    cleanups.push(stopRefresh);
    const first = await start();
    expect(refresh).not.toHaveBeenCalled();

    // Une première ouverture peut déjà avoir manqué une écriture pendant
    // la négociation du WebSocket : elle déclenche aussi une relecture.
    first.socket.open();
    expect(refresh).toHaveBeenCalledTimes(1);
    refresh.mockClear();
    await vi.advanceTimersByTimeAsync(PANEL_POLL_SLOW_MS - 1);
    expect(refresh).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(refresh).toHaveBeenCalledTimes(1);

    first.socket.finishClose();
    refresh.mockClear();
    await vi.advanceTimersByTimeAsync(PANEL_POLL_MS - 1);
    expect(refresh).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(ControlledWebSocket.instances).toHaveLength(2);

    refresh.mockClear();
    const reconnect = ControlledWebSocket.instances[1];
    reconnect.open();
    expect(refresh).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(PANEL_POLL_SLOW_MS - 1);
    expect(refresh).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(refresh).toHaveBeenCalledTimes(2);

    stopRefresh();
    reconnect.message();
    await vi.advanceTimersByTimeAsync(PANEL_POLL_SLOW_MS);
    expect(refresh).toHaveBeenCalledTimes(2);
  });
});

describe('tickets HTTP et transition du Worker', () => {
  it('envoie le JWT par Authorization et un nouveau ticket à chaque reconnexion', async () => {
    const first = await start();
    const [path, options] = fetchTicket.mock.calls[0];
    expect(path).toBe('/api/v1/rt/ticket');
    expect(options).toMatchObject({
      method: 'POST', headers: { Authorization: 'Bearer jeton-de-test' },
      cache: 'no-store', redirect: 'error', credentials: 'same-origin',
    });
    expect(options.signal.aborted).toBe(false);
    const firstUrl = new URL(first.socket.url);
    expect(firstUrl.origin).toBe('wss://seven-motion-backend.manzilionel-lm.workers.dev');
    expect(firstUrl.pathname).toBe('/api/v1/rt/ws');
    expect(firstUrl.searchParams.has('token')).toBe(false);
    expect(first.socket.url).not.toContain('jeton-de-test');
    first.socket.open();
    first.socket.finishClose();
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchTicket).toHaveBeenCalledTimes(2);
    const nextUrl = new URL(ControlledWebSocket.instances[1].url);
    expect(nextUrl.searchParams.get('ticket')).not.toBe(firstUrl.searchParams.get('ticket'));
    expect(nextUrl.searchParams.has('token')).toBe(false);
  });

  it.each([401, 403, 404, 405, 429, 500, 503])('HTTP %s maintient le sondage 2 s sans socket JWT', async (status) => {
    fetchTicket.mockImplementation(async () => Response.json({ error: 'unavailable' }, { status }));
    const refresh = vi.fn();
    cleanups.push(channel.bindPanelRefresh(refresh));
    begin();
    await settle();
    expect(channel.panelChannelUp()).toBe(false);
    await vi.advanceTimersByTimeAsync(2000);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(ControlledWebSocket.instances).toHaveLength(0);
    expect(channel.panelChannelUp()).toBe(false);
    if (status === 401 || status === 403) {
      await vi.advanceTimersByTimeAsync(60_000);
      expect(fetchTicket).toHaveBeenCalledTimes(1);
    }
  });

  it('un ancien Worker sans ticket est réévalué après sa mise à jour', async () => {
    fetchTicket.mockImplementationOnce(async () => Response.json({ error: 'not_found' }, { status: 404 }));
    begin();
    await settle();
    await vi.advanceTimersByTimeAsync(29_999);
    expect(ControlledWebSocket.instances).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(1);
    expect(ControlledWebSocket.instances).toHaveLength(1);
    expect(channel.panelChannelUp()).toBe(false);
    ControlledWebSocket.instances[0].open();
    expect(channel.panelChannelUp()).toBe(true);
  });

  it.each([
    () => Response.json({ token: 'must-not-be-used' }),
    () => Response.json({ ticket: 'jwt-is-not-a-ticket' }),
    () => new Response('not-json', { status: 200 }),
  ])('une réponse ticket invalide ne crée pas de WebSocket', async (response) => {
    fetchTicket.mockImplementation(response);
    begin();
    await settle();
    expect(ControlledWebSocket.instances).toHaveLength(0);
    expect(channel.panelChannelUp()).toBe(false);
  });

  it('une panne réseau reste en sondage puis redemande un ticket', async () => {
    fetchTicket.mockRejectedValueOnce(new TypeError('network'));
    begin();
    await settle();
    expect(ControlledWebSocket.instances).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchTicket).toHaveBeenCalledTimes(2);
    expect(ControlledWebSocket.instances).toHaveLength(1);
  });

  it('un ticket refusé à l’upgrade ne peut pas être réutilisé', async () => {
    const first = await start();
    first.socket.onerror?.();
    expect(first.socket.close).toHaveBeenCalledOnce();
    expect(channel.panelChannelUp()).toBe(false);
    await vi.advanceTimersByTimeAsync(2000);
    expect(ControlledWebSocket.instances).toHaveLength(2);
    expect(ControlledWebSocket.instances[1].url).not.toBe(first.socket.url);
  });

  it('un résultat reçu après suspension et expiration du ticket est abandonné', async () => {
    const pending = deferredResponse();
    fetchTicket.mockReturnValueOnce(pending.promise);
    begin();
    vi.setSystemTime(Date.now() + 60_001);
    pending.resolve(ticketResponse());
    await settle();
    expect(ControlledWebSocket.instances).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchTicket).toHaveBeenCalledTimes(2);
    expect(ControlledWebSocket.instances).toHaveLength(1);
  });

  it('une demande ticket bloquée est annulée et le sondage continue', async () => {
    fetchTicket.mockImplementationOnce((_path: string, options: RequestInit) => new Promise((_resolve, reject) => {
      options.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
    }));
    const refresh = vi.fn();
    cleanups.push(channel.bindPanelRefresh(refresh));
    begin();
    const signal = fetchTicket.mock.calls[0][1].signal;
    await vi.advanceTimersByTimeAsync(10_000);
    expect(signal.aborted).toBe(true);
    expect(refresh).toHaveBeenCalledTimes(5);
    expect(ControlledWebSocket.instances).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchTicket).toHaveBeenCalledTimes(2);
    expect(ControlledWebSocket.instances).toHaveLength(1);
  });
});

describe('annulation des tickets et protocole vivant', () => {
  it('logout annule le ticket et ignore sa réponse tardive', async () => {
    const pending = deferredResponse();
    fetchTicket.mockReturnValueOnce(pending.promise);
    const stop = begin();
    const signal = fetchTicket.mock.calls[0][1].signal;
    auth.token = null;
    stop();
    expect(signal.aborted).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
    pending.resolve(ticketResponse());
    await settle();
    expect(ControlledWebSocket.instances).toHaveLength(0);
    expect(channel.panelChannelUp()).toBe(false);
  });

  it('changer de session annule l’ancien ticket sans laisser son cleanup annuler le nouveau', async () => {
    const previous = deferredResponse();
    const current = deferredResponse();
    fetchTicket.mockReturnValueOnce(previous.promise).mockReturnValueOnce(current.promise);
    const stopOld = begin();
    const previousSignal = fetchTicket.mock.calls[0][1].signal;
    auth.token = 'nouveau-jeton';
    begin();
    const currentSignal = fetchTicket.mock.calls[1][1].signal;
    stopOld();
    expect(previousSignal.aborted).toBe(true);
    expect(currentSignal.aborted).toBe(false);
    expect(fetchTicket.mock.calls[1][1].headers.Authorization).toBe('Bearer nouveau-jeton');
    current.resolve(ticketResponse());
    await settle();
    const socket = ControlledWebSocket.instances[0];
    socket.open();
    previous.resolve(ticketResponse());
    await settle();
    expect(ControlledWebSocket.instances).toHaveLength(1);
    expect(socket.close).not.toHaveBeenCalled();
    expect(channel.panelChannelUp()).toBe(true);
  });

  it('une session changée avant la réponse ne peut pas ouvrir le ticket précédent', async () => {
    const pending = deferredResponse();
    fetchTicket.mockReturnValueOnce(pending.promise);
    begin();
    auth.token = 'autre-session';
    pending.resolve(ticketResponse());
    await settle();
    expect(ControlledWebSocket.instances).toHaveLength(0);
    expect(channel.panelChannelUp()).toBe(false);
  });

  it('onopen seul ne rend pas le canal vert et un serveur muet est fermé', async () => {
    const refresh = vi.fn();
    cleanups.push(channel.bindPanelRefresh(refresh));
    const current = await start();
    current.socket.replyToHello = false;
    current.socket.open();
    current.socket.message({ v: 2, type: 'hello' });
    expect(channel.panelChannelUp()).toBe(false);
    await vi.advanceTimersByTimeAsync(10_000);
    expect(current.socket.close).toHaveBeenCalledOnce();
    expect(refresh).toHaveBeenCalledTimes(5);
    expect(channel.panelChannelUp()).toBe(false);
  });

  it('les hello entretiennent le bail, puis une absence de réponse rétablit le sondage 2 s', async () => {
    const refresh = vi.fn();
    cleanups.push(channel.bindPanelRefresh(refresh));
    const current = await start();
    current.socket.open();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(current.socket.send).toHaveBeenCalledTimes(5);
    expect(current.socket.close).not.toHaveBeenCalled();
    expect(channel.panelChannelUp()).toBe(true);
    current.socket.replyToHello = false;
    await vi.advanceTimersByTimeAsync(30_000);
    expect(current.socket.close).toHaveBeenCalledOnce();
    expect(channel.panelChannelUp()).toBe(false);
    refresh.mockClear();
    await vi.advanceTimersByTimeAsync(2000);
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it('un reçu sans seq réveille les lecteurs avec son order_id exact', async () => {
    const received = vi.fn();
    cleanups.push(channel.onPanelChannel(received));
    const current = await start();
    current.socket.open();
    current.socket.message({
      type: 'receipt', mac: 'MK:AA:BB:CC:DD:EE', at: 1,
      order_id: 'ordre-courant', kind: 'source_clear', state: 'applied',
      config_rev: 4, applied_rev: 4,
    });
    expect(received).toHaveBeenCalledWith(expect.objectContaining({
      type: 'receipt', order_id: 'ordre-courant', state: 'applied', applied_rev: 4,
    }));
    expect(received).toHaveBeenCalledOnce();
  });

  it('une session changée ne laisse ni état vert ni message de l’ancienne socket', async () => {
    const received = vi.fn();
    cleanups.push(channel.onPanelChannel(received));
    const current = await start();
    current.socket.open();
    auth.token = 'autre-session';
    expect(channel.panelChannelUp()).toBe(false);
    current.socket.message();
    expect(received).not.toHaveBeenCalled();
    expect(current.socket.close).toHaveBeenCalledOnce();
  });
});
