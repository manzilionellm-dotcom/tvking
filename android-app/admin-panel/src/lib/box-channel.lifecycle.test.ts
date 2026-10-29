// @vitest-environment jsdom
// Régressions du vrai canal : aucun réseau, mais les mêmes callbacks et
// minuteries que le navigateur. close() reste volontairement asynchrone :
// un événement de l'ancienne socket peut arriver après le prochain login.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PANEL_POLL_MS, PANEL_POLL_SLOW_MS } from './live-sync';

vi.mock('@/lib/api', () => ({ getToken: () => 'jeton-de-test' }));

class ControlledWebSocket {
  static instances: ControlledWebSocket[] = [];
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  close = vi.fn();

  constructor(readonly url: string) {
    ControlledWebSocket.instances.push(this);
  }

  open() { this.onopen?.(); }
  finishClose() { this.onclose?.(); }
  message() {
    this.onmessage?.({ data: JSON.stringify({
      v: 1, seq: 1, type: 'source', mac: 'MK:AA:BB:CC:DD:EE', at: 1,
    }) });
  }
}

let channel: typeof import('./box-channel');
let cleanups: Array<() => void>;

function start() {
  const stop = channel.startPanelChannel();
  cleanups.push(stop);
  return { stop, socket: ControlledWebSocket.instances.at(-1)! };
}

beforeEach(async () => {
  vi.resetModules();
  vi.useFakeTimers();
  vi.stubGlobal('WebSocket', ControlledWebSocket);
  ControlledWebSocket.instances = [];
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
  it('une fermeture tardive après stop/start ne perturbe pas la nouvelle socket', () => {
    const old = start();
    old.socket.open();
    old.stop();
    const current = start();
    current.socket.open();

    // Le navigateur livre maintenant la fermeture demandée au logout.
    old.socket.finishClose();
    expect(channel.panelChannelUp()).toBe(true);
    vi.advanceTimersByTime(PANEL_POLL_SLOW_MS);
    expect(ControlledWebSocket.instances).toHaveLength(2);
    expect(current.socket.close).not.toHaveBeenCalled();
  });

  it('les ouvertures et messages obsolètes restent sans effet', () => {
    const received = vi.fn();
    cleanups.push(channel.onPanelChannel(received));
    const old = start();
    old.stop();
    const current = start();

    old.socket.open();
    old.socket.message();
    expect(channel.panelChannelUp()).toBe(false);
    expect(received).not.toHaveBeenCalled();

    current.socket.open();
    current.socket.message();
    expect(channel.panelChannelUp()).toBe(true);
    expect(received).toHaveBeenCalledTimes(1);
  });

  it('chaque arrêt appartient à sa session et ne ferme pas une session plus récente', () => {
    const old = start();
    old.socket.open();
    const current = start();
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

  it('un arrêt définitif ignore les callbacks tardifs et annule toute reconnexion', () => {
    const received = vi.fn();
    cleanups.push(channel.onPanelChannel(received));
    const current = start();
    current.socket.open();
    current.socket.finishClose();
    current.stop();

    current.socket.open();
    current.socket.message();
    current.socket.finishClose();
    vi.advanceTimersByTime(PANEL_POLL_SLOW_MS);
    expect(channel.panelChannelUp()).toBe(false);
    expect(received).not.toHaveBeenCalled();
    expect(ControlledWebSocket.instances).toHaveLength(1);
  });

  it('relit dès la première ouverture et la reconnexion, en conservant les deux cadences', () => {
    const refresh = vi.fn();
    const stopRefresh = channel.bindPanelRefresh(refresh);
    cleanups.push(stopRefresh);
    const first = start();
    expect(refresh).not.toHaveBeenCalled();

    // Une première ouverture peut déjà avoir manqué une écriture pendant
    // la négociation du WebSocket : elle déclenche aussi une relecture.
    first.socket.open();
    expect(refresh).toHaveBeenCalledTimes(1);
    refresh.mockClear();
    vi.advanceTimersByTime(PANEL_POLL_SLOW_MS - 1);
    expect(refresh).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(refresh).toHaveBeenCalledTimes(1);

    first.socket.finishClose();
    refresh.mockClear();
    vi.advanceTimersByTime(PANEL_POLL_MS - 1);
    expect(refresh).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(ControlledWebSocket.instances).toHaveLength(2);

    refresh.mockClear();
    const reconnect = ControlledWebSocket.instances[1];
    reconnect.open();
    expect(refresh).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(PANEL_POLL_SLOW_MS - 1);
    expect(refresh).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1);
    expect(refresh).toHaveBeenCalledTimes(2);

    stopRefresh();
    reconnect.message();
    vi.advanceTimersByTime(PANEL_POLL_SLOW_MS);
    expect(refresh).toHaveBeenCalledTimes(2);
  });
});
