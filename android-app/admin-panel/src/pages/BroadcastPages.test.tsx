// @vitest-environment jsdom
// Parcours réels sans réseau : une écriture serveur n'est pas un accusé de
// réception client, et aucune configuration inconnue ne doit être écrasée.
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  list: vi.fn(), settings: vi.fn(), setSettings: vi.fn(), create: vi.fn(),
  clear: vi.fn(), remove: vi.fn(), setActive: vi.fn(),
  adGet: vi.fn(), adSave: vi.fn(), confirm: vi.fn(),
}));
vi.mock('@/lib/api', async (importOriginal) => {
  const api = await importOriginal<typeof import('@/lib/api')>();
  return {
    ...api,
    announcementsApi: {
      list: mocks.list, getSettings: mocks.settings, setSettings: mocks.setSettings,
      create: mocks.create, clear: mocks.clear, remove: mocks.remove, setActive: mocks.setActive,
    },
    adApi: { get: mocks.adGet, save: mocks.adSave },
  };
});
vi.mock('@/components/confirm', () => ({ confirmAction: mocks.confirm }));
vi.mock('@/components/AppLayout', () => ({
  AppLayout: ({ children, title }: { children: ReactNode; title: string }) => <main><h1>{title}</h1>{children}</main>,
}));
import { ApiError } from '@/lib/api';
import { NotificationsPage } from './NotificationsPage';
import { AdPage } from './AdPage';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
let host: HTMLDivElement;
let root: Root | null;
let blockedFetch: ReturnType<typeof vi.fn>;
const onLogout = vi.fn();
const announcement = { id: 41, title: 'Annonce existante', body: 'Information', url: '', active: 1, created_at: 1 };
const adConfig = { enabled: false, url: '', skip: 5, freq: 'always' };
const text = () => host.textContent ?? '';
const button = (label: string) => Array.from(host.querySelectorAll('button')).find((b) => b.textContent?.trim() === label)!;
const globalToggle = () => host.querySelector('button[aria-label="Activer les notifications"]') as HTMLButtonElement;
const adToggle = () => host.querySelector('button[aria-label="Activer la pub au démarrage"]') as HTMLButtonElement;
async function mount(page: 'announcements' | 'ad' = 'announcements') {
  await act(async () => root!.render(page === 'ad' ? <AdPage onLogout={onLogout} /> : <NotificationsPage onLogout={onLogout} />));
}
async function click(el: HTMLElement) { await act(async () => el.click()); }
async function submit() {
  await act(async () => { host.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
}
function edit(selector: string, value: string) {
  const el = host.querySelector(selector) as HTMLInputElement;
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset());
  mocks.list.mockResolvedValue({ items: [announcement] });
  mocks.settings.mockResolvedValue({ enabled: true });
  mocks.setSettings.mockImplementation(async (enabled: boolean) => ({ ok: true, enabled }));
  mocks.create.mockResolvedValue({ ok: true, id: 42 });
  mocks.clear.mockResolvedValue({ ok: true });
  mocks.remove.mockResolvedValue({ ok: true });
  mocks.setActive.mockImplementation(async (_id: number, active: boolean) => ({ ok: true, active }));
  mocks.adGet.mockResolvedValue(adConfig);
  mocks.adSave.mockImplementation(async (cfg: typeof adConfig) => ({ ok: true, ...cfg }));
  mocks.confirm.mockResolvedValue(true);
  onLogout.mockReset();
  blockedFetch = vi.fn(() => Promise.reject(new Error('Aucun réseau réel autorisé.')));
  vi.stubGlobal('fetch', blockedFetch);
  host = document.createElement('div'); document.body.appendChild(host); root = createRoot(host);
});
afterEach(() => {
  if (root) act(() => root!.unmount());
  root = null; host.remove(); vi.unstubAllGlobals();
  expect(blockedFetch).not.toHaveBeenCalled();
});

describe('annonces : état serveur et écritures sérialisées', () => {
  it('garde l’état inconnu et les actions désactivées pendant une lecture lente', async () => {
    const pending = deferred<{ enabled: boolean }>();
    mocks.settings.mockReturnValue(pending.promise);
    await mount();
    expect(text()).toContain('État des notifications inconnu');
    expect(text()).not.toContain('Notifications activées');
    expect(globalToggle().disabled).toBe(true);
    await submit();
    expect(mocks.create).not.toHaveBeenCalled();
    await act(async () => pending.resolve({ enabled: false }));
    expect(text()).toContain('Notifications désactivées');
    expect(globalToggle().disabled).toBe(false);
  });

  it('montre les erreurs de lecture et permet de réessayer sans écrire les valeurs par défaut', async () => {
    mocks.settings.mockRejectedValueOnce(new ApiError(503, 'unavailable', 'Configuration indisponible'));
    await mount();
    expect(text()).toContain('Configuration indisponible');
    expect(globalToggle().disabled).toBe(true);
    await click(button('Réessayer le chargement'));
    expect(text()).toContain('Notifications activées');
    expect(globalToggle().disabled).toBe(false);
    expect(mocks.setSettings).not.toHaveBeenCalled();
  });

  it('gère un 401 de la liste et ne remplace pas la liste par un succès vide', async () => {
    mocks.list.mockRejectedValueOnce(new ApiError(401, 'unauthorized', 'Session expirée'));
    await mount();
    expect(onLogout).toHaveBeenCalledTimes(1);
    expect((host.querySelector('button[type="submit"]') as HTMLButtonElement).disabled).toBe(true);
    expect(mocks.create).not.toHaveBeenCalled();
  });

  it('enregistre sans promettre la diffusion lorsque le global est désactivé', async () => {
    mocks.settings.mockResolvedValue({ enabled: false });
    await mount();
    edit('input[maxlength="120"]', '  Nouvelle annonce  ');
    await submit();
    expect(mocks.create).toHaveBeenCalledWith(expect.objectContaining({ title: 'Nouvelle annonce', durationMin: 30, country: '' }));
    expect(text()).toContain('La diffusion est désactivée');
    expect(text()).not.toContain('Visible à la prochaine');
    expect(mocks.setSettings).not.toHaveBeenCalled();
  });

  it.each([
    'pas un lien', '/offres', 'javascript:alert(1)', 'mailto:client@example.test',
    'ftp://example.test/offres', 'https://', 'http:/example.test/offres',
    'https://user:secret@example.test/offres', 'http://user@example.test/offres',
  ])('refuse un lien d’annonce non ouvrable ou contenant des identifiants : %s', async (url) => {
    await mount(); edit('input[maxlength="120"]', 'Offre'); edit('#ann-url', url);
    await submit();
    expect(mocks.create).not.toHaveBeenCalled();
    expect(text()).toContain('adresse HTTP ou HTTPS complète, sans identifiants');
    expect((host.querySelector('#ann-url') as HTMLInputElement).value).toBe(url);
  });

  it.each(['https://example.test/offres?ref=annonce#details', 'http://example.test:8080/info'])(
    'conserve le protocole et le lien d’annonce valide sans conversion IPTV : %s', async (url) => {
      await mount(); edit('input[maxlength="120"]', 'Offre'); edit('#ann-url', ` ${url} `);
      await submit();
      expect(mocks.create).toHaveBeenCalledTimes(1);
      expect(mocks.create).toHaveBeenCalledWith(expect.objectContaining({url}));
    },
  );

  it('permet une annonce sans lien optionnel', async () => {
    await mount(); edit('input[maxlength="120"]', 'Information'); edit('#ann-url', '   ');
    await submit(); expect(mocks.create).toHaveBeenCalledWith(expect.objectContaining({url:''}));
  });

  it('bloque les doubles clics et les mutations concurrentes, puis applique la réponse serveur', async () => {
    const pending = deferred<{ ok: boolean; enabled: boolean }>();
    mocks.setSettings.mockReturnValue(pending.promise);
    await mount();
    await act(async () => { globalToggle().click(); globalToggle().click(); });
    expect(mocks.setSettings).toHaveBeenCalledTimes(1);
    expect(mocks.setSettings).toHaveBeenCalledWith(false);
    expect(text()).toContain('Notifications activées');
    expect((host.querySelector('button[type="submit"]') as HTMLButtonElement).disabled).toBe(true);
    const remove = host.querySelector('button[title="Supprimer cette annonce"]') as HTMLButtonElement;
    expect(remove.disabled).toBe(true);
    await click(remove);
    expect(mocks.remove).not.toHaveBeenCalled();
    await act(async () => pending.resolve({ ok: true, enabled: false }));
    expect(text()).toContain('Notifications désactivées');
    expect(globalToggle().disabled).toBe(false);
  });

  it('conserve les réglages et le texte saisi si le serveur refuse une écriture', async () => {
    mocks.setSettings.mockRejectedValue(new ApiError(503, 'unavailable', 'Écriture refusée'));
    await mount();
    await click(globalToggle());
    expect(text()).toContain('Notifications activées');
    expect(text()).toContain('Écriture refusée');
    mocks.create.mockResolvedValue({ ok: false });
    edit('input[maxlength="120"]', 'À conserver');
    await submit();
    expect((host.querySelector('input[maxlength="120"]') as HTMLInputElement).value).toBe('À conserver');
    expect(text()).not.toContain('Annonce enregistrée');
  });

  it('relie activation individuelle, suppression et retrait global aux bons identifiants', async () => {
    await mount();
    await click(host.querySelector('button[title="Désactiver"]') as HTMLButtonElement);
    expect(mocks.setActive).toHaveBeenCalledWith(41, false);
    expect(host.querySelector('button[title="Activer"]')).not.toBeNull();
    await click(host.querySelector('button[title="Supprimer cette annonce"]') as HTMLButtonElement);
    expect(mocks.remove).toHaveBeenCalledWith(41);
    expect(text()).not.toContain('Annonce existante');
    await click(button('Tout retirer'));
    expect(mocks.confirm).toHaveBeenCalledTimes(1);
    expect(mocks.clear).toHaveBeenCalledTimes(1);
    expect(text()).toContain('retirées du serveur');
  });
});

describe('pub vidéo : configuration valide et confirmation honnête', () => {
  it('ne permet pas de sauvegarder après un échec de chargement, puis recharge', async () => {
    mocks.adGet.mockRejectedValueOnce(new ApiError(503, 'unavailable', 'Pub indisponible'));
    await mount('ad');
    expect(text()).toContain('Pub indisponible');
    expect(host.querySelector('form')).toBeNull();
    await click(button('Réessayer le chargement'));
    expect(host.querySelector('form')).not.toBeNull();
    expect(mocks.adSave).not.toHaveBeenCalled();
  });

  it.each(['', 'pas un lien', 'ftp://cdn.example.test/promo.mp4', 'javascript:alert(1)', 'https://www.youtube.com/watch?v=demo', 'https://youtu.be/demo'])(
    'refuse une pub activée avec une URL impropre : %s', async (url) => {
      await mount('ad');
      await click(adToggle());
      edit('#ad-url', url);
      await submit();
      expect(mocks.adSave).not.toHaveBeenCalled();
      expect(text()).toMatch(/URL vidéo complète|pas une page YouTube/);
    },
  );

  it.each(['https://cdn.example.test/promo.mp4?token=demo', 'http://cdn.example.test/stream?id=demo'])(
    'enregistre un lien direct http(s) et empêche la double sauvegarde : %s', async (url) => {
      const pending = deferred<typeof adConfig & { ok: boolean }>();
      mocks.adSave.mockReturnValue(pending.promise);
      await mount('ad');
      await click(adToggle()); edit('#ad-url', ` ${url} `);
      await submit(); await submit();
      expect(mocks.adSave).toHaveBeenCalledTimes(1);
      expect(mocks.adSave).toHaveBeenCalledWith({ enabled: true, url, skip: 5, freq: 'always' });
      expect(button('…').disabled).toBe(true);
      await act(async () => pending.resolve({ ...adConfig, ok: true, enabled: true, url }));
      expect(text()).toContain('Configuration vidéo enregistrée');
      expect(text()).toContain('n’est pas encore confirmée');
      expect(text()).not.toContain('elle se jouera');
    },
  );

  it('permet de désactiver une ancienne URL invalide et déconnecte sur 401', async () => {
    mocks.adGet.mockResolvedValue({ ...adConfig, enabled: true, url: 'ancien lien cassé' });
    await mount('ad'); await click(adToggle()); await submit();
    expect(mocks.adSave).toHaveBeenCalledWith(expect.objectContaining({ enabled: false, url: 'ancien lien cassé' }));
    expect(text()).toContain('désactivée sur le serveur');
    mocks.adSave.mockRejectedValue(new ApiError(401, 'unauthorized', 'Session expirée'));
    await submit();
    expect(onLogout).toHaveBeenCalledTimes(1);
    expect(text()).not.toContain('désactivée sur le serveur');
  });

  it('ignore une erreur arrivée après la fermeture de la page', async () => {
    const pending = deferred<typeof adConfig>();
    mocks.adGet.mockReturnValue(pending.promise);
    await mount('ad');
    act(() => root!.unmount()); root = null;
    await act(async () => pending.reject(new ApiError(401, 'unauthorized', 'Ancienne requête')));
    expect(onLogout).not.toHaveBeenCalled();
  });
});
