// =========================================================
//  activation_m3u.test.mjs — activation et lien M3U, séparés
// =========================================================
//  Couvre le Worker (api_v1 + statut public) sur une base SQLite
//  en mémoire. Aucun secret réel, aucun lien de flux : les URL sont
//  sur example.test (domaine réservé) et les mots de passe sont
//  tirés au hasard à l'exécution, jamais écrits dans les messages.
//
//  Lancer :
//    node --experimental-sqlite cloudflare/activation_m3u.test.mjs
//  (depuis android-app/)
// =========================================================

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
const here = dirname(fileURLToPath(import.meta.url));
const DAY = 24 * 60 * 60 * 1000;

let pass = 0;
let fail = 0;
function check(cond, msg) {
  if (cond) {
    pass += 1;
    console.log('PASS', msg);
  } else {
    fail += 1;
    console.log('FAIL', msg);
  }
}

function makeDb() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec(readFileSync(join(here, 'schema.sql'), 'utf8'));
  // Colonnes ajoutées par les migrations (absentes du schema.sql de base).
  for (const sql of [
    'ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT',
    'ALTER TABLE devices ADD COLUMN block_status TEXT',
  ]) {
    try { db.exec(sql); } catch (_) { /* déjà dans le schéma */ }
  }
  const DB = {
    prepare(sql) {
      const runWith = (args) => {
        const params = args.map((v) => (v === undefined ? null : v));
        return {
          async first() {
            const row = db.prepare(sql).get(...params);
            return row === undefined ? null : row;
          },
          async all() {
            return { results: db.prepare(sql).all(...params) };
          },
          async run() {
            const info = db.prepare(sql).run(...params);
            return { success: true, meta: { changes: info.changes } };
          },
        };
      };
      return {
        bind(...args) { return runWith(args); },
        first() { return runWith([]).first(); },
        all() { return runWith([]).all(); },
        run() { return runWith([]).run(); },
      };
    },
    async batch(stmts) {
      db.exec('BEGIN');
      try {
        const out = [];
        for (const s of stmts) out.push(await s.run());
        db.exec('COMMIT');
        return out;
      } catch (e) {
        try { db.exec('ROLLBACK'); } catch (_) { /* déjà annulé */ }
        throw e;
      }
    },
  };
  return { db, env: { DB, ADMIN_SECRET: crypto.randomUUID(), SECRETS_KEY: crypto.randomUUID() } };
}

async function api(env, method, path, { token, body } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await worker.fetch(new Request(`https://app.test${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  }), env, ctx);
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { json = null; }
  return { status: res.status, json };
}

function scalar(db, sql, ...args) {
  try {
    const row = db.prepare(sql).get(...args);
    if (!row) return 0;
    return Object.values(row)[0];
  } catch (_) {
    return 0;
  }
}

let seq = 0;
function mac() {
  seq += 1;
  const h = seq.toString(16).padStart(2, '0').toUpperCase();
  return `MK:A1:B2:C3:D4:${h}`;
}
function fakeM3u() {
  return `http://example.test/l/${crypto.randomUUID()}`;
}

// Même formule que l'app (subscription_backend.dart : shouldBlock).
function appBlocks(st) {
  if (!st) return false;
  return !!st.banned || !!st.frozen || (!!st.expired && !st.paid);
}

async function login(env) {
  const res = await api(env, 'POST', '/api/v1/auth/login', {
    body: { email: 'admin', password: env.ADMIN_SECRET },
  });
  return res.json && res.json.token;
}

async function makeReseller(env, admin, perms, credits) {
  const email = `r-${crypto.randomUUID()}@example.test`;
  const password = crypto.randomUUID();
  const created = await api(env, 'POST', '/api/v1/resellers', {
    token: admin,
    body: { email, password, name: 'Revendeur test', credit_balance: credits },
  });
  check(created.status === 201 && created.json && created.json.id, 'création revendeur');
  const id = created.json && created.json.id;
  const patched = await api(env, 'PATCH', `/api/v1/resellers/${id}`, {
    token: admin,
    body: { permissions: perms },
  });
  check(patched.status === 200, 'droits revendeur enregistrés');
  const logged = await api(env, 'POST', '/api/v1/auth/reseller/login', {
    body: { email, password },
  });
  check(logged.status === 200 && logged.json && logged.json.token, 'login revendeur');
  return {
    token: logged.json && logged.json.token,
    id,
    balance: logged.json && logged.json.user && logged.json.user.credit_balance,
  };
}

function licCount(db, m) {
  return scalar(
    db,
    `SELECT COUNT(*) AS n FROM licenses l
     JOIN devices d ON d.id = l.device_id WHERE d.mac = ?`,
    m,
  );
}

async function main() {
  const { db, env } = makeDb();
  const admin = await login(env);
  check(!!admin, 'login admin');
  if (!admin) {
    console.log(`\n${pass} passed, ${fail} failed`);
    process.exit(1);
  }

  // --- Durées ---
  {
    const cases = [
      ['monthly', 30 * DAY],
      ['yearly', 365 * DAY],
      ['trial_24h', DAY],
      ['trial_7d', 7 * DAY],
    ];
    for (const [plan, expectMs] of cases) {
      const m = mac();
      const before = Date.now();
      const res = await api(env, 'POST', '/api/v1/activate', {
        token: admin, body: { mac: m, plan },
      });
      const exp = res.json && res.json.expires_at;
      const delta = exp == null ? NaN : exp - before;
      check(res.status === 201 && Math.abs(delta - expectMs) < 120000,
        `durée ${plan}`);
    }
    const life = mac();
    const lifeRes = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: life, plan: 'lifetime' },
    });
    check(lifeRes.status === 201 && lifeRes.json && lifeRes.json.expires_at === null,
      'durée lifetime → expires_at null');
    const custom = mac();
    const c0 = Date.now();
    const customRes = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: custom, plan: 'custom', custom_days: 10 },
    });
    const cExp = customRes.json && customRes.json.expires_at;
    check(customRes.status === 201 && cExp && Math.abs((cExp - c0) - 10 * DAY) < 120000,
      'durée custom 10 jours');
    const huge = mac();
    const h0 = Date.now();
    const hugeRes = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: huge, plan: 'custom', custom_days: 100000 },
    });
    const hExp = hugeRes.json && hugeRes.json.expires_at;
    const hDays = hExp ? (hExp - h0) / DAY : 99999;
    check(hugeRes.status === 201 && hDays < 4000, 'custom_days énorme est plafonné');
    const badPlan = mac();
    const bad = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: badPlan, plan: 'nope' },
    });
    check(bad.status === 400 && licCount(db, badPlan) === 0, 'plan inconnu refusé sans licence');
  }

  // --- Activation et M3U indépendants ---
  {
    const m = mac();
    const url = fakeM3u();
    const act = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: m, plan: 'yearly' },
    });
    check(act.status === 201 && act.json && act.json.license_id, 'activation sans lien');
    const src = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(m)}`, { token: admin });
    check(src.status === 200 && src.json && src.json.source == null,
      'activation ne crée pas de lien M3U');
    const put = await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
      token: admin,
      body: { source: { type: 'm3u', m3u_url: url, label: 'liste' } },
    });
    check(put.status === 200, 'ajout du lien après activation');
    const expBefore = act.json.expires_at;
    const url2 = fakeM3u();
    const put2 = await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
      token: admin,
      body: { source: { type: 'm3u', m3u_url: url2, label: 'liste' } },
    });
    const lic = scalar(db, 'SELECT expires_at AS n FROM licenses WHERE id = ?', act.json.license_id);
    check(put2.status === 200 && lic === expBefore, 'modifier le lien ne change pas l expiration');
    const got = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(m)}`, { token: admin });
    const gotUrl = got.json && got.json.source && got.json.source.m3u_url;
    check(gotUrl === url2, 'le lien modifié est relu en clair par le panel');
    const row = db.prepare('SELECT m3u_url, sources_json FROM device_sources WHERE mac = ?').get(m);
    const token = url2.split('/').pop();
    const stored = `${row && row.m3u_url}|${row && row.sources_json}`;
    // Format unifié avec le coffre secret_box (enc1.). L'ancien préfixe
    // enc1: de source_crypto reste lisible au déchiffrement.
    const sealedUrl = String(row && row.m3u_url || '');
    check(!!row && (sealedUrl.startsWith('enc1.') || sealedUrl.startsWith('enc1:')) && !stored.includes(token),
      'lien M3U chiffré au repos');
    const pub = await api(env, 'GET', `/api/device-source/${m}`);
    const pubUrl = pub.json && pub.json.source && pub.json.source.m3u_url;
    check(pub.status === 200 && pubUrl === url2, 'l app reçoit le lien déchiffré');

    const bare = mac();
    const bareUrl = fakeM3u();
    const only = await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(bare)}`, {
      token: admin,
      body: { source: { type: 'm3u', m3u_url: bareUrl } },
    });
    check(only.status === 200 && licCount(db, bare) === 0,
      'ajouter un lien n active pas l appareil');
  }

  // --- source collée à l'activation : refus AVANT toute écriture ---
  {
    const r = await makeReseller(env, admin, ['activate', 'sources'], 5);
    const m = mac();
    const res = await api(env, 'POST', '/api/v1/activate', {
      token: r.token,
      body: {
        mac: m,
        plan: 'yearly',
        source: { type: 'm3u', m3u_url: fakeM3u() },
      },
    });
    const bal = scalar(db, 'SELECT credit_balance AS n FROM resellers WHERE id = ?', r.id);
    check(res.status === 400 && res.json && res.json.error === 'source_separate',
      'activation + lien dans le même appel refusé');
    check(licCount(db, m) === 0 && bal === 5, 'refus sans licence et sans débit');

    const m2 = mac();
    const bad = await api(env, 'POST', '/api/v1/activate', {
      token: admin,
      body: { mac: m2, plan: 'yearly', source: { type: 'm3u', m3u_url: '' } },
    });
    check(bad.status === 400 && licCount(db, m2) === 0,
      'lien vide collé à l activation ne crée pas de licence');
  }

  // --- URL invalide / vide ---
  {
    const m = mac();
    const samples = ['', '   ', 'pas-une-url', 'javascript:alert(1)', 'ftp://example.test/a.m3u', 'http://'];
    for (const m3u_url of samples) {
      const res = await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
        token: admin,
        body: { source: { type: 'm3u', m3u_url } },
      });
      check(res.status === 400 && scalar(db, 'SELECT COUNT(*) AS n FROM device_sources WHERE mac = ?', m) === 0,
        'lien M3U refusé');
    }
    const longUrl = `http://example.test/${'a'.repeat(3000)}`;
    const longRes = await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
      token: admin,
      body: { source: { type: 'm3u', m3u_url: longUrl } },
    });
    check(longRes.status === 400, 'lien trop long refusé');
  }

  // --- Effacement : licence intacte, listes perso conservées ---
  {
    const m = mac();
    const selfUrl = fakeM3u();
    const panelUrl = fakeM3u();
    const act = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: m, plan: 'yearly' },
    });
    const self = await api(env, 'POST', `/api/self-source/${m}`, {
      body: { type: 'm3u', m3u_url: selfUrl, label: 'perso' },
    });
    check(self.status === 200 && self.json && self.json.ok === true, 'ajout liste perso');
    await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
      token: admin,
      body: { source: { type: 'm3u', m3u_url: panelUrl, label: 'panel' } },
    });
    const del = await api(env, 'DELETE', `/api/v1/sources/${encodeURIComponent(m)}`, { token: admin });
    check(del.status === 200, 'effacement du lien panel');
    const st = await api(env, 'GET', `/api/status/${m}`);
    check(st.json && st.json.paid === true && appBlocks(st.json) === false,
      'effacer le lien ne désactive pas');
    const left = await api(env, 'GET', `/api/self-source/${m}`);
    const items = (left.json && left.json.items) || [];
    check(items.some((it) => it && it.m3u_url === selfUrl && it.origin === 'self'),
      'effacer le lien panel garde la liste perso');
    check(act.json && licCount(db, m) === 1, 'la licence est toujours là');
  }

  // --- Désactivation, expiration, renouvellement, à vie ---
  {
    const m = mac();
    const url = fakeM3u();
    const act = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: m, plan: 'yearly' },
    });
    await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
      token: admin, body: { source: { type: 'm3u', m3u_url: url } },
    });
    const id = act.json.license_id;
    const off = await api(env, 'PATCH', `/api/v1/licenses/${id}`, {
      token: admin, body: { status: 'inactive' },
    });
    check(off.status === 200, 'désactivation enregistrée');
    const st = await api(env, 'GET', `/api/status/${m}`);
    check(st.json && st.json.paid === false && st.json.expired === true && appBlocks(st.json),
      'licence inactive bloque l app');
    const pub = await api(env, 'GET', `/api/device-source/${m}`);
    check(pub.json && pub.json.source == null && pub.json.blocked === 'expired',
      'licence inactive ne livre plus le lien');
    const kept = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(m)}`, { token: admin });
    check(kept.json && kept.json.source && kept.json.source.m3u_url === url,
      'le lien reste en base après désactivation');

    const back = await api(env, 'POST', `/api/v1/licenses/${id}/renew`, {
      token: admin, body: { plan: 'yearly' },
    });
    check(back.status === 200 && back.json && back.json.expires_at > Date.now(),
      'renouvellement réactive');
    const st2 = await api(env, 'GET', `/api/status/${m}`);
    check(st2.json && st2.json.paid === true && appBlocks(st2.json) === false,
      'après renouvellement l app est ouverte');

    // Expiré : on repart de maintenant, le lien ne bouge pas.
    db.prepare('UPDATE licenses SET status = ?, expires_at = ? WHERE id = ?')
      .run('active', Date.now() - DAY, id);
    const expSt = await api(env, 'GET', `/api/status/${m}`);
    check(expSt.json && expSt.json.expired === true && appBlocks(expSt.json),
      'licence dont la date est passée bloque');
    const t0 = Date.now();
    const again = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: m, plan: 'yearly' },
    });
    const newExp = again.json && again.json.expires_at;
    check(again.status === 201 && again.json && again.json.renewed === true
      && newExp && Math.abs((newExp - t0) - 365 * DAY) < 120000,
      'réactivation d un expiré repart de maintenant');
    const still = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(m)}`, { token: admin });
    check(still.json && still.json.source && still.json.source.m3u_url === url,
      'réactivation ne modifie pas le lien');

    // Empilement si encore valide.
    const base = Date.now() + 10 * DAY;
    db.prepare('UPDATE licenses SET status = ?, expires_at = ? WHERE id = ?')
      .run('active', base, id);
    const stacked = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: m, plan: 'yearly' },
    });
    const stackedExp = stacked.json && stacked.json.expires_at;
    check(stacked.status === 201 && stackedExp && Math.abs((stackedExp - base) - 365 * DAY) < 120000,
      'réactivation avant échéance empile les jours');
  }

  {
    const m = mac();
    const first = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: m, plan: 'lifetime' },
    });
    const down = await api(env, 'POST', '/api/v1/activate', {
      token: admin, body: { mac: m, plan: 'yearly' },
    });
    const exp = scalar(db, 'SELECT expires_at AS n FROM licenses WHERE id = ?', first.json.license_id);
    check(down.status === 409 && down.json && down.json.error === 'already_lifetime' && exp == null,
      'un plan daté ne raccourcit pas un à vie');
    const renew = await api(env, 'POST', `/api/v1/licenses/${first.json.license_id}/renew`, {
      token: admin, body: { plan: 'monthly' },
    });
    const exp2 = scalar(db, 'SELECT expires_at AS n FROM licenses WHERE id = ?', first.json.license_id);
    check(renew.status === 409 && exp2 == null, 'renouvellement daté refusé sur un à vie');

    const r = await makeReseller(env, admin, ['activate'], 4);
    const m2 = mac();
    const a1 = await api(env, 'POST', '/api/v1/activate', {
      token: r.token, body: { mac: m2, plan: 'lifetime' },
    });
    const bal1 = scalar(db, 'SELECT credit_balance AS n FROM resellers WHERE id = ?', r.id);
    const a2 = await api(env, 'POST', '/api/v1/activate', {
      token: r.token, body: { mac: m2, plan: 'lifetime' },
    });
    const bal2 = scalar(db, 'SELECT credit_balance AS n FROM resellers WHERE id = ?', r.id);
    check(a1.status === 201 && bal1 === 2, 'à vie débite 2 crédits la première fois');
    check(a2.status === 200 && a2.json && a2.json.credits_charged === 0 && bal2 === 2,
      'réactiver un à vie ne redébite pas');
    const off = await api(env, 'PATCH', `/api/v1/licenses/${a1.json.license_id}`, {
      token: admin, body: { status: 'inactive' },
    });
    check(off.status === 200, 'à vie désactivé');
    const st = await api(env, 'GET', `/api/status/${m2}`);
    check(appBlocks(st.json), 'à vie désactivé bloque quand même');
    const on = await api(env, 'POST', '/api/v1/activate', {
      token: r.token, body: { mac: m2, plan: 'lifetime' },
    });
    const bal3 = scalar(db, 'SELECT credit_balance AS n FROM resellers WHERE id = ?', r.id);
    const stOn = await api(env, 'GET', `/api/status/${m2}`);
    check(on.status === 200 && bal3 === 2 && stOn.json && stOn.json.paid === true,
      'remettre un à vie ne redébite pas et rouvre l app');
  }

  // --- Deux box, crédits insuffisants, plan interdit ---
  {
    const a = mac();
    const b = mac();
    const urlA = fakeM3u();
    const urlB = fakeM3u();
    await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: a, plan: 'yearly' } });
    await api(env, 'POST', '/api/v1/activate', { token: admin, body: { mac: b, plan: 'monthly' } });
    await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(a)}`, {
      token: admin, body: { source: { type: 'm3u', m3u_url: urlA } },
    });
    await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(b)}`, {
      token: admin, body: { source: { type: 'm3u', m3u_url: urlB } },
    });
    const idA = scalar(db, `SELECT l.id AS n FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?`, a);
    await api(env, 'PATCH', `/api/v1/licenses/${idA}`, { token: admin, body: { status: 'inactive' } });
    const stB = await api(env, 'GET', `/api/status/${b}`);
    const srcB = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(b)}`, { token: admin });
    check(stB.json && stB.json.paid === true, 'désactiver la box A laisse la box B active');
    check(srcB.json && srcB.json.source && srcB.json.source.m3u_url === urlB,
      'le lien de la box B n est pas celui de la box A');

    const poor = await makeReseller(env, admin, ['activate', 'sources'], 0);
    const m = mac();
    const denied = await api(env, 'POST', '/api/v1/activate', {
      token: poor.token, body: { mac: m, plan: 'yearly' },
    });
    check(denied.status === 402 && licCount(db, m) === 0, 'crédits insuffisants : pas de licence');
    const month = await api(env, 'POST', '/api/v1/activate', {
      token: poor.token, body: { mac: mac(), plan: 'monthly' },
    });
    check(month.status === 403 && month.json && month.json.error === 'plan_forbidden',
      'le revendeur ne peut pas vendre 1 mois');
  }

  // --- Un revendeur ne lit pas le lien d'un autre ---
  {
    const a = await makeReseller(env, admin, ['activate', 'sources'], 3);
    const b = await makeReseller(env, admin, ['activate', 'sources'], 3);
    const m = mac();
    const url = fakeM3u();
    const act = await api(env, 'POST', '/api/v1/activate', {
      token: a.token, body: { mac: m, plan: 'yearly' },
    });
    check(act.status === 201, 'revendeur A active sa box');
    const put = await api(env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
      token: a.token, body: { source: { type: 'm3u', m3u_url: url } },
    });
    check(put.status === 200, 'revendeur A pose son lien');
    const peek = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(m)}`, { token: b.token });
    check(peek.status === 403, 'revendeur B ne lit pas le lien de A');
    const wipe = await api(env, 'DELETE', `/api/v1/sources/${encodeURIComponent(m)}`, { token: b.token });
    check(wipe.status === 403, 'revendeur B n efface pas le lien de A');
    const still = await api(env, 'GET', `/api/v1/sources/${encodeURIComponent(m)}`, { token: a.token });
    check(still.json && still.json.source && still.json.source.m3u_url === url,
      'le lien de A est intact');
  }

  // --- Famille : un autre revendeur ne supprime pas le lien ---
  {
    const a = await makeReseller(env, admin, ['activate'], 2);
    const b = await makeReseller(env, admin, ['activate'], 2);
    const created = await api(env, 'POST', '/api/v1/families', {
      token: a.token,
      body: {
        name: 'Foyer test',
        source: { type: 'm3u', m3u_url: fakeM3u() },
      },
    });
    check(created.status === 201 && created.json && created.json.family, 'famille créée');
    const fid = created.json && created.json.family && created.json.family.id;
    const bye = await api(env, 'DELETE', `/api/v1/families/${fid}`, { token: b.token });
    check(bye.status === 403, 'un autre revendeur ne supprime pas la famille');
    const still = await api(env, 'GET', `/api/v1/families/${fid}`, { token: a.token });
    check(still.status === 200, 'la famille de A existe encore');
    const badFam = await api(env, 'POST', '/api/v1/families', {
      token: a.token,
      body: { name: 'Mauvais lien', source: { type: 'm3u', m3u_url: 'pas-une-url' } },
    });
    check(badFam.status === 400, 'famille avec lien invalide refusée');
  }

  // Sans SECRETS_KEY : on ne casse pas les lignes déjà en clair.
  {
    const plain = makeDb();
    plain.env.SECRETS_KEY = undefined;
    const token = await login(plain.env);
    const m = mac();
    const url = fakeM3u();
    await api(plain.env, 'POST', '/api/v1/activate', {
      token, body: { mac: m, plan: 'monthly' },
    });
    const put = await api(plain.env, 'PUT', `/api/v1/sources/${encodeURIComponent(m)}`, {
      token, body: { source: { type: 'm3u', m3u_url: url } },
    });
    const row = plain.db.prepare('SELECT m3u_url AS u FROM device_sources WHERE mac = ?').get(m);
    const pub = await api(plain.env, 'GET', `/api/device-source/${m}`);
    const pubUrl = pub.json && pub.json.source && pub.json.source.m3u_url;
    check(put.status === 200 && row && row.u === url && pubUrl === url,
      'sans clé de chiffrement le lien reste lisible');
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => {
  console.error('TEST CRASH', e && e.message ? e.message : e);
  process.exit(1);
});
