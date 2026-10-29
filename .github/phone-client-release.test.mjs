import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { assertClientReferenceUnchanged, createPhoneManifest, assertPublishedPhone } from './phone-client-release.mjs';

const apk = Buffer.from('APK de recette signé par le constructeur');
const sha = 'a'.repeat(40);
const manifest = () => createPhoneManifest({ apk, versionCode: 1793300000, versionName: '0.3.8', buildLabel: '1988114', sourceSha: sha });
const release = { id: 1, tag_name: 'phone-latest', assets: [{ id: 2, name: '7motion.apk', download_count: 4 }] };

test('manifeste lié aux octets et au commit, mise à jour ordinaire par défaut', () => {
  const m = manifest();
  assert.equal(m.sha256, createHash('sha256').update(apk).digest('hex'));
  assert.equal(m.size, apk.length);
  assert.equal(m.commit, sha);
  assert.equal(m.buildLabel, '1988114');
  assert.equal(m.mandatory, false);
  assert.equal(m.url, 'https://github.com/manzilionellm-dotcom/tvking/releases/download/phone-latest/7motion.apk');
});

test('lecture de référence admise, remplacement concurrent refusé', () => {
  const downloaded = structuredClone(release);
  downloaded.assets[0].download_count++;
  assert.doesNotThrow(() => assertClientReferenceUnchanged(release, downloaded));
  for (const key of ['id', 'name', 'digest']) {
    const changed = structuredClone(downloaded);
    changed.assets[0][key] = 'nouveau';
    assert.throws(() => assertClientReferenceUnchanged(release, changed));
  }
  assert.throws(() => assertClientReferenceUnchanged(release, { ...release, tag_name: 'phone-test' }));
});

test('valeurs de version et provenance invalides refusées avant écriture', () => {
  const input = { apk, versionCode: 1793300000, versionName: '0.3.8', buildLabel: '1988114', sourceSha: sha };
  for (const versionCode of [0, -1, 1.5, 2100000000, Number.NaN]) {
    assert.throws(() => createPhoneManifest({ ...input, versionCode }));
  }
  for (const change of [{ apk: Buffer.alloc(0) }, { versionName: '' }, { buildLabel: '' }, { sourceSha: 'main' }, { mandatory: 'true' }]) {
    assert.throws(() => createPhoneManifest({ ...input, ...change }));
  }
});

test('publication vérifiée sur APK et manifeste, pas seulement sur le nom', () => {
  const m = manifest();
  const bytes = Buffer.from(JSON.stringify(m, null, 2) + '\n');
  const published = { tag_name: 'phone-latest', assets: [
    { name: '7motion.apk', digest: `sha256:${m.sha256}`, size: m.size },
    { name: 'version.json', digest: `sha256:${createHash('sha256').update(bytes).digest('hex')}`, size: bytes.length },
  ] };
  assert.doesNotThrow(() => assertPublishedPhone(published, m, bytes));
  for (let i = 0; i < 2; i++) {
    const bad = structuredClone(published); bad.assets[i].digest = 'sha256:incorrect';
    assert.throws(() => assertPublishedPhone(bad, m, bytes));
  }
  assert.throws(() => assertPublishedPhone({ ...published, assets: published.assets.slice(0, 1) }, m, bytes));
});
