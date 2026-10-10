// Exécuter la règle réelle, ses refus et ses parcours autorisés, sans publication.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
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

test('le vrai processus lit le gel du fichier, jamais une entrée de dégel falsifiée', () => {
  const directory = mkdtempSync(join(tmpdir(), 'zuno-guard-'));
  const eventPath = join(directory, 'event.json');
  try {
    writeFileSync(eventPath, JSON.stringify({ inputs: { publish: 'true', confirme: 'PUBLIER_APP', mode: 'reviewed' } }));
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('app-release-guard.mjs', import.meta.url))], {
      encoding: 'utf8', env: { ...process.env, GITHUB_EVENT_PATH: eventPath, GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REPOSITORY: base.repository, GITHUB_ACTOR: base.actor, GITHUB_TRIGGERING_ACTOR: base.triggeringActor, GITHUB_REF: base.ref, APP_OPERATION: 'client', APP_MODE: 'reviewed', APP_PUBLISH: 'true', APP_CONFIRMATION: 'PUBLIER_APP' },
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Action apps refusée/);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
