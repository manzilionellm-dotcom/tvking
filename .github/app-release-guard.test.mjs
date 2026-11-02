// Exécuter la règle réelle, ses refus et ses parcours autorisés, sans publication.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { assertAppOperationAllowed } from './app-release-guard.mjs';

const base = { repository: 'manzilionellm-dotcom/tvking', actor: 'manzilionellm-dotcom', triggeringActor: 'manzilionellm-dotcom', ref: 'refs/heads/ccr-b93e1afd-gwirw0', event: 'workflow_dispatch', operation: 'build', mode: 'frozen', publish: 'false', testBox: 'false', playAab: 'false', backendUrl: '', variant: 'box', confirmation: '' };
const pr = { user: { login: 'manzilionellm-dotcom' }, head: { ref: 'ccr-b93e1afd-gwirw0', repo: { full_name: base.repository } }, base: { ref: 'ccr-sport-preuve-20261008' } };

test('compiler sans publier reste autorisé au propriétaire pendant le gel', () => assert.doesNotThrow(() => assertAppOperationAllowed(base)));
test('le push peut compiler sans publier', () => assert.doesNotThrow(() => assertAppOperationAllowed({ ...base, event: 'push' })));
test('le canal de test manuel exige publish=false', () => {
  assert.doesNotThrow(() => assertAppOperationAllowed({ ...base, operation: 'test', testBox: 'true' }));
  assert.throws(() => assertAppOperationAllowed({ ...base, operation: 'test', testBox: 'true', publish: 'true' }));
});
test('la PR de preuve exacte peut construire et publier uniquement le test', () => {
  for (const operation of ['build', 'test']) assert.doesNotThrow(() => assertAppOperationAllowed({ ...base, operation, event: 'pull_request', pr, testBox: 'true' }));
});
for (const field of ['actor', 'triggeringActor', 'repository', 'ref']) {
  test(`une autre valeur de ${field} est refusée`, () => assert.throws(() => assertAppOperationAllowed({ ...base, [field]: 'autre' })));
}
for (const mode of [undefined, null, '', 'autre']) {
  test(`mode ${String(mode)} : refus fermé`, () => assert.throws(() => assertAppOperationAllowed({ ...base, mode })));
}
test('même le propriétaire ne peut pas publier un client pendant le gel', () => {
  for (const operation of ['build', 'client', 'cleanup']) assert.throws(() => assertAppOperationAllowed({ ...base, operation, publish: 'true', confirmation: operation === 'cleanup' ? 'NETTOYER_RELEASES' : 'PUBLIER_APP' }));
});
test('un dégel revu exige toujours la confirmation et le lancement manuel', () => {
  const client = { ...base, mode: 'reviewed', operation: 'client', confirmation: 'PUBLIER_APP' };
  assert.doesNotThrow(() => assertAppOperationAllowed(client));
  assert.throws(() => assertAppOperationAllowed({ ...client, confirmation: '' }));
  assert.throws(() => assertAppOperationAllowed({ ...client, event: 'push' }));
  assert.throws(() => assertAppOperationAllowed({ ...client, triggeringActor: 'autre' }));
});
test('une PR étrangère ou une option client est refusée', () => {
  const context = { ...base, event: 'pull_request', pr, testBox: 'true' };
  for (const change of [{ publish: 'true' }, { testBox: 'false' }, { playAab: 'true' }, { backendUrl: 'https://backend.invalid' }, { operation: 'client' }, { variant: 'telephone' }, { pr: null }]) assert.throws(() => assertAppOperationAllowed({ ...context, ...change }));
  for (const invalid of [ { ...pr, user: { login: 'autre' } }, { ...pr, head: { ...pr.head, ref: 'autre' } }, { ...pr, head: { ...pr.head, repo: { full_name: 'autre/depot' } } }, { ...pr, base: { ref: 'main' } } ]) assert.throws(() => assertAppOperationAllowed({ ...context, pr: invalid }));
});
test('une opération inconnue ne reçoit pas de permission', () => assert.throws(() => assertAppOperationAllowed({ ...base, operation: 'autre' })));

test('le vrai processus lit le manifeste, jamais un mode fourni par une entrée', () => {
  const directory = mkdtempSync(join(tmpdir(), 'zuno-guard-'));
  const eventPath = join(directory, 'event.json');
  const guardPath = join(directory, 'app-release-guard.mjs');
  try {
    // Même garde, manifestes isolés : le test ne dépend pas du gel courant.
    copyFileSync(new URL('app-release-guard.mjs', import.meta.url), guardPath);
    writeFileSync(eventPath, JSON.stringify({ inputs: { publish: 'true', confirme: 'PUBLIER_APP', mode: 'reviewed' } }));
    for (const mode of ['frozen', 'reviewed', 'invalide']) {
      writeFileSync(join(directory, 'app-production.json'), JSON.stringify({ mode }));
      const result = spawnSync(process.execPath, [guardPath], {
        encoding: 'utf8', env: { ...process.env, GITHUB_EVENT_PATH: eventPath, GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REPOSITORY: base.repository, GITHUB_ACTOR: base.actor, GITHUB_TRIGGERING_ACTOR: base.triggeringActor, GITHUB_REF: base.ref, APP_OPERATION: 'client', APP_MODE: 'reviewed', APP_PUBLISH: 'true', APP_CONFIRMATION: 'PUBLIER_APP' },
      });
      assert.equal(result.status, mode === 'reviewed' ? 0 : 1, mode);
      if (mode !== 'reviewed') assert.match(result.stderr, /Action apps refusée/);
    }
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test('le bundle manuel reste une construction sans dégel ni publication clients', () => {
  const build = { ...base, playAab: 'true', testBox: 'true' };
  assert.doesNotThrow(() => assertAppOperationAllowed(build));
  for (const change of [{ operation: 'client' }, { publish: 'true' },
    { ref: 'refs/heads/main' }, { actor: 'autre' }, { triggeringActor: 'autre' },
    { event: 'pull_request', pr }]) {
    assert.throws(() => assertAppOperationAllowed({ ...build, ...change }));
  }
});

// La revue autorise un APK précis, sans dégel global ni permission transmise
// par une entrée workflow. Les valeurs Git ci-dessous sont des fixtures.
const reviewedAt = Date.parse('2026-11-02T09:00:00Z');
const workflowRef = 'manzilionellm-dotcom/tvking/.github/workflows/build-zuno-tv.yml@refs/heads/ccr-b93e1afd-gwirw0';
const review = {
  scope: 'zuno-tv', reviewedBy: base.actor, reason: 'APK Zuno demandé par le propriétaire',
  reviewedAt: new Date(reviewedAt).toISOString(), expiresAt: new Date(reviewedAt + 86400000).toISOString(),
  sourceCommit: '1'.repeat(40), androidTree: '2'.repeat(40), workflowBlob: '3'.repeat(40),
};
const reviewedZuno = {
  ...base, operation: 'client', publish: 'true', confirmation: 'PUBLIER_APP',
  zunoTvReview: review, now: reviewedAt + 60000, workflowRef,
  sourceSha: '4'.repeat(40), workflowSha: '4'.repeat(40),
  checkout: { head: '4'.repeat(40), androidTree: review.androidTree, workflowBlob: review.workflowBlob },
};

test('la revue du dépôt désigne exactement le constructeur présent', () => {
  const manifest = JSON.parse(readFileSync(new URL('app-production.json', import.meta.url), 'utf8'));
  if (!manifest.zunoTvReview) return; // La revue est retirée après publication.
  const workflow = readFileSync(new URL('workflows/build-zuno-tv.yml', import.meta.url));
  const blob = createHash('sha1').update(`blob ${workflow.length}\0`).update(workflow).digest('hex');
  assert.equal(manifest.mode, 'frozen');
  assert.equal(manifest.zunoTvReview.workflowBlob, blob);
});

test('une revue ponctuelle autorise seulement le build et la publication de cet APK Zuno', () => {
  for (const operation of ['build', 'client']) {
    assert.doesNotThrow(() => assertAppOperationAllowed({ ...reviewedZuno, operation }));
  }
  assert.equal(reviewedZuno.mode, 'frozen');
});

test('la revue Zuno ne dégèle ni les autres workflows ni le nettoyage', () => {
  for (const file of ['build-7motion-sport-test.yml', 'publish-7motion-test.yml',
    'publish-phone-aab.yml', 'build-zuno-windows.yml', 'build-zuno-play-editions.yml']) {
    assert.throws(() => assertAppOperationAllowed({ ...reviewedZuno,
      workflowRef: workflowRef.replace('build-zuno-tv.yml', file) }), file);
  }
  assert.throws(() => assertAppOperationAllowed({ ...reviewedZuno, operation: 'cleanup', confirmation: 'NETTOYER_RELEASES' }));
});

test('une revue Zuno conserve les identités, le lancement manuel et les paramètres exacts', () => {
  for (const change of [{ actor: 'autre' }, { triggeringActor: 'autre' }, { repository: 'autre/depot' },
    { ref: 'refs/heads/main' }, { event: 'push' }, { event: 'pull_request', pr },
    { confirmation: '' }, { testBox: 'true' }, { playAab: 'true' }, { variant: 'telephone' },
    { backendUrl: 'https://autre.invalid' }, { publish: 'false' }, { workflowRef: undefined },
    { workflowRef: workflowRef.replace('@refs/heads/ccr-b93e1afd-gwirw0', '@refs/heads/main') },
    { workflowSha: '5'.repeat(40) }, { sourceSha: undefined }, { checkout: null }]) {
    assert.throws(() => assertAppOperationAllowed({ ...reviewedZuno, ...change }), JSON.stringify(change));
  }
});

test('un autre arbre Android, workflow ou checkout exige une nouvelle revue', () => {
  for (const field of ['head', 'androidTree', 'workflowBlob']) {
    assert.throws(() => assertAppOperationAllowed({ ...reviewedZuno,
      checkout: { ...reviewedZuno.checkout, [field]: '5'.repeat(40) } }), field);
  }
});

test('une revue absente, invalide, future ou expirée ne permet aucune publication', () => {
  for (const change of [{ scope: '7motion' }, { reviewedBy: 'autre' }, { reason: '' },
    { sourceCommit: '' }, { androidTree: 'incorrect' }, { workflowBlob: 'incorrect' },
    { reviewedAt: 'invalide' }, { expiresAt: 'invalide' },
    { reviewedAt: new Date(reviewedZuno.now + 1).toISOString() },
    { expiresAt: new Date(reviewedZuno.now).toISOString() },
    { expiresAt: new Date(reviewedAt + 86400001).toISOString() }]) {
    assert.throws(() => assertAppOperationAllowed({ ...reviewedZuno,
      zunoTvReview: { ...review, ...change } }), JSON.stringify(change));
  }
  for (const zunoTvReview of [undefined, null, {}]) {
    assert.throws(() => assertAppOperationAllowed({ ...reviewedZuno, zunoTvReview }));
  }
});

test('le vrai processus vérifie les objets Git, le workflow GitHub et le checkout propre', () => {
  const directory = mkdtempSync(join(tmpdir(), 'zuno-review-'));
  const github = join(directory, '.github');
  const eventPath = join(directory, 'event.json');
  const guardPath = join(github, 'app-release-guard.mjs');
  const git = (...args) => execFileSync('git', args, { cwd: directory, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  try {
    mkdirSync(join(github, 'workflows'), { recursive: true });
    mkdirSync(join(directory, 'android-app'));
    copyFileSync(new URL('app-release-guard.mjs', import.meta.url), guardPath);
    const workflowPath = join(github, 'workflows', 'build-zuno-tv.yml');
    const appPath = join(directory, 'android-app', 'main.dart');
    writeFileSync(workflowPath, 'name: APK de fixture\n');
    writeFileSync(appPath, 'void main() {}\n');
    git('init', '-q'); git('config', 'user.name', 'Test local'); git('config', 'user.email', 'test@example.invalid');
    git('add', 'android-app', '.github/workflows'); git('commit', '-qm', 'Source de fixture');
    const now = Date.now();
    const localReview = { ...review, sourceCommit: git('rev-parse', 'HEAD'),
      androidTree: git('rev-parse', 'HEAD:android-app'), workflowBlob: git('rev-parse', 'HEAD:.github/workflows/build-zuno-tv.yml'),
      reviewedAt: new Date(now - 1000).toISOString(), expiresAt: new Date(now + 3600000).toISOString() };
    writeFileSync(join(github, 'app-production.json'), JSON.stringify({ mode: 'frozen', zunoTvReview: localReview }));
    writeFileSync(eventPath, JSON.stringify({ inputs: { publish: 'true', confirme: 'PUBLIER_APP' } }));
    const run = (overrides = {}) => {
      const head = git('rev-parse', 'HEAD');
      return spawnSync(process.execPath, [guardPath], { cwd: directory, encoding: 'utf8', env: {
        ...process.env, GITHUB_EVENT_PATH: eventPath, GITHUB_EVENT_NAME: 'workflow_dispatch',
        GITHUB_REPOSITORY: base.repository, GITHUB_ACTOR: base.actor, GITHUB_TRIGGERING_ACTOR: base.triggeringActor,
        GITHUB_REF: base.ref, GITHUB_SHA: head, GITHUB_WORKFLOW_SHA: head, GITHUB_WORKFLOW_REF: workflowRef,
        APP_OPERATION: 'client', APP_PUBLISH: 'true', APP_TEST_BOX: 'false', APP_PLAY_AAB: 'false',
        APP_VARIANT: 'box', APP_BACKEND_URL: '', APP_CONFIRMATION: 'PUBLIER_APP', ...overrides,
      } });
    };
    assert.equal(run().status, 0, 'objets exacts autorisés');
    assert.equal(run({ GITHUB_WORKFLOW_REF: workflowRef.replace('build-zuno-tv.yml', 'publish-7motion-test.yml') }).status, 1);
    writeFileSync(appPath, 'void main() { /* changement non revu */ }\n');
    assert.equal(run().status, 1, 'fichier suivi modifié refusé avant le build');
    git('checkout', '--', 'android-app');
    writeFileSync(join(directory, 'android-app', 'extra.dart'), '// fichier non suivi\n');
    assert.equal(run().status, 1, 'fichier non suivi refusé');
    rmSync(join(directory, 'android-app', 'extra.dart'));
    writeFileSync(appPath, 'void main() { /* autre version */ }\n');
    git('add', 'android-app'); git('commit', '-qm', 'Autre source');
    assert.equal(run().status, 1, 'nouvel arbre Android refusé');
    git('checkout', localReview.sourceCommit, '--', 'android-app');
    writeFileSync(workflowPath, 'name: Workflow modifié\n');
    git('add', 'android-app', '.github/workflows'); git('commit', '-qm', 'Autre constructeur');
    assert.equal(run().status, 1, 'nouveau blob workflow refusé');
    git('checkout', localReview.sourceCommit, '--', '.github/workflows'); git('commit', '-qm', 'Restaurer le constructeur');
    assert.equal(run().status, 0, 'mêmes objets revus dans un commit de préparation');
    writeFileSync(join(github, 'app-production.json'), JSON.stringify({ mode: 'frozen' }));
    writeFileSync(eventPath, JSON.stringify({ inputs: { publish: 'true', confirme: 'PUBLIER_APP', zunoTvReview: localReview, scope: 'zuno-tv' } }));
    assert.equal(run({ APP_SCOPE: 'zuno-tv', APP_MODE: 'reviewed' }).status, 1, 'une entrée ne remplace pas la revue du manifeste');
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

