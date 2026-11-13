// Ligne client du panel : pays, appareil, version, dernière vue.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  appVersionLabel, countryCode, countryName, deviceKind, seenInfo,
} from './clientRow.ts';

test('pays : seulement un vrai code ISO2, jamais inventé', () => {
  assert.equal(countryCode('se'), 'SE');
  assert.equal(countryCode(' Ca '), 'CA');
  for (const bad of ['', null, undefined, 'XX', 'T1', 'SWE', '??', 12]) {
    assert.equal(countryCode(bad), '', String(bad));
  }
  assert.equal(countryName('SE'), 'Suède');
  assert.equal(countryName('us'), 'États-Unis');
  assert.equal(countryName(''), '');
});

test('appareil : du modèle le plus précis au plus général', () => {
  assert.equal(deviceKind({ platform: 'tv', device_model: 'Amazon AFTKA' }), 'Fire TV');
  assert.equal(deviceKind({ platform: 'tv', device_model: 'NVIDIA SHIELD Android TV' }), 'NVIDIA Shield');
  assert.equal(deviceKind({ platform: 'tv', device_model: 'Google Chromecast' }), 'Google TV');
  assert.equal(deviceKind({ platform: 'tv', device_model: 'Xiaomi MIBOX4' }), 'Xiaomi TV');
  assert.equal(deviceKind({ platform: 'tv', device_model: 'Sony BRAVIA 4K' }), 'Sony TV');
  assert.equal(deviceKind({ platform: 'tv', device_model: 'Inconnu 123' }), 'Android TV');
  assert.equal(deviceKind({ platform: 'mobile', device_model: 'samsung SM-G991B' }), 'Mobile');
  assert.equal(deviceKind({ platform: 'mobile', device_model: 'Sony XQ-AT51' }), 'Mobile');
  assert.equal(deviceKind({ platform: null, device_model: 'OnePlus 9' }), 'Android');
  assert.equal(deviceKind({}), '');
});

test('dernière vue : en ligne sous 15 min, puis durée lisible', () => {
  const now = 1_800_000_000_000;
  const ago = (ms: number) => seenInfo(now - ms, now);
  assert.deepEqual(ago(60_000), { online: true, label: 'En ligne' });
  assert.deepEqual(ago(20 * 60_000), { online: false, label: 'il y a 20 min' });
  assert.deepEqual(ago(3 * 3_600_000), { online: false, label: 'il y a 3 h' });
  assert.deepEqual(ago(5 * 86_400_000), { online: false, label: 'il y a 5 j' });
  assert.deepEqual(ago(90 * 86_400_000), { online: false, label: 'il y a 3 mois' });
  // Vieille ligne en secondes : même résultat.
  assert.deepEqual(seenInfo((now - 3 * 3_600_000) / 1000, now), { online: false, label: 'il y a 3 h' });
  assert.deepEqual(seenInfo(null, now), { online: false, label: '—' });
  assert.deepEqual(seenInfo(0, now), { online: false, label: '—' });
});

test('version : le nom si l\'app l\'envoie, sinon le build', () => {
  assert.equal(appVersionLabel('117', 1794559149), 'v117');
  assert.equal(appVersionLabel('', 1794559149), 'build 1794559149');
  assert.equal(appVersionLabel(null, null), '');
});
