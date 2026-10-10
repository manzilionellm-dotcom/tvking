// Tester les configurations réellement exécutées, avant tout accès de production.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (name) => readFileSync(new URL(name, import.meta.url), 'utf8');
const secret = read('workflows/set-admin-password.yml');
const deploy = read('workflows/deploy-panel-cloudflare.yml');
const e2e = read('workflows/e2e-panel-box.yml');

test('le workflow de secret exige le même environnement que le déploiement', () => {
  assert.match(secret, /environment: zuno-panel-production/);
  assert.match(secret, /needs: \[validation\]/);
  assert.match(secret, /panel-deploy-guard\.mjs/);
});

test('le nouveau secret ne passe jamais dans les entrées du workflow', () => {
  assert.doesNotMatch(secret, /inputs\.password|^      password:/m);
  assert.match(secret, /secrets\.PANEL_ADMIN_SECRET_NEXT/);
});

for (const [name, content] of [['déploiement', deploy], ['mot de passe', secret], ['E2E', e2e]]) {
  test(`${name} : chaque action distante est figée par son commit complet`, () => {
    const actions = [...content.matchAll(/\buses:\s*([^\s#]+)/g)].map((m) => m[1]);
    assert.ok(actions.length > 0);
    for (const action of actions) {
      if (action.startsWith('./')) continue;
      assert.match(action, /^[\w-]+\/[\w.-]+@[a-f0-9]{40}$/, action);
    }
  });
  test(`${name} : les identifiants Git ne restent pas dans le checkout`, () => {
    const checkouts = [...content.matchAll(/uses: actions\/checkout@[^\n]+\n([\s\S]*?)(?=\n\s*- (?:name:|uses:|run:)|$)/g)];
    assert.ok(checkouts.length > 0);
    for (const checkout of checkouts) assert.match(checkout[1], /persist-credentials: false/);
  });
}

test('le déploiement utilise une version exacte et actuelle de Wrangler', () => {
  assert.match(deploy, /WRANGLER_VERSION: '4\.149\.0'/);
});

test('le propriétaire couvre aussi le code et les configurations des apps', () => {
  assert.match(read('CODEOWNERS'), /^\/android-app\/ @manzilionellm-dotcom$/m);
});
