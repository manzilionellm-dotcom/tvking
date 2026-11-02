// @vitest-environment jsdom
// Parcours réel de la page : le registre enrichit les lignes de présence sans
// bloquer leur rafraîchissement et sans confondre deux MAC.
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ online: vi.fn(), devices: vi.fn() }));
vi.mock('@/lib/api', async (importOriginal) => {
  const api = await importOriginal<typeof import('@/lib/api')>();
  return {
    ...api,
    onlineApi: { ...api.onlineApi, get: mocks.online },
    devicesApi: { ...api.devicesApi, list: mocks.devices },
  };
});
vi.mock('@/components/AppLayout', () => ({
  AppLayout: ({ children, title }: { children: ReactNode; title: string }) => <main><h1>{title}</h1>{children}</main>,
}));
import { OnlinePage } from './OnlinePage';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
const PHONE_MAC = 'MK:AA:BB:CC:DD:01';
const TV_MAC = 'MK:AA:BB:CC:DD:02';
const onlineRow = (mac: string, channel = '') => ({
  mac, channel, ip: '192.0.2.1', country: 'SE', lastSeen: Date.now(),
});
const onlineSnapshot = (items = [onlineRow(PHONE_MAC), onlineRow(TV_MAC)]) => ({
  onlineCount: items.length, todayCount: 11, byCountry: { SE: items.length }, items,
});
const phone = { mac: PHONE_MAC.toLowerCase(), device_model: 'Samsung SM-S938B', android_release: '17', platform: 'tv' };
const tv = { mac: TV_MAC, device_model: 'NVIDIA SHIELD Android TV', android_release: '11', platform: 'tv' };
const devicePage = (items: unknown[] = [tv, phone]) => ({ items, total: items.length, limit: 500, offset: 0 });

let host: HTMLDivElement;
let root: Root | null;
let blockedFetch: ReturnType<typeof vi.fn>;
const onLogout = vi.fn();
const rows = () => Array.from(host.querySelectorAll('tbody tr'));
const rowFor = (mac: string) => rows().find((row) => row.textContent?.includes(mac));
const deviceText = (mac: string) => rowFor(mac)?.querySelectorAll('td')[1]?.textContent ?? '';
const text = () => host.textContent ?? '';

async function mount() {
  await act(async () => { root!.render(<OnlinePage onLogout={onLogout} />); });
}
async function advance(ms: number) {
  await act(async () => { await vi.advanceTimersByTimeAsync(ms); });
}
function search(value: string) {
  const input = host.querySelector('input') as HTMLInputElement;
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(input, value);
    input.setSelectionRange(value.length, value.length);
    input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertFromPaste' }));
  });
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

beforeEach(() => {
  vi.useFakeTimers();
  mocks.online.mockReset().mockResolvedValue(onlineSnapshot());
  mocks.devices.mockReset().mockResolvedValue(devicePage());
  onLogout.mockClear();
  blockedFetch = vi.fn(() => Promise.reject(new Error('Aucun réseau réel autorisé.')));
  vi.stubGlobal('fetch', blockedFetch);
  host = document.createElement('div'); document.body.appendChild(host);
  root = createRoot(host);
});
afterEach(() => {
  if (root) act(() => root!.unmount());
  root = null; host.remove();
  vi.clearAllTimers(); vi.useRealTimers(); vi.unstubAllGlobals();
  expect(blockedFetch).not.toHaveBeenCalled();
});

describe('appareil connecté dans la page En ligne', () => {
  it('rapproche le modèle par MAC malgré l’ordre inversé et la casse du registre', async () => {
    await mount();
    expect(rows()).toHaveLength(2);
    expect(deviceText(PHONE_MAC)).toContain('Samsung SM-S938B');
    expect(deviceText(PHONE_MAC)).toContain('Android 17');
    expect(deviceText(PHONE_MAC)).not.toContain('Android TV');
    expect(deviceText(PHONE_MAC)).not.toContain('NVIDIA');
    expect(deviceText(TV_MAC)).toContain('Android TV');
    expect(deviceText(TV_MAC)).toContain('NVIDIA SHIELD Android TV');
    expect(deviceText(TV_MAC)).toContain('Android 11');
    expect(mocks.devices).toHaveBeenCalledTimes(1);
    expect(mocks.devices.mock.calls[0][0]).toBe('');
  });

  it('recherche le modèle et le type, puis trie la nouvelle colonne sans relire l’API', async () => {
    await mount();
    search('SHIELD');
    expect(rows()).toHaveLength(1);
    expect(rowFor(TV_MAC)).toBeDefined();
    search('Android TV');
    expect(rows()).toHaveLength(1);
    expect(rowFor(TV_MAC)).toBeDefined();
    search('Samsung');
    expect(rows()).toHaveLength(1);
    expect(rowFor(PHONE_MAC)).toBeDefined();
    search('');
    const sort = Array.from(host.querySelectorAll('thead button')).find((button) => button.textContent?.startsWith('Appareil'))!;
    act(() => (sort as HTMLButtonElement).click());
    const ascending = rows().map((row) => row.textContent);
    expect(sort.closest('th')?.getAttribute('aria-sort')).toBe('ascending');
    act(() => (sort as HTMLButtonElement).click());
    expect(rows().map((row) => row.textContent)).toEqual(ascending.slice().reverse());
    expect(sort.closest('th')?.getAttribute('aria-sort')).toBe('descending');
    expect(mocks.devices).toHaveBeenCalledTimes(1);
    expect(mocks.online).toHaveBeenCalledTimes(1);
  });

  it('garde la présence et la chaîne à jour pendant une lecture lente du modèle', async () => {
    const pending = deferred<ReturnType<typeof devicePage>>();
    mocks.devices.mockReturnValue(pending.promise);
    await mount();
    expect(rows()).toHaveLength(2);
    expect(text()).toContain('Lecture des informations');
    mocks.online.mockResolvedValue(onlineSnapshot([onlineRow(PHONE_MAC, 'Chaîne nouvelle'), onlineRow(TV_MAC)]));
    await advance(6_000);
    expect(rowFor(PHONE_MAC)?.textContent).toContain('Chaîne nouvelle');
    expect(mocks.online).toHaveBeenCalledTimes(4);
    expect(mocks.devices).toHaveBeenCalledTimes(1);
    await act(async () => pending.resolve(devicePage()));
    expect(deviceText(PHONE_MAC)).toContain('Samsung SM-S938B');
    expect(rowFor(PHONE_MAC)?.textContent).toContain('Chaîne nouvelle');
  });

  it('une panne du registre ne masque pas les appareils en ligne ni leur actualisation', async () => {
    mocks.devices.mockRejectedValue(new Error('Registre temporairement indisponible'));
    await mount();
    expect(rows()).toHaveLength(2);
    expect(text()).toContain('informations d’appareil sont indisponibles');
    expect(text()).toContain('Modèle non communiqué');
    mocks.online.mockResolvedValue(onlineSnapshot([onlineRow(PHONE_MAC, 'Direct maintenu'), onlineRow(TV_MAC)]));
    await advance(4_000);
    expect(rowFor(PHONE_MAC)?.textContent).toContain('Direct maintenu');
    expect(mocks.devices).toHaveBeenCalledTimes(1);
    expect(mocks.online).toHaveBeenCalledTimes(3);
  });

  it('rafraîchit les modèles une fois par minute et conserve les derniers connus sur erreur', async () => {
    await mount();
    mocks.devices.mockRejectedValue(new Error('Erreur au renouvellement'));
    await advance(60_000);
    expect(mocks.devices).toHaveBeenCalledTimes(2);
    expect(mocks.online).toHaveBeenCalledTimes(31);
    expect(deviceText(PHONE_MAC)).toContain('Samsung SM-S938B');
    expect(deviceText(TV_MAC)).toContain('NVIDIA SHIELD Android TV');
    expect(text()).toContain('informations d’appareil sont indisponibles');
  });

  it('ignore une réponse ancienne quand la liste des MAC connectées a changé', async () => {
    const stale = deferred<ReturnType<typeof devicePage>>();
    mocks.online.mockResolvedValue(onlineSnapshot([onlineRow(PHONE_MAC)]));
    mocks.devices.mockReturnValueOnce(stale.promise).mockResolvedValue(devicePage([tv]));
    await mount();
    const firstSignal = mocks.devices.mock.calls[0][2] as AbortSignal;
    mocks.online.mockResolvedValue(onlineSnapshot([onlineRow(TV_MAC)]));
    await advance(2_000);
    expect(firstSignal.aborted).toBe(true);
    expect(rows()).toHaveLength(1);
    expect(deviceText(TV_MAC)).toContain('NVIDIA SHIELD Android TV');
    await act(async () => stale.resolve(devicePage([phone])));
    expect(rows()).toHaveLength(1);
    expect(deviceText(TV_MAC)).toContain('NVIDIA SHIELD Android TV');
    expect(text()).not.toContain('Samsung SM-S938B');
  });

  it('annule la lecture et les minuteries à la sortie de la page', async () => {
    const pending = deferred<ReturnType<typeof devicePage>>();
    mocks.devices.mockReturnValue(pending.promise);
    await mount();
    const metadataSignal = mocks.devices.mock.calls[0][2] as AbortSignal;
    act(() => root!.unmount()); root = null;
    expect(metadataSignal.aborted).toBe(true);
    await act(async () => pending.resolve(devicePage()));
    await advance(65_000);
    expect(mocks.devices).toHaveBeenCalledTimes(1);
    expect(mocks.online).toHaveBeenCalledTimes(1);
    expect(host.textContent).toBe('');
  });
});
