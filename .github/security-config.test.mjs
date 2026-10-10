// Les contrôles lisent les vrais workflows ; aucun appel à une release réelle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

const read = (name) => readFileSync(new URL(name, import.meta.url), 'utf8');
const tv = read('workflows/build-zuno-tv.yml');
const phone = read('workflows/build-7motion-sport-test.yml');
const quality = read('workflows/quality-zuno.yml');
const cleanup = read('workflows/cleanup-old-apks.yml');

for (const [name, content] of [['box', tv], ['mobile', phone], ['qualité', quality]]) {
  test(`${name} : les actions sont figées par commit complet`, () => {
    for (const [, action] of content.matchAll(/\buses:\s*([^\s#]+)/g)) {
      if (action.startsWith('./')) continue;
      assert.match(action, /^[\w-]+\/[\w.-]+@[a-f0-9]{40}$/, action);
    }
  });
  test(`${name} : le SDK stable est fixé à la version validée`, () => {
    const setups = [...content.matchAll(/uses: subosito\/flutter-action@[^\n]+\n([\s\S]*?)(?=\n\s*- (?:name:|uses:|run:)|$)/g)];
    assert.ok(setups.length > 0);
    for (const setup of setups) assert.match(setup[1], /flutter-version: ['"]?3\.47\.7['"]?/);
  });
  test(`${name} : les paramètres Flutter sont placés dans with`, () => {
    const setups = [...content.matchAll(/uses: subosito\/flutter-action@[^\n]+\n([\s\S]*?)(?=\n\s*- (?:name:|uses:|run:)|$)/g)];
    assert.ok(setups.length > 0);
    for (const [, block] of setups) {
      const withLine = block.match(/^( +)with:\s*$/m);
      assert.ok(withLine, 'with absent pour Flutter');
      const inputs = [...block.matchAll(/^( +)(?:flutter-version|channel|cache|pub-cache):/gm)];
      assert.ok(inputs.length > 0);
      for (const input of inputs) {
        assert.equal(input[1].length, withLine[1].length + 2, input[0].trim());
      }
    }
  });
}

test('les tests et la compilation TV n’ont pas le droit d’écrire les releases', () => {
  assert.match(tv, /^permissions:\n  contents: read/m);
  const build = tv.match(/^  build-tv:\n([\s\S]*?)(?=^  [a-z][\w-]*:|$(?![\s\S]))/m)?.[1];
  assert.ok(build);
  assert.doesNotMatch(build, /contents: write|gh release upload/);
  assert.match(tv, /^  publish:\n/m);
});

test('la suppression traite les tags comme des données, jamais comme du shell', () => {
  assert.doesNotMatch(cleanup, /for t in \$\{\{ inputs\.tags \}\}/);
  assert.match(cleanup, /release-cleanup\.mjs/);
  assert.match(cleanup, /github\.triggering_actor == github\.repository_owner/);
});

test('les apps et leurs protections appartiennent au propriétaire', () => {
  const path = new URL('CODEOWNERS', import.meta.url);
  assert.ok(existsSync(path), 'CODEOWNERS absent sur la branche app');
  assert.match(read('CODEOWNERS'), /^\/android-app\/ @manzilionellm-dotcom$/m);
  assert.match(read('CODEOWNERS'), /^\/\.github\/ @manzilionellm-dotcom$/m);
});

test('le snapshot ne réécrit jamais l’histoire et utilise un accès Cloudflare distinct', () => {
  const snapshot = read('workflows/worker-prod-snapshot.yml');
  assert.doesNotMatch(snapshot, /git push (?:-f|--force)/);
  assert.match(snapshot, /secrets\.CLOUDFLARE_READ_TOKEN/);
  assert.match(snapshot, /environment: zuno-panel-audit/);
});

test('le publisher TV relit les artefacts aux chemins réellement utilisés par ses scripts', () => {
  const publish = tv.match(/^  publish:\n([\s\S]*)/m)?.[1];
  assert.ok(publish);
  assert.match(publish, /name: Télécharger l’APK de ce build[\s\S]*?path: android-app\/build\/app\/outputs\/flutter-apk/);
  assert.match(publish, /name: Télécharger l’AAB seulement si construit[\s\S]*?path: android-app\/build\/app\/outputs\/bundle\/release/);
});

test('la preuve de signature réellement mesurée par le build traverse les jobs TV', () => {
  const build = tv.match(/^  build-tv:\n([\s\S]*?)(?=^  [a-z][\w-]*:|$(?![\s\S]))/m)?.[1];
  const publish = tv.match(/^  publish:\n([\s\S]*)/m)?.[1];
  assert.ok(build && publish);
  assert.match(build, /apk-cert: \$\{\{ env\.APK_CERT \}\}/);
  assert.match(build, /echo "APK_CERT=\$CERT" >> "\$GITHUB_ENV"/);
  assert.match(publish, /APK_CERT: \$\{\{ needs\.build-tv\.outputs\.apk-cert \}\}/);
  assert.match(publish, /\[ "\$\{APK_CERT:-\}" = "\$EXPECTED_CERT" \]/);
});

test('le build mobile ne peut modifier aucune release', () => {
  const build = phone.match(/^  phone:\n([\s\S]*?)(?=^  [a-z][\w-]*:|$(?![\s\S]))/m)?.[1];
  assert.ok(build);
  assert.doesNotMatch(build, /contents: write|gh release (?:upload|edit|create)/);
  assert.match(phone, /^  publish:\n/m);
});

test('le build mobile vérifie la vraie garde avant de préparer la signature', () => {
  const build = phone.match(/^  phone:\n([\s\S]*?)(?=^  [a-z][\w-]*:|$(?![\s\S]))/m)?.[1];
  assert.ok(build);
  const guard = build.indexOf('run: node .github/app-release-guard.mjs');
  const signature = build.indexOf('KS_B64:');
  assert.ok(guard >= 0, 'garde réelle absente du build mobile');
  assert.ok(signature > guard, 'la signature précède la garde');
  assert.match(build, /working-directory: mission/);
});

test('Windows compile en lecture seule et ne publie jamais sur un push', () => {
  const windows = read('workflows/build-zuno-windows.yml');
  assert.match(windows, /^permissions:\n  contents: read/m);
  const build = windows.match(/^  build:\n([\s\S]*?)(?=^  [a-z][\w-]*:|$(?![\s\S]))/m)?.[1];
  assert.ok(build);
  assert.doesNotMatch(build, /gh release (?:upload|edit|create)/);
  const publisher = windows.match(/^  publish:\n([\s\S]*)/m)?.[1];
  assert.ok(publisher);
  assert.match(publisher, /github\.event_name == 'workflow_dispatch' && inputs\.publish == 'true'/);
  assert.doesNotMatch(publisher, /github\.event_name == 'push'/);
});

test('le workflow historique de secret ne peut redéployer le Worker', () => {
  const secret = read('workflows/set-admin-password.yml');
  assert.doesNotMatch(secret, /secrets\.[A-Z_]+|wrangler[^\n]*secret (?:put|bulk|delete)/);
  assert.match(secret, /deploy-panel-cloudflare\.yml/);
  assert.match(secret, /exit 1/);
});
