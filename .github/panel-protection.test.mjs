// Régressions des protections de production : les anciens jobs acceptaient
// un autre auteur ou une autre branche dès que « DEPLOYER » était renseigné.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const workflow = readFileSync(join(here, 'workflows/deploy-panel-cloudflare.yml'), 'utf8');
const block = (name) => workflow.match(new RegExp(`^  ${name}:\\n([\\s\\S]*?)(?=^  [a-z][a-z_-]*:|$(?![\\s\\S]))`, 'm'))?.[1] || '';
const context = (changes = {}) => ({ event: 'workflow_dispatch', actor: 'manzilionellm-dotcom', triggeringActor: 'manzilionellm-dotcom', ref: 'refs/heads/claude/panel-mise-en-ligne', confirmation: 'DEPLOYER', mode: 'reviewed', ...changes });

async function authorized(ctx) {
  const guardPath = join(here, 'panel-deploy-guard.mjs');
  if (existsSync(guardPath)) {
    const { assertDeploymentAllowed } = await import(guardPath);
    try { assertDeploymentAllowed(ctx); return true; } catch { return false; }
  }
  // Contre-preuve : exécuter la vraie condition de l'ancien job, sans la
  // remplacer par une simulation du comportement que nous souhaitons.
  const expression = block('worker').match(/^    if: (.+)$/m)?.[1];
  assert.ok(expression, 'condition Worker lisible');
  return Function('github', `return Boolean(${expression});`)({
    actor: ctx.actor, triggering_actor: ctx.triggeringActor, ref: ctx.ref,
    event_name: ctx.event, event: { inputs: { confirme: ctx.confirmation, cible: 'worker-puis-panel' } },
  });
}

test('un autre codeur ne peut pas déployer', async () => assert.equal(await authorized(context({ actor: 'autre-codeur' })), false));
test('une autre branche ne peut pas déployer', async () => assert.equal(await authorized(context({ ref: 'refs/heads/claude/autre' })), false));
test('un autre codeur ne peut pas relancer le déploiement du propriétaire', async () => assert.equal(await authorized(context({ triggeringActor: 'autre-codeur' })), false));
test('le gel bloque aussi un lancement du propriétaire', async () => assert.equal(await authorized(context({ mode: 'frozen' })), false));

for (const name of ['worker', 'panel']) {
  test(`${name} : autorisation vérifiée avant les secrets`, () => assert.match(block(name), /needs:[^\n]*validation|needs:\s*\n\s*- validation/));
  test(`${name} : environnement protégé de production obligatoire`, () => assert.match(block(name), /environment: zuno-panel-production/));
  test(`${name} : licence et nombre de listes comparés avant et après`, () => {
    assert.match(block(name), /panel-reference\.mjs capture/);
    assert.match(block(name), /panel-reference\.mjs compare/);
  });
}

test('les contrôles réels précèdent le déploiement', () => {
  assert.match(block('stabilite'), /npm test/);
  assert.match(block('stabilite'), /failure_injection\.test\.mjs/);
  assert.match(block('stabilite'), /panel_security\.audit\.mjs/);
  assert.match(block('worker'), /needs:[^\n]*stabilite/);
  assert.match(block('panel'), /needs:[^\n]*stabilite/);
});

test('le propriétaire contrôle le panel, le Worker et les protections', () => {
  const path = join(here, 'CODEOWNERS');
  assert.ok(existsSync(path), 'CODEOWNERS absent');
  const owners = readFileSync(path, 'utf8');
  for (const scope of ['/.github/', '/android-app/cloudflare/', '/android-app/admin-panel/']) {
    assert.ok(owners.split('\n').some((line) => line.startsWith(scope) && line.endsWith('@manzilionellm-dotcom')), scope);
  }
});
