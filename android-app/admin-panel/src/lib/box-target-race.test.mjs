// Régression exécutée sur la fonction reload réelle du composant, sans la réécrire.
// Le serveur HTTP local fournit deux appareils distincts ; les réponses et
// fins d'envoi sont ordonnées par des promesses, sans temporisation arbitraire.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

const A = 'MK:AA:BB:CC:DD:01';
const B = 'MK:AA:BB:CC:DD:02';
const page = await readFile(new URL('../pages/ChainesPage.tsx', import.meta.url), 'utf8');
const apiSource = await readFile(new URL('./api.ts', import.meta.url), 'utf8');
const arrow = page.match(/const reload = useCallback\((async[\s\S]*?\n  \}), \[onLogout\]\);/)?.[1];
assert.ok(arrow, 'la fonction reload de production reste identifiable');
const errorClass = apiSource.match(/export class ApiError[\s\S]*?^}/m)?.[0];
assert.ok(errorClass, 'ApiError est lu depuis le client de production');
const ApiError = new Function(stripTypeScriptTypes(errorClass.replace('export ', ''), { mode: 'transform' }) + '; return ApiError;')();
let sameBoxTarget;
try {
  ({ sameBoxTarget } = await import('./box-target.ts'));
} catch (e) {
  // La version de référence ne possède pas encore ce contrôle. Sa fonction
  // reload ne l'appelle pas ; aucun contrôle de production n'est simulé.
  if (e.code !== 'ERR_MODULE_NOT_FOUND') throw e;
}
const makeReload = new Function(
  'sourcesApi', 'setLooking', 'readSeq', 'setSources', 'setErr', 'setLoaded',
  'onLogout', 'ApiError', 'currentMac', 'sameBoxTarget',
  stripTypeScriptTypes('const reload = ' + arrow + ';', { mode: 'transform' }) + 'return reload;',
);

async function fixture(run) {
  const data = new Map([
    [A, [{ type: 'm3u', m3u_url: 'https://alpha.invalid/list.m3u' }]],
    [B, [
      { type: 'm3u', m3u_url: 'https://beta.invalid/list.m3u' },
      { type: 'm3u', m3u_url: 'https://gamma.invalid/list.m3u' },
    ]],
  ]);
  const status = new Map();
  const requests = [];
  const blocks = new Map();
  const server = createServer(async (req, res) => {
    const mac = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname.slice('/sources/'.length));
    requests.push(mac);
    if (blocks.has(mac)) await blocks.get(mac);
    const code = status.get(mac) ?? 200;
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(JSON.stringify(code === 200 ? { sources: data.get(mac) ?? [] } : { error: 'fixture_http' }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = 'http://127.0.0.1:' + server.address().port;
  const view = { sources: [], loaded: false, looking: false, err: null, logouts: 0 };
  const currentMac = { current: A };
  const readSeq = { current: 0 };
  const sourcesApi = {
    async get(mac) {
      const res = await fetch(base + '/sources/' + encodeURIComponent(mac));
      if (!res.ok) throw new ApiError(res.status, 'fixture_http', 'Erreur HTTP de la fixture.');
      return await res.json();
    },
  };
  const reload = makeReload(sourcesApi, v => { view.looking = v; }, readSeq,
    v => { view.sources = v; }, v => { view.err = v; }, v => { view.loaded = v; },
    () => { view.logouts++; }, ApiError, currentMac, sameBoxTarget);
  function select(mac) {
    currentMac.current = mac;
    readSeq.current++;
    view.sources = [];
    view.loaded = false;
  }
  try {
    await run({ reload, select, view, requests, status, blocks });
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}

test('fin de l’envoi A après sélection de B : les listes restent celles de B', async () => {
  await fixture(async ({ reload, select, view }) => {
    await reload(A);
    select(B);
    await reload(B);
    // Même appel que send(A) après le retour tardif du PUT.
    await reload(A);
    assert.equal(view.sources.length, 2);
    assert.equal(view.sources[0].m3u_url, 'https://beta.invalid/list.m3u');
    assert.equal(view.loaded, true);
  });
});

test('une relecture tardive du précédent appareil ne démarre aucun HTTP', async () => {
  await fixture(async ({ reload, select, requests }) => {
    select(B);
    await reload(B);
    const before = requests.length;
    await reload(A);
    assert.equal(requests.length, before);
  });
});

test('une ancienne relecture en erreur ne vide pas les listes du code courant', async () => {
  await fixture(async ({ reload, select, view, status }) => {
    select(B);
    await reload(B);
    status.set(A, 503);
    await reload(A);
    assert.equal(view.sources.length, 2);
    assert.equal(view.loaded, true);
    assert.equal(view.err, null);
  });
});

test('une réponse commencée avant le changement de code est ignorée', async () => {
  await fixture(async ({ reload, select, view, blocks }) => {
    let release;
    blocks.set(A, new Promise(resolve => { release = resolve; }));
    const old = reload(A);
    select(B);
    await reload(B);
    release();
    await old;
    assert.equal(view.sources.length, 2);
    assert.equal(view.loaded, true);
    assert.equal(view.looking, false);
  });
});

test('404 pour le code courant conserve la possibilité d’ajouter sa première liste', async () => {
  await fixture(async ({ reload, view, status }) => {
    status.set(A, 404);
    await reload(A);
    assert.equal(view.loaded, true);
    assert.equal(view.sources.length, 0);
    assert.equal(view.looking, false);
  });
});
