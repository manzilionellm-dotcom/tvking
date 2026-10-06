// =========================================================
//  blackbox.test.mjs — Journal boîte noire (Worker de production)
// =========================================================
//  node --experimental-sqlite cloudflare/blackbox.test.mjs
//  Même base SQLite en mémoire et mêmes comptes (admin + revendeurs
//  créés par l'API) que activation_m3u.test.mjs : les routes passent
//  par la vraie authentification du panel (requireAuth, hydrateActor).
//  Les phrases du filtre sont celles du test Dart
//  (test/core/blackbox/black_box_redaction_test.dart).
//  Aucun vrai lien de flux, aucun vrai mot de passe.
// =========================================================
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import worker from './worker.js';
import {
  BLACKBOX_MAX_BYTES,
  blackboxRequestedAt,
  prepareBlackBoxText,
  redactBlackBox,
} from './blackbox_journal.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
const here = dirname(fileURLToPath(import.meta.url));
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass += 1; console.log('PASS', m); }
  else { fail += 1; console.log('FAIL', m); }
};

const SON = '03/10 18:26:01 I [SON] [TF1] reçu : HE-AAC 48 kHz 2 voies 128 kb/s · '
  + 'décodé par : box (c2.android.aac.decoder) · sortie : PCM 16 bits 48 kHz '
  + '2 voies passthrough';
const FIXTURE = `${SON}\n`
  + '03/10 18:26:02 I [ACTION] Ajout liste Xtream exemple.test (utilisateur COMPTE)\n'
  + '03/10 18:26:03 E [SOURCE] echec http://COMPTE:JETON@exemple.test:8080/get.php?username=COMPTE&password=JETON\n'
  + '03/10 18:26:04 I [SOURCE] chemin /live/COMPTE/JETON/1.ts\n'
  + '03/10 18:26:05 W [SOURCE] recu password=JETON username=COMPTE\n'
  + '03/10 18:26:06 I [SOURCE] note COMPTE@exemple.test\n'
  + '05/10 18:35:09 I [PANEL] ordre source n°7 reçu (attente)\n'
  + '05/10 18:35:21 I [SOURCE] liste M3U du panel chargée en 12,4 s (18230 chaînes)\n';

const MAC = 'MK:AA:BB:CC:DD:11';

// ----- Base D1 simulée (SQLite en mémoire, même schéma que la prod) -----
function makeDb() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec(readFileSync(join(here, 'schema.sql'), 'utf8'));
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
  return { status: res.status, json, text };
}

async function login(env) {
  const res = await api(env, 'POST', '/api/v1/auth/login', {
    body: { email: 'admin', password: env.ADMIN_SECRET },
  });
  return res.json && res.json.token;
}

async function makeReseller(env, admin, perms) {
  const email = `r-${crypto.randomUUID()}@example.test`;
  const password = crypto.randomUUID();
  const created = await api(env, 'POST', '/api/v1/resellers', {
    token: admin,
    body: { email, password, name: 'Revendeur test', credit_balance: 5 },
  });
  ok(created.status === 201 && created.json && created.json.id, 'création revendeur');
  const id = created.json && created.json.id;
  await api(env, 'PATCH', `/api/v1/resellers/${id}`, { token: admin, body: { permissions: perms } });
  const logged = await api(env, 'POST', '/api/v1/auth/reseller/login', { body: { email, password } });
  ok(logged.status === 200 && logged.json && logged.json.token, 'login revendeur');
  return { token: logged.json && logged.json.token, id };
}

async function main() {
  // ----- Filtre (pur) -----
  const sonOnly = redactBlackBox(SON);
  ok(sonOnly === SON, 'ligne [SON] inchangée');
  ok(sonOnly.includes('passthrough') && sonOnly.includes('HE-AAC'), 'détail son conservé');

  const cleaned = prepareBlackBoxText(FIXTURE, { enabled: true });
  ok(cleaned && !cleaned.includes('JETON') && !cleaned.includes('COMPTE'), 'jeton et compte absents');
  ok(cleaned && !cleaned.includes('http://') && cleaned.includes('[lien]'), 'adresse remplacée');
  ok(cleaned && cleaned.includes('[masqué]') && cleaned.includes('[identifiant]'), 'marques de masque');
  ok(cleaned && cleaned.includes('[SON]'), 'la ligne son est toujours là');
  ok(cleaned && cleaned.includes('ordre source n°7 reçu (attente)')
    && cleaned.includes('chargée en 12,4 s (18230 chaînes)'),
  'les lignes de mesure panel → box passent telles quelles');
  ok(prepareBlackBoxText(cleaned, { enabled: true }) === cleaned, 'deuxième passage identique');
  ok(prepareBlackBoxText(FIXTURE, { enabled: false }) === null, 'interrupteur coupé : rien');
  ok(prepareBlackBoxText('  \n', { enabled: true }) === null, 'texte vide : rien');

  const huge = `${'B'.repeat(200000)}\n${SON}`;
  const tail = prepareBlackBoxText(huge, { enabled: true });
  ok(tail && new TextEncoder().encode(tail).length <= BLACKBOX_MAX_BYTES, 'plafond 32 Ko');
  ok(tail && tail.includes('[SON]') && tail.includes('HE-AAC'), 'la fin du journal est gardée');
  ok(BLACKBOX_MAX_BYTES === 32 * 1024, 'constante 32 Ko');

  // ----- Worker : écriture app, lecture panel -----
  const { db, env } = makeDb();
  const admin = await login(env);
  ok(!!admin, 'login admin');

  // La MAC appartient au revendeur A (activation d'essai par l'admin).
  const a = await makeReseller(env, admin, ['activate', 'devices', 'sources']);
  const b = await makeReseller(env, admin, ['activate', 'devices', 'sources']);
  await api(env, 'GET', `/api/status/${MAC}`);
  const claim = await api(env, 'POST', '/api/v1/activate', {
    token: admin, body: { mac: MAC, plan: 'trial_7d', reseller_id: a.id },
  });
  ok(claim.status === 200 || claim.status === 201, `MAC rattachée au revendeur A (${claim.status})`);

  let r = await api(env, 'POST', '/api/blackbox', { body: { mac: MAC, text: FIXTURE } });
  ok(r.status === 200 && r.json && r.json.ok === true && typeof r.json.updated_at === 'number',
    'POST /api/blackbox accepte le journal');
  ok(!r.text.includes('JETON'), 'la réponse POST ne renvoie pas le jeton');

  r = await api(env, 'GET', `/api/blackbox/${MAC}`);
  ok(r.status === 400 && !r.text.includes('JETON'),
    'GET public refusé : le journal ne se lit pas sans le panel');

  r = await api(env, 'POST', '/api/blackbox', { body: { mac: 'PAS-UNE-MAC', text: FIXTURE } });
  ok(r.status === 400, 'MAC invalide refusée');

  r = await api(env, 'GET', `/api/v1/blackbox/${encodeURIComponent(MAC)}`);
  ok(r.status === 401, 'lecture panel sans jeton : 401');

  r = await api(env, 'GET', `/api/v1/blackbox/${encodeURIComponent(MAC)}`, { token: admin });
  ok(r.status === 200 && r.json && typeof r.json.text === 'string' && r.json.updated_at > 0,
    `le panel lit le texte et l'heure (${r.status})`);
  ok(r.json && r.json.text.includes('[SON]') && r.json.text.includes('passthrough'),
    'le texte panel contient la ligne [SON]');
  ok(r.json && !r.json.text.includes('JETON') && !r.json.text.includes('COMPTE')
    && !r.json.text.includes('http://'),
  'le texte stocké ne contient ni jeton, ni compte, ni adresse');

  r = await api(env, 'GET', `/api/v1/blackbox/${encodeURIComponent(MAC)}`, { token: a.token });
  ok(r.status === 200 && r.json && r.json.text.includes('[SON]'), 'le revendeur lit SA box');

  r = await api(env, 'GET', `/api/v1/blackbox/${encodeURIComponent(MAC)}`, { token: b.token });
  ok(r.status === 403 && !r.text.includes('[SON]'), 'un autre revendeur ne voit pas le journal');

  r = await api(env, 'POST', `/api/v1/blackbox/${encodeURIComponent(MAC)}/ask`, { token: admin });
  ok(r.status === 200 && r.json && r.json.requested_at > 0, 'demande panel enregistrée');
  const requestedAt = r.json && r.json.requested_at;

  const stored = db.prepare('SELECT body, requested_at FROM device_blackbox WHERE mac = ?').get(MAC);
  ok(stored && stored.body.includes('[SON]') && stored.requested_at === requestedAt,
    'la demande n\'efface pas le journal');
  const pull = await blackboxRequestedAt(env, MAC);
  ok(pull === requestedAt && pull > 0, 'le statut peut lire la demande (blackbox_pull)');

  // Le statut public (que la box lit déjà) porte la demande.
  r = await api(env, 'GET', `/api/status/${MAC}`);
  ok(r.status === 200 && r.json && r.json.blackbox_pull === requestedAt,
    'GET /api/status renvoie blackbox_pull');
  ok(!r.text.includes('JETON') && !r.text.includes('[SON]'), 'le statut ne contient pas le journal');

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => {
  console.error('TEST CRASH', e && e.message ? e.message : e);
  process.exit(1);
});
