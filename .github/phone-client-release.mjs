// Prépare et vérifie la livraison exacte du téléphone, sans appel réseau.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = 'manzilionellm-dotcom/tvking';
const tag = 'phone-latest';
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

export function assertClientReferenceUnchanged(before, current) {
  const normalize = (release) => {
    const copy = structuredClone(release);
    for (const asset of copy.assets ?? []) delete asset.download_count;
    return copy;
  };
  assert.equal(before.tag_name, tag);
  assert.equal(current.tag_name, tag);
  assert.deepEqual(normalize(current), normalize(before),
    'La référence clients a changé pendant la compilation ; relire avant publication.');
}

export function createPhoneManifest({ apk, versionCode, versionName, buildLabel, sourceSha, mandatory = false }) {
  assert.ok(Buffer.isBuffer(apk) && apk.length > 0, 'APK absent');
  assert.ok(Number.isSafeInteger(versionCode) && versionCode > 0 && versionCode < 2100000000,
    'versionCode Android invalide');
  assert.ok(typeof versionName === 'string' && versionName.length > 0 && versionName.length <= 100 &&
    !/[\x00-\x1f]/.test(versionName), 'versionName invalide');
  assert.ok(typeof buildLabel === 'string' && buildLabel.length > 0 && buildLabel.length <= 100 &&
    !/[\x00-\x1f]/.test(buildLabel), 'Numéro lisible absent ou invalide');
  assert.match(sourceSha, /^[a-f0-9]{40}$/);
  assert.equal(typeof mandatory, 'boolean');
  return {
    versionCode, versionName, buildLabel,
    url: `https://github.com/${repository}/releases/download/${tag}/7motion.apk`,
    sha256: digest(apk), size: apk.length, mandatory, commit: sourceSha,
  };
}

export function assertPublishedPhone(release, manifest, manifestBytes) {
  assert.equal(release.tag_name, tag);
  for (const [name, sha256, size] of [
    ['7motion.apk', manifest.sha256, manifest.size],
    ['version.json', digest(manifestBytes), manifestBytes.length],
  ]) {
    const assets = release.assets.filter((asset) => asset.name === name);
    assert.equal(assets.length, 1, `Artefact publié absent ou ambigu : ${name}`);
    assert.equal(assets[0].digest, `sha256:${sha256}`, `Empreinte publiée différente : ${name}`);
    assert.equal(assets[0].size, size, `Taille publiée différente : ${name}`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const e = process.env;
  const output = e.PHONE_RELEASE_DIR;
  assert.ok(output, 'Dossier de livraison absent');
  const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
  if (process.argv[2] === 'prepare') {
    assertClientReferenceUnchanged(readJson(e.CLIENT_BEFORE), readJson(e.CLIENT_CURRENT));
    assert.ok(['true', 'false'].includes(e.MANDATORY));
    const manifest = createPhoneManifest({
      apk: readFileSync(e.APK_PATH), versionCode: Number(e.PHONE_VERSION_CODE),
      versionName: e.PHONE_VERSION_NAME, buildLabel: e.PHONE_BUILD_LABEL,
      sourceSha: e.SOURCE_SHA, mandatory: e.MANDATORY === 'true',
    });
    mkdirSync(output, { recursive: true });
    writeFileSync(join(output, 'version.json'), JSON.stringify(manifest, null, 2) + '\n');
    writeFileSync(join(output, 'notes.md'),
      `7 MOTION — téléphone\n\nVersion : ${manifest.versionName}\nVersionCode : ${manifest.versionCode}\n` +
      `Commit : ${manifest.commit}\nSHA-256 : ${manifest.sha256}\n\n` +
      'Synchronisation du panel, suppression durable, actualisation du catalogue, compatibilité des liens et confirmation des choix vidéo.\n');
  } else if (process.argv[2] === 'verify') {
    const bytes = readFileSync(join(output, 'version.json'));
    assertPublishedPhone(readJson(e.CLIENT_PUBLISHED), JSON.parse(bytes), bytes);
    console.log('APK et manifeste publiés identiques aux fichiers signés et contrôlés.');
  } else {
    throw new Error('Opération de livraison inconnue');
  }
}
