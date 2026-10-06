// =========================================================
//  delivery.test.ts — « Suivi de l'envoi » ne dit que ce que la box a accusé
// =========================================================
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deliveryStatus, findOrder } from './delivery.ts';

const here = dirname(fileURLToPath(import.meta.url));

test('sans accusé (ordre absent, created, sent) : en attente, jamais « confirmé »', () => {
  for (const o of [null, { order_id: 'o', state: 'created' }, { order_id: 'o', state: 'sent' }]) {
    const s = deliveryStatus(o);
    assert.equal(s.kind, 'wait');
    assert.equal(s.done, false);
    assert.equal(s.text, 'Enregistrée sur le serveur. En attente de la box…');
  }
});

test('received → chargement ; applied → confirmé ; failed → raison de la box', () => {
  assert.equal(deliveryStatus({ order_id: 'o', state: 'received' }).text, 'Ordre reçu par la box. Chargement en cours…');
  assert.deepEqual(deliveryStatus({ order_id: 'o', state: 'applied' }), { kind: 'ok', text: 'Listes confirmées sur la box.', done: true });
  assert.equal(
    deliveryStatus({ order_id: 'o', state: 'failed', error_message: 'Fournisseur injoignable.' }).text,
    'La box n’a pas chargé la liste : Fournisseur injoignable.',
  );
  assert.equal(deliveryStatus({ order_id: 'o', state: 'failed' }).text, 'La box n’a pas chargé la liste : raison non transmise.');
  assert.equal(deliveryStatus({ order_id: 'o', state: 'expired' }).kind, 'late');
});

test('retrait : textes du retrait', () => {
  assert.equal(deliveryStatus({ order_id: 'o', state: 'applied' }, 'remove').text, 'Retrait confirmé par la box.');
});

test('findOrder suit CET ordre, pas le plus récent d’une autre opération', () => {
  const items = [{ order_id: 'b', state: 'applied' }, { order_id: 'a', state: 'failed' }];
  assert.equal(findOrder(items, 'a')?.state, 'failed');
  assert.equal(findOrder(items, 'z'), null);
  assert.equal(findOrder(undefined, 'a'), null);
});

test('l’écran Listes n’annonce plus « la box est prévenue » sur la seule réponse HTTP', () => {
  // Code seulement : les commentaires qui racontent l'ancien défaut ne comptent pas.
  const page = readFileSync(join(here, '..', 'pages', 'ChainesPage.tsx'), 'utf8')
    .split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
  assert.equal(/box est prévenue/.test(page), false);
  assert.match(page, /deliveryStatus\(/);
});
