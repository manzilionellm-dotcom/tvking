// Vérification de bout en bout contre un VRAI moteur SQL (sql.js = SQLite, comme D1),
// en passant par le vrai routeur (login → routes admin → /api/status → interrupteur coupé).
// Hors dépôt (aucune dépendance ajoutée) :
//   mkdir -p /tmp/sqljs && cd /tmp/sqljs && npm init -y && npm i sql.js
//   cp <dépôt>/android-app/cloudflare/tools/client_powers.e2e.sqljs.mjs /tmp/sqljs/e2e.mjs
//   CF_DIR=<dépôt>/android-app/cloudflare/ node e2e.mjs
// ADMIN_SECRET ci-dessous est une valeur FACTICE de test. Aucune URL de flux.
import initSqlJs from 'sql.js';
import { readFileSync } from 'node:fs';
const CF = process.env.CF_DIR;
if (!CF) throw new Error('CF_DIR requis (dossier android-app/cloudflare/ avec / final)');
const SQL = await initSqlJs();
const sdb = new SQL.Database();
sdb.run(readFileSync(CF + 'schema.sql', 'utf8'));
for (const f of ['004_device_block.sql', '010_client_powers.sql']) {
  try { sdb.run(readFileSync(CF + 'migrations/' + f, 'utf8')); } catch (e) { console.log('mig', f, e.message); }
}
function D1() {
  return { prepare(sql) {
    let args = [];
    const st = {
      bind(...a) { args = a; return st; },
      async first() { const s = sdb.prepare(sql); s.bind(args); const r = s.step() ? s.getAsObject() : null; s.free(); return r; },
      async all() { const s = sdb.prepare(sql); s.bind(args); const out = []; while (s.step()) out.push(s.getAsObject()); s.free(); return { results: out }; },
      async run() { const s = sdb.prepare(sql); s.bind(args); s.step(); s.free(); return { meta: { changes: sdb.getRowsModified() } }; },
    };
    return st;
  }, batch: async (l) => { for (const s of l) await s.run(); return []; } };
}
const worker = (await import(CF + 'worker.js')).default;
const ctx = { waitUntil() {}, passThroughOnException() {} };
const env = { DB: D1(), ADMIN_SECRET: 'test-secret-e2e-xyz', CLIENT_POWERS: '1' };
const call = (p, o = {}) => worker.fetch(new Request('https://app.x' + p, o), env, ctx);
let r = await call('/api/v1/auth/login', { method: 'POST', body: JSON.stringify({ email: 'admin', password: 'test-secret-e2e-xyz' }) });
const login = await r.json(); console.log('login', r.status);
const tok = login.token;
const H = { Authorization: 'Bearer ' + tok, 'content-type': 'application/json' };
const MAC = 'MK:AA:BB:CC:DD:EE';
// appareil via /api/status (crée le device)
r = await call('/api/status/' + MAC); let st = await r.json(); console.log('status0', r.status, Object.keys(st).join(','));
const dev = await sdb.exec(`select id from devices where mac='${MAC}'`)[0].values[0][0];
const api = async (m, p, b, h = H) => { const x = await call('/api/v1/devices/' + dev + p, { method: m, headers: h, body: b ? JSON.stringify(b) : undefined }); return [x.status, await x.json()]; };
console.log('powers', JSON.stringify(await api('GET', '/powers')));
console.log('pay', JSON.stringify(await api('PUT', '/payment-request', { message: 'Merci de payer', amount: '20', currency: 'EUR', link: 'https://exemple.test/pay' })));
console.log('msg', JSON.stringify(await api('POST', '/message', { title: 'Info', body: 'Bonjour', expires_in_hours: 1 })));
console.log('block', JSON.stringify(await api('POST', '/block', { status: 'frozen', reason: 'impayé' })));
console.log('extend(trial)', JSON.stringify(await api('POST', '/extend', { days: 3 })));
console.log('suspend', JSON.stringify(await api('POST', '/suspend', { suspend: true })));
console.log('note', JSON.stringify(await api('POST', '/notes', { body: 'test' })));
console.log('refresh', JSON.stringify(await api('POST', '/refresh', {})));
r = await call('/api/status/' + MAC); st = await r.json(); console.log('status1', JSON.stringify({ frozen: st.frozen, banned: st.banned, pay: st.payment_request, msg: st.client_message, rev: st.refresh_rev }));
console.log('actions', JSON.stringify((await api('GET', '/actions'))[1].items.map(i => i.action)));
console.log('unauth', (await api('GET', '/powers', undefined, {}))[0]);
// interrupteur coupé
env.CLIENT_POWERS = '';
r = await call('/api/status/' + MAC); st = await r.json(); console.log('status flag off keys', Object.keys(st).join(','));
console.log('write off', JSON.stringify(await api('POST', '/refresh', {})));
console.log('powers off', JSON.stringify(await api('GET', '/powers')));
