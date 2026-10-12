import assert from 'node:assert/strict';
import { test } from 'node:test';
import { describeBoxTarget, sameBoxTarget } from './box-target.ts';

const A = 'MK:AA:BB:CC:DD:01';
const B = 'MK:AA:BB:CC:DD:02';

test('normalisation sans substitution : deux codes proches restent deux appareils', () => {
  assert.equal(sameBoxTarget(A, 'aa-bb-cc-dd-01'), true);
  assert.equal(sameBoxTarget(A, B), false);
  assert.equal(sameBoxTarget('', ''), false);
  assert.equal(sameBoxTarget('incomplet', 'incomplet'), false);
});

test('une création manuelle avec date et plateforme ne prouve pas un retour appareil', () => {
  assert.deepEqual(describeBoxTarget(A, [{ mac: A, platform: 'mobile', last_seen_at: 1_791_000_000 }]),
    { kind: 'unidentified', mac: A });
});

test('le modèle de l’autre code ne permet pas de déclarer le code sélectionné identifié', () => {
  assert.deepEqual(describeBoxTarget(A, [{ mac: B, device_model: 'TV de test', app_build: 175 }]),
    { kind: 'missing', mac: A });
});

test('le modèle retourné correspond uniquement au code choisi', () => {
  assert.deepEqual(describeBoxTarget(A, [
    { mac: B, device_model: 'Autre TV', app_build: 176 },
    { mac: A, device_model: 'TV de test', app_build: 175, last_seen_at: 1_791_000_000 },
  ]), { kind: 'reported', mac: A, model: 'TV de test', lastSeen: 1_791_000_000 });
});

test('les placeholders restent non identifiés ; une version reçue suffit', () => {
  assert.equal(describeBoxTarget(A, [{ mac: A, device_model: '—', app_build: null }]).kind, 'unidentified');
  assert.equal(describeBoxTarget(A, [{ mac: A, device_model: ' ', app_build: 0 }]).kind, 'unidentified');
  assert.equal(describeBoxTarget(A, [{ mac: A, app_build: 175 }]).kind, 'reported');
});
