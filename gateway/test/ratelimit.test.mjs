// Test unitaire du limiteur de débit (fenêtre glissante, horloge simulée).
import test from 'node:test';
import assert from 'node:assert/strict';
import { RateLimiter } from '../src/ratelimit.js';

test('RateLimiter — autorise jusqu’à max, refuse au-delà, se recharge', () => {
  let t = 1000;
  const rl = new RateLimiter(3, 1000, () => t);

  // 3 requêtes passent, la 4e est refusée (même fenêtre).
  assert.equal(rl.allow('papa'), true);
  assert.equal(rl.allow('papa'), true);
  assert.equal(rl.allow('papa'), true);
  assert.equal(rl.allow('papa'), false, '4e requête dans la fenêtre : refusée');

  // Un AUTRE utilisateur a son propre quota.
  assert.equal(rl.allow('maman'), true, 'quota indépendant par clé');

  // On avance au-delà de la fenêtre → le quota se recharge.
  t += 1001;
  assert.equal(rl.allow('papa'), true, 'fenêtre écoulée : de nouveau autorisé');
});

test('RateLimiter — max=0 désactive la limite', () => {
  const rl = new RateLimiter(0, 1000, () => 0);
  for (let i = 0; i < 100; i++) assert.equal(rl.allow('x'), true);
});

test('RateLimiter — recharge PARTIELLE (glissement, pas remise à zéro)', () => {
  let t = 0;
  const rl = new RateLimiter(2, 100, () => t);
  assert.equal(rl.allow('a'), true); // à t=0
  t = 50;
  assert.equal(rl.allow('a'), true); // à t=50 (2 dans la fenêtre)
  assert.equal(rl.allow('a'), false); // plein
  t = 101; // le hit de t=0 sort ; celui de t=50 reste
  assert.equal(rl.allow('a'), true, 'un seul créneau libéré');
  assert.equal(rl.allow('a'), false, 'toujours plein (hit t=50 + t=101)');
});
