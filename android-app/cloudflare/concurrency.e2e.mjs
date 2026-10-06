// =========================================================
//  concurrency.e2e.mjs — Vraie concurrence, vrai runtime
// =========================================================
//  Lance `wrangler dev --local` (workerd + D1 local en SQLite + Durable
//  Object), envoie des requêtes HTTP SIMULTANÉES (Promise.all sur des
//  connexions distinctes : le Worker les entrelace à chaque accès D1,
//  comme en production), puis relit l'état final directement dans la base
//  locale. Rien n'est simulé côté serveur.
//
//  Usage :
//    WRANGLER=/chemin/vers/wrangler TRIAL_ENFORCEMENT=1 \
//      node --experimental-sqlite cloudflare/concurrency.e2e.mjs
//  (TRIAL_ENFORCEMENT=0 pour l'autre mode ; les invariants sont les mêmes.)
//  Sans le proxy de `wrangler dev` (recommandé, voir miniflare_server.mjs) :
//    wrangler deploy --dry-run --outdir /tmp/paquet
//    WORKER_BUNDLE=/tmp/paquet/worker.js MINIFLARE=…/miniflare/dist/src/index.js \
//      node --experimental-sqlite cloudflare/concurrency.e2e.mjs
//
//  Invariants vérifiés (06/10/2026) :
//    A. même Idempotency-Key ×20 simultanées → UNE exécution : 1 licence,
//       1 débit, 1 extension ; les autres : rejeu identique ou 409 « en cours ».
//    B. même renouvellement ×20 simultanés (clés distinctes, même MAC) →
//       extensions = débits = réponses 2xx ; date finale exacte ; aucune
//       5xx ; solde = initial − succès.
//    C. même client (MAC neuve) ×20 premières activations simultanées →
//       1 appareil, 1 client (aucun orphelin), 1 licence ; date = succès × durée.
//    D. mêmes crédits : 5 crédits, 20 activations simultanées de MAC
//       différentes → exactement 5 réussites, 15 refus 402, solde 0,
//       jamais négatif, 5 lignes de journal.
//    E. même liste ×10 envois simultanés → révisions 1..10 sans trou ni
//       doublon, une ligne device_sources, chaque envoi a son ordre.
// =========================================================
import { spawn, execFileSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, readdirSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const WRANGLER = process.env.WRANGLER || 'wrangler';
const ENFORCE = process.env.TRIAL_ENFORCEMENT ?? '1';
const PORT = Number(process.env.PORT || 8799);
const BASE = `http://127.0.0.1:${PORT}`;
const N = 20;
const DAY = 24 * 3600 * 1000;
const YEAR_DAYS = 365;

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass += 1; console.log('PASS', m); }
  else { fail += 1; console.log('FAIL', m); }
};

const persist = mkdtempSync(join(tmpdir(), 'zuno-e2e-'));
const ADMIN_SECRET = crypto.randomUUID();
const SECRETS_KEY = crypto.randomUUID();

function wr(args) {
  return execFileSync(WRANGLER, args, { cwd: here, stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, CI: '1' } }).toString();
}

function findSqlite(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      const found = findSqlite(p);
      if (found) return found;
    } else if (name.endsWith('.sqlite') && name !== 'metadata.sqlite' && p.includes('D1DatabaseObject')) {
      return p;
    }
  }
  return null;
}

async function waitReady(proc) {
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (proc.exitCode !== null) throw new Error(`wrangler dev s'est arrêté (code ${proc.exitCode})`);
    try {
      const r = await fetch(`${BASE}/api/status/MK:00:00:00:00:01`);
      if (r.status > 0) return;
    } catch (_) { /* pas encore prêt */ }
    await new Promise((res) => setTimeout(res, 500));
  }
  throw new Error('wrangler dev : délai dépassé');
}

async function api(method, path, { token, body, headers: extra } = {}) {
  const headers = { 'content-type': 'application/json', ...(extra || {}) };
  if (token) headers.authorization = `Bearer ${token}`;
  const r = await fetch(`${BASE}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { json = null; }
  return { status: r.status, json, text, headers: r.headers };
}

async function main() {
  // Deux façons de lancer le MÊME Worker sur workerd :
  //  • défaut : `wrangler dev --local` (un « ProxyWorker » de développement
  //    est placé devant le Worker) ;
  //  • MINIFLARE=chemin/vers/miniflare/dist/src/index.js : Miniflare seul,
  //    sans ce proxy (test_support/miniflare_server.mjs). Sert à séparer un
  //    défaut du Worker d'un défaut de l'outil de développement.
  let proc;
  if (process.env.MINIFLARE) {
    proc = spawn(process.execPath, [join(here, 'test_support', 'miniflare_server.mjs'),
      String(PORT), persist, ADMIN_SECRET, SECRETS_KEY, ENFORCE],
    { cwd: here, env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
  } else {
    // Base locale : schéma de production + colonnes ajoutées par les migrations.
    wr(['d1', 'execute', 'tvking_licensing', '--local', '--persist-to', persist, '--file', join(here, 'schema.sql')]);
    for (const sql of [
      'ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT',
    ]) {
      try { wr(['d1', 'execute', 'tvking_licensing', '--local', '--persist-to', persist, '--command', sql]); } catch (_) { /* déjà là */ }
    }
    proc = spawn(WRANGLER, [
      'dev', '--local', '--port', String(PORT), '--persist-to', persist,
      '--var', `ADMIN_SECRET:${ADMIN_SECRET}`, '--var', `SECRETS_KEY:${SECRETS_KEY}`,
      '--var', `TRIAL_ENFORCEMENT:${ENFORCE}`, '--log-level', process.env.WRANGLER_LOG_LEVEL || 'warn',
    ], { cwd: here, env: { ...process.env, CI: '1' }, stdio: ['ignore', 'pipe', 'pipe'] });
  }
  let logs = '';
  proc.stdout.on('data', (d) => { logs += d; });
  proc.stderr.on('data', (d) => { logs += d; });
  try {
    await waitReady(proc);
    const sqlitePath = findSqlite(persist);
    ok(!!sqlitePath, `base D1 locale trouvée (${sqlitePath ? 'ok' : 'absente'})`);
    const db = () => new DatabaseSync(sqlitePath, { readOnly: true });
    const q1 = (sql, ...a) => { const d = db(); try { return d.prepare(sql).get(...a); } finally { d.close(); } };

    const login = await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: ADMIN_SECRET } });
    const admin = login.json && login.json.token;
    ok(!!admin, `connexion admin sur workerd (mode TRIAL_ENFORCEMENT=${ENFORCE})`);

    async function reseller(credits) {
      const email = `r-${crypto.randomUUID()}@example.test`;
      const password = crypto.randomUUID();
      const c = await api('POST', '/api/v1/resellers', { token: admin, body: { email, password, name: 'R', credit_balance: credits } });
      await api('PATCH', `/api/v1/resellers/${c.json.id}`, { token: admin, body: { permissions: ['activate', 'devices', 'sources'] } });
      const l = await api('POST', '/api/v1/auth/reseller/login', { body: { email, password } });
      return { id: c.json.id, token: l.json.token };
    }
    const debits = (rid) => q1("SELECT COUNT(*) AS n FROM credit_ledger WHERE reseller_id = ? AND reason IN ('activation','renew')", rid).n;
    const balance = (rid) => q1('SELECT credit_balance AS b FROM resellers WHERE id = ?', rid).b;
    const tally = (rs) => rs.reduce((m, r) => { m[r.status] = (m[r.status] || 0) + 1; return m; }, {});

    const levels = (process.env.LEVELS || '2,10,50,100').split(',').map(Number);
    let macSeq = 0;
    const nextMac = () => {
      macSeq += 1;
      return `MK:C${(macSeq >> 16) & 15}:${((macSeq >> 8) & 255).toString(16).padStart(2, '0').toUpperCase()}:${(macSeq & 255).toString(16).padStart(2, '0').toUpperCase()}:00:01`;
    };
    for (const n of levels) {
      // ---------- A. même clé ×n ----------
      {
        const r = await reseller(1000);
        const MAC = nextMac();
        const key = crypto.randomUUID();
        const rs = await Promise.all(Array.from({ length: n }, () => api('POST', '/api/v1/activate', {
          token: r.token, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': key },
        })));
        const t = tally(rs);
        const executed = rs.filter((x) => x.status === 201 && !x.headers.get('idempotent-replayed'));
        const lic = q1('SELECT COUNT(*) AS n FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?', MAC).n;
        ok(executed.length === 1 && rs.every((x) => x.status === 201 || x.status === 409) && debits(r.id) === 1 && lic === 1
          && rs.filter((x) => x.status === 201).every((x) => x.json.license_id === executed[0].json.license_id && x.json.expires_at === executed[0].json.expires_at),
          `A n=${n}. même clé : 1 exécution, 1 débit, 1 licence, tous les 201 identiques (${JSON.stringify(t)})`);
      }
      // ---------- B. même renouvellement ×n ----------
      {
        const r = await reseller(1000);
        const MAC = nextMac();
        const first = await api('POST', '/api/v1/activate', { token: r.token, body: { mac: MAC, plan: 'yearly' } });
        const base = first.json.expires_at;
        const rs = await Promise.all(Array.from({ length: n }, () => api('POST', '/api/v1/activate', {
          token: r.token, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': crypto.randomUUID() },
        })));
        const okCount = rs.filter((x) => x.status === 201).length;
        const lic = q1('SELECT l.expires_at AS e FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?', MAC);
        const ledgerBal = q1("SELECT MIN(balance_after) AS lo, COUNT(DISTINCT balance_after) AS d, COUNT(*) AS c FROM credit_ledger WHERE reseller_id = ? AND reason IN ('activation','renew')", r.id);
        ok(!rs.some((x) => x.status >= 500) && lic.e === base + okCount * YEAR_DAYS * DAY
          && debits(r.id) === okCount + 1 && balance(r.id) === 1000 - (okCount + 1)
          && ledgerBal.d === ledgerBal.c && ledgerBal.lo === balance(r.id),
          `B n=${n}. renouvellements : ${okCount}/${n} réussis = ${okCount} débits = ${okCount} × 365 j ; journal : ${ledgerBal.c} soldes distincts, le plus bas = solde final (${JSON.stringify(tally(rs))})`);
      }
      // ---------- C. même client neuf ×n ----------
      {
        const r = await reseller(1000);
        const MAC = nextMac();
        const t0 = Date.now();
        const rs = await Promise.all(Array.from({ length: n }, () => api('POST', '/api/v1/activate', {
          token: r.token, body: { mac: MAC, plan: 'yearly' }, headers: { 'Idempotency-Key': crypto.randomUUID() },
        })));
        const okCount = rs.filter((x) => x.status === 201).length;
        const dev = q1('SELECT COUNT(*) AS n FROM devices WHERE mac = ?', MAC).n;
        const orphans = q1('SELECT COUNT(*) AS n FROM customers c WHERE NOT EXISTS (SELECT 1 FROM devices d WHERE d.customer_id = c.id)').n;
        const lic = q1('SELECT COUNT(*) AS n, MAX(l.expires_at) AS e FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?', MAC);
        const days = (lic.e - t0) / DAY;
        ok(!rs.some((x) => x.status >= 500) && dev === 1 && lic.n === 1 && orphans === 0
          && Math.abs(days - okCount * YEAR_DAYS) < 1 && debits(r.id) === okCount,
          `C n=${n}. client neuf : 1 appareil, 1 licence, 0 orphelin, ${okCount} succès = ${okCount} débits = ${days.toFixed(1)} j (${JSON.stringify(tally(rs))})`);
      }
      // ---------- D. mêmes crédits ----------
      {
        const r = await reseller(5);
        const rs = await Promise.all(Array.from({ length: n }, () => api('POST', '/api/v1/activate', {
          token: r.token, body: { mac: nextMac(), plan: 'yearly' }, headers: { 'Idempotency-Key': crypto.randomUUID() },
        })));
        const t = tally(rs);
        const won = t[201] || 0;
        ok(won === Math.min(5, n) && (t[402] || 0) === n - won && !rs.some((x) => x.status >= 500)
          && balance(r.id) === 5 - won && debits(r.id) === won,
          `D n=${n}. 5 crédits : ${won} réussies, ${n - won} refus 402, solde ${balance(r.id)} jamais négatif, ${debits(r.id)} lignes de journal`);
      }
      // ---------- E. listes : panel ×n + client ×3, mêmes MAC ----------
      {
        const MAC = nextMac();
        await api('POST', '/api/v1/activate', { token: admin, body: { mac: MAC, plan: 'yearly' } });
        const selfN = Math.min(n, 3);
        const rs = await Promise.all([
          ...Array.from({ length: n }, (_, i) => api('PUT', `/api/v1/sources/${MAC}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: `http://p${i}.example.test/l.m3u` }] } })),
          ...Array.from({ length: selfN }, (_, i) => api('POST', `/api/self-source/${MAC}`, { body: { type: 'm3u', m3u_url: `http://perso${i}.example.test/l.m3u`, label: `P${i}` } })),
        ]);
        const panelOk = rs.slice(0, n).filter((x) => x.status === 200).length;
        const selfOk = rs.slice(n).filter((x) => x.status === 200).length;
        const conflicts = rs.filter((x) => x.status === 409).length;
        const row = q1('SELECT version, sources_json FROM device_sources WHERE mac = ?', MAC);
        const items = JSON.parse(row.sources_json);
        const d = db();
        let revs = [];
        let lastPanel = null;
        try {
          revs = d.prepare('SELECT rev FROM source_revisions WHERE mac = ? ORDER BY rev').all(MAC).map((x) => x.rev);
          lastPanel = d.prepare('SELECT panel_json FROM source_revisions WHERE mac = ? ORDER BY rev DESC LIMIT 1').get(MAC);
        } finally { d.close(); }
        const contiguous = revs.length > 0 && revs.every((v, i) => v === i + 1);
        const panelNow = items.filter((s) => s.origin !== 'self').map((s) => s.m3u_url);
        const panelRev = JSON.parse(lastPanel.panel_json).map((s) => s.m3u_url);
        const orders = q1("SELECT COUNT(DISTINCT order_id) AS n FROM box_orders WHERE mac = ? AND kind = 'source'", MAC).n;
        const respRevs = rs.slice(0, n).filter((x) => x.status === 200).map((x) => x.json.rev);
        ok(!rs.some((x) => x.status >= 500) && rs.every((x) => [200, 409].includes(x.status))
          && items.filter((s) => s.origin === 'self').length === selfOk
          && row.version === panelOk + selfOk && revs.length === panelOk + selfOk && contiguous
          && new Set(respRevs).size === respRevs.length
          && JSON.stringify(panelNow) === JSON.stringify(panelRev) && orders === panelOk,
          `E n=${n}. listes : ${panelOk} panel + ${selfOk} client réussis, ${conflicts} conflits 409 explicites ; `
          + `aucune liste client perdue, version ${row.version}, révisions 1..${revs.length} continues, `
          + `${orders} ordres pour ${panelOk} envois, dernière révision = liste servie ; statuts ${JSON.stringify(tally(rs))}`);
      }
    }

    // ---------- Accusés réels sur workerd (un ordre, chemin complet) ----------
    {
      const MAC = nextMac();
      const act = await api('POST', '/api/v1/activate', { token: admin, body: { mac: MAC, plan: 'yearly' }, headers: { 'X-Request-Id': 'trace-workerd-0001' } });
      const w = await api('GET', `/api/box/wait/${MAC}?after=0&timeout=500`);
      const fr = (w.json && w.json.box || []).find((b) => b.order_id === act.json.order_id);
      const a1 = await api('POST', `/api/box/ack/${MAC}`, { body: { orders: [{ order_id: act.json.order_id, state: 'received', received_at: Date.now() }] } });
      const a2 = await api('POST', `/api/box/ack/${MAC}`, { body: { orders: [{ order_id: act.json.order_id, state: 'applied', applied_at: Date.now(), result: 'status:active' }] } });
      const st = q1('SELECT state, trace_id, t3_published, received_srv, applied_srv FROM box_orders WHERE order_id = ?', act.json.order_id);
      ok(fr && fr.trace_id === 'trace-workerd-0001' && a1.status === 200 && a2.status === 200 && st.state === 'applied'
        && st.trace_id === 'trace-workerd-0001' && st.t3_published && st.received_srv && st.applied_srv,
        'workerd : trame avec order_id + trace_id via le Durable Object réel, accusés RECEIVED → APPLIED persistés');
    }
  } finally {
    proc.kill('SIGTERM');
  }
  if (fail) console.log(logs.split('\n').slice(-30).join('\n'));
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => { console.error('TEST CRASH', e && e.stack ? e.stack : e); process.exit(1); });
