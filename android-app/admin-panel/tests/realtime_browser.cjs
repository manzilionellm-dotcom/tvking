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
    device = (await fixture.mf.dispatchFetch(`${fixture.origin}/api/box/ws?mac=${mac}`, {
      headers: { Upgrade: 'websocket', 'X-Device-Secret': secret },
    })).webSocket;
    assert.ok(device);
    device.accept();
    let applied = false;
    let appError;
    device.addEventListener('message', event => {
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
    });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [], sockets = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('websocket', ws => sockets.push(ws.url()));
    await page.addInitScript(token => localStorage.setItem('auth_token', token), fixture.token);
    await page.goto('http://127.0.0.1:4173/devices');
    const row = page.getByRole('row').filter({ hasText: mac });
    await row.getByText(/en ligne/).waitFor();
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
    console.log(JSON.stringify({ passed: true, appliedMs, offlineMs, errors }));
  } finally {
    try { device?.close(); } catch { /* Déjà fermée par la recette hors ligne. */ }
    await browser.close();
    await fixture.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
