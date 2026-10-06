// =========================================================
//  latency_local.e2e.mjs — Mesure LOCALE (workerd + D1 local), JAMAIS
//  présentée comme une mesure de production
// =========================================================
//  WRANGLER=/chemin/wrangler node --experimental-sqlite cloudflare/latency_local.e2e.mjs
//  Lance `wrangler dev --local`, joue N activations, N renouvellements et
//  N changements de listes l'un après l'autre ; une « box » simulée lit la
//  trame (attente longue), accuse RECEIVED puis APPLIED. Les centiles sont
//  ensuite lus sur GET /api/v1/metrics/latency — le MÊME calcul que la
//  production, sur les MÊMES colonnes. Ce qui diffère de la production :
//  D1 local (pas de réseau vers D1), aucun trajet Internet, box simulée
//  (son temps de traitement ≈ 0). Les segments box sont donc non
//  représentatifs ; les segments serveur donnent un plancher.
// =========================================================
import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const WRANGLER = process.env.WRANGLER || 'wrangler';
const PORT = Number(process.env.PORT || 8810);
const BASE = `http://127.0.0.1:${PORT}`;
const N = Number(process.env.N || 200);
const persist = mkdtempSync(join(tmpdir(), 'zuno-lat-'));
const ADMIN_SECRET = crypto.randomUUID();

async function api(method, path, { token, body, headers: extra } = {}) {
  const headers = { 'content-type': 'application/json', ...(extra || {}) };
  if (token) headers.authorization = `Bearer ${token}`;
  const r = await fetch(`${BASE}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { json = null; }
  return { status: r.status, json };
}

// Chaque box simulée a sa propre IP (comme en vrai) : le seau de limite de
// débit est par IP.
function boxIp(mac) {
  const tail = mac.split(':').slice(-2).map((h) => parseInt(h, 16));
  return `198.51.${tail[0]}.${tail[1]}`;
}

async function boxAcks(mac, orderId) {
  const ip = { 'CF-Connecting-IP': boxIp(mac) };
  const w = await api('GET', `/api/box/wait/${mac}?after=0&timeout=2000`, { headers: ip });
  const seen = (w.json && w.json.box || []).some((b) => b.order_id === orderId);
  if (!seen) return false;
  await api('POST', `/api/box/ack/${mac}`, { headers: ip, body: { orders: [{ order_id: orderId, state: 'received', received_at: Date.now() }] } });
  await api('POST', `/api/box/ack/${mac}`, { headers: ip, body: { orders: [{ order_id: orderId, state: 'applied', applied_at: Date.now(), result: 'loaded' }] } });
  return true;
}

async function main() {
  // Sans le proxy de `wrangler dev` si MINIFLARE + WORKER_BUNDLE sont donnés
  // (voir test_support/miniflare_server.mjs et concurrency.e2e.mjs).
  let proc;
  if (process.env.MINIFLARE) {
    proc = spawn(process.execPath, [join(here, 'test_support', 'miniflare_server.mjs'),
      String(PORT), persist, ADMIN_SECRET, crypto.randomUUID(), '1'],
    { cwd: here, env: process.env, stdio: 'ignore' });
  } else {
    execFileSync(WRANGLER, ['d1', 'execute', 'tvking_licensing', '--local', '--persist-to', persist, '--file', join(here, 'schema.sql')], { cwd: here, stdio: 'ignore' });
    try {
      execFileSync(WRANGLER, ['d1', 'execute', 'tvking_licensing', '--local', '--persist-to', persist, '--command', 'ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT'], { cwd: here, stdio: 'ignore' });
    } catch (_) { /* déjà là */ }
    proc = spawn(WRANGLER, ['dev', '--local', '--port', String(PORT), '--persist-to', persist,
      '--var', `ADMIN_SECRET:${ADMIN_SECRET}`, '--var', `SECRETS_KEY:${crypto.randomUUID()}`, '--log-level', 'warn'],
    { cwd: here, env: { ...process.env, CI: '1' }, stdio: 'ignore' });
  }
  try {
    for (let i = 0; i < 180; i++) {
      try { const r = await fetch(`${BASE}/api/status/MK:00:00:00:00:01`); if (r.status) break; } catch (_) { /* attente */ }
      await new Promise((res) => setTimeout(res, 500));
    }
    const admin = (await api('POST', '/api/v1/auth/login', { body: { email: 'admin', password: ADMIN_SECRET } })).json.token;
    let missed = 0;
    for (let i = 0; i < N; i++) {
      const mac = `MK:A0:00:00:${(i >> 8).toString(16).padStart(2, '0').toUpperCase()}:${(i & 255).toString(16).padStart(2, '0').toUpperCase()}`;
      const h = () => ({ 'X-Client-Sent-At': String(Date.now()), 'X-Request-Id': `lat-${crypto.randomUUID()}` });
      const a = await api('POST', '/api/v1/activate', { token: admin, body: { mac, plan: 'yearly' }, headers: h() });
      if (!(await boxAcks(mac, a.json.order_id))) missed += 1;
      const r = await api('POST', '/api/v1/activate', { token: admin, body: { mac, plan: 'yearly' }, headers: h() });
      if (!(await boxAcks(mac, r.json.order_id))) missed += 1;
      const s = await api('PUT', `/api/v1/sources/${mac}`, { token: admin, body: { sources: [{ type: 'm3u', m3u_url: `http://l${i}.example.test/x.m3u` }] }, headers: h() });
      if (!(await boxAcks(mac, s.json.order_id))) missed += 1;
    }
    const m = await api('GET', '/api/v1/metrics/latency?hours=1', { token: admin });
    console.log(`MESURE LOCALE workerd + D1 local (PAS la production) — ${process.env.MINIFLARE ? 'Miniflare direct' : 'wrangler dev'} — N=${N} par opération, ordres non vus par la box simulée : ${missed}`);
    for (const [op, o] of Object.entries(m.json.ops)) {
      console.log(`\n${op} (${o.orders} ordres, états ${JSON.stringify(o.states)})`);
      for (const [seg, v] of Object.entries(o.segments)) {
        console.log(`  ${seg.padEnd(20)} ${v.n ? `p50 ${v.p50} ms  p95 ${v.p95} ms  p99 ${v.p99} ms  n=${v.n}` : 'non mesuré'}`);
      }
    }
  } finally {
    proc.kill('SIGTERM');
  }
}

main().catch((e) => { console.error('ÉCHEC', e && e.stack ? e.stack : e); process.exit(1); });
