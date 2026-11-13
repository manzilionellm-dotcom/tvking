// @vitest-environment jsdom
// Vraie page Appareils : saisie visible et requêtes sont vérifiées ensemble.
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Device } from '@/lib/api';
import { LIST_PAGE_SIZE } from '@/lib/robust';

const mocks = vi.hoisted(() => ({ list: vi.fn() }));
vi.mock('@/lib/api', async (importOriginal) => {
  const api = await importOriginal<typeof import('@/lib/api')>();
  return { ...api, devicesApi: { ...api.devicesApi, list: mocks.list } };
});
vi.mock('@/lib/box-channel', () => ({
  bindPanelRefresh: () => () => {},
  onPanelChannel: () => () => {},
  onPanelChannelState: () => () => {},
}));
vi.mock('@/components/AppLayout', () => ({
  AppLayout: ({ children, subtitle }: { children: ReactNode; subtitle: string }) => <main><p>{subtitle}</p>{children}</main>,
}));
import { DevicesPage } from './DevicesPage';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
const device: Device = {
  id: 'device-test', customer_id: 'client-test', mac: 'MK:FB:88:05:2B:68',
  label: null, first_seen_at: 1, last_seen_at: 1, customer_name: 'Client conservé',
};
const page = (total = 1, items = [device]) => ({ items, total, limit: LIST_PAGE_SIZE, offset: 0, truncated: total > items.length });
let host: HTMLDivElement;
let root: Root;
let blockedFetch: ReturnType<typeof vi.fn>;
const input = () => host.querySelector('input[placeholder="MAC, nom, client…"]') as HTMLInputElement;
const text = () => host.textContent ?? '';
async function advance(ms = 200) { await act(async () => { await vi.advanceTimersByTimeAsync(ms); }); }
function edit(raw: string, caret = raw.length, inputType = 'insertText') {
  const el = input();
  el.focus();
  act(() => {
    el.dispatchEvent(new InputEvent('beforeinput', { inputType, bubbles: true }));
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(el, raw);
    el.setSelectionRange(caret, caret);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
function type(chars: string) {
  for (const ch of chars) edit(input().value + ch);
}
async function mount() {
  await act(async () => {
    root.render(<MemoryRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}><DevicesPage onLogout={() => {}} /></MemoryRouter>);
  });
  await advance();
  mocks.list.mockClear();
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}
beforeEach(() => {
  vi.useFakeTimers();
  mocks.list.mockReset().mockResolvedValue(page());
  blockedFetch = vi.fn(() => Promise.reject(new Error('Aucun réseau réel autorisé.')));
  vi.stubGlobal('fetch', blockedFetch);
  host = document.createElement('div'); document.body.appendChild(host); root = createRoot(host);
});
afterEach(() => {
  act(() => root.unmount()); host.remove(); vi.clearAllTimers(); vi.useRealTimers(); vi.unstubAllGlobals();
  expect(blockedFetch).not.toHaveBeenCalled();
});

describe('recherche mixte réelle des appareils', () => {
  it('capture utilisateur : 5454 devient 54:54 tout en cherchant le brut en premier', async () => {
    await mount();
    for (const [key, expected] of [['5', '5'], ['4', '54'], ['5', '54:5'], ['4', '54:54']]) {
      type(key); expect(input().value).toBe(expected);
    }
    for (const [raw, expected] of [['54:5', '54:5'], ['54:', '54'], ['5', '5']]) {
      edit(raw, raw.length, 'deleteContentBackward');
      expect(input().value).toBe(expected);
      expect(input().selectionStart).toBe(expected.length);
    }
    type('454'); expect(input().value).toBe('54:54');
    await advance();
    expect(mocks.list).toHaveBeenCalledTimes(1);
    expect(mocks.list.mock.calls[0][0]).toBe('5454');
  });

  it('frappe progressive MK : majuscules, séparateurs, curseur et query brute', async () => {
    await mount();
    let raw = '';
    for (const ch of 'mkfb88052b68') {
      raw += ch; edit(input().value + ch);
      if (raw.length >= 4) expect(input().value).toBe(raw.toUpperCase().match(/.{1,2}/g)!.join(':'));
      expect(input().selectionStart).toBe(input().value.length);
    }
    await advance();
    expect(mocks.list.mock.calls[0][0]).toBe('mkfb88052b68');
  });

  it.each(['aabbccddeeff', 'aa-bb-cc-dd-ee-ff', 'aa bb cc dd ee ff'])('collage %s : rendu MAC et texte original conservé pour l’API', async (raw) => {
    await mount(); edit(raw, raw.length, 'insertFromPaste');
    expect(input().value).toBe('AA:BB:CC:DD:EE:FF');
    await advance(); expect(mocks.list.mock.calls[0][0]).toBe(raw);
  });

  it('suppression mobile d’un séparateur et édition au milieu conservent le curseur', async () => {
    await mount(); edit('mkfb88');
    expect(input().value).toBe('MK:FB:88');
    edit('MK:FB88', 5, 'deleteContentBackward');
    expect(input().value).toBe('MK:F8:8'); expect(input().selectionStart).toBe(4);
    edit('mkfb', 4, 'insertFromPaste');
    edit('MK:1FB', 4);
    expect(input().value).toBe('MK:1F:B'); expect(input().selectionStart).toBe(4);
  });

  it.each(['Jean-Pierre', 'john.doe', 'TV salon', 'école', 'client@example.org', '192.168.1.1', 'cafe', 'mkern', 'UtilisateurTrèsLongPlusDeDouze'])('la recherche libre %s reste exacte', async (raw) => {
    await mount(); edit(raw, raw.length, 'insertFromPaste');
    expect(input().value).toBe(raw);
    await advance(); expect(mocks.list.mock.calls[0][0]).toBe(raw);
  });

  it('sort d’un préfixe MAC sans perdre le nom ni limiter à douze caractères', async () => {
    await mount(); type('5454'); expect(input().value).toBe('54:54');
    type('ServiceClientTrèsLong');
    expect(input().value).toBe('5454ServiceClientTrèsLong');
    edit('', 0, 'deleteContentBackward'); type('mkfb'); expect(input().value).toBe('MK:FB');
    type('office'); expect(input().value).toBe('mkfboffice');
    await advance(); expect(mocks.list.mock.calls.at(-1)?.[0]).toBe('mkfboffice');
  });

  it.each(['aabb.cd@example.org', '5454 Service', '5454-service'])('la ponctuation de %s reste intacte pendant la frappe progressive', async (raw) => {
    await mount(); type(raw);
    expect(input().value).toBe(raw);
    await advance(); expect(mocks.list.mock.calls[0][0]).toBe(raw);
  });

  it('une insertion au milieu reste après le séparateur original et conserve son curseur', async () => {
    await mount(); edit('aabb.cd', 7, 'insertFromPaste');
    expect(input().value).toBe('AA:BB:CD');
    edit('AA:BB:XCD', 7);
    expect(input().value).toBe('aabb.Xcd'); expect(input().selectionStart).toBe(6);
    await advance(); expect(mocks.list.mock.calls[0][0]).toBe('aabb.Xcd');
  });

  it('fallback seulement sur zéro exact, même signal et pagination, total serveur intact', async () => {
    await mount();
    mocks.list.mockResolvedValueOnce(page(0, [])).mockResolvedValueOnce(page(287));
    edit('mkfb88052b68'); await advance();
    expect(mocks.list).toHaveBeenCalledTimes(2);
    const [raw, fallback] = mocks.list.mock.calls;
    expect(raw[0]).toBe('mkfb88052b68'); expect(fallback[0]).toBe('MK:FB:88:05:2B:68');
    expect(fallback[1]).toEqual(raw[1]); expect(fallback[2]).toBe(raw[2]);
    expect(text()).toContain('287 appareil(s)');
    mocks.list.mockResolvedValue(page(287));
    const next = Array.from(host.querySelectorAll('button')).find((b) => b.textContent === 'Suivant')!;
    await act(async () => next.click()); await advance();
    expect(mocks.list.mock.calls.at(-1)?.slice(0, 2)).toEqual(['mkfb88052b68', { limit: LIST_PAGE_SIZE, offset: LIST_PAGE_SIZE }]);
    edit('Jean-Pierre'); await advance();
    expect(mocks.list.mock.calls.at(-1)?.[1].offset).toBe(0);
  });

  it.each([{ items: [], total: 8 }, { items: [] }, page(1)])('une réponse sans zéro exact ne déclenche aucun fallback', async (result) => {
    await mount(); mocks.list.mockResolvedValue(result); edit('mkfb88052b68'); await advance();
    expect(mocks.list).toHaveBeenCalledTimes(1);
  });

  it('conserve le repli API historique même quand une IP reste littérale à l’écran', async () => {
    await mount(); mocks.list.mockResolvedValueOnce(page(0, [])).mockResolvedValue(page());
    edit('192.168.1.1'); await advance();
    expect(input().value).toBe('192.168.1.1');
    // looksLikeMac appartient au contrat existant de recherche serveur :
    // le masque visuel plus prudent ne change pas ce repli sur zéro exact.
    expect(mocks.list.mock.calls.map((call) => call[0])).toEqual(['192.168.1.1', '19:21:68:11']);
  });

  it('la recherche suivante annule le fallback et ignore sa réponse tardive', async () => {
    await mount();
    const pending = deferred<ReturnType<typeof page>>();
    mocks.list.mockResolvedValueOnce(page(0, [])).mockImplementationOnce(() => pending.promise).mockResolvedValue(page(3));
    edit('mkfb88052b68'); await advance();
    const signal = mocks.list.mock.calls[1][2] as AbortSignal;
    edit('Client récent'); expect(signal.aborted).toBe(true); await advance();
    expect(text()).toContain('3 appareil(s)');
    await act(async () => pending.resolve(page(999)));
    expect(text()).toContain('3 appareil(s)'); expect(text()).not.toContain('999 appareil(s)');
    edit('', 0, 'deleteContentBackward'); await advance();
    expect(input().value).toBe(''); expect(mocks.list.mock.calls.at(-1)?.[0]).toBe('');
  });
});
