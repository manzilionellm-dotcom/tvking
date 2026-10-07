// Vérifier les refus ET le parcours autorisé ; aucune connexion de production.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { assertDeploymentAllowed } from './panel-deploy-guard.mjs';
import { referenceState, assertReferenceUnchanged, captureReference } from './panel-reference.mjs';

const allowed = { event: 'workflow_dispatch', actor: 'manzilionellm-dotcom', triggeringActor: 'manzilionellm-dotcom', ref: 'refs/heads/claude/panel-mise-en-ligne', confirmation: 'DEPLOYER', mode: 'reviewed' };
test('propriétaire, bonne branche et dégel revu : autorisé', () => assert.doesNotThrow(() => assertDeploymentAllowed(allowed)));
for (const [field, value] of Object.entries({ event: 'push', actor: 'autre-codeur', triggeringActor: 'autre-codeur', ref: 'refs/heads/main', confirmation: '', mode: 'frozen' })) {
  test(`refus si ${field} n'est pas autorisé`, () => assert.throws(() => assertDeploymentAllowed({ ...allowed, [field]: value })));
}
test('mode absent ou inconnu : refus fermé', () => {
  for (const mode of [undefined, null, '', 'autre']) assert.throws(() => assertDeploymentAllowed({ ...allowed, mode }));
});

const status = { exists: true, paid: true, plan: 'lifetime', paid_until: null, status: 'active', frozen: false, banned: false };
const lists = { sources: [{ type: 'm3u', m3u_url: 'https://liste.invalid/liste.m3u' }] };
test('identiques : comparaison acceptée sans recopier les données des listes', () => {
  const state = referenceState({ ...status, extra: 'à exclure' }, lists);
  assert.equal(state.sourceCount, 1);
  assert.doesNotThrow(() => assertReferenceUnchanged(state, referenceState(status, lists)));
  assert.equal(JSON.stringify(state).includes('liste.invalid'), false);
  assert.equal(JSON.stringify(state).includes('à exclure'), false);
});
test('même HTTP et même licence, mais deux listes : déploiement refusé', () => {
  assert.throws(() => assertReferenceUnchanged(referenceState(status, lists), referenceState(status, { sources: [...lists.sources, ...lists.sources] })), /Nombre de listes/);
});
for (const [field, value] of Object.entries({ paid: false, plan: 'yearly', paid_until: 123, frozen: true, banned: true })) {
  test(`changement de ${field} : déploiement refusé`, () => assert.throws(() => assertReferenceUnchanged(referenceState(status, lists), referenceState({ ...status, [field]: value }, lists))));
}
test('zéro liste et source historique unique restent mesurables', () => {
  assert.equal(referenceState(status, { sources: [] }).sourceCount, 0);
  assert.equal(referenceState(status, { source: null }).sourceCount, 0);
  assert.equal(referenceState(status, { source: lists.sources[0] }).sourceCount, 1);
});
test('réponses absentes ou appareil inconnu : arrêt', () => {
  assert.throws(() => referenceState({ exists: false }, lists));
  assert.throws(() => referenceState(status, {}));
  assert.throws(() => referenceState(status, null));
  assert.throws(() => referenceState({ ...status, plan: { extra: 'à exclure' } }, lists), /Champ de licence/);
});
test('lecture HTTP réelle sur 127.0.0.1, erreur serveur et JSON invalide : aucun succès caché', async () => {
  let mode = 'ok';
  const server = createServer((req, res) => {
    res.setHeader('content-type', 'application/json');
    if (mode === 'http') { res.writeHead(503); res.end('{}'); return; }
    if (mode === 'json') { res.end('invalide'); return; }
    res.end(JSON.stringify(req.url.startsWith('/api/status/') ? status : lists));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.deepEqual(await captureReference(base, 'MK:00:00:00:00:01'), referenceState(status, lists));
    mode = 'http'; await assert.rejects(captureReference(base, 'MK:00:00:00:00:01'), /HTTP 503/);
    mode = 'json'; await assert.rejects(captureReference(base, 'MK:00:00:00:00:01'), /JSON invalide/);
    await assert.rejects(captureReference(base, '../'), /MAC/);
  } finally { await new Promise((resolve) => server.close(resolve)); }
});
