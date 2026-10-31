// Vérifie les octets du canal Zuno avant et après sa publication autorisée.
// Une lecture réseau absente n'est jamais interprétée comme une version zéro.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const tag = 'zuno-tv';
const repository = 'manzilionellm-dotcom/tvking';
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

function assertAsset(release, name, bytes) {
  const assets = release.assets?.filter((asset) => asset.name === name) ?? [];
  assert.equal(assets.length, 1, `Artefact absent ou ambigu : ${name}`);
  assert.equal(assets[0].size, bytes.length, `Taille différente : ${name}`);
  assert.equal(assets[0].digest, `sha256:${digest(bytes)}`, `Empreinte différente : ${name}`);
}

export function readZunoReference(release, manifestBytes) {
  assert.equal(release.tag_name, tag);
  assert.equal(release.draft, false, 'La référence Zuno doit être publiée');
  assertAsset(release, 'version.json', manifestBytes);
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  assert.ok(Number.isSafeInteger(manifest.versionCode) && manifest.versionCode > 0,
    'VersionCode précédent absent ou invalide');
  assert.match(manifest.versionName, /^\d+$/, 'Version visible précédente invalide');
  const apks = release.assets.filter((asset) => asset.name === 'zuno-tv.apk');
  assert.equal(apks.length, 1, 'APK précédent absent ou ambigu');
  assert.equal(apks[0].digest, `sha256:${manifest.sha256}`, 'Le manifeste précédent ne désigne pas son APK');
  assert.equal(apks[0].size, manifest.size, 'Taille du précédent APK incohérente');
  return manifest;
}

export function assertZunoReferenceUnchanged(before, current) {
  const normalize = (release) => {
    const copy = structuredClone(release);
    for (const asset of copy.assets ?? []) delete asset.download_count;
    return copy;
  };
  assert.equal(before.tag_name, tag);
  assert.equal(current.tag_name, tag);
  assert.deepEqual(normalize(current), normalize(before),
    'Le canal Zuno a changé pendant la compilation ; relire avant publication.');
}

export function createZunoManifest({ apk, versionCode, versionName, sourceSha, previous }) {
  assert.ok(Buffer.isBuffer(apk) && apk.length > 0, 'APK Zuno absent');
  assert.ok(Number.isSafeInteger(versionCode) && versionCode > previous.versionCode && versionCode < 2100000000,
    'Le versionCode Zuno doit progresser');
  assert.match(versionName, /^\d+$/, 'Version visible Zuno invalide');
  assert.ok(Number(versionName) > Number(previous.versionName), 'La version visible Zuno doit progresser');
  assert.match(sourceSha, /^[a-f0-9]{40}$/);
  return {
    versionCode, versionName,
    url: `https://github.com/${repository}/releases/download/${tag}/zuno-tv.apk`,
    sha256: digest(apk), size: apk.length, mandatory: false, commit: sourceSha,
  };
}

export function assertPublishedZuno(release, apk, manifestBytes) {
  assert.equal(release.tag_name, tag);
  assert.equal(release.draft, false);
  assertAsset(release, 'zuno-tv.apk', apk);
  assertAsset(release, 'version.json', manifestBytes);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const e = process.env;
  const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
  const before = () => readJson(e.ZUNO_CLIENT_BEFORE);
  const previous = () => readZunoReference(before(), readFileSync(e.ZUNO_PREVIOUS_MANIFEST));
  if (process.argv[2] === 'reference') {
    // Seul le numéro validé est écrit ; aucune clé ni entrée brute n'est affichée.
    process.stdout.write(previous().versionName);
  } else if (process.argv[2] === 'prepare') {
    assertZunoReferenceUnchanged(before(), readJson(e.ZUNO_CLIENT_CURRENT));
    const apk = readFileSync(e.ZUNO_APK_PATH);
    assert.equal(digest(apk), e.ZUNO_APK_SHA256, 'APK différent du binaire contrôlé');
    const manifest = createZunoManifest({
      apk, versionCode: Number(e.TV_BUILD_NUMBER), versionName: e.TV_VERSION_NAME,
      sourceSha: e.SOURCE_SHA, previous: previous(),
    });
    writeFileSync(e.ZUNO_MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n');
  } else if (process.argv[2] === 'verify') {
    assertPublishedZuno(readJson(e.ZUNO_CLIENT_PUBLISHED), readFileSync(e.ZUNO_APK_PATH),
      readFileSync(e.ZUNO_MANIFEST_PATH));
    console.log('APK Zuno et manifeste publiés identiques au binaire signé et contrôlé.');
  } else {
    throw new Error('Opération Zuno inconnue');
  }
}
