// Vrai panel compilé + HTTP/WS + Worker/DO. Le client de test accuse seulement
// après relecture du statut ; les deux apps Flutter sont vérifiées séparément.
const { chromium } = require(process.env.PANEL_PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
(async () => {
  const { startRealtimeFixture } = await import('../../cloudflare/tests/realtime_fixture.mjs');
  const fixture = await startRealtimeFixture(8787);
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PANEL_BROWSER_EXECUTABLE || undefined, args: ['--no-sandbox'] });
  const mac = 'MK:22:33:44:55:66', secret = 'fixture-browser-device-proof-32-characters';
  let device;
  try {
    const call = async (path, method = 'GET', body, proof = false) => {
      const response = await fixture.mf.dispatchFetch(`${fixture.origin}${path}`, { method,
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${fixture.token}`,
          ...(proof ? { 'X-Device-Secret': secret } : {}) },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
      const value = await response.json();
      assert.ok(response.ok, `${path}: ${response.status} ${JSON.stringify(value)}`);
      return value;
    };
    await call('/__fixture/register', 'POST', { mac, androidId: 'browser-fixture' });
    await call('/api/device-proof', 'POST', { mac, androidId: 'browser-fixture', secret });
    let applied = false;
    let appError;
    const onDeviceMessage = event => {
      void (async () => {
        const order = JSON.parse(event.data);
        if (order.type !== 'suspend') return;
        const status = await call(`/api/status/${mac}`, 'GET', undefined, true);
        assert.equal(status.frozen, true);
        applied = true;
        await call(`/api/box/ack/${mac}`, 'POST', { orders: [{
          order_id: order.order_id, state: 'applied', result: 'refreshed', applied_at: Date.now(),
        }] }, true);
      })().catch(error => { appError = error; });
    };
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [], sockets = [];
    const deferred = () => {
      let resolve;
      const promise = new Promise(done => { resolve = done; });
      return { promise, resolve };
    };
    const within = async (promise, label) => {
      let timer;
      try {
        return await Promise.race([promise, new Promise((_, reject) => {
          timer = setTimeout(() => reject(new Error(`Attente dépassée : ${label}`)), 10000);
        })]);
      } finally { clearTimeout(timer); }
    };
    const snapshot = deferred(), releaseSnapshot = deferred(), releaseTicket = deferred(), connected = deferred();
    let snapshotReads = 0;
    page.on('pageerror', error => errors.push(error.message));
    page.on('websocket', ws => {
      sockets.push(ws.url());
      ws.on('framereceived', () => connected.resolve());
    });
    // Une vraie lecture hors ligne part avant la connexion de l'appareil.
    // Sa réponse arrive après l'ouverture du socket panel : elle doit être
    // réconciliée, même si la présence a été publiée pendant cet intervalle.
    await page.route('**/api/v1/rt/ticket', async route => {
      await releaseTicket.promise;
      await route.continue();
    });
    await page.route('**/api/v1/boxes/live**', async route => {
      snapshotReads++;
      if (snapshotReads !== 1) { await route.continue(); return; }
      const response = await route.fetch();
      snapshot.resolve();
      await releaseSnapshot.promise;
      await route.fulfill({ response });
    });
    await page.addInitScript(token => localStorage.setItem('auth_token', token), fixture.token);
    await page.goto('http://127.0.0.1:4173/devices');
    await within(snapshot.promise, 'lecture initiale');
    device = (await fixture.mf.dispatchFetch(`${fixture.origin}/api/box/ws?mac=${mac}`, {
      headers: { Upgrade: 'websocket', 'X-Device-Secret': secret },
    })).webSocket;
    assert.ok(device);
    device.accept();
    device.addEventListener('message', onDeviceMessage);
    releaseTicket.resolve();
    await within(connected.promise, 'connexion panel');
    releaseSnapshot.resolve();
    const row = page.getByRole('row').filter({ hasText: mac });
    await row.getByText(/en ligne/).waitFor();
    assert.ok(snapshotReads >= 2, 'présence relue après une connexion pendant la lecture initiale');
    // Toute actualisation de présence ultérieure doit venir du WebSocket.
    await page.route('**/api/v1/boxes/live**', route => route.abort());
    const click = Date.now();
    await row.getByRole('button', { name: 'Geler', exact: true }).click();
    await row.getByText(/appliqué à .*suspension/).waitFor();
    const appliedMs = Date.now() - click;
    assert.ifError(appError);
    assert.equal(applied, true);
    assert.ok(appliedMs < 2000, `clic → accusé visible ${appliedMs} ms`);
    const disconnect = Date.now();
    device.close(1000, 'test');
    await row.getByText(/hors ligne/).waitFor();
    const offlineMs = Date.now() - disconnect;
    assert.ok(offlineMs < 2000, `déconnexion → hors ligne ${offlineMs} ms`);
    assert.ok(sockets.some(url => url.includes('/api/v1/rt/ws?ticket=')));
    assert.ok(sockets.every(url => !url.includes(fixture.token) && !url.includes(secret)));
    assert.deepEqual(errors, []);
    if (process.env.PANEL_CAPTURE_DIR) await page.screenshot({ path: `${process.env.PANEL_CAPTURE_DIR}/panel-realtime.png`, fullPage: true });
    console.log(JSON.stringify({ passed: true, initialSnapshotReconciled: true, appliedMs, offlineMs, errors }));
  } finally {
    try { device?.close(); } catch { /* Déjà fermée par la recette hors ligne. */ }
    await browser.close();
    await fixture.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
