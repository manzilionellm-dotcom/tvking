// Tests des « Pouvoirs clients » (Worker). Aucun secret, aucune URL de flux.
// Exécuter : node --test android-app/cloudflare/client_powers.test.mjs
//
// D1 est simulée en mémoire (fake_d1 ci-dessous) : elle ne reconnaît que
// les requêtes de client_powers.js. Pour valider le SQL contre un vrai
// moteur, voir docs/CONTRAT-API-POUVOIRS-CLIENTS.md (section « Vérification »).
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  clientPowersOn, cleanText, cleanPayLink, nextRev, scrubAudit,
  readPublicNotices, handleClientPowers, resetClientPowersCache,
} from './client_powers.js';

const MAC = 'MK:AA:BB:CC:DD:EE';
const NOW = () => Date.now();

// ---------- D1 simulée ----------
function makeEnv(extra = {}) {
  const db = {
    devices: [{ id: 'dev_1', mac: MAC, block_status: null }],
    licenses: [],
    notices: new Map(),   // `${mac}|${kind}` -> ligne
    notes: [],
    audit: [],
  };
  const norm = (s) => s.replace(/\s+/g, ' ').trim();
  function exec(sqlRaw, args, mode) {
    const sql = norm(sqlRaw);
    const meta = { changes: 0 };
    const rows = (r) => ({ results: r });
    if (/^CREATE TABLE/.test(sql)) return mode === 'all' ? rows([]) : null;
    if (/^SELECT id, mac, block_status FROM devices WHERE id/.test(sql)) {
      return db.devices.find((d) => d.id === args[0]) || null;
    }
    if (/^SELECT \* FROM client_notices WHERE mac = \? AND kind/.test(sql)) {
      return db.notices.get(`${args[0]}|${args[1]}`) || null;
    }
    if (/^SELECT \* FROM client_notices WHERE mac = \?$/.test(sql)
      || /FROM client_notices WHERE mac = \?$/.test(sql)) {
      return rows([...db.notices.values()].filter((n) => n.mac === args[0]));
    }
    if (/^INSERT OR REPLACE INTO client_notices/.test(sql)) {
      const [mac, kind, active, title, body, amount, currency, link, due_at,
        expires_at, rev, actor_id, created_at, updated_at] = args;
      db.notices.set(`${mac}|${kind}`, { mac, kind, active, title, body, amount,
        currency, link, due_at, expires_at, rev, actor_id, created_at, updated_at });
      return { meta: { changes: 1 } };
    }
    if (/^UPDATE client_notices SET active = 0/.test(sql)) {
      const n = db.notices.get(`${args[1]}|${args[2]}`);
      if (n) { n.active = 0; n.updated_at = args[0]; meta.changes = 1; }
      return { meta };
    }
    if (/^UPDATE devices SET block_status/.test(sql)) {
      const d = db.devices.find((x) => x.id === args[1]);
      if (d) { d.block_status = args[0]; meta.changes = 1; }
      return { meta };
    }
    if (/FROM licenses WHERE device_id = \? ORDER BY/.test(sql)) {
      const l = db.licenses.filter((x) => x.device_id === args[0])
        .sort((a, b) => (b.expires_at ?? Infinity) - (a.expires_at ?? Infinity));
      return l[0] || null;
    }
    if (/^UPDATE licenses SET expires_at/.test(sql)) {
      const l = db.licenses.find((x) => x.id === args[2]);
      if (l) { l.expires_at = args[0]; meta.changes = 1; }
      return { meta };
    }
    if (/^SELECT COUNT\(\*\) AS n FROM licenses/.test(sql)) {
      return { n: db.licenses.filter((x) => x.device_id === args[0]).length };
    }
    if (/^UPDATE licenses SET status = \? , updated_at|^UPDATE licenses SET status = \?, updated_at/.test(sql)) {
      for (const l of db.licenses) {
        if (l.device_id === args[2] && l.status === args[3]) { l.status = args[0]; meta.changes++; }
      }
      return { meta };
    }
    if (/^INSERT INTO client_notes/.test(sql)) {
      db.notes.push({ id: args[0], mac: args[1], body: args[2], actor_id: args[3], created_at: args[4] });
      return { meta: { changes: 1 } };
    }
    if (/^SELECT id, body, actor_id, created_at FROM client_notes/.test(sql)) {
      return rows(db.notes.filter((n) => n.mac === args[0]));
    }
    if (/^DELETE FROM client_notes/.test(sql)) {
      const i = db.notes.findIndex((n) => n.id === args[0] && n.mac === args[1]);
      if (i >= 0) { db.notes.splice(i, 1); meta.changes = 1; }
      return { meta };
    }
    if (/FROM audit_logs/.test(sql)) {
      return rows(db.audit.filter((a) =>
        (a.target_type === 'device' && a.target_id === args[0])
        || (a.target_type === 'device_source' && a.target_id === args[1]))
        .map((a) => ({ ...a, after_json: a.after ? JSON.stringify(a.after) : null })));
    }
    throw new Error('SQL non simulé : ' + sql.slice(0, 80));
  }
  const DB = {
    prepare(sql) {
      let args = [];
      const st = {
        bind(...a) { args = a; return st; },
        async first() { return exec(sql, args, 'first'); },
        async all() { return exec(sql, args, 'all'); },
        async run() { return exec(sql, args, 'run'); },
      };
      return st;
    },
  };
  return { env: { DB, CLIENT_POWERS: '1', ...extra }, db };
}

function makeDeps(db) {
  return {
    errResp: (error, message, status = 400) =>
      new Response(JSON.stringify({ error, message }), { status }),
    jsonResp: (body, status = 200) => new Response(JSON.stringify(body), { status }),
    logAudit: async (_env, _req, actor, action, target, before, after) => {
      db.audit.push({ actor_id: actor.id, action, target_type: target.type,
        target_id: target.id, before, after, created_at: NOW() });
    },
    genId: (p) => `${p}_${Math.random().toString(36).slice(2, 10)}`,
    trialExtend: async (req) => {
      const b = await req.json();
      db.audit.push({ action: 'trial.extend', target_type: 'device', target_id: 'dev_1',
        after: { days: b.days }, created_at: NOW() });
      return new Response(JSON.stringify({ ok: true, trial_until: 1 }), { status: 200 });
    },
  };
}

const ADMIN = { role: 'super_admin', sub: 'adm_1' };
const ACTOR = { type: 'admin', id: 'adm_1' };

async function call(ctx, method, path, body, user = ADMIN) {
  resetClientPowersCache();
  const parts = path.split('/').filter(Boolean);
  const req = new Request('https://x.invalid/api/v1/' + path, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const res = await handleClientPowers({
    request: req, env: ctx.env, parts, user, actor: ACTOR, deps: makeDeps(ctx.db),
  });
  if (!res) return { res: null };
  return { res, json: await res.json().catch(() => null) };
}

// ---------- fonctions pures ----------
test('interrupteur : coupé par défaut, allumé par 1/true/on/yes', () => {
  assert.equal(clientPowersOn({}), false);
  assert.equal(clientPowersOn({ CLIENT_POWERS: '0' }), false);
  for (const v of ['1', 'true', 'ON', 'yes']) assert.equal(clientPowersOn({ CLIENT_POWERS: v }), true);
});

test('cleanText : retire les caractères de contrôle et coupe', () => {
  assert.equal(cleanText('a\u0000b\u0007c', 10), 'abc');
  assert.equal(cleanText('x'.repeat(50), 10).length, 10);
  assert.equal(cleanText(42, 10), '');
});

test('cleanPayLink : https seulement, sans identifiants', () => {
  assert.deepEqual(cleanPayLink(''), { link: null });
  assert.ok(cleanPayLink('http://exemple.test/p').error);
  assert.ok(cleanPayLink('https://u:p@exemple.test/').error);
  assert.ok(cleanPayLink('javascript:alert(1)').error);
  assert.equal(cleanPayLink('https://exemple.test/p').link, 'https://exemple.test/p');
});

test('nextRev : strictement croissant même dans la même milliseconde', () => {
  const a = nextRev(0, 1000);
  const b = nextRev(a, 1000);
  assert.ok(b > a);
});

test('scrubAudit : retire mots de passe et URL', () => {
  const out = scrubAudit({ password: 'x', m3u_url: 'http://a', server_url: 'http://b', count: 2, nested: { token: 't', ok: 1 } });
  assert.deepEqual(out, { count: 2, nested: { ok: 1 } });
});

// ---------- accès ----------
test('revendeur refusé (403), pas d’écriture', async () => {
  const ctx = makeEnv();
  const { res } = await call(ctx, 'POST', 'devices/dev_1/refresh', {}, { role: 'reseller', sub: 'r1' });
  assert.equal(res.status, 403);
  assert.equal(ctx.db.notices.size, 0);
  assert.equal(ctx.db.audit.length, 0);
});

test('interrupteur coupé : écritures 404, lecture powers = enabled:false', async () => {
  const ctx = makeEnv({ CLIENT_POWERS: '' });
  const w = await call(ctx, 'PUT', 'devices/dev_1/payment-request', { message: 'x' });
  assert.equal(w.res.status, 404);
  assert.equal(w.json.error, 'client_powers_off');
  const r = await call(ctx, 'GET', 'devices/dev_1/powers');
  assert.equal(r.json.enabled, false);
  assert.equal(ctx.db.notices.size, 0);
});

test('routes inconnues ou autres : null (le routeur continue)', async () => {
  const ctx = makeEnv();
  assert.equal((await call(ctx, 'GET', 'devices/dev_1/overview')).res, null);
  assert.equal((await call(ctx, 'GET', 'devices/dev_1/constructor')).res, null);
  assert.equal((await call(ctx, 'PATCH', 'devices/dev_1')).res, null);
});

test('appareil inconnu : 404', async () => {
  const ctx = makeEnv();
  const { res } = await call(ctx, 'POST', 'devices/nope/refresh', {});
  assert.equal(res.status, 404);
});

// ---------- blocage ----------
test('bloquer puis débloquer : block_status, relecture forcée, journal', async () => {
  const ctx = makeEnv();
  let r = await call(ctx, 'POST', 'devices/dev_1/block', { status: 'frozen', reason: 'impayé' });
  assert.equal(r.res.status, 200);
  assert.equal(ctx.db.devices[0].block_status, 'frozen');
  assert.ok(r.json.refresh_rev > 0);
  r = await call(ctx, 'POST', 'devices/dev_1/block', { status: 'active' });
  assert.equal(ctx.db.devices[0].block_status, null);
  const acts = ctx.db.audit.filter((a) => a.action === 'client.block');
  assert.equal(acts.length, 2);
  assert.equal(acts[0].after.reason, 'impayé');
  r = await call(ctx, 'POST', 'devices/dev_1/block', { status: 'nimporte' });
  assert.equal(r.res.status, 400);
});

// ---------- demande de paiement ----------
test('demande de paiement : visible sur le statut public puis retirée', async () => {
  const ctx = makeEnv();
  let r = await call(ctx, 'PUT', 'devices/dev_1/payment-request',
    { message: 'Merci de payer', amount: '20', currency: 'EUR', link: 'https://exemple.test/pay' });
  assert.equal(r.res.status, 200);
  let pub = await readPublicNotices(ctx.env, MAC);
  assert.equal(pub.payment_request.message, 'Merci de payer');
  assert.equal(pub.payment_request.amount, '20');
  assert.equal(pub.payment_request.link, 'https://exemple.test/pay');
  const id1 = pub.payment_request.id;
  // Un nouvel envoi change l'id (la box réaffiche).
  await call(ctx, 'PUT', 'devices/dev_1/payment-request', { message: 'Rappel' });
  pub = await readPublicNotices(ctx.env, MAC);
  assert.notEqual(pub.payment_request.id, id1);
  r = await call(ctx, 'DELETE', 'devices/dev_1/payment-request');
  assert.equal(r.json.cleared, 1);
  pub = await readPublicNotices(ctx.env, MAC);
  assert.equal(pub.payment_request, null);
  assert.ok(ctx.db.audit.some((a) => a.action === 'client.payment_request.set'));
  assert.ok(ctx.db.audit.some((a) => a.action === 'client.payment_request.clear'));
});

test('demande de paiement : message par défaut, lien http refusé', async () => {
  const ctx = makeEnv();
  let r = await call(ctx, 'PUT', 'devices/dev_1/payment-request', {});
  assert.equal(r.res.status, 200);
  const pub = await readPublicNotices(ctx.env, MAC);
  assert.ok(pub.payment_request.message.length > 10);
  r = await call(ctx, 'PUT', 'devices/dev_1/payment-request', { link: 'http://exemple.test' });
  assert.equal(r.res.status, 400);
});

// ---------- message ----------
test('message au client : expiré = invisible, vide refusé', async () => {
  const ctx = makeEnv();
  let r = await call(ctx, 'POST', 'devices/dev_1/message', { body: '   ' });
  assert.equal(r.res.status, 400);
  r = await call(ctx, 'POST', 'devices/dev_1/message', { title: 'Info', body: 'Bonjour', expires_in_hours: 2 });
  assert.equal(r.res.status, 200);
  let pub = await readPublicNotices(ctx.env, MAC);
  assert.equal(pub.client_message.body, 'Bonjour');
  pub = await readPublicNotices(ctx.env, MAC, NOW() + 3 * 3600 * 1000);
  assert.equal(pub.client_message, null);
  r = await call(ctx, 'POST', 'devices/dev_1/message', { body: 'x', expires_in_hours: -1 });
  assert.equal(r.res.status, 400);
});

test('statut public : interrupteur coupé ou MAC invalide = {} (inchangé)', async () => {
  const ctx = makeEnv();
  await call(ctx, 'POST', 'devices/dev_1/message', { body: 'Bonjour' });
  assert.deepEqual(await readPublicNotices({ ...ctx.env, CLIENT_POWERS: '' }, MAC), {});
  assert.deepEqual(await readPublicNotices(ctx.env, 'pas-une-mac'), {});
  assert.deepEqual(await readPublicNotices({ DB: null, CLIENT_POWERS: '1' }, MAC), {});
});

test('statut public : une panne D1 ne casse rien', async () => {
  const env = { CLIENT_POWERS: '1', DB: { prepare() { throw new Error('boom'); } } };
  resetClientPowersCache();
  assert.deepEqual(await readPublicNotices(env, MAC), {});
});

// ---------- prolonger / suspendre ----------
test('prolonger : licence datée +N jours, à vie refusé, jours invalides refusés', async () => {
  const ctx = makeEnv();
  const end = NOW() + 5 * 86400000;
  ctx.db.licenses.push({ id: 'lic_1', device_id: 'dev_1', status: 'active', plan: '1m', expires_at: end });
  let r = await call(ctx, 'POST', 'devices/dev_1/extend', { days: 10 });
  assert.equal(r.res.status, 200);
  assert.equal(ctx.db.licenses[0].expires_at, end + 10 * 86400000);
  r = await call(ctx, 'POST', 'devices/dev_1/extend', { days: 0 });
  assert.equal(r.res.status, 400);
  r = await call(ctx, 'POST', 'devices/dev_1/extend', { days: 9999 });
  assert.equal(r.res.status, 400);
  ctx.db.licenses[0].expires_at = null;
  r = await call(ctx, 'POST', 'devices/dev_1/extend', { days: 3 });
  assert.equal(r.res.status, 409);
});

test('prolonger sans licence : délègue à l’ajout de jours d’essai', async () => {
  const ctx = makeEnv();
  const r = await call(ctx, 'POST', 'devices/dev_1/extend', { days: 7 });
  assert.equal(r.res.status, 200);
  assert.ok(ctx.db.audit.some((a) => a.action === 'trial.extend'));
});

test('suspendre / reprendre : statut de licence, date conservée', async () => {
  const ctx = makeEnv();
  const end = NOW() + 86400000;
  ctx.db.licenses.push({ id: 'lic_1', device_id: 'dev_1', status: 'active', plan: '1m', expires_at: end });
  let r = await call(ctx, 'POST', 'devices/dev_1/suspend', { suspend: true, reason: 'litige' });
  assert.equal(r.json.changed, 1);
  assert.equal(ctx.db.licenses[0].status, 'suspended');
  assert.equal(ctx.db.licenses[0].expires_at, end);
  const p = await call(ctx, 'GET', 'devices/dev_1/powers');
  assert.equal(p.json.suspended, true);
  r = await call(ctx, 'POST', 'devices/dev_1/suspend', { suspend: false });
  assert.equal(ctx.db.licenses[0].status, 'active');
  r = await call(ctx, 'POST', 'devices/dev_1/suspend', { suspend: 'oui' });
  assert.equal(r.res.status, 400);
});

test('suspendre sans licence : 409', async () => {
  const ctx = makeEnv();
  const r = await call(ctx, 'POST', 'devices/dev_1/suspend', { suspend: true });
  assert.equal(r.res.status, 409);
});

// ---------- relecture, notes, journal ----------
test('forcer la relecture : refresh_rev augmente à chaque appel', async () => {
  const ctx = makeEnv();
  const a = await call(ctx, 'POST', 'devices/dev_1/refresh', {});
  const b = await call(ctx, 'POST', 'devices/dev_1/refresh', {});
  assert.ok(b.json.refresh_rev > a.json.refresh_rev);
  const pub = await readPublicNotices(ctx.env, MAC);
  assert.equal(pub.refresh_rev, b.json.refresh_rev);
});

test('notes : ajout, liste, suppression, jamais visibles côté public', async () => {
  const ctx = makeEnv();
  let r = await call(ctx, 'POST', 'devices/dev_1/notes', { body: 'Paye en espèces' });
  assert.equal(r.res.status, 201);
  const id = r.json.id;
  r = await call(ctx, 'GET', 'devices/dev_1/notes');
  assert.equal(r.json.items.length, 1);
  const pub = await readPublicNotices(ctx.env, MAC);
  assert.ok(!JSON.stringify(pub).includes('espèces'));
  r = await call(ctx, 'DELETE', `devices/dev_1/notes/${id}`);
  assert.equal(r.json.deleted, 1);
  r = await call(ctx, 'DELETE', `devices/dev_1/notes/${id}`);
  assert.equal(r.res.status, 404);
  r = await call(ctx, 'POST', 'devices/dev_1/notes', { body: '' });
  assert.equal(r.res.status, 400);
});

test('journal : actions du client, sans secret', async () => {
  const ctx = makeEnv();
  await call(ctx, 'POST', 'devices/dev_1/block', { status: 'frozen' });
  ctx.db.audit.push({ actor_id: 'adm_1', action: 'source.set', target_type: 'device_source',
    target_id: MAC, after: { count: 1, types: ['m3u'], password: 'secret', m3u_url: 'http://x' },
    created_at: NOW() });
  const r = await call(ctx, 'GET', 'devices/dev_1/actions');
  const actions = r.json.items.map((i) => i.action);
  assert.ok(actions.includes('client.block'));
  assert.ok(actions.includes('source.set'));
  assert.ok(!JSON.stringify(r.json).includes('secret'));
  assert.ok(!JSON.stringify(r.json).includes('http://x'));
});

test('toute écriture admin laisse une ligne de journal', async () => {
  const ctx = makeEnv();
  ctx.db.licenses.push({ id: 'lic_1', device_id: 'dev_1', status: 'active', plan: '1m', expires_at: NOW() + 86400000 });
  const writes = [
    ['POST', 'devices/dev_1/block', { status: 'banned' }],
    ['PUT', 'devices/dev_1/payment-request', { message: 'x' }],
    ['DELETE', 'devices/dev_1/payment-request'],
    ['POST', 'devices/dev_1/message', { body: 'x' }],
    ['DELETE', 'devices/dev_1/message'],
    ['POST', 'devices/dev_1/extend', { days: 1 }],
    ['POST', 'devices/dev_1/suspend', { suspend: true }],
    ['POST', 'devices/dev_1/refresh', {}],
    ['POST', 'devices/dev_1/notes', { body: 'n' }],
  ];
  for (const [m, p, b] of writes) {
    const before = ctx.db.audit.length;
    const r = await call(ctx, m, p, b);
    assert.ok(r.res.status < 300, `${m} ${p} -> ${r.res.status}`);
    assert.ok(ctx.db.audit.length > before, `journal manquant pour ${m} ${p}`);
  }
});
