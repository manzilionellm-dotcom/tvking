import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readZunoReference, assertZunoReferenceUnchanged, createZunoManifest, assertPublishedZuno } from './zuno-client-release.mjs';

const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const apk = Buffer.from('Zuno APK signé');
const prior = { versionCode: 1791700000, versionName: '142', sha256: digest(apk), size: apk.length };
const bytes = Buffer.from(JSON.stringify(prior) + '\n');
const reference = { id: 1, tag_name: 'zuno-tv', draft: false, assets: [
  { id: 2, name: 'version.json', size: bytes.length, digest: `sha256:${digest(bytes)}`, download_count: 1 },
  { id: 3, name: 'zuno-tv.apk', size: apk.length, digest: `sha256:${digest(apk)}`, download_count: 2 },
] };

test('la référence précédente exige un manifeste et un APK cohérents', () => {
  assert.deepEqual(readZunoReference(reference, bytes), prior);
  for (const key of ['size', 'digest']) {
    const bad = structuredClone(reference);
    bad.assets[0][key] = 'incorrect';
    assert.throws(() => readZunoReference(bad, bytes));
  }
  const wrongApk = structuredClone(reference);
  wrongApk.assets[1].digest = 'sha256:incorrect';
  assert.throws(() => readZunoReference(wrongApk, bytes));
  assert.throws(() => readZunoReference({ ...reference, assets: [] }, bytes));
  assert.throws(() => readZunoReference({ ...reference, draft: true }, bytes));
});

test('les téléchargements clients sont permis, un remplacement concurrent bloque la publication', () => {
  const current = structuredClone(reference);
  current.assets[0].download_count++;
  assert.doesNotThrow(() => assertZunoReferenceUnchanged(reference, current));
  current.assets[1].id++;
  assert.throws(() => assertZunoReferenceUnchanged(reference, current));
});

test('un retour de version, un numéro invalide ou une provenance absente sont refusés', () => {
  const input = { apk, versionCode: 1793300000, versionName: '143', sourceSha: 'a'.repeat(40), previous: prior };
  const m = createZunoManifest(input);
  assert.equal(m.mandatory, false);
  assert.equal(m.sha256, digest(apk));
  assert.equal(m.commit, input.sourceSha);
  for (const change of [
    { versionCode: prior.versionCode }, { versionCode: 2100000000 },
    { versionCode: Number.NaN }, { versionName: '142' },
    { versionName: '143-test' }, { sourceSha: 'main' }, { apk: Buffer.alloc(0) },
  ]) assert.throws(() => createZunoManifest({ ...input, ...change }));
});

test('la preuve après publication porte sur les deux fichiers exacts', () => {
  assert.doesNotThrow(() => assertPublishedZuno(reference, apk, bytes));
  assert.throws(() => assertPublishedZuno(reference, Buffer.from('autre APK'), bytes));
  assert.throws(() => assertPublishedZuno(reference, apk, Buffer.from('{}')));
  assert.throws(() => assertPublishedZuno({ ...reference, tag_name: 'zuno-tv-test' }, apk, bytes));
});
