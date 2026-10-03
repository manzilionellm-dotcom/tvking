// =========================================================
//  La page ne parle qu'à une MAC valide, et elle relit le
//  journal assez souvent pour l'afficher 1 à 2 s après l'envoi.
//  Lancer : node --experimental-strip-types --test src/lib/blackbox.test.ts
// =========================================================

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  BLACKBOX_POLL_MS,
  formatBlackBoxUpdated,
  normalizePanelMac,
} from './blackbox.ts';

test('relecture entre 1 et 2 secondes', () => {
  assert.equal(BLACKBOX_POLL_MS, 1500);
  assert.ok(BLACKBOX_POLL_MS >= 1000 && BLACKBOX_POLL_MS <= 2000);
});

test('une MAC de box est reconnue, le reste non', () => {
  assert.equal(normalizePanelMac(' mk:aa:bb:cc:dd:01 '), 'MK:AA:BB:CC:DD:01');
  assert.equal(normalizePanelMac('AA:BB:CC:DD:EE:FF'), null);
  assert.equal(normalizePanelMac(''), null);
  assert.equal(normalizePanelMac('MK:ZZ:00:00:00:01'), null);
});

test('pas d\'heure tant que rien n\'est arrivé', () => {
  assert.equal(formatBlackBoxUpdated(0), '');
  const label = formatBlackBoxUpdated(1_700_000_000_000);
  assert.ok(label.length > 8);
});
