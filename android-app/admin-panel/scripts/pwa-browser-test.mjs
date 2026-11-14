// Chromium réel, profil jetable, API locale simulée. Aucun compte, abonnement
// Push ou serveur de production n'est contacté par ce scénario.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { constants } from 'node:fs';
import { access, readFile, stat, mkdir } from 'node:fs/promises';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const evidence = resolve(process.env.PANEL_TEST_OUTPUT || join(root, 'test-output/pwa'));
await mkdir(evidence, { recursive: true });
let checks = 0;
const check = (value, message) => { assert.ok(value, message); checks++; };
const MAC = 'MK:AA:BB:CC:DD:EE';
const NOW = Date.now();
const account = { id: 'owner_fixture', email: 'fixture@example.invalid', name: 'Compte de test', role: 'super_admin' };
const vapid = Buffer.from([4, ...Array(64).fill(1)]).toString('base64url');
const types = { new_device: true, activation: true, problem: true };
const fixtureDevice = { id: 'device_fixture', customer_id: 'customer_fixture', mac: MAC, label: 'Téléviseur de démonstration', first_seen_at: NOW, last_seen_at: NOW, platform: 'tv', device_model: 'Android TV de test', block_status: 'active' };
const events = [
  { event_id: 'fixture-event-3', type: 'problem', title: 'Liste non chargée', message: 'Un échec de chargement a été confirmé. Le diagnostic est disponible.', seq: 3 },
  { event_id: 'fixture-event-2', type: 'activation', title: 'Activation enregistrée', message: 'L’activation de l’appareil a été enregistrée.', seq: 2 },
  { event_id: 'fixture-event-1', type: 'new_device', title: 'Nouvel appareil', message: 'Un appareil vient de s’enregistrer.', seq: 1 },
].map((value) => ({ v: 1, ...value, url: `${value.type === 'problem' ? '/blackbox' : '/devices'}?mac=${encodeURIComponent(MAC)}`, created_at: NOW - value.seq * 10_000, read_at: null }));

const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    let file = resolve(root, 'dist', '.' + path);
    if (!file.startsWith(resolve(root, 'dist') + '/')) file = join(root, 'dist/index.html');
    try { if (!(await stat(file)).isFile()) throw new Error(); }
    catch { file = join(root, 'dist/index.html'); }
    let body = await readFile(file);
    if (path === '/panel-sw.js') {
      // Instrumentation de test seulement : conserve les vrais handlers et
      // leur stockage IndexedDB, sans modifier le fichier livré.
      body = Buffer.concat([Buffer.from("self.__fixtureHandlers={};const fixtureAdd=self.addEventListener.bind(self);self.addEventListener=(name,fn,...rest)=>{self.__fixtureHandlers[name]=fn;return fixtureAdd(name,fn,...rest)};\n"), body]);
    }
    response.writeHead(200, { 'Content-Type': ({ '.html': 'text/html', '.js': 'application/javascript', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' })[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store', 'Service-Worker-Allowed': '/' });
    response.end(body);
  } catch { response.writeHead(500); response.end(); }
});
await new Promise((done) => server.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${server.address().port}`;
let executablePath = process.env.PANEL_TEST_CHROMIUM?.trim() || undefined;
if (!executablePath) {
  try { await access('/usr/bin/chromium', constants.X_OK); executablePath = '/usr/bin/chromium'; }
  catch { /* Sans binaire système, utilise le navigateur fourni par Playwright. */ }
}
let browser;
try {
  browser = await chromium.launch({ ...(executablePath ? { executablePath } : {}), headless: true,
    args: ['--no-sandbox', '--disable-background-networking', '--disable-component-update', '--disable-sync'] });
} catch (failure) {
  await new Promise((done) => server.close(done));
  throw failure;
}
const pageErrors = [];
let forbiddenNetwork = 0;

async function context({ token = true, permission = 'denied-on-click', width = 390, role = 'super_admin', unavailable = false } = {}) {
  const ctx = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 960 }, locale: 'fr-FR' });
  await ctx.grantPermissions(['notifications'], { origin }); // Uniquement ce profil de fixture local.
  const state = { posts: 0, deletes: 0, failure: false, offline: false, holdPost: false, releasePost: null, sub: null, prefs: { ok: true, enabled: true, types: { ...types }, push_available: true, public_key: vapid }, read: new Set(), routes: [] };
  await ctx.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== origin) { forbiddenNetwork++; return route.abort(); }
    if (!url.pathname.startsWith('/api/')) return route.continue();
    if (state.offline) return route.abort();
    const method = route.request().method();
    state.routes.push([method, url.pathname]);
    const fulfill = (body, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body), headers: { 'Cache-Control': 'no-store' } });
    if (url.pathname.endsWith('/rt/ticket')) return fulfill({ error: 'fixture_no_realtime' }, 404);
    if (url.pathname.endsWith('/auth/login') || url.pathname.endsWith('/auth/reseller/login')) return fulfill({ token: 'fixture-token', user: { ...account, role } });
    if (url.pathname.endsWith('/auth/me') || url.pathname === '/api/v1/me') return fulfill({ user: { ...account, role } });
    if (url.pathname.endsWith('/panel-alerts/preferences')) {
      if (method === 'PUT') state.prefs = { ...state.prefs, ...route.request().postDataJSON() };
      return fulfill(state.prefs);
    }
    if (url.pathname === '/api/v1/panel-alerts/events') {
      const after = Number(url.searchParams.get('after') || 0);
      return fulfill({ ok: true, items: events.filter((item) => item.seq > after).map((item) => ({ ...item, read_at: state.read.has(item.event_id) ? NOW : null })), next_cursor: 3, unread_count: 3 - state.read.size });
    }
    if (url.pathname.endsWith('/panel-alerts/read')) { for (const id of route.request().postDataJSON().event_ids) state.read.add(id); return fulfill({ ok: true }); }
    if (url.pathname === '/api/v1/panel-alerts/subscriptions') {
      if (method === 'POST') {
        state.posts++;
        if (state.holdPost) await new Promise((resolve) => { state.releasePost = resolve; });
        if (state.failure) return fulfill({ ok: false, error: 'fixture_unavailable', message: 'Service de test indisponible.' }, 503);
        state.sub = { id: 'subscription_fixture', enabled: true, current_session: true, created_at: NOW, consented_at: NOW, expires_at: NOW + 7 * 86400000, last_success_at: null, revoked_at: null, revoked_reason: null, label: 'Navigateur de test' };
        return fulfill({ ok: true, id: state.sub.id, enabled: true, delivery_confirmed: false, consented_at: NOW, expires_at: state.sub.expires_at });
      }
      return fulfill({ ok: true, items: state.sub ? [state.sub] : [] });
    }
    if (url.pathname.startsWith('/api/v1/panel-alerts/subscriptions/') && method === 'DELETE') {
      check(route.request().headers().authorization === 'Bearer fixture-token', 'Révocation encore authentifiée');
      state.deletes++; state.sub = null; return fulfill({ ok: true });
    }
    if (url.pathname === '/api/v1/devices') return fulfill({ items: [fixtureDevice], total: 1, limit: 100, offset: 0 });
    if (url.pathname.endsWith('/device_fixture/overview')) return fulfill({ mac: MAC, license: null, presence: { online: false, ip: '', country: '', channel: '', last_seen: NOW }, sources: [] });
    if (url.pathname.endsWith('/novatube4k/reassociate')) return fulfill({ error: 'recovery_not_supported' }, 404);
    if (url.pathname.endsWith('/sessions')) return fulfill({ items: [] });
    if (url.pathname.endsWith('/2fa')) return fulfill({ enabled: false });
    return fulfill({ ok: true });
  });
  await ctx.addInitScript(({ token, permission, unavailable }) => {
    if (token) localStorage.setItem('auth_token', 'fixture-token');
    window.__permissionRequests = 0; window.__subscribeCalls = 0; window.__unsubscribeCalls = 0;
    let currentPermission = permission === 'granted' ? 'granted' : 'default';
    if (unavailable) delete window.PushManager;
    Object.defineProperty(Notification, 'permission', { configurable: true, get: () => currentPermission });
    Notification.requestPermission = async () => { window.__permissionRequests++; currentPermission = permission === 'denied-on-click' ? 'denied' : 'granted'; return currentPermission; };
    let subscription = null;
    const push = {
      getSubscription: async () => subscription,
      subscribe: async () => {
        window.__subscribeCalls++;
        subscription = { endpoint: 'https://push.example.invalid/local-fixture', toJSON: () => ({ endpoint: 'https://push.example.invalid/local-fixture', keys: { p256dh: 'fixture-p256dh', auth: 'fixture-auth' }, expirationTime: null }), unsubscribe: async () => { window.__unsubscribeCalls++; if (window.__failUnsubscribe) throw new Error('fixture offline'); subscription = null; return true; } };
        return subscription;
      },
    };
    Object.defineProperty(ServiceWorkerRegistration.prototype, 'pushManager', { configurable: true, get: () => push });
  }, { token, permission, unavailable });
  const page = await ctx.newPage();
  page.on('pageerror', (error) => pageErrors.push(error.message));
  return { ctx, page, state };
}

try {
  const phone = await context();
  await phone.page.goto(origin + '/account');
  const enable = phone.page.getByRole('button', { name: 'Activer sur ce téléphone', exact: true });
  await enable.waitFor();
  await phone.page.waitForFunction(() => Array.from(document.querySelectorAll('button')).some((button) => button.textContent === 'Activer sur ce téléphone' && !button.disabled));
  check(await phone.page.evaluate(() => window.__permissionRequests) === 0, 'Aucune permission automatique');
  check(phone.state.posts === 0, 'Aucun abonnement au chargement');
  await enable.click();
  await phone.page.getByText('Notifications bloquées dans les réglages du navigateur.', { exact: false }).waitFor();
  check(await phone.page.evaluate(() => window.__permissionRequests) === 1, 'Permission demandée par clic seulement');
  check(phone.state.posts === 0, 'Refus navigateur bloque l’abonnement serveur');
  await phone.page.getByRole('region', { name: 'Alertes sur ce téléphone' }).scrollIntoViewIfNeeded();
  await phone.page.screenshot({ path: join(evidence, 'phone-permission-denied.png') });
  await phone.page.evaluate(() => {
    window.__installCalls = 0;
    const event = new Event('beforeinstallprompt', { cancelable: true });
    Object.defineProperty(event, 'prompt', { value: async () => { window.__installCalls++; } });
    Object.defineProperty(event, 'userChoice', { value: Promise.resolve({ outcome: 'accepted' }) });
    window.dispatchEvent(event);
  });
  check(await phone.page.evaluate(() => window.__installCalls) === 0, 'Installation jamais ouverte automatiquement');
  await phone.page.getByRole('button', { name: 'Installer le panneau', exact: true }).click();
  await phone.page.getByText('Installation demandée.', { exact: false }).waitFor();
  check(await phone.page.getByText('Le panneau est installé.', { exact: true }).count() === 0, 'Acceptation seule ne prétend pas installation terminée');
  await phone.page.evaluate(() => window.dispatchEvent(new Event('appinstalled')));
  await phone.page.getByText('Le panneau est installé.', { exact: true }).waitFor();
  checks++;
  await phone.page.getByRole('region', { name: 'Installer le panneau' }).scrollIntoViewIfNeeded();
  await phone.page.screenshot({ path: join(evidence, 'phone-installation.png') });
  const cdp = await phone.ctx.newCDPSession(phone.page);
  const manifest = await cdp.send('Page.getAppManifest');
  check(manifest.errors.length === 0 && JSON.parse(manifest.data).display === 'standalone', 'Manifeste lu par Chromium');

  const inbox = await context({ permission: 'granted' });
  await inbox.page.goto(origin + '/alerts');
  await inbox.page.getByText('3 alertes non lues', { exact: true }).waitFor();
  check(await inbox.page.locator('article').count() === 3, 'Trois événements réels de fixture, aucun doublon');
  await inbox.page.getByRole('button', { name: 'Marquer comme lue' }).first().click();
  await inbox.page.getByText('2 alertes non lues', { exact: true }).waitFor();
  checks++;
  await inbox.page.screenshot({ path: join(evidence, 'phone-inbox.png') });
  await inbox.page.goto(origin + '/account');
  inbox.state.failure = true;
  await inbox.page.getByRole('button', { name: 'Activer sur ce téléphone', exact: true }).click();
  await inbox.page.getByText('Les alertes n’ont pas pu être configurées.', { exact: false }).waitFor();
  check(await inbox.page.getByText('Alertes activées sur ce téléphone.', { exact: true }).count() === 0, 'Souscription navigateur seule jamais affichée active');
  inbox.state.failure = false;
  await inbox.page.getByRole('button', { name: 'Activer sur ce téléphone', exact: true }).click();
  await inbox.page.getByText('Alertes activées sur ce téléphone.', { exact: true }).waitFor();
  check(await inbox.page.getByText('Cet abonnement est valable jusqu’au', { exact: false }).count() === 1, 'Expiration réelle affichée');
  const remembered = await inbox.page.evaluate(() => localStorage.getItem('panel_push_binding_v1'));
  check(!remembered.includes('fixture-auth') && !remembered.includes('push.example.invalid'), 'Mapping sans endpoint ou clés Push');
  await inbox.page.getByRole('button', { name: 'Déconnexion', exact: true }).first().click();
  await inbox.page.waitForURL('**/login');
  check(inbox.state.deletes === 1, 'Abonnement serveur révoqué avant logout');
  check(await inbox.page.evaluate(() => window.__unsubscribeCalls) === 1, 'Abonnement navigateur retiré');
  check(await inbox.page.evaluate(() => localStorage.getItem('auth_token')) === null, 'Jeton retiré après révocation');

  const unsupported = await context({ unavailable: true });
  await unsupported.page.goto(origin + '/account');
  await unsupported.page.getByText('Les notifications ne sont pas disponibles dans ce navigateur.', { exact: true }).waitFor();
  check(await unsupported.page.getByRole('button', { name: 'Activer sur ce téléphone', exact: true }).count() === 0, 'Navigateur non compatible sans faux bouton actif');
  const support = await context({ role: 'support' });
  await support.page.goto(origin + '/account');
  await support.page.getByRole('region', { name: 'Installer le panneau' }).waitFor();
  check(await support.page.getByRole('region', { name: 'Alertes sur ce téléphone' }).count() === 0, 'Alertes réservées super_admin');
  check(!support.state.routes.some(([, path]) => path.startsWith('/api/v1/panel-alerts/')), 'Aucune lecture alertes par support');

  const login = await context({ token: false, width: 1280 });
  await login.page.goto(origin + '/devices?mac=' + encodeURIComponent(MAC));
  await login.page.waitForURL('**/login');
  await login.page.locator('#login-id').fill('admin');
  await login.page.locator('#login-password').fill('Fixture-only-Password-2026');
  await login.page.locator('form button[type=submit]').click();
  await login.page.waitForURL('**/devices?mac=*');
  await login.page.getByRole('heading', { name: 'Centre de contrôle appareil' }).waitFor();
  check(login.state.routes.some(([, path]) => path === '/api/v1/devices'), 'Fiche relue par API authentifiée');
  check(login.state.routes.some(([, path]) => path.endsWith('/device_fixture/overview')), 'Ouverture de la vraie fiche retournée');
  await login.page.screenshot({ path: join(evidence, 'desktop-deep-link.png') });
  await login.page.goto(origin + '/alerts');
  await login.page.locator('article').first().waitFor();
  await login.page.screenshot({ path: join(evidence, 'desktop-inbox.png') });

  // Vrai runtime ServiceWorker/IndexedDB ; appels synthétiques de ses handlers,
  // aucune connexion à un service Push externe.
  const pushFixture = await context({ permission: 'granted' });
  await pushFixture.page.goto(origin + '/account');
  await pushFixture.page.getByRole('button', { name: 'Activer sur ce téléphone', exact: true }).click();
  await pushFixture.page.getByText('Alertes activées sur ce téléphone.', { exact: true }).waitFor();
  const worker = pushFixture.ctx.serviceWorkers()[0] || await pushFixture.ctx.waitForEvent('serviceworker');
  const invoke = (data) => worker.evaluate(async (value) => {
    const tasks = [];
    self.__fixtureHandlers.push({ data: value == null ? null : { text: () => typeof value === 'string' ? value : JSON.stringify(value) }, waitUntil: (task) => tasks.push(task) });
    await Promise.all(tasks);
    return (await self.registration.getNotifications()).length;
  }, data);
  const alert = { v: 1, event_id: 'browser-event-1', type: 'new_device', title: 'Nouvel appareil de test', message: 'Événement local de test.', url: '/devices?mac=' + encodeURIComponent(MAC) };
  check(await invoke(alert) === 1, 'Notification valide affichée par le vrai worker');
  await Promise.all([invoke(alert), invoke(alert), invoke(alert)]);
  check(await invoke(alert) === 1, 'Claim IndexedDB atomique contre les doublons');
  for (const malformed of [null, 'invalid json', { ...alert, event_id: 'browser-event-bad', token: 'fixture' }, { ...alert, event_id: 'browser-event-bad', url: 'https://external.invalid/' }, { ...alert, event_id: 'browser-event-bad', title: 'password=fixture' }]) {
    check(await invoke(malformed) === 1, 'Payload invalide ignoré sans notification');
  }
  const keys = await worker.evaluate(async () => {
    const db = await openSeen();
    const rows = await new Promise((done) => { const request = db.transaction('seen').objectStore('seen').getAll(); request.onsuccess = () => done(request.result); });
    db.close(); return rows.map((row) => Object.keys(row).sort());
  });
  check(keys.every((row) => JSON.stringify(row) === '["at","id"]'), 'Déduplication stocke seulement ID et date');
  check(await worker.evaluate(async () => (await caches.keys()).length) === 0, 'Aucun cache du worker');
  check(await worker.evaluate(() => !self.__fixtureHandlers.fetch), 'Aucun intercepteur fetch/API');
  await worker.evaluate(() => { self.__originalShow = self.registration.showNotification.bind(self.registration); self.registration.showNotification = async () => { throw new Error('fixture failure'); }; });
  const retry = { ...alert, event_id: 'browser-event-retry' };
  await invoke(retry);
  await worker.evaluate(() => { self.registration.showNotification = self.__originalShow; });
  check(await invoke(retry) === 2, 'Échec showNotification libère le claim pour une reprise');
  const clickResult = await worker.evaluate(async () => {
    const opened = [];
    self.clients.matchAll = async () => [];
    self.clients.openWindow = async (url) => { opened.push(url); return null; };
    async function click(url) { const tasks = []; self.__fixtureHandlers.notificationclick({ notification: { close() {}, data: { url } }, waitUntil: (task) => tasks.push(task) }); await Promise.all(tasks); }
    await click('https://external.invalid/');
    await click('/devices?mac=MK%3AAA%3ABB%3ACC%3ADD%3AEE');
    return opened;
  });
  check(clickResult.length === 1 && clickResult[0].startsWith(origin + '/devices?mac='), 'Clic limité à une destination autorisée de cette origine');
  await worker.evaluate(() => {
    self.__lateShowStarted = false;
    self.registration.showNotification = async (...args) => {
      self.__lateShowStarted = true;
      await new Promise((resolve) => { self.__releaseLateShow = resolve; });
      return self.__originalShow(...args);
    };
  });
  const lateDisplay = invoke({ ...alert, event_id: 'browser-late-display' });
  for (let i = 0; i < 100 && !await worker.evaluate(() => self.__lateShowStarted); i++) {
    await new Promise((done) => setTimeout(done, 20));
  }
  check(await worker.evaluate(() => self.__lateShowStarted), 'Affichage asynchrone commencé avant logout');
  pushFixture.state.offline = true;
  await pushFixture.page.evaluate(() => { window.__failUnsubscribe = true; });
  await pushFixture.page.getByRole('button', { name: 'Déconnexion', exact: true }).first().click();
  await pushFixture.page.waitForURL('**/login');
  await worker.evaluate(() => { self.__releaseLateShow(); self.registration.showNotification = self.__originalShow; });
  check(await lateDisplay === 0, 'Affichage terminé après logout immédiatement fermé');
  check(await invoke({ ...alert, event_id: 'browser-after-offline-logout' }) === 0, 'Logout hors réseau coupe les affichages et ferme les notifications existantes');
  check(await worker.evaluate(async () => (await consent()).enabled) === false, 'Consentement coupé persiste malgré échec unsubscribe et réseau');

  const stale = await context({ permission: 'granted' });
  await stale.page.goto(origin + '/account');
  stale.state.holdPost = true;
  await stale.page.getByRole('button', { name: 'Activer sur ce téléphone', exact: true }).click();
  for (let i = 0; !stale.state.releasePost && i < 100; i++) await new Promise((done) => setTimeout(done, 20));
  check(typeof stale.state.releasePost === 'function', 'Approbation réseau de fixture en attente');
  const staleWorker = stale.ctx.serviceWorkers()[0];
  await staleWorker.evaluate(async () => {
    const tasks = [];
    self.__fixtureHandlers.message({ data: { type: 'panel-consent-off', nonce: 'fixture-stale-disabled-nonce' }, ports: [], waitUntil: (task) => tasks.push(task) });
    await Promise.all(tasks);
  });
  stale.state.releasePost();
  await stale.page.getByText('Les alertes n’ont pas pu être configurées.', { exact: false }).waitFor();
  check(await stale.page.getByText('Alertes activées sur ce téléphone.', { exact: true }).count() === 0, 'Réponse tardive ne réactive pas le téléphone');
  check(await staleWorker.evaluate(async () => (await consent()).enabled) === false, 'CAS de consentement refuse l’ancienne tentative');
  check(pageErrors.length === 0, 'Aucune exception React/runtime : ' + pageErrors.join(';'));
  console.log(`PASS ${checks} vérifications Chromium/ServiceWorker (fixtures locales uniquement).`);
  console.log(`Captures : ${evidence}`);
  console.log(`Réseau externe bloqué : ${forbiddenNetwork} requêtes de ressources, aucun Push ou abonnement externe.`);
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
}
