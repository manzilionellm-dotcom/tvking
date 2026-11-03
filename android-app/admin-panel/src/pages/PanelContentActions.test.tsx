// @vitest-environment jsdom
// Les boutons écrivent une configuration connue, une seule fois, et ne
// remplacent les données affichées qu'après confirmation du serveur.
import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  featuredGet: vi.fn(), featuredSet: vi.fn(), promptGet: vi.fn(), promptSave: vi.fn(), feedbackList: vi.fn(),
  serversList: vi.fn(), serversCreate: vi.fn(), serversUpdate: vi.fn(), serversRemove: vi.fn(), confirm: vi.fn(),
  forceGet: vi.fn(), forceEnable: vi.fn(), forceDisable: vi.fn(), pricingGet: vi.fn(), pricingSave: vi.fn(), pricingGrant: vi.fn(),
}));
vi.mock('@/lib/api', async (original) => ({
  ...await original<typeof import('@/lib/api')>(),
  forceUpdateApi: { get: mocks.forceGet, force: mocks.forceEnable, disable: mocks.forceDisable },
  pricingApi: { get: mocks.pricingGet, save: mocks.pricingSave, grantTrialAll: mocks.pricingGrant },
  featuredApi: { get: mocks.featuredGet, set: mocks.featuredSet },
  feedbackApi: { getPrompt: mocks.promptGet, savePrompt: mocks.promptSave, list: mocks.feedbackList },
  serversApi: { list: mocks.serversList, create: mocks.serversCreate, update: mocks.serversUpdate, remove: mocks.serversRemove },
}));
vi.mock('@/components/confirm', () => ({ confirmAction: mocks.confirm }));
vi.mock('@/components/AppLayout', () => ({ AppLayout: ({ children, actions }: { children: ReactNode; actions: ReactNode }) => <main>{actions}{children}</main> }));
import { FeaturedPage } from './FeaturedPage';
import { ReviewsPage } from './ReviewsPage';
import { ServersPage } from './ServersPage';
import { ForceUpdatePage } from './ForceUpdatePage';
import { TarifsPage } from './TarifsPage';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
let host: HTMLDivElement; let root: Root;
let blockedFetch: ReturnType<typeof vi.fn>;
const onLogout = vi.fn();
const button = (text: string) => Array.from(host.querySelectorAll('button')).find((b) => b.textContent?.trim() === text)!;
async function click(el: HTMLElement) { await act(async () => el.click()); }
async function submit() { await act(async () => host.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))); }
function edit(selector: string, value: string) {
  const el = host.querySelector(selector) as HTMLInputElement | HTMLTextAreaElement;
  act(() => {
    const prototype = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(prototype, 'value')!.set!.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>((r) => resolve = r); return { promise, resolve }; }
beforeEach(() => {
  Object.values(mocks).forEach(m => m.mockReset()); onLogout.mockReset();
  mocks.featuredGet.mockResolvedValue({ name: 'Chaîne existante', note: 'Note existante' });
  mocks.featuredSet.mockImplementation(async (name, note) => ({ ok:true, name, note }));
  mocks.promptGet.mockResolvedValue({ enabled:true, message:'Votre avis' });
  mocks.promptSave.mockImplementation(async cfg => ({ ok:true, ...cfg })); mocks.feedbackList.mockResolvedValue({ items:[] });
  mocks.serversList.mockResolvedValue({items:[{id:'srv_one',label:'Personnel',url:'https://fixture.invalid',enabled:true}]});
  mocks.serversCreate.mockResolvedValue({ id:'srv_new' }); mocks.serversUpdate.mockResolvedValue({ updated:1 }); mocks.serversRemove.mockResolvedValue({ deleted:1 }); mocks.confirm.mockResolvedValue(true);
  mocks.forceGet.mockResolvedValue({minBuildTs:0,configuredMinBuildTs:0,latestBuildTs:1000,publishedBuildTs:1000,observedLatestBuildTs:1000,canForce:true}); mocks.forceEnable.mockResolvedValue({ok:true,minBuildTs:1000}); mocks.forceDisable.mockResolvedValue({ok:true,minBuildTs:0});
  mocks.pricingGet.mockResolvedValue({currency:'€',lifetime:'9,90',yearly:'4,90',trialDays:7}); mocks.pricingSave.mockImplementation(async cfg => ({ok:true,...cfg})); mocks.pricingGrant.mockResolvedValue({ok:true,updated:2,days:7});
  blockedFetch = vi.fn(() => Promise.reject(new Error('No live network'))); vi.stubGlobal('fetch', blockedFetch);
  host = document.createElement('div'); document.body.appendChild(host); root = createRoot(host);
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.unstubAllGlobals(); expect(blockedFetch).not.toHaveBeenCalled(); });

it('favori : une lecture échouée interdit une suppression accidentelle puis peut être retentée', async () => {
  mocks.featuredGet.mockRejectedValueOnce(new Error('offline'));
  await act(async () => root.render(<FeaturedPage onLogout={onLogout}/>));
  expect(host.querySelector('form')).toBeNull(); expect(mocks.featuredSet).not.toHaveBeenCalled();
  await click(button('Réessayer le chargement'));
  expect((host.querySelector('input[maxlength="80"]') as HTMLInputElement).value).toBe('Chaîne existante');
});
it('favori : retirer attend le serveur et préserve la chaîne si la suppression est refusée', async () => {
  mocks.featuredSet.mockResolvedValue({ok:false});
  await act(async () => root.render(<FeaturedPage onLogout={onLogout}/>));
  await click(button('Retirer'));
  expect(mocks.featuredSet).toHaveBeenCalledWith('','');
  expect((host.querySelector('input[maxlength="80"]') as HTMLInputElement).value).toBe('Chaîne existante');
  expect(host.textContent).not.toContain('Favori du jour retiré.');
});
it('favori : deux soumissions rapides produisent une seule écriture', async () => {
  const pending = deferred<{ok:boolean}>(); mocks.featuredSet.mockReturnValue(pending.promise);
  await act(async () => root.render(<FeaturedPage onLogout={onLogout}/>));
  await act(async () => { const form=host.querySelector('form')!; for(let i=0;i<2;i++) form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true})); });
  expect(mocks.featuredSet).toHaveBeenCalledTimes(1); expect(host.querySelector('fieldset')!.disabled).toBe(true);
  await act(async () => pending.resolve({ok:true})); expect(host.querySelector('fieldset')!.disabled).toBe(false);
});
it('avis : une configuration non lue ne peut être enregistrée vide', async () => {
  mocks.promptGet.mockRejectedValue(new Error('offline'));
  await act(async () => root.render(<ReviewsPage onLogout={onLogout}/>));
  expect(host.querySelector('form')).toBeNull(); expect(mocks.promptSave).not.toHaveBeenCalled();
});
it('avis : le refus serveur conserve le message et ne promet pas sa diffusion', async () => {
  mocks.promptSave.mockResolvedValue({ok:false});
  await act(async () => root.render(<ReviewsPage onLogout={onLogout}/>));
  edit('textarea', 'Message à conserver'); await submit();
  expect(mocks.promptSave).toHaveBeenCalledWith({enabled:true,message:'Message à conserver'});
  expect((host.querySelector('textarea') as HTMLTextAreaElement).value).toBe('Message à conserver');
  expect(host.textContent).not.toContain('Invitation enregistrée');
});
it('avis : enregistrement sérialisé et modifications verrouillées pendant la réponse', async () => {
  const pending = deferred<{ok:boolean}>(); mocks.promptSave.mockReturnValue(pending.promise);
  await act(async () => root.render(<ReviewsPage onLogout={onLogout}/>));
  await act(async () => { const form=host.querySelector('form')!; for(let i=0;i<2;i++) form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true})); });
  expect(mocks.promptSave).toHaveBeenCalledTimes(1); expect(host.querySelector('fieldset')!.disabled).toBe(true);
  await act(async () => pending.resolve({ok:true}));
  expect(host.textContent).toContain('Invitation enregistrée');
});
it('serveurs : état inconnu bloque la création, relecture réussie ouvre le catalogue', async () => {
  mocks.serversList.mockRejectedValueOnce(new Error('offline'));
  await act(async () => root.render(<ServersPage onLogout={onLogout}/>));
  expect(button('+ Nouveau serveur').disabled).toBe(true);
  await click(button('+ Nouveau serveur')); expect(host.querySelector('form')).toBeNull();
  await click(button('Réessayer le chargement')); expect(button('+ Nouveau serveur').disabled).toBe(false);
});
it('serveurs : création explicite HTTP valide, sans credentials dans le lien', async () => {
  await act(async () => root.render(<ServersPage onLogout={onLogout}/>)); await click(button('+ Nouveau serveur'));
  edit('input[maxlength="80"]','Mon serveur'); edit('input[maxlength="2000"]','https://user:secret@fixture.invalid'); await submit();
  expect(mocks.serversCreate).not.toHaveBeenCalled();
  edit('input[maxlength="2000"]','https://fixture.invalid:8080'); await submit();
  expect(mocks.serversCreate).toHaveBeenCalledWith({label:'Mon serveur',url:'https://fixture.invalid:8080'});
  expect(host.querySelector('form')).toBeNull();
});
it('serveurs : masquer et supprimer visent le bon identifiant, annuler ne supprime rien', async () => {
  await act(async () => root.render(<ServersPage onLogout={onLogout}/>)); await click(button('Masquer'));
  expect(mocks.serversUpdate).toHaveBeenCalledWith('srv_one',{enabled:false});
  mocks.confirm.mockResolvedValueOnce(false); await click(button('Supprimer')); expect(mocks.serversRemove).not.toHaveBeenCalled();
  await click(button('Supprimer')); expect(mocks.serversRemove).toHaveBeenCalledWith('srv_one');
  expect(mocks.confirm).toHaveBeenCalledWith(expect.objectContaining({message:expect.stringContaining('listes déjà ajoutées')}));
});
it('serveurs : une double validation ne crée pas deux suggestions', async () => {
  const pending=deferred<{id:string}>(); mocks.serversCreate.mockReturnValue(pending.promise);
  await act(async () => root.render(<ServersPage onLogout={onLogout}/>)); await click(button('+ Nouveau serveur'));
  edit('input[maxlength="80"]','Mon serveur'); edit('input[maxlength="2000"]','https://fixture.invalid');
  await act(async () => {const form=host.querySelector('form')!; for(let i=0;i<2;i++) form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));});
  expect(mocks.serversCreate).toHaveBeenCalledTimes(1); await click(button('Annuler')); expect(host.querySelector('form')).not.toBeNull();
  await act(async () => pending.resolve({id:'srv_new'})); expect(host.querySelector('form')).toBeNull();
});

it('mise à jour : un chargement inconnu ne permet aucun forçage, puis peut être retenté', async () => {
  mocks.forceGet.mockRejectedValueOnce(new Error('offline'));
  await act(async () => root.render(<ForceUpdatePage onLogout={onLogout}/>));
  expect(button('Forcer la mise à jour')).toBeUndefined(); expect(host.textContent).not.toContain('Inactive');
  await click(button('Réessayer le chargement')); expect(button('Forcer la mise à jour').disabled).toBe(false);
  expect(mocks.forceEnable).not.toHaveBeenCalled();
});
it('mise à jour : une réponse mobile tardive ne remplace pas la configuration Zuno', async () => {
  const late=deferred<{minBuildTs:number;latestBuildTs:number}>();
  mocks.forceGet.mockImplementation(platform => platform === 'mobile' ? late.promise : Promise.resolve({minBuildTs:123,configuredMinBuildTs:123,latestBuildTs:2000,publishedBuildTs:2000,canForce:true}));
  await act(async () => root.render(<ForceUpdatePage onLogout={onLogout}/>)); await click(button('ZUNO'));
  await act(async () => late.resolve({minBuildTs:0,latestBuildTs:0}));
  expect(host.textContent).toContain('Forcée active'); expect(button('Forcer la mise à jour').disabled).toBe(false);
  await click(button('Désactiver')); expect(mocks.forceDisable).toHaveBeenCalledWith('tv');
});
it('mise à jour : la confirmation verrouille la plateforme et les doubles écritures', async () => {
  const pending=deferred<boolean>(); mocks.confirm.mockReturnValue(pending.promise);
  await act(async () => root.render(<ForceUpdatePage onLogout={onLogout}/>));
  await click(button('Forcer la mise à jour')); expect(button('ZUNO').disabled).toBe(true);
  await click(button('ZUNO')); expect(mocks.forceGet).toHaveBeenCalledTimes(1);
  expect(mocks.forceEnable).not.toHaveBeenCalled(); await act(async () => pending.resolve(true));
  expect(mocks.forceEnable).toHaveBeenCalledTimes(1); expect(mocks.forceEnable).toHaveBeenCalledWith('mobile');
});
it('mise à jour : le refus serveur ne confirme pas le forçage', async () => {
  mocks.forceEnable.mockResolvedValue({ok:false,minBuildTs:1000});
  await act(async () => root.render(<ForceUpdatePage onLogout={onLogout}/>)); await click(button('Forcer la mise à jour'));
  expect(host.textContent).not.toContain('ACTIVÉE'); expect(host.textContent).toContain('Inactive');
});
it.each([
  {minBuildTs:77,latestBuildTs:9000},
  {minBuildTs:0,configuredMinBuildTs:77,latestBuildTs:0,publishedBuildTs:0,observedLatestBuildTs:9000,canForce:false,blockedReason:'APK absent du canal client.'},
  {minBuildTs:0,configuredMinBuildTs:77,latestBuildTs:9000,publishedBuildTs:0,observedLatestBuildTs:9000,canForce:true},
])('mise à jour : sans preuve publiée, aucun forçage mais un ancien seuil peut être retiré (%j)', async (status) => {
  mocks.forceGet.mockResolvedValue(status);
  await act(async () => root.render(<ForceUpdatePage onLogout={onLogout}/>));
  expect(button('Forcer la mise à jour').disabled).toBe(true);
  await click(button('Forcer la mise à jour')); expect(mocks.forceEnable).not.toHaveBeenCalled(); expect(mocks.confirm).not.toHaveBeenCalled();
  expect(host.textContent).toContain('Forçage indisponible'); expect(button('Désactiver').disabled).toBe(false);
  await click(button('Désactiver')); expect(mocks.forceDisable).toHaveBeenCalledWith('mobile');
  expect(button('Désactiver').disabled).toBe(true);
});
it('mise à jour : seul le build publié autorise le forçage malgré une observation plus récente', async () => {
  mocks.forceGet.mockResolvedValue({minBuildTs:0,configuredMinBuildTs:0,latestBuildTs:9000,publishedBuildTs:1000,observedLatestBuildTs:9000,canForce:true});
  await act(async () => root.render(<ForceUpdatePage onLogout={onLogout}/>));
  expect(button('Forcer la mise à jour').disabled).toBe(false);
  expect(host.textContent).toContain(`Version publiée vérifiée : ${new Date(1000*1000).toLocaleString()}`);
  await click(button('Forcer la mise à jour'));
  expect(mocks.forceEnable).toHaveBeenCalledTimes(1); expect(mocks.forceEnable).toHaveBeenCalledWith('mobile');
  expect(host.textContent).toContain(`Versions antérieures au ${new Date(1000*1000).toLocaleString()}`);
});
it('tarifs : une configuration inconnue interdit enregistrement et prolongation de masse', async () => {
  mocks.pricingGet.mockRejectedValueOnce(new Error('offline'));
  await act(async () => root.render(<TarifsPage onLogout={onLogout}/>));
  await submit(); expect(mocks.pricingSave).not.toHaveBeenCalled();
  expect(button('Donner 7 jours à tous les appareils actifs').disabled).toBe(true);
  await click(button('Réessayer le chargement')); expect(button('Enregistrer les tarifs').disabled).toBe(false);
});
it('tarifs : retirer les deux montants transmet des valeurs vides sans prix de remplacement', async () => {
  await act(async () => root.render(<TarifsPage onLogout={onLogout}/>));
  edit('[aria-label="Prix à vie"]',''); edit('[aria-label="Prix 1 an"]',''); await submit();
  expect(mocks.pricingSave).toHaveBeenCalledWith(expect.objectContaining({lifetime:'',yearly:''}));
  expect((host.querySelector('[aria-label="Prix à vie"]') as HTMLInputElement).value).toBe('');
  expect(host.textContent).not.toContain('9,90'); expect(host.textContent).toContain('Non proposée');
});
it('tarifs : lien de paiement invalide refusé et sauvegarde sérialisée', async () => {
  const pending=deferred<{ok:boolean;lifetime:string;yearly:string}>(); mocks.pricingSave.mockReturnValue(pending.promise);
  await act(async () => root.render(<TarifsPage onLogout={onLogout}/>));
  edit('input[placeholder="Lien https de paiement (vide par défaut)"]','http://fixture.invalid'); await submit();
  expect(mocks.pricingSave).not.toHaveBeenCalled(); edit('input[placeholder="Lien https de paiement (vide par défaut)"]','https://fixture.invalid');
  await act(async () => {const form=host.querySelector('form')!; for(let i=0;i<2;i++) form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));});
  expect(mocks.pricingSave).toHaveBeenCalledTimes(1); expect(host.querySelector('fieldset')!.disabled).toBe(true);
  expect(button('Donner 7 jours à tous les appareils actifs').disabled).toBe(true);
  await act(async () => pending.resolve({ok:true,lifetime:'9,90',yearly:'4,90'}));
});
it('tarifs : attendre ou annuler une prolongation ne permet pas une sauvegarde concurrente', async () => {
  const pending=deferred<boolean>(); mocks.confirm.mockReturnValue(pending.promise);
  const prompt=vi.spyOn(window,'prompt').mockReturnValue('7');
  await act(async () => root.render(<TarifsPage onLogout={onLogout}/>)); await click(button('Donner 7 jours à tous les appareils actifs'));
  expect(host.querySelector('fieldset')!.disabled).toBe(true); await submit(); expect(mocks.pricingSave).not.toHaveBeenCalled();
  await act(async () => pending.resolve(false)); expect(mocks.pricingGrant).not.toHaveBeenCalled();
  expect(host.querySelector('fieldset')!.disabled).toBe(false); prompt.mockRestore();
});
