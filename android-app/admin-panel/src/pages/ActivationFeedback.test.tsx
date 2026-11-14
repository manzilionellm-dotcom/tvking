// @vitest-environment jsdom
// Vérifie les gestes réels du panneau : reçu de licence, diagnostic séparé,
// absence de faux succès TV et conservation de la confirmation physique.
// Les frontières API sont simulées ; aucune requête réseau réelle n'est admise.
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  activate: vi.fn(), costs: vi.fn(), apps: vi.fn(), me: vi.fn(),
  capability: vi.fn(), preview: vi.fn(), approve: vi.fn(),
  devices: vi.fn(), overview: vi.fn(), journal: vi.fn(), ask: vi.fn(),
}));
vi.mock('@/lib/api', async (importOriginal) => {
  const api = await importOriginal<typeof import('@/lib/api')>();
  return { ...api,
    activateApi: { ...api.activateApi, activate: mocks.activate },
    planCostsApi: { ...api.planCostsApi, list: mocks.costs },
    appsApi: { ...api.appsApi, list: mocks.apps },
    meApi: { ...api.meApi, get: mocks.me },
    devicesApi: { ...api.devicesApi, list: mocks.devices, overview: mocks.overview },
    novatubeReassociationApi: { capability: mocks.capability, preview: mocks.preview, approve: mocks.approve },
    blackboxApi: { get: mocks.journal, ask: mocks.ask },
  };
});
vi.mock('@/components/AppLayout', () => ({ AppLayout: ({ children }: { children: ReactNode }) => <main>{children}</main> }));
vi.mock('@/lib/box-channel', () => ({
  bindPanelRefresh: () => () => {}, panelChannelUp: () => false,
  onPanelChannel: () => () => {}, onPanelChannelState: () => () => {},
}));
vi.mock('./TracePanel', () => ({ TracePanel: () => null }));

import { ApiError, setCurrentUser } from '@/lib/api';
import { ActivatePage } from './ActivatePage';
import { DevicesPage } from './DevicesPage';
import { BlackBoxPage } from './BlackBoxPage';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
const MAC = 'MK:AA:BB:CC:DD:EE';
const OTHER = 'MK:11:22:33:44:55';
const NOW = Date.parse('2026-11-14T22:30:00Z');
const user = { id: 'owner-fixture', email: 'owner@example.invalid', name: 'Propriétaire', role: 'super_admin' };
const receipt = {
  ok: true, license_id: 'license-fixture', device_id: 'device-fixture', customer_id: 'customer-fixture',
  mac: MAC, plan: 'lifetime', expires_at: null, credits_charged: 0, credit_balance: null, renewed: false,
};
const device = { id: 'device-fixture', customer_id: 'customer-fixture', mac: MAC, label: 'Box de test',
  first_seen_at: NOW - 86_400_000, last_seen_at: NOW - 86_400_000, platform: 'tv', block_status: 'active' };
const pending = { ok: true, supported: true, app_id: 'app_novatube4k', mac: MAC,
  installation_status: 'verification_required', recovery_pending: true, server_now: NOW, recovery_expires_at: NOW + 600_000 };

let host: HTMLDivElement;
let root: Root;
let blockedFetch: ReturnType<typeof vi.fn>;
const text = () => host.textContent || '';
function button(label: string): HTMLButtonElement {
  const match = Array.from(host.querySelectorAll('button')).filter((item) => item.textContent?.trim() === label).at(-1);
  expect(match, `Bouton ${label}`).toBeDefined();
  return match!;
}
async function click(label: string) { await act(async () => { button(label).click(); }); }
async function render(page: ReactNode, path = '/activate?mac=' + encodeURIComponent(MAC)) {
  await act(async () => { root.render(<MemoryRouter initialEntries={[path]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>{page}</MemoryRouter>); });
}
async function advance(ms: number) { await act(async () => { await vi.advanceTimersByTimeAsync(ms); }); }
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}
function assertNoAppSuccess() {
  expect(text()).not.toMatch(/La box est prévenue à l’instant|débloque l.app tout de suite|Activé ✔|connexion confirmée/i);
  expect(mocks.approve).not.toHaveBeenCalled();
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'Date', 'performance'] });
  vi.setSystemTime(NOW);
  setCurrentUser(user);
  for (const mock of Object.values(mocks)) mock.mockReset();
  mocks.activate.mockResolvedValue(receipt);
  mocks.costs.mockResolvedValue({ items: [] });
  mocks.apps.mockResolvedValue({ items: [{ id: 'app_7motion', name: 'The Few' }, { id: 'app_novatube4k', name: 'NovaTube' }] });
  mocks.me.mockResolvedValue({ user: { ...user, credit_balance: null } });
  mocks.capability.mockResolvedValue(pending);
  mocks.devices.mockResolvedValue({ items: [device], total: 1, offset: 0, limit: 100 });
  mocks.overview.mockResolvedValue({ mac: MAC, license: { status: 'active', plan: 'lifetime', expires_at: null }, presence: null, sources: [] });
  mocks.journal.mockResolvedValue({ mac: MAC, text: '', updated_at: 0 });
  mocks.ask.mockResolvedValue({ ok: true, requested_at: NOW });
  blockedFetch = vi.fn(() => Promise.reject(new Error('Réseau réel interdit.')));
  vi.stubGlobal('fetch', blockedFetch);
  host = document.createElement('div'); document.body.appendChild(host); root = createRoot(host);
});
afterEach(() => {
  act(() => root.unmount()); host.remove();
  vi.clearAllTimers(); vi.useRealTimers(); vi.unstubAllGlobals(); setCurrentUser(null);
  expect(blockedFetch).not.toHaveBeenCalled();
});

describe('Activation et journal — licence et installation distinctes', () => {
  it('le reçu à vie affiche le conflit, son action et aucune nouvelle facturation automatique', async () => {
    await render(<ActivatePage onLogout={() => {}} />);
    await click('Activer · essai gratuit');
    expect(mocks.activate).toHaveBeenCalledTimes(1);
    expect(mocks.activate.mock.calls[0][0]).toMatchObject({ mac: MAC, app_id: 'app_7motion' });
    expect(text()).toContain('Licence enregistrée sur le serveur. Activée à vie.');
    expect(text()).toContain('La réception par l’application n’est pas encore confirmée.');
    expect(text()).toContain('Installation NovaTube à vérifier');
    expect(button('Licence enregistrée').disabled).toBe(true);
    expect(host.querySelector('form form')).toBeNull();
    expect(host.querySelector('a[href="/devices?mac=MK%3AAA%3ABB%3ACC%3ADD%3AEE"]')).not.toBeNull();
    await click('Réassocier NovaTube');
    expect(text()).toContain('Code d’assistance transmis par le client');
    expect(mocks.preview).not.toHaveBeenCalled();
    assertNoAppSuccess();
  });

  it('une panne du diagnostic conserve le reçu de licence sans confirmer la box', async () => {
    mocks.capability.mockRejectedValue(new ApiError(503, 'unavailable', 'Indisponible.'));
    await render(<ActivatePage onLogout={() => {}} />);
    await click('Activer · essai gratuit');
    expect(text()).toContain('Licence enregistrée sur le serveur');
    expect(text()).toContain('Vérification NovaTube indisponible');
    expect(text()).not.toContain('Installation NovaTube à vérifier');
    assertNoAppSuccess();
  });

  it('une réponse d’une autre MAC reste non confirmée et garde la clé du premier envoi', async () => {
    mocks.activate.mockResolvedValue({ ...receipt, mac: OTHER });
    await render(<ActivatePage onLogout={() => {}} />);
    await click('Activer · essai gratuit');
    expect(text()).toContain('Le résultat de l’activation n’a pas pu être confirmé');
    expect(text()).not.toContain('Licence enregistrée sur le serveur');
    expect(mocks.capability).not.toHaveBeenCalled();
    await click('Activer · essai gratuit');
    expect(mocks.activate.mock.calls[1][1]).toBe(mocks.activate.mock.calls[0][1]);
    assertNoAppSuccess();
  });

  it('un revendeur reçoit le reçu et la fiche, sans accès au diagnostic du propriétaire', async () => {
    setCurrentUser({ ...user, role: 'reseller' });
    await render(<ActivatePage onLogout={() => {}} />);
    await click('Activer · essai gratuit');
    expect(text()).toContain('Licence enregistrée sur le serveur');
    expect(text()).toContain('Vérifier la fiche de l’appareil');
    expect(mocks.capability).not.toHaveBeenCalled();
    expect(text()).not.toContain('Réassocier NovaTube');
    assertNoAppSuccess();
  });

  it('le modal conserve le résultat lisible et la vérification au lieu de disparaître après 900 ms', async () => {
    await render(<DevicesPage onLogout={() => {}} />, '/devices');
    await advance(200);
    await click('Activer');
    await click('Activer');
    expect(text()).toContain('Licence enregistrée sur le serveur');
    expect(text()).toContain('Installation NovaTube à vérifier');
    await advance(1000);
    expect(text()).toContain('Licence enregistrée sur le serveur');
    expect(button('Terminer')).toBeDefined();
    assertNoAppSuccess();
    const reads = mocks.devices.mock.calls.length;
    await act(async () => { (host.querySelector('.fixed.inset-0') as HTMLDivElement).click(); });
    expect(text()).not.toContain('Licence enregistrée sur le serveur');
    expect(mocks.devices).toHaveBeenCalledTimes(reads + 1);
    expect(mocks.activate).toHaveBeenCalledTimes(1);
  });

  it('la fiche affiche la demande de vérification avec la licence à vie conservée', async () => {
    await render(<DevicesPage onLogout={() => {}} />, '/devices');
    await advance(200);
    await click('Détails');
    expect(text()).toContain('À vie');
    expect(text()).toContain('Installation NovaTube à vérifier');
    expect(mocks.activate).not.toHaveBeenCalled();
    assertNoAppSuccess();
  });

  it('un journal vide et sa demande ne valent pas connexion ; la réassociation reste accessible', async () => {
    await render(<BlackBoxPage onLogout={() => {}} />, '/blackbox?mac=' + encodeURIComponent(MAC.toLowerCase()));
    expect(mocks.journal).toHaveBeenCalledWith(MAC);
    expect(mocks.ask).toHaveBeenCalledWith(MAC);
    expect(mocks.capability).toHaveBeenCalledWith(MAC, expect.any(AbortSignal));
    expect(text()).toContain('Pas encore de journal reçu pour cette box.');
    expect(text()).toContain('Installation NovaTube à vérifier');
    expect((host.querySelector('textarea') as HTMLTextAreaElement).value).toBe('');
    await click('Réassocier NovaTube');
    expect(text()).toContain('Code d’assistance transmis par le client');
    expect(mocks.activate).not.toHaveBeenCalled();
    assertNoAppSuccess();
  });

  it('changer de MAC retire l’ancien journal et ignore sa réponse tardive', async () => {
    const oldRead = deferred<{ mac: string; text: string; updated_at: number }>();
    const newRead = deferred<{ mac: string; text: string; updated_at: number }>();
    mocks.journal.mockResolvedValueOnce({ mac: MAC, text: 'Journal appareil A', updated_at: NOW })
      .mockReturnValueOnce(oldRead.promise).mockReturnValueOnce(newRead.promise);
    await render(<BlackBoxPage onLogout={() => {}} />, '/blackbox?mac=' + encodeURIComponent(MAC));
    expect((host.querySelector('textarea') as HTMLTextAreaElement).value).toBe('Journal appareil A');
    await advance(1500);
    await act(async () => {
      const input = host.querySelector('input')!;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(input, OTHER);
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await click('Afficher');
    expect(mocks.journal).toHaveBeenLastCalledWith(OTHER);
    expect((host.querySelector('textarea') as HTMLTextAreaElement).value).toBe('');
    await act(async () => { oldRead.resolve({ mac: MAC, text: 'Ancien journal tardif', updated_at: NOW }); });
    expect((host.querySelector('textarea') as HTMLTextAreaElement).value).toBe('');
    await act(async () => { newRead.resolve({ mac: OTHER, text: 'Journal appareil B', updated_at: NOW }); });
    expect((host.querySelector('textarea') as HTMLTextAreaElement).value).toBe('Journal appareil B');
    expect(text()).not.toContain('Ancien journal tardif');
  });
});
