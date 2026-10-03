// =========================================================
//  blackbox.test.mjs — Journal boîte noire
// =========================================================
//  node cloudflare/blackbox.test.mjs
//  Les phrases sont les mêmes que le test Dart
//  (test/core/blackbox/black_box_redaction_test.dart).
//  Aucun vrai lien de flux, aucun vrai mot de passe.
// =========================================================
import worker from './worker.js';
import {
  BLACKBOX_MAX_BYTES,
  blackboxRequestedAt,
  prepareBlackBoxText,
  redactBlackBox,
} from './blackbox_journal.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
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
  + '03/10 18:26:06 I [SOURCE] note COMPTE@exemple.test\n';

const MAC = 'MK:AA:BB:CC:DD:11';
const TEST_ADMIN = 'unit-test-admin-secret';

function memoryDb() {
  const rows = [];
  const rates = [];
  const devices = [];
  function prepare(sql) {
    const q = sql.replace(/\s+/g, ' ').trim();
    const stmt = (args) => ({
      first: async () => apply(q, args, rows, rates, devices).first,
      run: async () => apply(q, args, rows, rates, devices).run,
      all: async () => ({ results: [] }),
    });
    const bound = stmt([]);
    return {
      bind(...args) { return stmt(args); },
      run: bound.run,
      first: bound.first,
      all: bound.all,
    };
  }
  return { prepare, rows, devices };
}

function apply(q, args, rows, rates, devices) {
  if (/^CREATE /i.test(q)) return { run: {} };
  if (q.includes('FROM rate_limits')) {
    return { first: rates.find((r) => r.k === args[0]) || null, run: {} };
  }
  if (q.includes('INSERT INTO rate_limits')) {
    const k = args[0];
    const now = args[1];
    const prev = rates.find((r) => r.k === k);
    if (prev) { prev.count = 1; prev.window_start = now; }
    else rates.push({ k, count: 1, window_start: now });
    return { run: {} };
  }
  if (q.includes('UPDATE rate_limits SET count')) {
    const row = rates.find((r) => r.k === args[0]);
    if (row) row.count += 1;
    return { run: {} };
  }
  if (q.includes('reseller_id, customer_id FROM devices')) {
    const row = devices.find((d) => d.mac === args[0]);
    return { first: row || null, run: {} };
  }
  if (q.includes('SELECT body, updated_at FROM device_blackbox')) {
    const row = rows.find((r) => r.mac === args[0]);
    return {
      first: row ? { body: row.body, updated_at: row.updated_at } : null,
      run: {},
    };
  }
  if (q.includes('SELECT requested_at FROM device_blackbox')) {
    const row = rows.find((r) => r.mac === args[0]);
    return { first: row ? { requested_at: row.requested_at } : null, run: {} };
  }
  if (q.includes('INSERT INTO device_blackbox') && q.includes('requested_at = excluded')) {
    const mac = args[0];
    const requested = args[1];
    const prev = rows.find((r) => r.mac === mac);
    if (prev) prev.requested_at = requested;
    else rows.push({ mac, body: '', updated_at: 0, requested_at: requested });
    return { run: {} };
  }
  if (q.includes('INSERT INTO device_blackbox') && q.includes('body = excluded.body')) {
    const mac = args[0];
    const body = args[1];
    const updated = args[2];
    const prev = rows.find((r) => r.mac === mac);
    if (prev) {
      prev.body = body;
      prev.updated_at = updated;
    } else {
      rows.push({ mac, body, updated_at: updated, requested_at: 0 });
    }
    return { run: {} };
  }
  return { first: null, run: {} };
}

function b64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
async function signJwt(payload, secret) {
  const h = b64url(new TextEncoder().encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const now = Math.floor(Date.now() / 1000);
  const p = b64url(new TextEncoder().encode(JSON.stringify({
    ...payload, iat: now, exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = b64url(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${h}.${p}`)));
  return `${h}.${p}.${sig}`;
}

// ----- Filtre (pur) -----
const sonOnly = redactBlackBox(SON);
ok(sonOnly === SON, 'ligne [SON] inchangée');
ok(sonOnly.includes('passthrough') && sonOnly.includes('HE-AAC'), 'détail son conservé');

const cleaned = prepareBlackBoxText(FIXTURE, { enabled: true });
ok(cleaned && !cleaned.includes('JETON') && !cleaned.includes('COMPTE'), 'jeton et compte absents');
ok(cleaned && !cleaned.includes('http://') && cleaned.includes('[lien]'), 'adresse remplacée');
ok(cleaned && cleaned.includes('[masqué]') && cleaned.includes('[identifiant]'), 'marques de masque');
ok(cleaned && cleaned.includes('[SON]'), 'la ligne son est toujours là');
ok(prepareBlackBoxText(cleaned, { enabled: true }) === cleaned, 'deuxième passage identique');
ok(prepareBlackBoxText(FIXTURE, { enabled: false }) === null, 'interrupteur coupé : rien');
ok(prepareBlackBoxText('  \n', { enabled: true }) === null, 'texte vide : rien');

const huge = `${'B'.repeat(200000)}\n${SON}`;
const tail = prepareBlackBoxText(huge, { enabled: true });
ok(tail && new TextEncoder().encode(tail).length <= BLACKBOX_MAX_BYTES, 'plafond 32 Ko');
ok(tail && tail.includes('[SON]') && tail.includes('HE-AAC'), 'la fin du journal est gardée');
ok(BLACKBOX_MAX_BYTES === 32 * 1024, 'constante 32 Ko');

// ----- Worker : écriture app, lecture panel -----
const db = memoryDb();
db.devices.push({ mac: MAC, reseller_id: 'rsl_owner', customer_id: 'cus1' });
const env = { DB: db, ADMIN_SECRET: TEST_ADMIN };

let r = await worker.fetch(new Request('https://app.x/api/blackbox', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ mac: MAC, text: FIXTURE }),
}), env, ctx);
let body = await r.json();
ok(r.status === 200 && body.ok === true && typeof body.updated_at === 'number',
  'POST /api/blackbox accepte le journal');
ok(!JSON.stringify(body).includes('JETON'), 'la réponse POST ne renvoie pas le jeton');

r = await worker.fetch(new Request(`https://app.x/api/blackbox/${MAC}`), env, ctx);
body = await r.json();
ok(r.status === 400 && !JSON.stringify(body).includes('JETON'),
  'GET public refusé : le journal ne se lit pas sans le panel');

r = await worker.fetch(new Request('https://app.x/api/blackbox', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ mac: 'PAS-UNE-MAC', text: FIXTURE }),
}), env, ctx);
ok(r.status === 400, 'MAC invalide refusée');

r = await worker.fetch(new Request(`https://app.x/api/v1/blackbox/${encodeURIComponent(MAC)}`), env, ctx);
ok(r.status === 401, 'lecture panel sans jeton : 401');

const owner = await signJwt(
  { sub: 'adm_1', role: 'super_admin', email: 'admin@exemple.test' },
  TEST_ADMIN,
);
r = await worker.fetch(new Request(`https://app.x/api/v1/blackbox/${encodeURIComponent(MAC)}`, {
  headers: { Authorization: `Bearer ${owner}` },
}), env, ctx);
body = await r.json();
ok(r.status === 200 && typeof body.text === 'string' && body.updated_at > 0,
  'le panel lit le texte et l\'heure');
ok(body.text.includes('[SON]') && body.text.includes('passthrough'),
  'le texte panel contient la ligne [SON]');
ok(!body.text.includes('JETON') && !body.text.includes('COMPTE') && !body.text.includes('http://'),
  'le texte stocké ne contient ni jeton, ni compte, ni adresse');

const mine = await signJwt(
  { sub: 'rsl_owner', role: 'reseller', email: 'lionel@exemple.test' },
  TEST_ADMIN,
);
r = await worker.fetch(new Request(`https://app.x/api/v1/blackbox/${encodeURIComponent(MAC)}`, {
  headers: { Authorization: `Bearer ${mine}` },
}), env, ctx);
body = await r.json();
ok(r.status === 200 && body.text.includes('[SON]'), 'le revendeur lit SA box');

const other = await signJwt(
  { sub: 'rsl_intrus', role: 'reseller', email: 'intrus@exemple.test' },
  TEST_ADMIN,
);
r = await worker.fetch(new Request(`https://app.x/api/v1/blackbox/${encodeURIComponent(MAC)}`, {
  headers: { Authorization: `Bearer ${other}` },
}), env, ctx);
body = await r.json();
ok(r.status === 403 && !JSON.stringify(body).includes('JETON') && !JSON.stringify(body).includes('[SON]'),
  'un autre revendeur ne voit pas le journal');

r = await worker.fetch(new Request(`https://app.x/api/v1/blackbox/${encodeURIComponent(MAC)}/ask`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${owner}` },
}), env, ctx);
body = await r.json();
ok(r.status === 200 && body.requested_at > 0, 'demande panel enregistrée');

const stored = db.rows.find((row) => row.mac === MAC);
ok(stored && stored.body.includes('[SON]') && stored.requested_at === body.requested_at,
  'la demande n\'efface pas le journal');
const pull = await blackboxRequestedAt(env, MAC);
ok(pull === body.requested_at && pull > 0,
  'le statut peut lire la demande (blackbox_pull)');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
