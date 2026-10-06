// Retirer UNE liste : on renvoie les autres, intactes. Adresses factices.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planRemoveSource, toSourceInput, type SourceLike } from './sources.ts';

// Champs internes que le serveur renvoie aussi (ils ne doivent pas repartir).
const xtream = {
  type: 'xtream',
  label: 'Principal',
  server_url: 'http://serveur.example.invalid',
  username: 'u1',
  password: 'p1',
  epg_url: 'http://guide.example.invalid/xmltv.php',
  mac: 'MK:AA:BB:CC:DD:EE',
  updated_at: 123,
  reseller_id: 'r1',
} as SourceLike;
const m3u: SourceLike = { type: 'm3u', m3u_url: 'http://liste.example.invalid/l.m3u' };
const m3u2: SourceLike = { type: 'm3u', label: 'Sport', m3u_url: 'http://liste.example.invalid/s.m3u' };

test('retirer la 2e de 3 : les deux autres repartent, dans l\'ordre, intactes', () => {
  const plan = planRemoveSource([xtream, m3u, m3u2], 1);
  assert.equal(plan.kind, 'keep');
  if (plan.kind !== 'keep') return;
  assert.deepEqual(plan.sources, [
    {
      type: 'xtream',
      label: 'Principal',
      server_url: 'http://serveur.example.invalid',
      username: 'u1',
      password: 'p1',
      epg_url: 'http://guide.example.invalid/xmltv.php',
    },
    { type: 'm3u', label: 'Sport', m3u_url: 'http://liste.example.invalid/s.m3u' },
  ]);
});

test('le mot de passe n\'est jamais perdu en route', () => {
  const plan = planRemoveSource([m3u, xtream], 0);
  assert.equal(plan.kind, 'keep');
  if (plan.kind !== 'keep') return;
  assert.equal(plan.sources[0].password, 'p1');
});

test('dernière liste : effacement complet', () => {
  assert.deepEqual(planRemoveSource([m3u], 0), { kind: 'clear' });
});

test('index hors limites : on n\'envoie rien', () => {
  assert.deepEqual(planRemoveSource([m3u], 3), { kind: 'invalid' });
  assert.deepEqual(planRemoveSource([], 0), { kind: 'invalid' });
  assert.deepEqual(planRemoveSource([m3u], -1), { kind: 'invalid' });
});

test('champs internes retirés (mac, date, revendeur)', () => {
  const input = toSourceInput(xtream) as Record<string, unknown>;
  assert.equal('mac' in input, false);
  assert.equal('updated_at' in input, false);
  assert.equal('reseller_id' in input, false);
});

// ---------------------------------------------------------------
//  Listes ajoutées par le CLIENT (origin = self) : jamais renvoyées.
// ---------------------------------------------------------------
import {
  isClientList, planActivationList, sourceFingerprint, validateListInput,
} from './sources.ts';

const clientList = { type: 'm3u', m3u_url: 'http://perso.example.invalid/p.m3u', origin: 'self' } as SourceLike;
const panelList = { type: 'm3u', m3u_url: 'http://liste.example.invalid/a.m3u', origin: 'panel' } as SourceLike;

test('retirer une liste du panel : celle du client ne repart pas (le serveur la garde)', () => {
  const plan = planRemoveSource([panelList, clientList, m3u2], 0);
  assert.equal(plan.kind, 'keep');
  if (plan.kind !== 'keep') return;
  assert.deepEqual(plan.sources, [
    { type: 'm3u', label: 'Sport', m3u_url: 'http://liste.example.invalid/s.m3u' },
  ]);
});

test('dernière liste du panel, il reste celle du client : effacement panel seulement', () => {
  assert.deepEqual(planRemoveSource([panelList, clientList], 0), { kind: 'clear' });
});

test('liste du client visée : rien n\'est envoyé', () => {
  assert.deepEqual(planRemoveSource([panelList, clientList], 1), { kind: 'client', id: null });
  // Avec son identifiant serveur, le panel peut la retirer (05/10/2026).
  const clientWithId = { ...clientList, id: 'c-123' } as SourceLike;
  assert.deepEqual(planRemoveSource([panelList, clientWithId], 1), { kind: 'client', id: 'c-123' });
  assert.equal(isClientList(clientList), true);
  assert.equal(isClientList(panelList), false);
});

test('empreinte identique à la box (slash final et casse du serveur ignorés)', () => {
  assert.equal(
    sourceFingerprint({ type: 'xtream', server_url: 'HTTP://Srv.example.invalid:8080/', username: 'u1' }),
    'xtream|http://srv.example.invalid:8080|u1',
  );
  assert.equal(sourceFingerprint({ type: 'm3u', m3u_url: ' http://l.example.invalid/x.m3u ' }), 'm3u|http://l.example.invalid/x.m3u');
  assert.equal(sourceFingerprint({ type: 'm3u', m3u_url: '' }), null);
});

test('saisie vérifiée AVANT d\'activer', () => {
  assert.equal(validateListInput({ type: 'm3u', m3u_url: 'http://l.example.invalid/x.m3u' }), null);
  assert.match(validateListInput({ type: 'm3u', m3u_url: '' })!, /manquant/);
  assert.match(validateListInput({ type: 'm3u', m3u_url: 'ftp://x' })!, /http/);
  assert.equal(validateListInput({ type: 'xtream', server_url: 'http://s.example.invalid', username: 'u', password: 'p' }), null);
  assert.match(validateListInput({ type: 'xtream', server_url: 'http://s.example.invalid', username: 'u', password: '' })!, /Mot de passe/);
  assert.match(validateListInput({ type: 'xtream', server_url: 's.example', username: 'u', password: 'p' })!, /http/);
});

test('activation + liste : la liste saisie remplace celles du panel, celle du client reste', () => {
  const add = { type: 'xtream' as const, server_url: 'http://s.example.invalid', username: 'u9', password: 'p9' };
  const plan = planActivationList([panelList, clientList], add);
  assert.equal(plan.kind, 'send');
  assert.deepEqual(plan.sources, [add]);
  assert.equal(plan.replaced, 1);
  assert.equal(plan.clientKept, 1);
  assert.equal(plan.unchanged, false);
});

test('activation + liste : 3 listes du panel déjà posées → remplacées, jamais « full » (mesuré 05/10/2026)', () => {
  const three = [panelList, m3u, m3u2];
  const plan = planActivationList(three, { type: 'm3u', m3u_url: 'http://neuf.example.invalid/n.m3u' });
  assert.equal(plan.sources.length, 1);
  assert.equal(plan.sources[0].m3u_url, 'http://neuf.example.invalid/n.m3u');
  assert.equal(plan.replaced, 3);
  assert.equal(plan.clientKept, 0);
});

test('activation + liste : déjà la seule liste du panel → renvoyée telle quelle (la box est prévenue)', () => {
  const plan = planActivationList([panelList, clientList], { type: 'm3u', m3u_url: 'http://liste.example.invalid/a.m3u' });
  assert.equal(plan.unchanged, true);
  assert.equal(plan.replaced, 0);
  assert.deepEqual(plan.sources, [{ type: 'm3u', m3u_url: 'http://liste.example.invalid/a.m3u' }]);
});

test('activation + liste : déjà présente parmi d\'autres listes du panel → les autres sont remplacées', () => {
  const plan = planActivationList([panelList, m3u], { type: 'm3u', m3u_url: 'http://liste.example.invalid/a.m3u' });
  assert.equal(plan.unchanged, false);
  assert.equal(plan.replaced, 1);
  assert.equal(plan.sources.length, 1);
});

test('activation + liste : box sans liste → envoi simple', () => {
  const plan = planActivationList([], { type: 'm3u', m3u_url: 'http://neuf.example.invalid/n.m3u' });
  assert.equal(plan.replaced, 0);
  assert.equal(plan.clientKept, 0);
  assert.equal(plan.sources.length, 1);
});

// ---------------------------------------------------------------
//  Interrupteur allumé / éteint
// ---------------------------------------------------------------
import { isListOn, planToggleSource } from './sources.ts';

test('éteindre la 2e liste : toutes les listes du panel repartent, la 2e avec enabled:false', () => {
  const plan = planToggleSource([panelList, m3u2, clientList], 1);
  assert.equal(plan.kind, 'send');
  if (plan.kind !== 'send') return;
  assert.equal(plan.nowOn, false);
  assert.equal(plan.sources.length, 2, 'la liste du client ne repart pas');
  assert.equal(plan.sources[0].enabled, undefined);
  assert.equal(plan.sources[1].enabled, false);
  assert.equal(plan.sources[1].m3u_url, 'http://liste.example.invalid/s.m3u');
});

test('rallumer : le champ disparaît, les autres listes éteintes le restent', () => {
  const offA = { ...panelList, enabled: false } as SourceLike;
  const offB = { ...m3u2, enabled: false } as SourceLike;
  const plan = planToggleSource([offA, offB], 0);
  assert.equal(plan.kind, 'send');
  if (plan.kind !== 'send') return;
  assert.equal(plan.nowOn, true);
  assert.equal(plan.sources[0].enabled, undefined);
  assert.equal(plan.sources[1].enabled, false);
  assert.equal(isListOn(offA), false);
  assert.equal(isListOn(panelList), true);
});

test('interrupteur sur une liste du client ou hors limites : rien', () => {
  assert.deepEqual(planToggleSource([panelList, clientList], 1), { kind: 'client' });
  assert.deepEqual(planToggleSource([panelList], 5), { kind: 'invalid' });
});

test('supprimer une liste garde l\'état éteint des autres', () => {
  const offB = { ...m3u2, enabled: false } as SourceLike;
  const plan = planRemoveSource([panelList, offB], 0);
  assert.equal(plan.kind, 'keep');
  if (plan.kind !== 'keep') return;
  assert.equal(plan.sources[0].enabled, false);
});

// ----- Écran Listes : « Ajouter » garde les autres listes (06/10/2026) -----
import { listDisplayName, planAddList } from './sources.ts';

const A = { type: 'm3u' as const, m3u_url: 'http://a.invalid/l.m3u', enabled: false };
const B = { type: 'm3u' as const, m3u_url: 'http://b.invalid/l.m3u' };
const X = { type: 'xtream' as const, server_url: 'http://x.invalid', username: 'u', password: 'p' };
const SELF = { type: 'm3u' as const, m3u_url: 'http://c.invalid/l.m3u', origin: 'self', id: 'self-1' };

test('ajouter un M3U garde les M3U déjà là, éteints compris', () => {
  const p = planAddList([A, SELF], 'http://b.invalid/l.m3u', false);
  assert.equal(p.kind, 'send');
  if (p.kind !== 'send') return;
  assert.deepEqual(p.sources, [
    { type: 'm3u', m3u_url: 'http://a.invalid/l.m3u', enabled: false },
    { type: 'm3u', m3u_url: 'http://b.invalid/l.m3u' },
  ], 'A reste éteinte, la liste du client n’est pas renvoyée');
});

test('trois listes du panel : un 4e ajout est refusé, rien n’est écrasé', () => {
  assert.equal(planAddList([A, B, X], 'http://d.invalid/l.m3u', false).kind, 'full');
});

test('lien déjà présent : pas de doublon, il est rallumé à sa place', () => {
  const p = planAddList([A, B], ' http://a.invalid/l.m3u ', false);
  assert.equal(p.kind, 'send');
  if (p.kind !== 'send') return;
  assert.equal(p.sources.length, 2);
  assert.equal(p.already, true);
  assert.equal(p.sources[0].enabled, undefined);
});

test('remplacer : la nouvelle seule ; lien invalide : rien n’est envoyé', () => {
  const p = planAddList([A, B, X], 'http://d.invalid/l.m3u', true);
  assert.equal(p.kind === 'send' && p.sources.length, 1);
  assert.equal(planAddList([A], 'ftp://x', false).kind, 'invalid');
  assert.equal(planAddList([A], '', false).kind, 'invalid');
});

test('nom affiché : libellé ou hôte, jamais le chemin ni les codes', () => {
  assert.equal(listDisplayName({ type: 'm3u', m3u_url: 'http://h.invalid:8080/get.php?username=u&password=p' }), 'h.invalid:8080');
  assert.equal(listDisplayName({ type: 'm3u', label: 'Salon', m3u_url: 'http://h.invalid/x' }), 'Salon');
  assert.equal(listDisplayName({ type: 'xtream', server_url: 'pas une adresse' }), 'Xtream');
});
