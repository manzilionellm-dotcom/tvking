// @vitest-environment jsdom
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  homeGet: vi.fn(), homeSave: vi.fn(), homeHistory: vi.fn(), homeRestore: vi.fn(),
  themeGet: vi.fn(), themeSave: vi.fn(), rulesGet: vi.fn(), rulesSave: vi.fn(),
  serversList: vi.fn(), serversCreate: vi.fn(), serversUpdate: vi.fn(), serversRemove: vi.fn(),
}));
vi.mock('@/lib/api', async (original) => ({
  ...await original<typeof import('@/lib/api')>(),
  homeLayoutApi: { get: mocks.homeGet, save: mocks.homeSave, history: mocks.homeHistory, restore: mocks.homeRestore },
  themeApi: { get: mocks.themeGet, save: mocks.themeSave, getAutomations: mocks.rulesGet, saveAutomations: mocks.rulesSave },
  serversApi: { list: mocks.serversList, create: mocks.serversCreate, update: mocks.serversUpdate, remove: mocks.serversRemove },
}));
vi.mock('@/components/AppLayout', () => ({ AppLayout: ({ children, actions, subtitle }: { children: ReactNode; actions: ReactNode; subtitle: string }) => <main>{subtitle}{actions}{children}</main> }));
import { HomeManagerPage } from './HomeManagerPage';
import { ThemePage } from './ThemePage';
import { ServersPage } from './ServersPage';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
let host: HTMLDivElement; let root: Root;
let blockedFetch: ReturnType<typeof vi.fn>;
const onLogout = vi.fn();
const homeItems = ['recent','sport','favorites','entertainment','info','kids','general','cinema'].map((key, position) => ({key, position, enabled:1, featured:0, ribbon: key === 'sport' ? 'VIP' : ''}));
const button = (text: string) => Array.from(host.querySelectorAll('button')).find((b) => b.textContent?.trim() === text)!;
async function click(el: HTMLElement) { await act(async () => el.click()); }
async function submit() { await act(async () => { host.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); }); }
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>((r) => resolve = r); return { promise, resolve }; }
beforeEach(() => {
  Object.values(mocks).forEach(m => m.mockReset()); onLogout.mockReset();
  mocks.homeGet.mockResolvedValue({ items: homeItems }); mocks.homeHistory.mockResolvedValue({ items: [] });
  mocks.homeSave.mockImplementation(async (items) => ({ items }));
  mocks.themeGet.mockResolvedValue({ appName: 'Mobile', accent:'#D63A30', bg:'dark' }); mocks.themeSave.mockResolvedValue({ ok: true });
  mocks.rulesGet.mockResolvedValue({ rules: [] }); mocks.rulesSave.mockImplementation(async rules => ({rules}));
  mocks.serversList.mockResolvedValue({ items: [{ id:'s1', label:'Ancien', url:'https://example.invalid', enabled:true }] });
  blockedFetch = vi.fn(() => Promise.reject(new Error('No live network'))); vi.stubGlobal('fetch', blockedFetch);
  host = document.createElement('div'); document.body.appendChild(host); root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.unstubAllGlobals(); expect(blockedFetch).not.toHaveBeenCalled(); });

it('six sections sans consommateur restent en lecture seule sans écriture', async () => {
  await act(async () => root.render(<HomeManagerPage onLogout={onLogout}/>));
  for (const key of ['sport','entertainment','info','kids','general','cinema']) {
    const toggle = host.querySelector(`[aria-label="Visibilité — ${key}"]`) as HTMLButtonElement;
    expect(toggle.disabled).toBe(true); await click(toggle);
    expect((host.querySelector(`[aria-label="Vedette — ${key}"]`) as HTMLButtonElement).disabled).toBe(true);
  }
  await click(button('Enregistrer'));
  expect(mocks.homeSave).not.toHaveBeenCalled();
  expect(host.textContent).toContain('7 MOTION ne prend pas encore en charge');
});

it('favoris visibles et ordre peuvent changer sans altérer les six sections historiques', async () => {
  await act(async () => root.render(<HomeManagerPage onLogout={onLogout}/>));
  await click(host.querySelector('[aria-label="Visibilité — favorites"]') as HTMLElement);
  await click(host.querySelector('[aria-label="Visibilité — recent"]')!.closest('li')!.querySelector('[aria-label="Descendre"]') as HTMLElement);
  await click(button('Enregistrer'));
  const sent = mocks.homeSave.mock.calls[0][0] as typeof homeItems;
  expect(sent.filter(x => !['recent','favorites'].includes(x.key))).toEqual(homeItems.filter(x => !['recent','favorites'].includes(x.key)));
  expect(sent.find(x => x.key === 'favorites')).toMatchObject({ enabled:0, position:0 });
  expect(sent.find(x => x.key === 'recent')).toMatchObject({ position:2 });
});

it('le mobile garde le fond sombre et exclut Light des règles', async () => {
  await act(async () => root.render(<ThemePage onLogout={onLogout}/>));
  expect(button('Clair / Blanc').disabled).toBe(true);
  expect(button('Sombre').disabled).toBe(true);
  expect(button('☀️Light').disabled).toBe(true);
  await click(button('Clair / Blanc'));
  await click(button('+ Ajouter une règle'));
  expect((host.querySelector('option[value="light"]') as HTMLOptionElement).disabled).toBe(true);
  await submit();
  expect(mocks.themeSave).toHaveBeenCalledWith({appName:'Mobile',accent:'#D63A30',bg:'dark'},'mobile');
});

it('ZUNO applique un fond clair et une réponse mobile tardive ne remplace pas ses valeurs', async () => {
  const late = deferred<{appName:string;accent:string;bg:string}>();
  mocks.themeGet.mockImplementation(platform => platform === 'mobile' ? late.promise : Promise.resolve({appName:'ZUNO test',accent:'#123456',bg:'dark'}));
  await act(async () => root.render(<ThemePage onLogout={onLogout}/>));
  await click(button('ZUNO'));
  await act(async () => late.resolve({appName:'Ancien mobile',accent:'#ffffff',bg:'light'}));
  expect(button('Clair / Blanc').disabled).toBe(false);
  await click(button('Clair / Blanc')); await submit();
  expect(mocks.themeSave).toHaveBeenCalledWith({appName:'ZUNO test',accent:'#123456',bg:'light'},'tv');
});

it('une lecture de thème refusée ne permet ni sauvegarde vide ni réinitialisation', async () => {
  mocks.themeGet.mockRejectedValue(new Error('offline'));
  await act(async () => root.render(<ThemePage onLogout={onLogout}/>));
  expect(button('Enregistrer le thème').disabled).toBe(true);
  await submit(); await click(button('Réinitialiser'));
  expect(mocks.themeSave).not.toHaveBeenCalled();
});

it('une lecture de règles refusée ne peut effacer les règles existantes', async () => {
  mocks.rulesGet.mockRejectedValue(new Error('offline'));
  await act(async () => root.render(<ThemePage onLogout={onLogout}/>));
  expect(button('Enregistrer les règles').disabled).toBe(true);
  await click(button('Enregistrer les règles'));
  expect(mocks.rulesSave).not.toHaveBeenCalled();
  expect(host.textContent).toContain('Règles non chargées');
});

it('une sauvegarde de règles garde la plateforme verrouillée jusqu’à sa fin', async () => {
  const pending = deferred<{rules: []}>(); mocks.rulesSave.mockReturnValue(pending.promise);
  await act(async () => root.render(<ThemePage onLogout={onLogout}/>));
  await click(button('Enregistrer les règles'));
  expect(button('ZUNO').disabled).toBe(true);
  await click(button('ZUNO')); expect(mocks.themeGet).toHaveBeenCalledTimes(1);
  await act(async () => pending.resolve({rules:[]}));
  expect(host.textContent).toContain('évaluées en UTC à la prochaine lecture');
  expect(button('ZUNO').disabled).toBe(false);
});

it('le catalogue historique des serveurs est consultable sans actions sans effet', async () => {
  await act(async () => root.render(<ServersPage onLogout={onLogout}/>));
  for (const b of Array.from(host.querySelectorAll('button'))) { expect(b.disabled).toBe(true); await click(b); }
  expect(host.textContent).toContain('Ancien');
  expect(mocks.serversCreate).not.toHaveBeenCalled(); expect(mocks.serversUpdate).not.toHaveBeenCalled(); expect(mocks.serversRemove).not.toHaveBeenCalled();
});
