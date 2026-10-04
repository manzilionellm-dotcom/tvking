// Pouvoirs clients : logique pure du panel. Aucune donnée réelle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_PAYMENT_MESSAGE, buildPaymentPayload, checkPayLink, describeAction,
  parseDays, parseHours,
} from './powers.ts';

test('parseDays : 1 à 365, entier seulement', () => {
  assert.deepEqual(parseDays(' 30 '), { days: 30 });
  for (const bad of ['', '0', '-3', '1.5', 'abc', '366']) {
    assert.ok('error' in parseDays(bad), bad);
  }
});

test('parseHours : vide = sans limite ; bornes', () => {
  assert.deepEqual(parseHours(''), { hours: null });
  assert.deepEqual(parseHours('2,5'), { hours: 2.5 });
  for (const bad of ['0', '-1', 'x', '2161']) assert.ok('error' in parseHours(bad), bad);
});

test('checkPayLink : https seulement', () => {
  assert.deepEqual(checkPayLink(''), { link: null });
  assert.ok('error' in checkPayLink('http://exemple.test'));
  assert.ok('error' in checkPayLink('https://u:p@exemple.test'));
  assert.ok('error' in checkPayLink('pas un lien'));
  assert.deepEqual(checkPayLink('https://exemple.test/p'), { link: 'https://exemple.test/p' });
});

test('buildPaymentPayload : message par défaut, devise en majuscules', () => {
  const r = buildPaymentPayload({ message: '  ', amount: ' 20 ', currency: 'eur', link: '' });
  assert.ok('payload' in r);
  if (!('payload' in r)) return;
  assert.equal(r.payload.message, DEFAULT_PAYMENT_MESSAGE);
  assert.equal(r.payload.amount, '20');
  assert.equal(r.payload.currency, 'EUR');
  assert.equal('link' in r.payload, false);
  assert.ok('error' in buildPaymentPayload({ message: 'x', amount: '', currency: '', link: 'ftp://a' }));
});

test('describeAction : libellé FR connu, sinon la clé brute', () => {
  assert.equal(describeAction('client.refresh'), 'Relecture forcée');
  assert.equal(describeAction('autre.chose'), 'autre.chose');
});
