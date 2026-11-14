// @vitest-environment jsdom
// Les clics et changements de code passent par le composant réel. Seules les
// trois routes dédiées sont simulées ; tout autre accès réseau est interdit.
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { NovatubeReassociationPreview, NovatubeReassociationResult } from '@/lib/api';

const mocks = vi.hoisted(() => ({ capability: vi.fn(), preview: vi.fn(), approve: vi.fn() }));
vi.mock('@/lib/api', async (importOriginal) => {
  const api = await importOriginal<typeof import('@/lib/api')>();
  return { ...api, novatubeReassociationApi: mocks };
});
import { ApiError, setCurrentUser } from '@/lib/api';
import { normalizeAssistanceCode, NovatubeReassociation } from './NovatubeReassociation';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
const MAC = 'MK:AA:BB:CC:DD:EE';
const OTHER = 'MK:11:22:33:44:55';
const CODE = 'ABCD-1234-EFGH';
const NEXT_CODE = 'WXYZ-5678-9ABC';
const NOW = Date.parse('2026-11-14T21:00:00Z');
const REQUEST_ID = '11111111-2222-4333-8444-555555555555';
const candidate = (mac = MAC, remaining = 600_000): NovatubeReassociationPreview => ({
  ok: true, app_id: 'app_novatube4k', mac, server_now: NOW,
  candidate: { request_id: REQUEST_ID, created_at: NOW, expires_at: NOW + remaining,
    model: 'Téléviseur de test', app_version: '334.2.3', platform: 'tv' },
});
const approved = (mac = MAC): NovatubeReassociationResult => ({
  ok: true, app_id: 'app_novatube4k', mac, result: 'device_reassociated', approved_at: NOW + 10_000,
});
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}
function user(role: string | null) {
  setCurrentUser(role ? { id: 'fixture-admin', email: 'admin@example.invalid', name: 'Test', role } : null);
}

let host: HTMLDivElement;
let root: Root;
let blockedFetch: ReturnType<typeof vi.fn>;
const text = () => host.textContent || '';
function button(label: string): HTMLButtonElement {
  const match = Array.from(host.querySelectorAll('button')).find((item) => item.textContent?.trim() === label);
  expect(match, `Bouton « ${label} » présent`).toBeDefined();
  return match!;
}
async function render(mac = MAC, disabled = false) {
  await act(async () => { root.render(<NovatubeReassociation mac={mac} disabled={disabled} />); });
}
async function click(label: string) {
  await act(async () => { button(label).click(); });
}
async function enter(value: string) {
  await act(async () => {
    const input = host.querySelector('input')!;
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
async function open(code = CODE) {
  await render();
  await click('Réassocier NovaTube');
  await enter(code);
}
async function preview() { await open(); await click('Vérifier le code'); }

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'Date', 'performance'] });
  vi.setSystemTime(NOW);
  user('super_admin');
  mocks.capability.mockReset().mockImplementation(async (mac: string) => ({ ok: true, supported: true, app_id: 'app_novatube4k', mac }));
  mocks.preview.mockReset().mockResolvedValue(candidate());
  mocks.approve.mockReset().mockResolvedValue(approved());
  blockedFetch = vi.fn(() => Promise.reject(new Error('Réseau réel interdit.')));
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
  user(null);
  expect(blockedFetch).not.toHaveBeenCalled();
});

describe('Réassociation NovaTube — autorisation et confirmation', () => {
  it('signale une demande actuelle sans convertir une licence active en accès confirmé', async () => {
    mocks.capability.mockResolvedValue({ ok: true, supported: true, app_id: 'app_novatube4k', mac: MAC,
      installation_status: 'verification_required', recovery_pending: true, server_now: NOW, recovery_expires_at: NOW + 600_000 });
    await render();
    expect(text()).toContain('Installation NovaTube à vérifier');
    expect(text()).toContain('La licence existante est conservée');
    expect(text()).toContain('un nouvel achat ne résout pas cette liaison');
    expect(mocks.preview).not.toHaveBeenCalled();
    expect(mocks.approve).not.toHaveBeenCalled();
    await act(async () => { await vi.advanceTimersByTimeAsync(600_001); });
    expect(text()).not.toContain('Installation NovaTube à vérifier');
    expect(text()).not.toMatch(/connexion confirmée|activation réussie/i);
  });

  it.each([
    {},
    { installation_status: 'unknown', recovery_pending: false, server_now: NOW, recovery_expires_at: null },
    { installation_status: 'verification_required', recovery_pending: false, server_now: NOW, recovery_expires_at: NOW + 1000 },
    { installation_status: 'verification_required', recovery_pending: true, server_now: NOW, recovery_expires_at: NOW - 1 },
    { installation_status: 'verification_required', recovery_pending: true, server_now: NOW, recovery_expires_at: NOW + 600_001 },
  ])('un diagnostic absent, incohérent ou expiré reste neutre : %o', async (fields) => {
    mocks.capability.mockResolvedValue({ ok: true, supported: true, app_id: 'app_novatube4k', mac: MAC, ...fields });
    await render();
    expect(text()).not.toContain('Installation NovaTube à vérifier');
    expect(text()).not.toMatch(/connexion confirmée|activation réussie/i);
    expect(mocks.approve).not.toHaveBeenCalled();
  });

  it.each(['admin', 'support', 'reseller', 'unexpected', null])('ne montre et ne demande rien pour le rôle %s', async (role) => {
    user(role);
    await render();
    expect(host.childElementCount).toBe(0);
    expect(mocks.capability).not.toHaveBeenCalled();
    expect(mocks.preview).not.toHaveBeenCalled();
    expect(mocks.approve).not.toHaveBeenCalled();
  });

  it('attend la capacité vérifiée et masque les autres applications', async () => {
    const capability = deferred<never>();
    mocks.capability.mockReturnValueOnce(capability.promise);
    await render();
    expect(text()).not.toContain('Réassocier NovaTube');
    await render(OTHER);
    mocks.capability.mockRejectedValueOnce(new ApiError(404, 'recovery_not_supported', 'Application non prise en charge.'));
    await render(MAC);
    expect(text()).not.toContain('Réassocier NovaTube');
    expect(mocks.preview).not.toHaveBeenCalled();
  });

  it('n’approuve qu’après aperçu puis confirmation explicite, sans annoncer de lecture', async () => {
    await open('abcd 1234 efgh');
    expect(mocks.capability).toHaveBeenCalledWith(MAC, expect.any(AbortSignal));
    expect(mocks.preview).not.toHaveBeenCalled();
    expect(mocks.approve).not.toHaveBeenCalled();
    await click('Vérifier le code');
    expect(mocks.preview).toHaveBeenCalledWith(MAC, CODE, expect.any(AbortSignal));
    expect(text()).toContain('Informations déclarées');
    for (const value of [MAC, 'Téléviseur de test', '334.2.3', 'tv']) expect(text()).toContain(value);
    expect(mocks.approve).not.toHaveBeenCalled();
    await click('Confirmer la réassociation');
    expect(mocks.approve).toHaveBeenCalledWith(MAC, CODE, REQUEST_ID, expect.any(AbortSignal));
    expect(text()).toContain('Liaison remplacée.');
    expect(text()).toContain('laisser NovaTube ouverte');
    expect(text()).not.toMatch(/lecture confirmée|listes confirmées|activation réussie/i);
    expect(host.querySelector('input')).toBeNull();
  });

  it('refuse les caractères ambigus sans modifier le sens du code', async () => {
    expect(normalizeAssistanceCode('abcd-1234 efgh')).toBe(CODE);
    for (const value of ['ABCD-1234-EFGI', 'ABCD-1234-EFGO', 'ABCD-1234-EFGL', 'ABCD-1234-EFGU', 'ABCD-1234', ' '.repeat(65) + CODE]) {
      expect(normalizeAssistanceCode(value)).toBeNull();
    }
    await open('ABCD-1234-EFGO');
    expect(button('Vérifier le code').disabled).toBe(true);
    await click('Vérifier le code');
    expect(mocks.preview).not.toHaveBeenCalled();
  });

  it('bloque un aperçu déjà expiré selon l’heure du serveur', async () => {
    const response = candidate(MAC, -1);
    response.candidate.created_at = NOW - 600_000;
    mocks.preview.mockResolvedValue(response);
    vi.setSystemTime(NOW - 86_400_000); // L'horloge locale n'autorise pas un code expiré.
    await preview();
    expect(text()).toContain('Ce code a expiré.');
    expect(text()).not.toContain('Confirmer la réassociation');
    expect(mocks.approve).not.toHaveBeenCalled();
  });

  it('désactive la confirmation lorsque la durée restante est écoulée', async () => {
    mocks.preview.mockResolvedValue(candidate(MAC, 2_000));
    await preview();
    expect(button('Confirmer la réassociation').disabled).toBe(false);
    await act(async () => { await vi.advanceTimersByTimeAsync(2_001); });
    expect(button('Confirmer la réassociation').disabled).toBe(true);
    expect(text()).toContain('Ce code a expiré.');
    await click('Confirmer la réassociation');
    expect(mocks.approve).not.toHaveBeenCalled();
  });

  it('bloque les doubles soumissions avant même le rendu React suivant', async () => {
    const pendingPreview = deferred<NovatubeReassociationPreview>();
    mocks.preview.mockReturnValueOnce(pendingPreview.promise);
    await open();
    await act(async () => {
      const form = host.querySelector('form')!;
      form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
      form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    });
    expect(mocks.preview).toHaveBeenCalledTimes(1);
    await act(async () => { pendingPreview.resolve(candidate()); });
    const pendingApproval = deferred<NovatubeReassociationResult>();
    mocks.approve.mockReturnValueOnce(pendingApproval.promise);
    await act(async () => {
      const confirm = button('Confirmer la réassociation');
      confirm.click();
      confirm.click();
    });
    expect(mocks.approve).toHaveBeenCalledTimes(1);
    expect(host.querySelector('input')!.disabled).toBe(true);
    await act(async () => { pendingApproval.resolve(approved()); });
    expect(text()).toContain('Liaison remplacée.');
  });

  it('ignore l’ancien aperçu après modification du code et garde le nouveau', async () => {
    const old = deferred<NovatubeReassociationPreview>();
    mocks.preview.mockReturnValueOnce(old.promise);
    await open();
    await click('Vérifier le code');
    const oldSignal = mocks.preview.mock.calls[0][2] as AbortSignal;
    await enter(NEXT_CODE);
    expect(oldSignal.aborted).toBe(true);
    await act(async () => { old.resolve(candidate()); });
    expect(text()).not.toContain('Confirmer la réassociation');
    expect(host.querySelector('input')!.value).toBe(NEXT_CODE);
    await click('Vérifier le code');
    await click('Confirmer la réassociation');
    expect(mocks.approve).toHaveBeenCalledWith(MAC, NEXT_CODE, REQUEST_ID, expect.any(AbortSignal));
  });

  it('efface un aperçu déjà visible lorsque le code est modifié', async () => {
    await preview();
    await enter(NEXT_CODE);
    expect(text()).not.toContain('Téléviseur de test');
    expect(text()).not.toContain('Confirmer la réassociation');
    expect(mocks.approve).not.toHaveBeenCalled();
  });

  it('ignore l’aperçu et l’approbation tardifs après changement de fiche', async () => {
    const oldPreview = deferred<NovatubeReassociationPreview>();
    mocks.preview.mockReturnValueOnce(oldPreview.promise);
    await open();
    await click('Vérifier le code');
    await render(OTHER);
    await act(async () => { oldPreview.resolve(candidate()); });
    expect(text()).not.toContain('Téléviseur de test');
    await render(MAC);
    await click('Réassocier NovaTube');
    await enter(CODE);
    await click('Vérifier le code');
    const oldApproval = deferred<NovatubeReassociationResult>();
    mocks.approve.mockReturnValueOnce(oldApproval.promise);
    await click('Confirmer la réassociation');
    await render(OTHER);
    await act(async () => { oldApproval.resolve(approved()); });
    expect(text()).not.toContain('Liaison remplacée.');
    expect(text()).not.toContain(MAC);
  });

  it('invalide la confirmation si le rôle est retiré, même sans nouveau rendu', async () => {
    await preview();
    user('support');
    await click('Confirmer la réassociation');
    expect(mocks.approve).not.toHaveBeenCalled();
    await render();
    expect(host.childElementCount).toBe(0);
  });

  it('refuse un aperçu d’une autre MAC et une réponse de succès incohérente', async () => {
    mocks.preview.mockResolvedValueOnce(candidate(OTHER));
    await preview();
    expect(text()).toContain('L’aperçu n’a pas pu être vérifié.');
    expect(mocks.approve).not.toHaveBeenCalled();
    await click('Vérifier le code');
    mocks.approve.mockResolvedValueOnce(approved(OTHER));
    await click('Confirmer la réassociation');
    expect(text()).toContain('Le résultat n’a pas pu être confirmé.');
    expect(text()).not.toContain('Liaison remplacée.');
  });

  it('refuse une métadonnée objet sans crash ni confirmation et accepte les champs nulls', async () => {
    const malformed = candidate();
    malformed.candidate.model = { unexpected: 'objet' } as unknown as string;
    mocks.preview.mockResolvedValueOnce(malformed);
    await preview();
    expect(text()).toContain('L’aperçu n’a pas pu être vérifié.');
    expect(text()).not.toContain('Confirmer la réassociation');
    expect(mocks.approve).not.toHaveBeenCalled();
    const empty = candidate();
    empty.candidate.model = empty.candidate.app_version = empty.candidate.platform = null;
    mocks.preview.mockResolvedValueOnce(empty);
    await click('Vérifier le code');
    expect(button('Confirmer la réassociation').disabled).toBe(false);
    expect(text()).toContain('Non renseigné');
  });

  it('refuse un UUID, une durée, une chronologie ou un entier non conforme au contrat', async () => {
    const invalid = [
      { ...candidate(), candidate: { ...candidate().candidate, request_id: 'demande-non-uuid' } },
      candidate(MAC, 600_001),
      { ...candidate(), server_now: Number.MAX_SAFE_INTEGER + 1 },
      { ...candidate(), server_now: NOW + 0.5 },
      { ...candidate(), candidate: { ...candidate().candidate, created_at: NOW + 1 } },
      { ...candidate(), candidate: { ...candidate().candidate, platform: 'x'.repeat(25) } },
    ];
    await open();
    for (const response of invalid) {
      mocks.preview.mockResolvedValueOnce(response);
      await click('Vérifier le code');
      expect(text()).toContain('L’aperçu n’a pas pu être vérifié.');
      expect(text()).not.toContain('Confirmer la réassociation');
    }
    expect(mocks.approve).not.toHaveBeenCalled();
  });

  it('un conflit oblige à revérifier le code sans approbation automatique', async () => {
    mocks.approve.mockRejectedValueOnce(new ApiError(409, 'recovery_stale', 'La demande a changé. Vérifie le nouveau code.'));
    await preview();
    await click('Confirmer la réassociation');
    expect(text()).toContain('La demande a changé.');
    expect(text()).not.toContain('Confirmer la réassociation');
    expect(text()).not.toContain('Liaison remplacée.');
    await act(async () => { await vi.advanceTimersByTimeAsync(60_000); });
    expect(mocks.approve).toHaveBeenCalledTimes(1);
  });
});
