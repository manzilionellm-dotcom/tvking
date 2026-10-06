// idempotency.test.ts — vie de la clé d'idempotence (voir idempotency.ts).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { keepIdempotencyKeyAfter, newIdempotencyKey } from './idempotency.ts';

test('clé : 8 à 128 caractères [A-Za-z0-9_-], comme l’exige le Worker', () => {
  for (let i = 0; i < 20; i++) {
    const k = newIdempotencyKey();
    assert.match(k, /^[A-Za-z0-9_-]{8,128}$/);
  }
  assert.notEqual(newIdempotencyKey(), newIdempotencyKey());
});

test('coupure réseau ou 5xx : on garde la clé (la requête a pu passer)', () => {
  assert.equal(keepIdempotencyKeyAfter({ status: 0 }), true);
  assert.equal(keepIdempotencyKeyAfter({ status: 500 }), true);
  assert.equal(keepIdempotencyKeyAfter({ status: 503 }), true);
  assert.equal(keepIdempotencyKeyAfter(new TypeError('Failed to fetch')), true);
});

test('refus métier 4xx : nouvelle clé au prochain clic', () => {
  for (const status of [400, 401, 402, 403, 404, 409]) {
    assert.equal(keepIdempotencyKeyAfter({ status }), false, `status ${status}`);
  }
});
