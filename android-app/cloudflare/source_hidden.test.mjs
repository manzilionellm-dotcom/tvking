// Drapeau « hidden » par liste. Aucune adresse réelle, aucun mot de passe.
// Exécuter : node --test android-app/cloudflare/source_hidden.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  sourceHiddenOn, withHidden, applyHiddenPolicy, hiddenSignature, readHiddenSignature,
} from './source_hidden.js';

const ON = { SOURCE_HIDDEN: '1' };
const OFF = {};
const src = { type: 'm3u', label: 'Exemple', m3u_url: 'chiffre:factice', epg_url: null };

test('interrupteur : coupé par défaut', () => {
  assert.equal(sourceHiddenOn(OFF), false);
  assert.equal(sourceHiddenOn({ SOURCE_HIDDEN: '0' }), false);
  for (const v of ['1', 'true', 'ON', 'yes']) assert.equal(sourceHiddenOn({ SOURCE_HIDDEN: v }), true);
});

test('écriture coupée : hidden ignoré, source identique (même objet)', () => {
  const r = withHidden(OFF, src, { ...src, hidden: true });
  assert.equal(r.source, src);
  assert.equal('hidden' in r.source, false);
  // Même une valeur invalide est ignorée quand c'est coupé (comportement d'avant).
  assert.equal(withHidden(OFF, src, { hidden: 'oui' }).error, undefined);
});

test('écriture allumée : true stocké, false/absent non écrit, autre valeur refusée', () => {
  assert.deepEqual(withHidden(ON, src, { hidden: true }).source, { ...src, hidden: true });
  assert.equal('hidden' in withHidden(ON, src, { hidden: false }).source, false);
  assert.equal('hidden' in withHidden(ON, src, {}).source, false);
  assert.equal('hidden' in withHidden(ON, src, { hidden: null }).source, false);
  for (const bad of ['true', 1, 'oui', {}]) {
    assert.ok(withHidden(ON, src, { hidden: bad }).error, String(bad));
  }
});

test('lecture coupée : tout hidden stocké est retiré (réponse d’avant)', () => {
  const stored = [{ ...src, hidden: true }, { ...src }];
  const out = applyHiddenPolicy(OFF, stored);
  assert.equal(JSON.stringify(out).includes('hidden'), false);
  assert.deepEqual(out[1], src);
});

test('lecture allumée : seul hidden:true est livré', () => {
  const stored = [{ ...src, hidden: true }, { ...src, hidden: 'x' }, { ...src }];
  const out = applyHiddenPolicy(ON, stored);
  assert.equal(out[0].hidden, true);
  assert.equal('hidden' in out[1], false);
  assert.equal('hidden' in out[2], false);
  assert.equal(applyHiddenPolicy(ON, null), null);
});

test('signature : positions des listes du panel masquées, listes du client ignorées', () => {
  assert.equal(hiddenSignature([]), '');
  assert.equal(hiddenSignature([{ hidden: true }, {}, { hidden: true }]), '0,2');
  assert.equal(hiddenSignature([
    { origin: 'panel' }, { origin: 'panel', hidden: true }, { origin: 'self', hidden: true },
  ]), '1');
  assert.notEqual(hiddenSignature([{ hidden: true }]), hiddenSignature([{}]));
});

test('signature stockée : lue depuis sources_json, panne D1 = ""', async () => {
  const env = { DB: { prepare() { return { bind() { return { async first() {
    return { sources_json: JSON.stringify([{ origin: 'panel' }, { origin: 'panel', hidden: true }]) };
  } }; } }; } } };
  assert.equal(await readHiddenSignature(env, 'MK:AA:BB:CC:DD:EE'), '1');
  const broken = { DB: { prepare() { throw new Error('boom'); } } };
  assert.equal(await readHiddenSignature(broken, 'MK:AA:BB:CC:DD:EE'), '');
});
