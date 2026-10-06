// timeline.test.ts — mise en forme de la chronologie et des latences.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { eventLabel, eventTone, formatMs } from './timeline.ts';

test('un segment sans mesure ne montre jamais de chiffre', () => {
  assert.equal(formatMs(null), 'non mesuré');
  assert.equal(formatMs(undefined), 'non mesuré');
  assert.equal(formatMs(Number.NaN), 'non mesuré');
  assert.equal(formatMs(0), '0 ms');
  assert.equal(formatMs(193), '193 ms');
  assert.equal(formatMs(1100), '1.10 s');
  assert.equal(formatMs(14600), '14.6 s');
});

test('libellés et gravité des événements', () => {
  assert.equal(eventLabel('BOX_APPLIED'), 'Box : ordre appliqué');
  assert.equal(eventLabel('activate.renew'), 'Panel : renouvellement');
  assert.equal(eventLabel('source.rollback'), 'Panel : listes (rollback)');
  assert.equal(eventLabel('inconnu.x'), 'inconnu.x');
  assert.equal(eventTone('BOX_FAILED'), 'bad');
  assert.equal(eventTone('ORDER_EXPIRED'), 'warn');
  assert.equal(eventTone('BOX_APPLIED'), 'ok');
});
