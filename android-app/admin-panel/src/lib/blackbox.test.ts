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
  lastTvPlayback,
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

test('la dernière lecture conserve son heure après un zap ou un passage dans les menus', () => {
  const journal = [
    '17/11 12:00:04 I [SON] [Démo A] Seconde 3 : volume lecteur 1,0',
    '17/11 12:00:10 I [IMAGE] [Démo B [HD]] Format 1920x1080',
    '17/11 12:00:22 I [SCREEN] Boîte noire ouverte',
    '17/11 12:01:05 I [MEM] [périodique] process 90 Mo',
  ].join('\n');
  assert.deepEqual(lastTvPlayback(journal), { name: 'Démo B [HD]', time: '17/11 12:00:10' });
  assert.equal(lastTvPlayback(journal + '\n17/11 12:02:00 I [BOOT] démarrage'), null);
});

test('les diagnostics techniques, les secrets et le son témoin ne sont pas des chaînes', () => {
  const lines = [
    '17/11 12:00:04 I [SOURCE] [Démo] importation',
    '17/11 12:00:05 I [SON] [Son témoin] Seconde 1 : volume',
    '17/11 12:00:06 I [IMAGE] [https://source.invalid/a] Format',
    '17/11 12:00:07 I [SON] [username=demo] Seconde 2 : volume',
    '17/11 12:00:08 I [SON] [masqué] autre diagnostic',
  ];
  assert.equal(lastTvPlayback(lines.join('\n')), null);
  assert.deepEqual(lastTvPlayback('17/11 12:00:12 I [SON] [Démo] Seconde 10 : volume'),
    { name: 'Démo', time: '17/11 12:00:12' });
});
