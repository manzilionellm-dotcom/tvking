// Test de l'écran React réel dans Chromium contre worker.fetch + SQLite.
// Ce harnais ne lance PAS workerd et ne reproduit PAS une télévision.
// Aucun appel hors localhost, aucun secret ni jeton dans le journal.
import assert from 'node:assert/strict';
import { createServer as createHttpServer } from 'node:http';
import { randomUUID, randomBytes } from 'node:crypto';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { chromium } from 'playwright';

// Lancer depuis panel-box : npm ci && npx playwright install chromium
// puis npm run audit:snapshot ; installer aussi le panel avec npm ci.
// Node 22+ requis pour node:sqlite. Aucune variable d'environnement modifiée.
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '../../..');
const INITIAL_CWD = process.cwd();
const { createServer: createViteServer } = await import(pathToFileURL(ROOT + '/android-app/admin-panel/node_modules/vite/dist/node/index.js'));
const { default: worker, RealtimeHub } = await import(pathToFileURL(ROOT + '/android-app/cloudflare/worker.js'));
const { createD1, fakeRealtimeHub } = await import(pathToFileURL(ROOT + '/android-app/cloudflare/test_support/d1_sqlite.mjs'));
const db = createD1({ extraSql: ['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT', 'ALTER TABLE devices ADD COLUMN block_status TEXT'] });
const env = { DB: db.DB, ADMIN_SECRET: randomUUID(), SECRETS_KEY: randomUUID() };
env.RT_HUB = fakeRealtimeHub(env, RealtimeHub);
const pending = new Set();
const ctx = {
  waitUntil(p) {
    const task = Promise.resolve(p).catch(() => {});
    pending.add(task);
    task.then(() => pending.delete(task));
  },
  passThroughOnException() {},
};
const WORKER = 'http://127.0.0.1:8799';
const PANEL = 'http://127.0.0.1:5199';
const MAC_A = 'MK:AA:BB:CC:DD:81';
const MAC_B = 'MK:AA:BB:CC:DD:82';
const MAC_C = 'MK:AA:BB:CC:DD:83';
const sourcePath = mac => '/api/v1/sources/' + encodeURIComponent(mac);
const sourcesA = { type: 'm3u', label: 'Audit A eteinte', m3u_url: 'http://127.0.0.1/audit/a.m3u', enabled: false };
const addedB = { type: 'm3u', label: 'Audit B concurrente', m3u_url: 'http://127.0.0.1/audit/b.m3u' };
const selfSource = { type: 'm3u', label: 'Audit client', m3u_url: 'http://127.0.0.1/audit/self.m3u' };
const freshC = { type: 'xtream', server_url: 'http://127.0.0.1:18991', username: 'fixture-' + randomBytes(8).toString('hex'), password: randomUUID() };
const otherSource = { type: 'xtream', label: 'Audit autre box', server_url: 'http://127.0.0.1:18992', username: 'fixture', password: randomUUID() };
const results = [];
let vite, browser, token;
const server = createHttpServer(async (incoming, outgoing) => {
  try {
    const bytes = [];
    for await (const chunk of incoming) bytes.push(chunk);
    const body = Buffer.concat(bytes);
    const request = new Request(WORKER + incoming.url, {
      method: incoming.method,
      headers: incoming.headers,
      ...(body.length ? { body } : {}),
    });
    const response = await worker.fetch(request, env, ctx);
    await Promise.allSettled([...pending]);
    outgoing.writeHead(response.status, Object.fromEntries(response.headers));
    outgoing.end(Buffer.from(await response.arrayBuffer()));
  } catch {
    outgoing.writeHead(500, { 'content-type': 'application/json' });
    outgoing.end('{"error":"harness_failure"}');
  }
});

function redact(message) {
  let clean = String(message);
  for (const value of [env.ADMIN_SECRET, env.SECRETS_KEY, freshC.username, freshC.password, otherSource.password, token]) {
    if (value) clean = clean.split(value).join('[masqué]');
  }
  return clean.replace(/Bearer\s+[A-Za-z0-9._-]+/gi, 'Bearer [masqué]');
}

function passed(name) {
  results.push({ name, status: 'passed' });
  process.stdout.write('PASS ' + name + '\n');
}
async function waitForHarness(promise, name) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Délai dépassé : ' + name)), 12000); }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}
async function api(method, path, body, auth = true) {
  const response = await fetch(WORKER + path, {
    method,
    headers: { 'content-type': 'application/json', ...(auth && token ? { authorization: 'Bearer ' + token } : {}) },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  return { status: response.status, json: await response.json() };
}
const snapshot = () => JSON.stringify({
  sources: db.db.prepare('SELECT * FROM device_sources ORDER BY mac').all(),
  revisions: db.db.prepare('SELECT * FROM source_revisions ORDER BY mac, rev').all(),
  orders: db.db.prepare('SELECT * FROM box_orders ORDER BY order_id').all(),
  licenses: db.db.prepare('SELECT * FROM licenses ORDER BY id').all(),
});
const licenses = () => JSON.stringify(db.db.prepare('SELECT * FROM licenses ORDER BY id').all());
const sourceMatches = (s, expected) => Object.keys(expected).every(k => s[k] === expected[k]);
const get = mac => api('GET', sourcePath(mac));
const put = (mac, sources, rev) => api('PUT', sourcePath(mac), { sources, ...(rev !== undefined ? { expected_rev: rev } : {}) });
const sourceSection = page => page.getByRole('region', { name: 'Listes de cette box', exact: true });

try {
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(8799, '127.0.0.1', resolve); });
  // Tailwind résout sa configuration depuis le cwd ; garder le vrai style du panel.
  process.chdir(ROOT + '/android-app/admin-panel');
  vite = await createViteServer({
    configFile: ROOT + '/android-app/admin-panel/vite.config.ts',
    root: ROOT + '/android-app/admin-panel',
    logLevel: 'silent',
    server: { host: '127.0.0.1', port: 5199, strictPort: true, proxy: { '/api': { target: WORKER, changeOrigin: true } } },
  });
  await vite.listen();
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  page.on('pageerror', error => process.stderr.write('UI JavaScript error: ' + redact(error.message) + '\n'));
  page.on('response', response => { if (response.status() >= 400 && !response.url().includes('/api/')) process.stderr.write('UI asset HTTP ' + response.status() + ' ' + new URL(response.url()).pathname + '\n'); });
  page.setDefaultTimeout(12000);
  // Bloque les ressources et appels inattendus, même si le panel change.
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    return url.hostname === '127.0.0.1' || url.hostname === 'localhost' ? route.continue() : route.abort();
  });
  await page.goto(PANEL + '/login');
  await page.locator('#login-id').fill('admin');
  await page.locator('input[type="password"]').fill(env.ADMIN_SECRET);
  await page.getByRole('button', { name: 'Se connecter', exact: true }).click();
  await page.getByRole('heading', { name: 'Tableau de bord', exact: true }).waitFor();
  token = await page.evaluate(() => localStorage.getItem('auth_token'));
  assert.ok(token, 'connexion doit fournir un jeton');
  const me = await api('GET', '/api/v1/auth/me');
  assert.ok(me.status === 200 && me.json.user.role === 'super_admin');
  passed('Connexion admin réelle dans Chromium');

  for (const mac of [MAC_A, MAC_B, MAC_C]) {
    const activate = await api('POST', '/api/v1/activate', { mac, plan: 'yearly' });
    assert.equal(activate.status, 201, 'licence de fixture créée');
  }
  assert.equal((await put(MAC_A, [sourcesA])).status, 200);
  assert.equal((await put(MAC_B, [otherSource])).status, 200);
  assert.equal((await put(MAC_C, [{ type: 'm3u', label: 'Audit nouvelle destination', m3u_url: 'http://127.0.0.1/audit/c.m3u' }])).status, 200);
  assert.equal((await api('POST', '/api/self-source/' + encodeURIComponent(MAC_A), selfSource, false)).status, 200);
  const licenseBefore = licenses();
  const otherBefore = JSON.stringify(await get(MAC_B));
  await page.goto(PANEL + '/chaines?mac=' + encodeURIComponent(MAC_A));
  await sourceSection(page).getByText('Audit A eteinte', { exact: true }).waitFor();
  await sourceSection(page).getByText('Audit client', { exact: true }).waitFor();
  const old = await get(MAC_A);
  assert.ok(Number.isSafeInteger(old.json.rev), 'GET sources renvoie une révision entière');
  await page.getByRole('radio', { name: 'Xtream', exact: true }).check();
  await page.locator('#chaines-server').fill(freshC.server_url);
  await page.locator('#chaines-username').fill(freshC.username);
  await page.locator('#chaines-password').fill(freshC.password);
  passed('Écran Listes affiche M3U éteinte, liste client et choix Xtream');

  assert.equal((await put(MAC_A, [sourcesA, addedB], old.json.rev)).status, 200);
  const beforeRejected = snapshot();
  const sentBodies = [];
  page.on('request', request => {
    if (request.method() === 'PUT' && new URL(request.url()).pathname === sourcePath(MAC_A)) sentBodies.push(request.postDataJSON());
  });
  const rejectedPromise = page.waitForResponse(response => response.request().method() === 'PUT' && new URL(response.url()).pathname === sourcePath(MAC_A));
  await page.getByRole('button', { name: 'Ajouter la source Xtream', exact: true }).click();
  const rejected = await rejectedPromise;
  assert.equal(rejected.status(), 409, 'snapshot périmé doit être refusé');
  assert.equal(sentBodies[0]?.expected_rev, old.json.rev, 'UI transmet sa révision lue');
  await sourceSection(page).getByText('Audit B concurrente', { exact: true }).waitFor();
  assert.ok(snapshot() === beforeRejected, 'conflit ne modifie aucune source, révision, ordre ni licence');
  assert.ok(await page.locator('#chaines-server').inputValue() === freshC.server_url);
  assert.ok(await page.locator('#chaines-username').inputValue() === freshC.username);
  assert.ok(await page.locator('#chaines-password').inputValue() === freshC.password);
  assert.ok(licenses() === licenseBefore);
  passed('Ajout concurrent refuse 409, recharge B et conserve les champs Xtream sans perte');

  const current = await get(MAC_A);
  const retryPromise = page.waitForResponse(response => response.request().method() === 'PUT' && new URL(response.url()).pathname === sourcePath(MAC_A));
  await page.getByRole('button', { name: 'Ajouter la source Xtream', exact: true }).click();
  assert.equal((await retryPromise).status(), 200);
  await page.waitForFunction(() => document.querySelector('#chaines-password')?.value === '');
  assert.equal(sentBodies[1]?.expected_rev, current.json.rev, 'nouvelle tentative emploie la révision rafraîchie');
  const final = await get(MAC_A);
  assert.ok(final.json.sources.some(s => sourceMatches(s, sourcesA)), 'M3U éteinte conservée');
  assert.ok(final.json.sources.some(s => sourceMatches(s, addedB)), 'ajout concurrent B conservé');
  assert.ok(final.json.sources.some(s => s.origin === 'self' && s.m3u_url === selfSource.m3u_url), 'liste client conservée');
  assert.ok(final.json.sources.some(s => sourceMatches(s, freshC)), 'nouvelle Xtream complète');
  assert.ok(JSON.stringify(await get(MAC_B)) === otherBefore, 'autre MAC intacte');
  assert.ok(licenses() === licenseBefore, 'licences inchangées');
  passed('Nouvelle tentative ajoute Xtream et garde A, B, client, autre MAC et licences');

  // Une lecture A déjà en cours ne doit ni remplir l'écran C, ni armer son envoi.
  let releaseRead;
  const holdRead = new Promise(resolve => { releaseRead = resolve; });
  let readIntercepted;
  const reachedRead = new Promise(resolve => { readIntercepted = resolve; });
  let intercepted = false;
  await page.route('**/api/v1/sources/**', async route => {
    if (!intercepted && route.request().method() === 'GET' && new URL(route.request().url()).pathname === sourcePath(MAC_A)) {
      intercepted = true;
      // Capture la vraie réponse A avant de la retarder au navigateur.
      const response = await route.fetch();
      readIntercepted();
      await holdRead;
      await route.fulfill({ response });
      return;
    }
    await route.continue();
  });
  await page.locator('#chaines-mac').fill('');
  await page.locator('#chaines-mac').fill(MAC_A);
  await waitForHarness(reachedRead, 'interception de la lecture A');
  await page.locator('#chaines-mac').fill(MAC_C);
  await sourceSection(page).getByText('Audit nouvelle destination', { exact: true }).waitFor();
  const delayedResponsePromise = page.waitForResponse(response => response.request().method() === 'GET' && new URL(response.url()).pathname === sourcePath(MAC_A));
  releaseRead();
  // Attend explicitement la réception de la réponse retardée via une marque réseau.
  await delayedResponsePromise;
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.waitForFunction(() => document.querySelector('#chaines-mac')?.value === 'MK:AA:BB:CC:DD:83');
  assert.equal(await sourceSection(page).getByText('Audit A eteinte', { exact: true }).count(), 0);
  assert.equal(await sourceSection(page).getByText('Audit nouvelle destination', { exact: true }).count(), 1);
  passed('Changement A vers C ignore la lecture A retardée');

  // Le retrait de la dernière liste utilise DELETE. L'ajout d'une autre liste
  // pendant la confirmation doit rendre ce DELETE périmé et préserver les deux.
  const baseC = await get(MAC_C);
  await sourceSection(page).getByRole('button', { name: 'Retirer Audit nouvelle destination', exact: true }).click();
  const dialog = page.getByRole('alertdialog');
  await dialog.waitFor();
  const extraC = { type: 'm3u', label: 'Audit C concurrente', m3u_url: 'http://127.0.0.1/audit/c-extra.m3u' };
  assert.equal((await put(MAC_C, [...baseC.json.sources, extraC], baseC.json.rev)).status, 200);
  const beforeDeleteConflict = snapshot();
  let deleteBody;
  page.on('request', request => {
    if (request.method() === 'DELETE' && new URL(request.url()).pathname === sourcePath(MAC_C)) deleteBody = request.postDataJSON();
  });
  const deleteConflict = page.waitForResponse(response => response.request().method() === 'DELETE' && new URL(response.url()).pathname === sourcePath(MAC_C));
  await dialog.getByRole('button', { name: 'Retirer', exact: true }).click();
  assert.equal((await deleteConflict).status(), 409);
  assert.equal(deleteBody?.expected_rev, baseC.json.rev);
  await sourceSection(page).getByText('Audit C concurrente', { exact: true }).waitFor();
  assert.ok(snapshot() === beforeDeleteConflict, 'DELETE périmé ne touche aucune liste, révision, ordre ou licence');
  passed('DELETE après confirmation périmée refuse 409 et conserve les deux listes');

  // Envoi réussi après changement de box : aucun snapshot A ne doit voyager vers C.
  const aBeforeSwitchWrite = JSON.stringify(await get(MAC_A));
  const cBeforeSwitchWrite = await get(MAC_C);
  let changedDestinationBody;
  page.on('request', request => {
    if (request.method() === 'PUT' && new URL(request.url()).pathname === sourcePath(MAC_C)) changedDestinationBody = request.postDataJSON();
  });
  await page.locator('#chaines-server').fill(freshC.server_url);
  await page.locator('#chaines-username').fill(freshC.username);
  await page.locator('#chaines-password').fill(freshC.password);
  const switchedWrite = page.waitForResponse(response => response.request().method() === 'PUT' && new URL(response.url()).pathname === sourcePath(MAC_C));
  await page.getByRole('button', { name: 'Ajouter la source Xtream', exact: true }).click();
  assert.equal((await switchedWrite).status(), 200);
  await page.waitForFunction(() => document.querySelector('#chaines-password')?.value === '');
  assert.equal(changedDestinationBody?.expected_rev, cBeforeSwitchWrite.json.rev);
  assert.ok(!changedDestinationBody.sources.some(s => s.m3u_url === sourcesA.m3u_url || s.m3u_url === addedB.m3u_url));
  const switchedFinal = await get(MAC_C);
  assert.ok(switchedFinal.json.sources.some(s => sourceMatches(s, freshC)));
  assert.ok(switchedFinal.json.sources.some(s => sourceMatches(s, extraC)));
  assert.ok(JSON.stringify(await get(MAC_A)) === aBeforeSwitchWrite);
  assert.ok(JSON.stringify(await get(MAC_B)) === otherBefore);
  const beforeInvalid = snapshot();
  await page.locator('#chaines-mac').fill('');
  assert.ok(await page.getByRole('button', { name: 'Ajouter la source Xtream', exact: true }).isDisabled());
  assert.ok(snapshot() === beforeInvalid, 'MAC vide ne modifie aucune donnée');
  assert.ok(licenses() === licenseBefore);
  passed('Envoi après passage sur C garde son snapshot, les MAC A/B intactes ; MAC vide bloque Ajouter');

  process.stdout.write('BILAN ' + results.length + ' contrôles Chromium réussis ; worker.fetch + SQLite, sans workerd ni télévision.\n');
} catch (error) {
  // Messages fixes seulement : ne jamais imprimer les objets d'assertion contenant des fixtures.
  process.stderr.write('ECHEC audit Chromium : ' + redact(error.message) + '\n');
  process.exitCode = 1;
} finally {
  if (browser) await browser.close();
  if (vite) await vite.close();
  await new Promise(resolve => server.close(resolve));
  db.db.close();
  process.chdir(INITIAL_CWD);
}
