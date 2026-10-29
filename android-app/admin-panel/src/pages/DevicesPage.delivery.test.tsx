// @vitest-environment jsdom
// Parcours réel « Appareils → Détails → Envoi instantané ». Les seules
// frontières simulées sont l'API, le canal et l'habillage de la page.
// Toute tentative de réseau réel fait échouer le test.
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Device, DeviceOverview, OrderView } from '@/lib/api';
import type { ChannelEvent } from '@/lib/box-channel-core';
import { DELIVERY_GIVE_UP_MS, DELIVERY_POLL_MS } from '@/lib/delivery';

const mocks = vi.hoisted(() => ({
  devices: vi.fn(),
  overview: vi.fn(),
  send: vi.fn(),
  orders: vi.fn(),
  events: new Set<(event: ChannelEvent) => void>(),
  states: new Set<(up: boolean) => void>(),
}));

vi.mock('@/lib/api', async (importOriginal) => {
  const api = await importOriginal<typeof import('@/lib/api')>();
  return {
    ...api,
    devicesApi: { ...api.devicesApi, list: mocks.devices, overview: mocks.overview },
    sourcesApi: { ...api.sourcesApi, setMany: mocks.send },
    ordersApi: { ...api.ordersApi, list: mocks.orders },
  };
});
vi.mock('@/lib/box-channel', () => ({
  // Les lectures ordinaires de la page ne doivent pas masquer celles du suivi.
  bindPanelRefresh: () => () => {},
  panelChannelUp: () => true,
  onPanelChannel: (listener: (event: ChannelEvent) => void) => {
    mocks.events.add(listener);
    return () => mocks.events.delete(listener);
  },
  onPanelChannelState: (listener: (up: boolean) => void) => {
    mocks.states.add(listener);
    return () => mocks.states.delete(listener);
  },
}));
vi.mock('@/components/AppLayout', () => ({
  AppLayout: ({ children }: { children: ReactNode }) => <main>{children}</main>,
}));

import { DevicesPage } from './DevicesPage';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const MAC = 'MK:AA:BB:CC:DD:EE';
const NOW = Date.parse('2026-10-29T12:00:00Z');
const device: Device = {
  id: 'device-test', customer_id: 'customer-test', mac: MAC, label: 'Box de test',
  first_seen_at: NOW - 86_400_000, last_seen_at: NOW - 86_400_000,
  platform: 'tv', block_status: 'active',
};
const overview: DeviceOverview = {
  mac: MAC,
  license: null,
  presence: { online: false, ip: '', country: '', channel: '', last_seen: NOW - 86_400_000 },
  sources: [{ type: 'm3u', m3u_url: 'https://fixtures.invalid/list.m3u', origin: 'panel' }],
  // Identique à la liste envoyée, mais présent avant cet envoi et avant la
  // dernière connexion de la box : cet inventaire ne prouve aucun nouvel ACK.
  localSources: [{ type: 'm3u', name: 'Ancienne liste TV', server: 'fixtures.invalid', username: '', channels: 64, active: true }],
};

type OrdersResult = { items: OrderView[] };
type SendResult = { ok: boolean; mac: string; count: number; order_id?: string | null };

function order(orderId: string, state: string, errorMessage?: string): OrderView {
  return { order_id: orderId, mac: MAC, kind: 'source', state, error_message: errorMessage };
}
function sent(orderId?: string | null): SendResult {
  return { ok: true, mac: MAC, count: 1, order_id: orderId };
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

let host: HTMLDivElement;
let root: Root;
let blockedFetch: ReturnType<typeof vi.fn>;
const pageText = () => host.textContent ?? '';

function button(label: string): HTMLButtonElement {
  const match = Array.from(host.querySelectorAll('button')).find((item) => item.textContent?.trim() === label);
  expect(match, `Bouton « ${label} » présent`).toBeDefined();
  return match!;
}
async function click(label: string) {
  await act(async () => { button(label).click(); });
}
async function advance(ms: number) {
  await act(async () => { await vi.advanceTimersByTimeAsync(ms); });
}
async function emit(mac = MAC, count = 1) {
  await act(async () => {
    for (let seq = 1; seq <= count; seq++) {
      for (const listener of mocks.events) listener({ v: 1, seq, type: 'order', mac, at: Date.now() });
    }
  });
}
function expectUnconfirmed() {
  expect(pageText()).not.toContain('Listes confirmées sur la box.');
  expect(pageText()).not.toContain('Liste sur la TV après');
}
async function openDevice() {
  await act(async () => {
    root.render(
      <MemoryRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <DevicesPage onLogout={() => {}} />
      </MemoryRouter>,
    );
  });
  await advance(200);
  await click('Détails');
  expect(pageText()).toContain('Ancienne liste TV');
  expect(pageText()).toContain('Hors ligne');
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  mocks.devices.mockReset().mockResolvedValue({ items: [device], total: 1, limit: 100, offset: 0 });
  mocks.overview.mockReset().mockResolvedValue(overview);
  mocks.send.mockReset().mockResolvedValue(sent('order-a'));
  mocks.orders.mockReset().mockResolvedValue({ items: [order('order-a', 'sent')] });
  mocks.events.clear();
  mocks.states.clear();
  blockedFetch = vi.fn(() => Promise.reject(new Error('Réseau réel interdit dans ces tests.')));
  vi.stubGlobal('fetch', blockedFetch);
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  expect(blockedFetch).not.toHaveBeenCalled();
});

describe('DevicesPage — confirmation de l’envoi exact', () => {
  it('un ancien inventaire identique ne confirme jamais un ordre encore envoyé', async () => {
    await openDevice();
    await click('⚡ Envoi instantané');
    expectUnconfirmed();
    expect(pageText()).toContain('Enregistrée sur le serveur. En attente de la box…');
    await advance(DELIVERY_POLL_MS * 2);
    expectUnconfirmed();
    expect(mocks.orders).toHaveBeenCalledWith(MAC);
  });

  it('un autre order_id APPLIED ne confirme pas cet envoi', async () => {
    mocks.orders.mockResolvedValue({ items: [order('autre-operation', 'APPLIED')] });
    await openDevice();
    await click('⚡ Envoi instantané');
    expectUnconfirmed();
    expect(pageText()).toContain('En attente de la box');
  });

  it('seul APPLIED pour l’order_id exact affiche la confirmation', async () => {
    mocks.orders.mockResolvedValueOnce({ items: [order('order-a', 'RECEIVED')] });
    await openDevice();
    await click('⚡ Envoi instantané');
    expectUnconfirmed();
    expect(pageText()).toContain('Ordre reçu par la box. Chargement en cours…');
    mocks.orders.mockResolvedValue({ items: [order('order-a', 'APPLIED')] });
    await emit();
    expect(pageText()).toContain('Listes confirmées sur la box.');
  });

  it.each([
    ['FAILED', 'La box n’a pas chargé la liste : Fournisseur indisponible.'],
    ['expired', 'La box n’a pas répondu en 10 minutes'],
  ])('%s reste terminal malgré les événements et minuteries suivants', async (state, expected) => {
    mocks.orders.mockResolvedValue({ items: [order('order-a', state, 'Fournisseur indisponible.')] });
    await openDevice();
    await click('⚡ Envoi instantané');
    expect(pageText()).toContain(expected);
    expectUnconfirmed();
    expect(mocks.orders).toHaveBeenCalledTimes(1);
    mocks.orders.mockResolvedValue({ items: [order('order-a', 'APPLIED')] });
    await emit();
    await advance(DELIVERY_POLL_MS * 3);
    expect(pageText()).toContain(expected);
    expectUnconfirmed();
    expect(mocks.orders).toHaveBeenCalledTimes(1);
  });

  it.each([undefined, null])('absence d’identifiant %s : application explicitement non confirmée', async (orderId) => {
    mocks.send.mockResolvedValue(sent(orderId));
    await openDevice();
    await click('⚡ Envoi instantané');
    expectUnconfirmed();
    expect(pageText()).toContain('Application des listes non confirmée');
    expect(pageText()).toContain('aucun identifiant d’ordre reçu');
    expect(mocks.orders).not.toHaveBeenCalled();
  });

  it('le clic d’un nouvel envoi invalide A avant même la réponse HTTP de B', async () => {
    const readA = deferred<OrdersResult>();
    const sendB = deferred<SendResult>();
    mocks.orders.mockImplementationOnce(() => readA.promise).mockResolvedValue({ items: [order('order-b', 'sent')] });
    mocks.send.mockResolvedValueOnce(sent('order-a')).mockImplementationOnce(() => sendB.promise);
    await openDevice();
    await click('⚡ Envoi instantané');
    expect(mocks.orders).toHaveBeenCalledTimes(1);
    await click('⚡ Envoi instantané');
    expect(mocks.send).toHaveBeenCalledTimes(2);

    // L'ordre A se termine pendant l'attente HTTP de B : ce succès ne doit
    // jamais réapparaître dans le suivi du nouvel envoi.
    await act(async () => { readA.resolve({ items: [order('order-a', 'APPLIED')] }); });
    expectUnconfirmed();
    await act(async () => { sendB.resolve(sent('order-b')); });
    expectUnconfirmed();
    expect(pageText()).toContain('En attente de la box');
    mocks.orders.mockResolvedValue({ items: [order('order-b', 'APPLIED')] });
    await emit();
    expect(pageText()).toContain('Listes confirmées sur la box.');
  });

  it('filtre la MAC et regroupe les rafales en une seule relance sans lectures parallèles', async () => {
    const first = deferred<OrdersResult>();
    const second = deferred<OrdersResult>();
    mocks.orders.mockImplementationOnce(() => first.promise).mockImplementationOnce(() => second.promise)
      .mockResolvedValue({ items: [order('order-a', 'APPLIED')] });
    await openDevice();
    await click('⚡ Envoi instantané');
    expect(mocks.orders).toHaveBeenCalledTimes(1);
    await emit('MK:11:22:33:44:55', 10);
    expect(mocks.orders).toHaveBeenCalledTimes(1);
    await emit(MAC, 20);
    await advance(DELIVERY_POLL_MS * 4);
    expect(mocks.orders).toHaveBeenCalledTimes(1);

    await act(async () => { first.resolve({ items: [order('order-a', 'sent')] }); });
    expect(mocks.orders).toHaveBeenCalledTimes(2);
    await act(async () => { second.resolve({ items: [order('order-a', 'RECEIVED')] }); });
    expect(mocks.orders).toHaveBeenCalledTimes(2);
    expect(pageText()).toContain('Chargement en cours');
    await emit();
    expect(mocks.orders).toHaveBeenCalledTimes(3);
    expect(pageText()).toContain('Listes confirmées sur la box.');
  });

  it('le délai local expire même si la lecture ne répond jamais, sans inventer un ACK', async () => {
    const pending = deferred<OrdersResult>();
    mocks.orders.mockImplementation(() => pending.promise);
    await openDevice();
    await click('⚡ Envoi instantané');
    await advance(DELIVERY_GIVE_UP_MS + 1);
    expect(pageText()).toContain('Application des listes non confirmée');
    expect(pageText()).toContain('11 minutes');
    expectUnconfirmed();
    expect(mocks.orders).toHaveBeenCalledTimes(1);

    await act(async () => { pending.resolve({ items: [order('order-a', 'APPLIED')] }); });
    expect(pageText()).toContain('Application des listes non confirmée');
    expectUnconfirmed();
  });
});
