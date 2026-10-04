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
