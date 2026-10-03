// =========================================================
//  source_pair.test.mjs — QR téléphone → page existante
// =========================================================
//  node cloudflare/source_pair.test.mjs
//  Hôtes bidons. Aucun mot de passe réel, aucune adresse de flux.
// =========================================================
import worker from './worker.js';
import { hashDeviceSecret } from './device_guard.js';
import { portalHtml } from './portal.js';
import {
  homeSourcePortalUrl,
  pairCodeStillValid,
  pairWriteAllowed,
  portalHashParts,
  sourcePairCodeOk,
} from './source_pair.js';

const ctx = { waitUntil() {}, passThroughOnException() {} };
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass += 1; console.log('PASS', m); }
  else { fail += 1; console.log('FAIL', m); }
};

const MAC = 'MK:AA:BB:CC:DD:11';
const BOX_SECRET = 'box-secret-unit-test-0123456789abcdef';
const PAIR = 'K7MNPQ';

ok(sourcePairCodeOk(PAIR), 'code court accepté');
ok(!sourcePairCodeOk('OOOOOO'), 'O et 0 refusés');
ok(!sourcePairCodeOk('ABC'), 'code trop court refusé');
ok(pairCodeStillValid(2_000, 1_000), 'code dans la fenêtre');
ok(!pairCodeStillValid(1_000, 1_000), 'code expiré à l\'instant pile');
ok(pairWriteAllowed({ enrolled: false, secretOk: false, pairOk: false }),
  'box pas enrôlée : la page peut encore écrire');
ok(!pairWriteAllowed({ enrolled: true, secretOk: false, pairOk: false }),
  'box enrôlée sans preuve : écriture refusée');
ok(pairWriteAllowed({ enrolled: true, secretOk: false, pairOk: true }),
  'code court encore valable : écriture acceptée');

const link = homeSourcePortalUrl('https://exemple.invalid/', MAC.toLowerCase(), PAIR);
ok(link === `https://exemple.invalid/mon-espace#mac=${MAC}&pair=${PAIR}`,
  'lien : MAC en clair, code dans le fragment');
ok(link && !link.includes('get.php') && !link.includes('.m3u'),
  'le lien n\'est pas une adresse de flux');
ok(homeSourcePortalUrl('ftp://exemple.invalid', MAC, PAIR) === null,
  'schéma autre que http(s) refusé');
ok(homeSourcePortalUrl('https://exemple.invalid', 'pas-une-mac', null) === null,
  'MAC illisible : pas de lien');

const parts = portalHashParts(`#mac=${MAC}&pair=${PAIR}`);
ok(parts.mac === MAC && parts.pair === PAIR, 'fragment relu comme la page');

const html = portalHtml();
ok(html.includes('X-Source-Pair'), 'la page envoie le code court');
ok(html.includes('pair=([^&]+)'), 'la page lit pair= dans le fragment');
ok(html.includes('Cette application ne vend aucune chaîne. Ajoutez votre propre abonnement.'),
  'la page répète la phrase obligatoire');

function memoryDb() {
  const t = {
    rate_limits: [],
    device_secrets: [],
    source_pairs: [],
    device_sources: [],
  };
  function prepare(sql) {
    const q = String(sql).replace(/\s+/g, ' ').trim();
    const exec = (args) => {
      const op = apply(q, args, t);
      return {
        first: async () => (op.first === undefined ? null : op.first),
        run: async () => op.run || {},
        all: async () => ({ results: op.all || [] }),
      };
    };
    // Ne pas exécuter tout de suite : prepare().bind() ne doit pas
    // aussi lancer la requête avec des arguments vides.
    return {
      bind(...args) { return exec(args); },
      run: () => exec([]).run(),
      first: () => exec([]).first(),
      all: () => exec([]).all(),
    };
  }
  return { prepare, t };
}

function apply(q, args, t) {
  if (/^CREATE |^ALTER /i.test(q)) return { run: {} };
  if (q.includes('FROM rate_limits')) {
    return { first: t.rate_limits.find((r) => r.k === args[0]) || null };
  }
  if (q.includes('INSERT INTO rate_limits')) {
    const row = { k: args[0], count: 1, window_start: args[1] };
    const i = t.rate_limits.findIndex((r) => r.k === row.k);
    if (i >= 0) t.rate_limits[i] = row;
    else t.rate_limits.push(row);
    return { run: {} };
  }
  if (q.includes('UPDATE rate_limits')) {
    const row = t.rate_limits.find((r) => r.k === args[0]);
    if (row) row.count += 1;
    return { run: {} };
  }
  if (q.includes('FROM device_secrets')) {
    return { first: t.device_secrets.find((r) => r.mac === args[0]) || null };
  }
  if (q.includes('FROM source_pairs')) {
    return { first: t.source_pairs.find((r) => r.mac === args[0]) || null };
  }
  if (q.includes('INSERT INTO source_pairs')) {
    const row = { mac: args[0], code_hash: args[1], expires_at: args[2] };
    const i = t.source_pairs.findIndex((r) => r.mac === row.mac);
    if (i >= 0) t.source_pairs[i] = row;
    else t.source_pairs.push(row);
    return { run: {} };
  }
  if (q.includes('FROM device_sources')) {
    return { first: t.device_sources.find((r) => r.mac === args[0]) || null };
  }
  if (q.includes('INSERT INTO device_sources')) {
    const row = {
      mac: args[0],
      type: args[1],
      label: args[2],
      server_url: args[3],
      username: args[4],
      password: args[5],
      m3u_url: args[6],
      epg_url: args[7],
      sources_json: args[8],
      origin: args[9],
      updated_at: args[10],
    };
    const i = t.device_sources.findIndex((r) => r.mac === row.mac);
    if (i >= 0) t.device_sources[i] = row;
    else t.device_sources.push(row);
    return { run: {} };
  }
  if (q.includes('DELETE FROM device_sources')) {
    t.device_sources = t.device_sources.filter((r) => r.mac !== args[0]);
    return { run: {} };
  }
  throw new Error(`SQL non prévu dans le test : ${q}`);
}

async function call(env, path, { method = 'GET', headers = {}, body } = {}) {
  const res = await worker.fetch(new Request(`https://exemple.invalid${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...headers },
    body: body == null ? undefined : JSON.stringify(body),
  }), env, ctx);
  const text = await res.text();
  let json = {};
  try { json = JSON.parse(text); } catch (_) { json = { raw: text }; }
  return { status: res.status, json };
}

const db = memoryDb();
const env = { DB: db };

const m3u = {
  type: 'm3u',
  label: 'Ma liste',
  m3u_url: 'http://liste.invalid/a.m3u',
};

const open = await call(env, `/api/self-source/${MAC}`, { method: 'POST', body: m3u });
ok(open.status === 200 && open.json.ok === true,
  `box pas enrôlée : la source passe (${open.status} ${open.json.error || ''})`);

const secretHash = await hashDeviceSecret(BOX_SECRET);
db.t.device_secrets.push({
  mac: MAC,
  secret_hash: secretHash,
  android_id: 'android-test',
  updated_at: 1,
});

const locked = await call(env, `/api/self-source/${MAC}`, { method: 'POST', body: m3u });
ok(locked.status === 401 && locked.json.error === 'device_secret_required',
  'box enrôlée : la MAC seule ne modifie plus');

const noSecret = await call(env, '/api/source-pair', {
  method: 'POST',
  body: { mac: MAC, code: PAIR },
});
ok(noSecret.status === 401, 'déclarer un code exige le secret de la box');

const badCode = await call(env, '/api/source-pair', {
  method: 'POST',
  headers: { 'X-Device-Secret': BOX_SECRET },
  body: { mac: MAC, code: 'OOOOOO' },
});
ok(badCode.status === 400, 'code ambigu refusé');

const declared = await call(env, '/api/source-pair', {
  method: 'POST',
  headers: { 'X-Device-Secret': BOX_SECRET },
  body: { mac: MAC, code: PAIR },
});
ok(declared.status === 200 && declared.json.ok === true && !declared.json.code,
  'la box déclare le code, le Worker ne le répète pas');

const withPair = await call(env, `/api/self-source/${MAC}`, {
  method: 'POST',
  headers: { 'X-Source-Pair': PAIR },
  body: m3u,
});
ok(withPair.status === 200 && withPair.json.ok === true,
  `le téléphone écrit avec le code court (${withPair.status})`);

const wrong = await call(env, `/api/self-source/${MAC}`, {
  method: 'POST',
  headers: { 'X-Source-Pair': 'K7MNPR' },
  body: m3u,
});
ok(wrong.status === 401, 'un autre code est refusé');

db.t.source_pairs[0].expires_at = 1;
const expired = await call(env, `/api/self-source/${MAC}`, {
  method: 'POST',
  headers: { 'X-Source-Pair': PAIR },
  body: m3u,
});
ok(expired.status === 401, 'code expiré : la page ne modifie plus');

const page = await call(env, '/mon-espace');
ok(page.status === 200 && String(page.json.raw || '').includes('X-Source-Pair'),
  'GET /mon-espace sert toujours la page');

console.log(fail === 0 ? `OK ${pass}` : `ECHEC ${fail}/${pass + fail}`);
if (fail) process.exit(1);
