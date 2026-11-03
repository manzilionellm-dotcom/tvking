// Les contrôles lisent les vrais workflows ; aucun appel à une release réelle.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

const read = (name) => readFileSync(new URL(name, import.meta.url), 'utf8');
const tv = read('workflows/build-zuno-tv.yml');
const phone = read('workflows/build-7motion-sport-test.yml');
const quality = read('workflows/quality-zuno.yml');
const cleanup = read('workflows/cleanup-old-apks.yml');

test('7 MOTION : le bundle et ses tests utilisent la même recette mobile revue', () => {
  const source = JSON.parse(read('../android-app/ci/mobile/reviewed-source.json'));
  assert.match(source.sourceSha, /^[a-f0-9]{40}$/);
  assert.equal(source.package, 'com.manzilionellm.tvking');
  assert.equal(source.backendUrl, 'https://api.zuno8k.com');
  for (const workflow of [phone, read('workflows/mobile-panel-sync-tests.yml')]) {
    assert.ok(workflow.includes(`ref: ${source.sourceSha}`));
    assert.ok(workflow.includes('prepare-reviewed-source.sh ../mobile-reviewed'));
  }
  assert.ok(phone.includes(`--build-name=${source.versionName}`));
  assert.match(phone, /"mobileSourceSha": subprocess.check_output/);
  const prepare = read('../android-app/ci/mobile/prepare-reviewed-source.sh');
  assert.match(prepare, /assert actual == expected\['sourceSha'\]/);
  assert.match(prepare, /assert base == expected\['mobileBaseSha'\]/);
});

test('la mise à jour ZUNO produit seulement le paquet adaptatif protégé, sans publication', () => {
  const editions = read('workflows/build-zuno-play-editions.yml');
  assert.match(editions, /^permissions:\n  contents: read/m);
  assert.doesNotMatch(editions, /contents: write|gh release|APP_OPERATION: client/);
  assert.match(editions, /edition: \[auto\]/);
  assert.match(editions, /environment: zuno-app-production/);
  assert.match(editions, /bundles:[\s\S]*?if: github\.ref == 'refs\/heads\/ccr-b93e1afd-gwirw0'/);
  assert.match(editions, /github\.triggering_actor == github\.repository_owner/);
  assert.ok(editions.indexOf('run: node .github/app-release-guard.mjs') < editions.indexOf('KS_B64:'));
  assert.match(editions, /test "\$SIGNING" = release/);
  assert.match(editions, /test "\$CERT" = "\$EXPECTED_CERT"/);
  assert.match(editions, /--dart-define=ZUNO_EDITION="\$ZUNO_EDITION"/);
  assert.match(editions, /ci\/play_editions\/verify\.py/);
  for (const [, action] of editions.matchAll(/\buses:\s*([^\s#]+)/g)) {
    assert.match(action, /^[\w-]+\/[\w.-]+@[a-f0-9]{40}$/);
  }
});

for (const [name, content] of [['box', tv], ['mobile', phone], ['qualité', quality]]) {
  test(`${name} : les actions sont figées par commit complet`, () => {
    for (const [, action] of content.matchAll(/\buses:\s*([^\s#]+)/g)) {
      if (action.startsWith('./')) continue;
      // Les actions officielles peuvent vivre dans un sous-dossier
      // (gradle/actions/setup-gradle). Le SHA complet reste obligatoire.
      assert.match(action, /^[\w-]+\/[\w.-]+(?:\/[\w-]+)*@[a-f0-9]{40}$/, action);
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

function tvJob(name) {
  const body = tv.match(new RegExp(
    '^  ' + name + ':\\n([\\s\\S]*?)(?=^  [a-z][\\w-]*:|$(?![\\s\\S]))', 'm'))?.[1];
  assert.ok(body, 'job TV absent : ' + name);
  return body;
}

function tvJobCondition(name) {
  const body = tvJob(name);
  const header = body.match(/^    if: ([^\n]*)\n/m);
  assert.ok(header, 'condition TV absente : ' + name);
  if (header[1] !== '>-') return header[1];
  const rest = body.slice(header.index + header[0].length);
  return rest.match(/^(?:      [^\n]*\n)+/)[0].trim();
}

// On évalue les VRAIES conditions du YAML, pas une seconde règle codée à la
// main. Ce sous-ensemble (&&, ||, ==, !cancelled) a le même sens en JS/GitHub.
// Sans fonction de statut, GitHub ajoute implicitement success() : c'est
// précisément le piège d'un besoin volontairement skipped pour le téléphone.
function tvJobAllowed(name, { variant = 'box', build = 'success', startup = 'success',
                             cancelled = false, publish = 'true', testBox = 'false',
                             event = 'workflow_dispatch', owner = true } = {}) {
  const body = tvJob(name);
  const expression = tvJobCondition(name).replaceAll('needs.build-tv', 'needs.build_tv');
  const results = { 'build-tv': build, startup };
  const dependencies = body.match(/^    needs: \[([^\]]+)\]/m)[1].split(',').map(x => x.trim());
  if (!/\b(?:always|cancelled|failure|success)\(/.test(expression) &&
      dependencies.some(dependency => results[dependency] !== 'success')) return false;
  const evaluate = new Function('needs', 'inputs', 'github', 'cancelled',
    'return !!(' + expression + ')');
  return evaluate(
    { build_tv: { result: build }, startup: { result: startup } },
    { variante: variant, publish, test_box: testBox },
    { actor: owner ? 'manzilionellm-dotcom' : 'other', triggering_actor: 'manzilionellm-dotcom',
      repository_owner: 'manzilionellm-dotcom', repository: 'manzilionellm-dotcom/tvking',
      event_name: event }, () => cancelled);
}

test('la publication box exige réellement le succès du smoke dans le même run', () => {
  assert.match(tvJob('publish'), /needs: \[build-tv, startup\]/);
  for (const variant of ['box', '', 'inconnue']) {
    assert.equal(tvJobAllowed('publish', { variant }), true, variant);
    for (const startup of ['failure', 'cancelled', 'skipped', '']) {
      assert.equal(tvJobAllowed('publish', { variant, startup }), false, variant + '/' + startup);
    }
    for (const build of ['failure', 'cancelled', 'skipped', '']) {
      assert.equal(tvJobAllowed('publish', { variant, build }), false, variant + '/' + build);
    }
  }
  assert.equal(tvJobAllowed('publish', { cancelled: true }), false);
  assert.equal(tvJobAllowed('publish', { owner: false }), false);
  assert.equal(tvJobAllowed('publish', { event: 'push' }), false);
  assert.equal(tvJobAllowed('publish', { publish: 'false' }), false);
  assert.equal(tvJobAllowed('publish', { publish: 'false', testBox: 'true' }), true);
});

test('la variante téléphone conserve son parcours sans autoriser un skip box', () => {
  assert.equal(tvJobAllowed('startup', { variant: 'telephone' }), false);
  assert.equal(tvJobAllowed('publish', { variant: 'telephone', startup: 'skipped',
    publish: 'false', testBox: 'true' }), true);
  for (const startup of ['success', 'failure', 'cancelled', '']) {
    assert.equal(tvJobAllowed('publish', { variant: 'telephone', startup,
      publish: 'false', testBox: 'true' }), false, startup);
  }
  assert.equal(tvJobAllowed('publish', { variant: 'telephone', startup: 'skipped',
    publish: 'false', testBox: 'true', cancelled: true }), false);
});

test('les deux API testent aussi le premier build box sans publication, sans secret', () => {
  const startup = tvJob('startup');
  assert.match(startup, /api: \[29, 35\]/);
  assert.match(startup, /fail-fast: false/);
  assert.match(startup, /permissions:\n      contents: read/);
  assert.doesNotMatch(startup, /\bsecrets\.|environment:|contents: write|gh release/);
  // Les deux runners ont échoué avant Android faute de libpulse.so.0.
  // La préparation de cette dépendance doit être obligatoire avant le smoke.
  const runtime = startup.match(/      - name: Préparer les bibliothèques Linux de l'émulateur\n([\s\S]*?)(?=\n      - name:)/)?.[1];
  assert.ok(runtime);
  assert.match(runtime, /set -euo pipefail/);
  assert.match(runtime, /sudo apt-get install -y --no-install-recommends libpulse0/);
  assert.doesNotMatch(runtime, /if:|continue-on-error:|\|\| true/);
  assert.ok(startup.indexOf(runtime) < startup.indexOf('run: bash android-app/ci/run-apk-startup.sh'));
  assert.equal(tvJobAllowed('startup', { publish: 'false', testBox: 'false' }), true);
  assert.equal(tvJobAllowed('startup', { publish: 'false', testBox: 'true' }), true);
  for (const build of ['failure', 'cancelled', 'skipped', '']) {
    assert.equal(tvJobAllowed('startup', { build }), false, build);
  }
});

test('le smoke et le publisher utilisent l’ID exact et les empreintes émises avant upload', () => {
  const build = tvJob('build-tv');
  const startup = tvJob('startup');
  const publish = tvJob('publish');
  assert.match(build, /apk-artifact-id: \$\{\{ steps\.apk-upload\.outputs\.artifact-id \}\}/);
  assert.match(build, /apk-artifact-digest: \$\{\{ steps\.apk-upload\.outputs\.artifact-digest \}\}/);
  assert.match(build, /apk-sha256: \$\{\{ steps\.apk-identity\.outputs\.sha256 \}\}/);
  assert.match(build, /apk-size: \$\{\{ steps\.apk-identity\.outputs\.size \}\}/);
  assert.match(build, /build-attempt: \$\{\{ steps\.apk-identity\.outputs\.build-attempt \}\}/);
  assert.ok(build.indexOf('sha256sum "$APK"') < build.indexOf('id: apk-upload'));
  for (const consumer of [startup, publish]) {
    assert.match(consumer, /artifact-ids: \$\{\{ needs\.build-tv\.outputs\.apk-artifact-id \}\}/);
    assert.match(consumer, /needs\.build-tv\.outputs\.apk-sha256/);
    assert.match(consumer, /needs\.build-tv\.outputs\.apk-size/);
  }
  assert.match(startup, /STARTUP_BUILD_ATTEMPT: \$\{\{ needs\.build-tv\.outputs\.build-attempt \}\}/);
  assert.match(startup, /STARTUP_APK_CERT: \$\{\{ needs\.build-tv\.outputs\.apk-cert \}\}/);
  assert.match(publish, /verify_apk_startup\.py bytes/);
  assert.ok(publish.indexOf('APP_OPERATION:') < publish.indexOf('artifact-ids:'));
  assert.ok(publish.indexOf('verify_apk_startup.py bytes') < publish.indexOf('gh release'));
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

test('le parcours Play manuel prépare un artefact et ne publie aucune release', () => {
  const dispatcher = read('workflows/publish-phone-aab.yml');
  assert.match(dispatcher, /workflow_dispatch:/);
  assert.match(dispatcher, /inputs\.confirme == 'PREPARER_AAB'/);
  assert.match(dispatcher, /github\.ref == 'refs\/heads\/ccr-b93e1afd-gwirw0'/);
  assert.match(dispatcher, /github\.actor == github\.repository_owner/);
  assert.match(dispatcher, /github\.triggering_actor == github\.repository_owner/);
  assert.match(dispatcher, /uses: \.\/\.github\/workflows\/build-7motion-sport-test\.yml/);
  assert.match(dispatcher, /play_aab: true/);
  assert.doesNotMatch(dispatcher, /gh release|run-id:|APP_OPERATION: client/);
  const build = phone.match(/^  phone:\n([\s\S]*?)(?=^  [a-z][\w-]*:|$(?![\s\S]))/m)?.[1];
  const publish = phone.match(/^  publish:\n([\s\S]*)/m)?.[1];
  assert.ok(build && publish);
  assert.match(build, /github\.event_name == 'workflow_dispatch'/);
  assert.match(build, /github\.ref == 'refs\/heads\/ccr-b93e1afd-gwirw0' && inputs\.play_aab/);
  assert.match(build, /APP_PLAY_AAB: \$\{\{ inputs\.play_aab && 'true' \|\| 'false' \}\}/);
  assert.match(build, /environment: zuno-app-test/);
  assert.match(publish, /^    if: github\.event_name == 'pull_request' && needs\.phone\.result == 'success'/m);
  assert.equal(JSON.parse(read('app-production.json')).mode, 'frozen');
});

test('le bundle Play emporte la preuve du commit et des logos réellement compilés', () => {
  assert.match(phone, /SOURCE_SHA: \$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}/);
  assert.equal((phone.match(/--dart-define=GIT_SHA=\$\{\{ env\.SOURCE_SHA \}\}/g) || []).length, 2);
  assert.match(phone, /assert int\(report\["targetSdk"\]\) >= 36/);
  assert.match(phone, /assert actual == source/);
  assert.match(phone, /archive\.read\("base\/assets\/flutter_assets\/"\+asset\)/);
  assert.match(phone, /assert shipped == expected/);
  assert.match(phone, /phone\/build\/play-review\/build-provenance\.json/);
});
