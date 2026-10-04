// MAC saisie sans « MK: » : le panel complète tout seul. MAC factices.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { displayMac, isValidMac, normalizeMac } from './mac.ts';

test('sans MK: ni séparateur, le format serveur est reconstruit', () => {
  for (const raw of [
    'AD:A6:98:70:6A',
    'ad:a6:98:70:6a',
    'AD-A6-98-70-6A',
    'ADA698706A',
    ' ada6 9870 6a ',
    'MK:AD:A6:98:70:6A',
    'mk:ad:a6:98:70:6a',
    'MKADA698706A',
    'MK AD A6 98 70 6A',
  ]) {
    assert.equal(normalizeMac(raw), 'MK:AD:A6:98:70:6A', raw);
    assert.equal(isValidMac(raw), true, raw);
  }
});

test('saisie incomplète, trop longue ou fausse : rien n\'est inventé', () => {
  assert.equal(normalizeMac('AD:A6:98'), 'AD:A6:98');
  assert.equal(isValidMac('AD:A6:98'), false);
  assert.equal(isValidMac('AD:A6:98:70:6A:FF'), false);
  assert.equal(isValidMac('ZZ:A6:98:70:6A'), false);
  assert.equal(isValidMac(''), false);
  assert.equal(normalizeMac('MK:'), 'MK:');
});

test('ce que voit le client : sans MK:', () => {
  assert.equal(displayMac('MK:AD:A6:98:70:6A'), 'AD:A6:98:70:6A');
  assert.equal(displayMac('n\'importe quoi'), 'n\'importe quoi');
});
