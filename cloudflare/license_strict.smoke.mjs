// =========================================================
//  license_strict.smoke.mjs — anti-freeloader côté Worker
// =========================================================
//  1) device-source : expiré / gelé / banni / prêté → source VIDE + blocked
//  2) heartbeat renvoie grace_hours (heures, pas jours)
//  3) GET /api/status ne CRÉE plus de device (pas d'essai au simple GET)
//  4) ensureD1Device hérite first_seen_at d'un android_id déjà vu
//
//  Lancer : node cloudflare/license_strict.smoke.mjs
// =========================================================
import worker from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

const MAC = 'MK:AA:BB:CC:DD:01';
const AID = 'android-stable-42';

const kvStub = {
  async get() { return null; },
  async put() {},
  async delete() {},
};

function makeDb(state) {
  const inserts = [];
  return {
    inserts,
    prepare(sql) {
      return {
        _sql: sql, _args: [],
        bind(...a) { this._args = a; return this; },
        async run() {
          inserts.push({ sql, args: this._args });
          return { success: true };
        },
        async first() {
          const s = this._sql;
          if (/FROM sqlite_master/.test(s)) return null;
          if (/FROM app_masters/.test(s)) return null;
          if (/FROM app_config/.test(s)) return { value: '7' };
          if (/FROM app_family_links/.test(s)) {
            return state.loan ? { owner_mac: 'MK:OWNER' } : null;
          }
          if (/SELECT id, first_seen_at, block_status FROM devices WHERE mac/.test(s)) {
            return state.device || null;
          }
          if (/SELECT id FROM devices WHERE mac/.test(s)) {
            return state.device ? { id: state.device.id } : null;
          }
          if (/FROM devices WHERE android_id/.test(s)) {
            return state.sibling || null;
          }
          if (/FROM licenses/.test(s)) {
            return state.license === undefined ? null : state.license;
          }
          if (/FROM device_sources/.test(s)) {
            return state.source || null;
          }
          if (/activeLoanForOwner|FROM app_loans|loan/.test(s)) return null;
          return null;
        },
        async all() {
          const q = this._sql;
          if (/SELECT mac FROM app_masters/.test(q)) return { results: [] };
          if (/FROM lab_sources/.test(q)) return { results: [] };
          return { results: [] };
        },
      };
    },
    async batch(stmts) {
      for (const st of stmts) {
        inserts.push({ sql: st._sql || 'batch', args: st._args || [] });
        if (/INSERT INTO devices/.test(String(st._sql || ''))) {
          const a = st._args || [];
          state.device = {
            id: a[0],
            first_seen_at: a[3],
            block_status: a.length >= 6 ? a[5] : null,
          };
        }
      }
      return { success: true };
    },
  };
}

const sourceRow = {
  type: 'xtream', label: 'Bouquet', server_url: 'http://iptv.example',
  username: 'u', password: 'p', m3u_url: null, epg_url: null,
  sources_json: null, updated_at: 1,
};

async function deviceSource(state) {
  const db = makeDb(state);
  const r = await worker.fetch(
    new Request('https://app.x/api/device-source/' + MAC),
    { DB: db, KV_7MOTION: kvStub }, ctx,
  );
  return { r, body: await r.json() };
}

// 1) Essai en cours → source livrée
{
  const now = Date.now();
  const { r, body } = await deviceSource({
    device: { id: 'dev_1', first_seen_at: now - 60_000, block_status: null },
    license: null,
    source: sourceRow,
  });
  ok(r.status === 200 && body.source && body.source.username === 'u',
    '1 essai en cours → source livrée');
  ok(!body.blocked, '1 essai en cours → pas de blocked');
}

// 2) Essai expiré → source vide + blocked=expired
{
  const now = Date.now();
  const { r, body } = await deviceSource({
    device: { id: 'dev_1', first_seen_at: now - 20 * 86400000, block_status: null },
    license: null,
    source: sourceRow,
  });
  ok(r.status === 200 && body.source === null && Array.isArray(body.sources) && body.sources.length === 0,
    '2 essai expiré → source vide');
  ok(body.blocked === 'expired', '2 blocked=expired');
}

// 3) Licence D1 expirée (status active mais expires_at passé)
{
  const { r, body } = await deviceSource({
    device: { id: 'dev_1', first_seen_at: 1, block_status: null },
    license: { lstatus: 'active', expires_at: Date.now() - 1000 },
    source: sourceRow,
  });
  ok(body.source === null && body.blocked === 'expired',
    '3 licence expires_at passé → blocked expired');
}

// 4) Gel admin
{
  const { body } = await deviceSource({
    device: { id: 'dev_1', first_seen_at: 1, block_status: 'frozen' },
    source: sourceRow,
  });
  ok(body.source === null && body.blocked === 'frozen', '4 gel → blocked frozen');
}

// 5) Ban admin
{
  const { body } = await deviceSource({
    device: { id: 'dev_1', first_seen_at: 1, block_status: 'banned' },
    source: sourceRow,
  });
  ok(body.source === null && body.blocked === 'banned', '5 ban → blocked banned');
}

// 6) GET /api/status MAC inconnue → pas d'INSERT device
{
  const db = makeDb({ device: null });
  const r = await worker.fetch(
    new Request('https://app.x/api/status/' + MAC),
    { DB: db, KV_7MOTION: kvStub }, ctx,
  );
  const body = await r.json();
  const created = db.inserts.some((i) => /INSERT INTO devices/.test(i.sql || ''));
  ok(r.status === 200, '6 status MAC inconnue répond');
  ok(!created, '6 status NE crée PAS de device (pas d\'essai au GET)');
  ok(body.exists === false || body.paid === false, '6 inconnue → pas paid');
}

// 7) heartbeat + android_id déjà vu → first_seen hérité
{
  const oldSeen = 1_700_000_000_000;
  const db = makeDb({
    device: null,
    sibling: { first_seen_at: oldSeen, block_status: 'banned' },
  });
  const r = await worker.fetch(
    new Request('https://app.x/api/heartbeat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        mac: MAC,
        androidId: AID,
        model: 'Fire TV',
        platform: 'tv',
      }),
    }),
    { DB: db, KV_7MOTION: kvStub }, ctx,
  );
  const body = await r.json();
  ok(r.status === 200 && body.grace_hours === 6, '7 heartbeat → grace_hours=6');
  const ins = db.inserts.find((i) => /INSERT INTO devices/.test(String(i.sql || '')));
  ok(!!ins, '7 nouvelle MAC → INSERT device');
  if (ins) {
    const args = ins.args || [];
    ok(args.includes(oldSeen), '7 first_seen_at hérité de l\'android_id');
    ok(args.includes('banned'), '7 block_status hérité (ban suit l\'appareil)');
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
