// Navigation vers les fiches et état des actions. Adresses factices.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toSourceInput, type SourceLike } from './sources.ts';
import { FLAG_FICHES, FLAG_LISTE_MASQUEE, flagOn, writeFlag, type FlagStore } from './flags.ts';
import {
  ACTIONS_APPAREIL,
  ACTIONS_CLIENT,
  ECRANS_CLIQUABLES,
  apercuesListes,
  actionsInertes,
  actionsPour,
  cheminFiche,
  cibleAppareil,
  cibleClient,
  cibleDepuisAudit,
  cibleListe,
  etatAction,
  joursEssaiValides,
  lireFlags,
  planHideSource,
  trouverAppareil,
} from './fiches.ts';

function memoire(init: Record<string, string> = {}): FlagStore & { data: Record<string, string> } {
  const data = { ...init };
  return {
    data,
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = v; },
  };
}

test('les interrupteurs sont coupés par défaut', () => {
  const store = memoire();
  assert.equal(flagOn(store, FLAG_FICHES), false);
  assert.equal(flagOn(store, FLAG_LISTE_MASQUEE), false);
  assert.deepEqual(lireFlags(store), { fiches: false, listeMasquee: false });
  assert.equal(flagOn(null, FLAG_FICHES), false);
  store.setItem(FLAG_FICHES, 'true');
  store.setItem(FLAG_LISTE_MASQUEE, '0');
  assert.equal(lireFlags(store).fiches, false);
  assert.equal(lireFlags(store).listeMasquee, false);
});

test('seul « 1 » allume un interrupteur', () => {
  const store = memoire();
  writeFlag(store, FLAG_FICHES, true);
  writeFlag(store, FLAG_LISTE_MASQUEE, false);
  assert.equal(store.data[FLAG_FICHES], '1');
  assert.equal(store.data[FLAG_LISTE_MASQUEE], '0');
  assert.equal(lireFlags(store).fiches, true);
  assert.equal(lireFlags(store).listeMasquee, false);
});

test('un clic MAC ou appareil ouvre la fiche appareil', () => {
  const avecId = cibleAppareil({ deviceId: 'dev_1', mac: 'mk:aa:bb:cc:dd:01' });
  assert.ok(avecId);
  assert.equal(avecId.kind, 'appareil');
  assert.equal(avecId.mac, 'MK:AA:BB:CC:DD:01');
  assert.equal(cheminFiche(avecId), '/fiches/appareil/dev_1');

  const macSeule = cibleAppareil({ mac: 'MK:AA:BB:CC:DD:02' });
  assert.equal(cheminFiche(macSeule!), '/fiches/appareil/MK%3AAA%3ABB%3ACC%3ADD%3A02');
  assert.equal(cibleAppareil({ mac: 'pas-une-mac' }), null);
  assert.equal(cibleAppareil({}), null);
});

test('un clic client ouvre la fiche client', () => {
  const c = cibleClient(' cus_1 ');
  assert.deepEqual(c, { kind: 'client', customerId: 'cus_1' });
  assert.equal(cheminFiche(c!), '/fiches/client/cus_1');
  assert.equal(cibleClient('  '), null);
});

test('un clic liste ouvre la fiche liste, panneau ou inventaire', () => {
  const panel = cibleListe({ mac: 'MK:AA:BB:CC:DD:01', index: 1 });
  assert.equal(panel?.kind, 'liste');
  assert.equal(panel?.listOrigin, 'panel');
  assert.equal(cheminFiche(panel!), '/fiches/liste/MK%3AAA%3ABB%3ACC%3ADD%3A01/panel/1');
  assert.equal(cibleListe({ mac: 'MK:AA:BB:CC:DD:01', index: 3 }), null);

  const locale = cibleListe({ deviceId: 'dev_9', index: 0, origin: 'locale' });
  assert.equal(locale?.listOrigin, 'locale');
  assert.equal(cheminFiche(locale!), '/fiches/liste/dev_9/locale/0');
});

test('l’historique mène à la fiche selon la cible', () => {
  assert.equal(cibleDepuisAudit({ target_type: 'customer', target_id: 'cus_2' })?.kind, 'client');
  assert.equal(cibleDepuisAudit({ target_type: 'device', target_id: 'dev_3' })?.deviceId, 'dev_3');
  assert.equal(
    cibleDepuisAudit({ target_type: 'device_source', target_id: 'MK:AA:BB:CC:DD:04' })?.mac,
    'MK:AA:BB:CC:DD:04',
  );
  assert.equal(cibleDepuisAudit({ target_type: 'theme', target_id: 'mobile' }), null);
});

test('les actions sans route sont « bientôt », le masquage est coupé', () => {
  const off = { listeMasquee: false };
  const on = { listeMasquee: true };
  const appareil = new Map(ACTIONS_APPAREIL.map((a) => [a.id, etatAction(a, off)]));
  assert.equal(appareil.get('geler'), 'prete');
  assert.equal(appareil.get('activer'), 'prete');
  assert.equal(appareil.get('copier-mac'), 'prete');
  assert.equal(appareil.get('desactiver'), 'bientot');
  assert.equal(appareil.get('notes-appareil'), 'bientot');
  assert.equal(appareil.get('historique'), 'bientot');

  for (const a of ACTIONS_CLIENT) {
    if (a.id === 'enregistrer-client' || a.id === 'copier-client') {
      assert.equal(etatAction(a, off), 'prete');
    } else {
      assert.equal(etatAction(a, off), 'bientot', a.id);
    }
  }

  const masquer = actionsPour('liste').find((a) => a.id === 'masquer-liste');
  assert.ok(masquer);
  assert.equal(etatAction(masquer, off), 'coupee');
  assert.equal(etatAction(masquer, on), 'bientot');
  assert.equal(etatAction(actionsPour('liste', 'locale').find((a) => a.id === 'retirer-liste')!, off), 'bientot');
  assert.equal(etatAction(actionsPour('liste', 'panel').find((a) => a.id === 'retirer-liste')!, off), 'prete');
});

test('une action prête est bloquée sans identifiant ou sans droit', () => {
  const ids = actionsInertes({
    canActivate: false,
    canSources: false,
    superAdmin: false,
    blockStatus: 'active',
    listeAbsente: true,
  });
  assert.ok(ids.includes('reactiver'));
  assert.ok(ids.includes('geler'));
  assert.ok(ids.includes('activer'));
  assert.ok(ids.includes('prolonger-essai'));
  assert.ok(ids.includes('pousser-liste'));
  assert.ok(ids.includes('notes-client'));
  assert.ok(ids.includes('retirer-liste'));
});

test('la recherche d’appareil préfère l’identifiant puis la MAC exacte', () => {
  const items = [
    { id: 'dev_a', mac: 'MK:AA:BB:CC:DD:01' },
    { id: 'dev_b', mac: 'MK:AA:BB:CC:DD:02' },
  ];
  assert.equal(trouverAppareil(items, { deviceId: 'dev_b', mac: 'MK:AA:BB:CC:DD:01' })?.id, 'dev_b');
  assert.equal(trouverAppareil(items, { mac: 'mk:aa:bb:cc:dd:01' })?.id, 'dev_a');
  assert.equal(trouverAppareil(items, { mac: 'MK:11:22:33:44:55' }), null);
});

test('l’aperçu de liste ne reprend pas les champs internes', () => {
  const brut = {
    type: 'xtream' as const,
    label: 'Liste exemple',
    username: 'abonne-exemple',
    hidden: true,
  };
  const [vue] = apercuesListes([brut], 'panel');
  assert.deepEqual(Object.keys(vue).sort(), ['identifiant', 'index', 'label', 'origin', 'resume', 'type']);
  assert.equal(JSON.stringify(vue).includes('hidden'), false);
  assert.equal(vue.identifiant, 'abonne-exemple');
  assert.equal(vue.resume, 'Identifiants enregistrés');
});

test('masquer une liste n’envoie rien, interrupteur coupé ou allumé', () => {
  assert.deepEqual(planHideSource(false), { send: false, reason: 'flag' });
  assert.deepEqual(planHideSource(true), { send: false, reason: 'no-route' });
});

test('le corps envoyé au Worker ne gagne pas le champ hidden', () => {
  const input = toSourceInput({
    type: 'm3u',
    label: 'Liste exemple',
    m3u_url: null,
    hidden: true,
  } as SourceLike);
  assert.equal('hidden' in input, false);
  assert.equal(input.m3u_url, null);
});

test('prolonger l’essai n’accepte qu’un entier de 1 à 365', () => {
  assert.equal(joursEssaiValides(7), 7);
  assert.equal(joursEssaiValides('365'), 365);
  assert.equal(joursEssaiValides(0), null);
  assert.equal(joursEssaiValides(1.5), null);
  assert.equal(joursEssaiValides(366), null);
});

test('chaque écran prévu a au moins une cible connue', () => {
  const kinds = new Set(['appareil', 'client', 'liste']);
  assert.ok(ECRANS_CLIQUABLES.length >= 10);
  for (const ecran of ECRANS_CLIQUABLES) {
    assert.ok(ecran.cibles.length > 0, ecran.ecran);
    for (const cible of ecran.cibles) assert.ok(kinds.has(cible), ecran.ecran);
  }
});
