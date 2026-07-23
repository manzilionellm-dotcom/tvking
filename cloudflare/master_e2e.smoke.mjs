// Smoke test BOUT-EN-BOUT — CONSOLE MAÎTRE (2 téléphones virtuels A et B).
//
// Rejoue le VRAI parcours de production sur une base D1 factice (mini-
// interpréteur SQL en mémoire) et un réseau simulé :
//   1. le maître enregistre sa liste de test (façade F1), puis CHANGE de
//      façade (F2) → les URLs doivent suivre (correctif structurel n°1) ;
//   2. test donné à A par MAC (panel) et à B par code (contrat redeem =
//      copyMasterSourceForTest, la décision pure est déjà couverte par
//      invite_master.smoke.mjs) ;
//   3. les DEUX appareils reçoivent la liste par la référence OPAQUE, la 1re
//      chaîne est SONDÉE JOIGNABLE (verdict green) — jamais « mondomaine » ;
//   4. SONDE PARALLÈLE : les flux de A et B sont sondés AU MÊME INSTANT
//      (hôte, statut, latence journalisés — aucun secret) et la MUTUALISATION
//      est vérifiée (même chaîne pour A et B = même URL → 1 connexion
//      fournisseur via le gateway) ;
//   5. liste HÉRITÉE sur le domaine d'exemple → simulateur ROUGE qui NOMME
//      l'hôte fautif ; ré-enregistrement avec une vraie façade → réparé ;
//   6. façade VIDE → URLs direct fournisseur servies telles quelles ;
//   7. liste VIDÉE → repli bouquet complet (kind 'bouquet') ;
//   8. INVISIBILITÉ : maître ET testeur partent dans admin_presence (jamais
//      dans les stats clients), kind master/test dans Admin Monitoring ;
//   9. PROLONGER (échéance qui bouge) et RÉVOQUER (accès coupé).
//
// Lancer : node cloudflare/master_e2e.smoke.mjs
import assert from 'node:assert/strict';
import {
  handleMasterTestListPut, handleMasterTestGrant, handleMasterTestCode,
  handleMasterTestExtend, handleMasterTestRevoke, handleMasterSimulate,
  handleAdminMonitorGet,
} from './api_v1.js';
import {
  handleMasterListServe, copyMasterSourceForTest, recordPresence,
} from './worker.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// =========================================================
//  FAUSSE D1 — mini-interpréteur des requêtes réellement utilisées
// =========================================================
//  Tables = tableaux d'objets. On couvre : INSERT (OR REPLACE / ON CONFLICT),
//  UPDATE, DELETE, SELECT mono-table par clé, et les quelques jointures des
//  handlers maîtres. Toute requête inconnue répond « vide » (jamais un crash)
//  et est journalisée pour le débogage.
function fakeD1() {
  const tables = {};
  const t = (name) => (tables[name] ||= []);
  const KEYS = {
    app_masters: 'mac', master_test_list: 'mac', device_sources: 'mac',
    presence: 'mac', admin_presence: 'mac', app_invites: 'code',
    devices: 'id', customers: 'id', licenses: 'id', audit_logs: 'id',
  };
  const unknown = [];

  // Découpe une liste « a, b, 'c,d', (e) » au niveau 0 (hors quotes/parenthèses).
  function splitTop(s) {
    const out = []; let cur = ''; let depth = 0; let q = null;
    for (const ch of s) {
      if (q) { cur += ch; if (ch === q) q = null; continue; }
      if (ch === "'" || ch === '"') { q = ch; cur += ch; continue; }
      if (ch === '(') depth++;
      if (ch === ')') depth--;
      if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; continue; }
      cur += ch;
    }
    if (cur.trim()) out.push(cur.trim());
    return out;
  }
  // Valeur d'un jeton SQL : '?' → prochain argument ; NULL / nombre / 'litéral'.
  function tokenValue(tok, args, cursor) {
    if (tok === '?') return args[cursor.i++];
    if (/^NULL$/i.test(tok)) return null;
    if (/^-?\d+$/.test(tok)) return Number(tok);
    const m = tok.match(/^'(.*)'$/s);
    if (m) return m[1];
    return tok;
  }

  function exec(sqlRaw, args) {
    const sql = sqlRaw.replace(/\s+/g, ' ').trim();

    // DDL (CREATE/ALTER/INDEX) → toujours OK.
    if (/^(CREATE|ALTER)\b/i.test(sql)) return { kind: 'ok' };

    // --- Jointures spécifiques des handlers maîtres -------------------------
    // Suivi/prolongation/révocation : app_invites JOIN app_masters.
    if (/FROM app_invites iv JOIN app_masters am/i.test(sql)) {
      const masters = new Set(t('app_masters').map((r) => r.mac));
      let rows = t('app_invites').filter((r) => masters.has(r.issuer_mac));
      if (/WHERE iv\.code = \?/i.test(sql)) rows = rows.filter((r) => r.code === args[0]);
      if (/SELECT DISTINCT iv\.redeemer_mac AS mac/i.test(sql)) {
        const now = args[0];
        const macs = [...new Set(rows.filter((r) => r.redeemer_mac && r.guest_until > now)
          .map((r) => r.redeemer_mac))];
        return { kind: 'rows', rows: macs.map((mac) => ({ mac })) };
      }
      const noteByMac = Object.fromEntries(t('app_masters').map((r) => [r.mac, r.note ?? null]));
      const projected = rows.map((r) => ({ ...r, master_note: noteByMac[r.issuer_mac] ?? null }));
      return { kind: 'rows', rows: projected };
    }
    // Admin Monitoring : admin_presence LEFT JOIN app_masters (kind master/test).
    if (/FROM admin_presence ap LEFT JOIN app_masters am/i.test(sql)) {
      const masters = new Set(t('app_masters').map((r) => r.mac));
      const since = args[0];
      const rows = t('admin_presence')
        .filter((r) => (r.last_seen || 0) > since)
        .map((r) => ({ ...r, kind: masters.has(r.mac) ? 'master' : 'test' }))
        .sort((a, b) => (b.last_seen || 0) - (a.last_seen || 0));
      return { kind: 'rows', rows };
    }
    // Meilleure licence d'un appareil (à vie d'abord, sinon la plus lointaine).
    if (/FROM licenses WHERE device_id = \? ORDER BY/i.test(sql)) {
      const rows = t('licenses').filter((r) => r.device_id === args[0])
        .sort((a, b) => {
          const an = a.expires_at == null ? 1 : 0;
          const bn = b.expires_at == null ? 1 : 0;
          if (an !== bn) return bn - an;
          return (b.expires_at || 0) - (a.expires_at || 0);
        });
      return { kind: 'rows', rows };
    }

    // --- INSERT (OR REPLACE / ON CONFLICT = remplace par clé) ---------------
    let m = sql.match(/^INSERT (?:OR REPLACE )?INTO (\w+)\s*\(([^)]+)\)\s*VALUES\s*\((.+?)\)(?:\s+ON CONFLICT.*)?$/is);
    if (m) {
      const [, table, colsRaw, valsRaw] = m;
      const cols = colsRaw.split(',').map((c) => c.trim());
      const toks = splitTop(valsRaw);
      const cursor = { i: 0 };
      const row = {};
      cols.forEach((c, i) => { row[c] = tokenValue(toks[i], args, cursor); });
      const key = KEYS[table];
      const arr = t(table);
      const idx = key ? arr.findIndex((r) => r[key] === row[key]) : -1;
      if (idx >= 0) arr[idx] = row; else arr.push(row);
      return { kind: 'ok' };
    }

    // --- UPDATE <t> SET … WHERE <k> = ? -------------------------------------
    m = sql.match(/^UPDATE (\w+) SET (.+) WHERE (\w+)\s*=\s*\?$/is);
    if (m) {
      const [, table, setRaw, whereKey] = m;
      const cursor = { i: 0 };
      const sets = splitTop(setRaw).map((pair) => {
        const [col, ...rest] = pair.split('=');
        return { col: col.trim(), val: tokenValue(rest.join('=').trim(), args, cursor) };
      });
      const keyVal = args[cursor.i];
      for (const r of t(table)) {
        if (r[whereKey] === keyVal) for (const s of sets) r[s.col] = s.val;
      }
      return { kind: 'ok' };
    }

    // --- DELETE FROM <t> WHERE <k> = ? --------------------------------------
    m = sql.match(/^DELETE FROM (\w+) WHERE (\w+)\s*=\s*\?$/i);
    if (m) {
      const [, table, key] = m;
      tables[table] = t(table).filter((r) => r[key] !== args[0]);
      return { kind: 'ok' };
    }

    // --- SELECT mono-table --------------------------------------------------
    m = sql.match(/^SELECT (.+?) FROM (\w+)(?:\s+WHERE (\w+)\s*=\s*\?)?(?:\s+ORDER BY .*)?$/is);
    if (m) {
      const [, colsRaw, table, whereKey] = m;
      let rows = t(table);
      if (whereKey) rows = rows.filter((r) => r[whereKey] === args[0]);
      if (/^\s*1 AS x\s*$/i.test(colsRaw)) {
        return { kind: 'rows', rows: rows.map(() => ({ x: 1 })) };
      }
      if (colsRaw.trim() === '*') return { kind: 'rows', rows: rows.map((r) => ({ ...r })) };
      const cols = colsRaw.split(',').map((c) => c.trim());
      return {
        kind: 'rows',
        rows: rows.map((r) => Object.fromEntries(cols.map((c) => [c, r[c] ?? null]))),
      };
    }

    unknown.push(sql);
    return { kind: 'rows', rows: [] };
  }

  const db = {
    _tables: tables,
    _unknown: unknown,
    prepare(sql) {
      return {
        bind(...args) { return stmt(sql, args); },
        // .first()/.run()/.all() sans bind (requêtes sans paramètre).
        first: (...a) => stmt(sql, []).first(...a),
        run: () => stmt(sql, []).run(),
        all: () => stmt(sql, []).all(),
      };
    },
    async batch(statements) {
      const out = [];
      for (const s of statements) out.push(await s.run());
      return out;
    },
  };
  function stmt(sql, args) {
    return {
      run: async () => { exec(sql, args); return { success: true }; },
      first: async () => { const r = exec(sql, args); return (r.rows && r.rows[0]) || null; },
      all: async () => { const r = exec(sql, args); return { results: r.rows || [] }; },
    };
  }
  return db;
}

// =========================================================
//  RÉSEAU SIMULÉ — sert la liste opaque via le VRAI handler du worker,
//  sonde les flux (200 + octets) sauf pour les domaines d'exemple (DNS mort).
// =========================================================
const ORIGIN = 'https://app.test';
const probeLog = [];            // journal { host, status, ms } — aucun secret
let inFlight = 0;               // sondes réellement simultanées
let maxInFlight = 0;
function installFetch(env) {
  globalThis.fetch = async (url) => {
    const u = String(url);
    // Liste de test opaque → le VRAI chemin de service du worker.
    const ml = u.match(/\/api\/master-list\/([^/?#]+)$/);
    if (ml) return handleMasterListServe(env, ml[1]);
    const { host, hostname } = new URL(u);
    // Domaine d'exemple → comme en vrai : le DNS ne résout pas.
    if (/(^|\.)(mondomaine|ton-domaine|tondomaine|example|exemple)\.(com|net|org|fr|tld)$/i.test(hostname)) {
      throw new Error('getaddrinfo ENOTFOUND ' + hostname);
    }
    // Flux : 200, deux octets « reçus » (sonde Range), latence simulée.
    inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
    await new Promise((r) => setTimeout(r, 30));
    inFlight--;
    const t0 = Date.now();
    probeLog.push({ host, status: 200, ms: Date.now() - t0 + 30 });
    return { ok: true, status: 200, body: null, text: async () => 'xx', json: async () => ({}) };
  };
}

// Requêtes factices vers les handlers (mêmes objets Request qu'en prod).
const jsonReq = (path, body) => new Request(ORIGIN + path, {
  method: 'POST', body: JSON.stringify(body), headers: { 'content-type': 'application/json' },
});
const putReq = (path, body) => new Request(ORIGIN + path, {
  method: 'PUT', body: JSON.stringify(body), headers: { 'content-type': 'application/json' },
});
const getReq = (path) => new Request(ORIGIN + path);
const ACTOR = { type: 'admin', id: 'smoke' };
const asJson = async (resp) => ({ status: resp.status, body: await resp.json() });

// MACs : 1 maître + 2 téléphones virtuels A (par MAC) et B (par code).
const MASTER = 'MK:11:22:33:44:55';
const MAC_A = 'MK:AA:AA:AA:AA:01';
const MAC_B = 'MK:BB:BB:BB:BB:02';
const F1 = 'https://f1.gw.tld1';
const F2 = 'https://f2.gw.tld2';

const env = { DB: fakeD1() };
installFetch(env);

// --- Décor : le maître existe et a une ligne fournisseur assignée -----------
env.DB._tables.app_masters = [{ mac: MASTER, note: 'exploitant', created_at: 1 }];
env.DB._tables.device_sources = [{
  mac: MASTER, type: 'xtream', label: 'Ligne', server_url: 'http://fournisseur.tld9:8080',
  username: 'ju', password: 'jp', m3u_url: null, epg_url: null,
  sources_json: null, origin: 'panel', updated_at: 1,
}];

// =========================================================
//  1) LISTE DE TEST : façade F1, puis CHANGEMENT de façade → URLs suivent
// =========================================================
const LIST_F1 = [
  '#EXTM3U',
  '#EXTINF:-1 group-title="Sport",Foot 1',
  F1 + '/live/diff/pass/1.ts',
  '#EXTINF:-1 group-title="Sport",Foot 2',
  F1 + '/live/diff/pass/2.ts',
].join('\n');

let r = await asJson(await handleMasterTestListPut(
  putReq('/api/v1/masters/test-list', { mac: MASTER, m3u: LIST_F1, gateway_base: F1, gateway_user: 'diff', gateway_pass: 'pass' }), env));
assert.equal(r.status, 200);
assert.equal(r.body.count, 2);
ok('liste de test enregistrée (2 chaînes, façade F1, identité de diffusion)');

// Le maître change de façade (F1 → F2) et ré-enregistre la MÊME liste (URLs
// encore sur F1 — exactement le bug de prod) : le serveur reconstruit.
r = await asJson(await handleMasterTestListPut(
  putReq('/api/v1/masters/test-list', { mac: MASTER, m3u: LIST_F1, gateway_base: F2, gateway_user: 'diff' }), env));
assert.equal(r.status, 200);
assert.equal(r.body.rebuilt, 2);
assert.ok(r.body.m3u.includes(F2 + '/live/diff/pass/1.ts'));
assert.ok(!r.body.m3u.includes('f1.gw'));
ok('CHANGEMENT DE FAÇADE → les 2 URLs sont reconstruites sur F2 (bug de prod corrigé)');

// L'identité de diffusion n'est JAMAIS réaffichée par l'API.
assert.equal(r.body.has_gateway_pass, true);
assert.ok(!JSON.stringify(r.body).includes('pass"')
  || !JSON.stringify(r.body).includes('"gateway_pass"'));
ok('mot de passe gateway conservé côté serveur mais jamais renvoyé');

// La façade « domaine d'exemple » est refusée NET avec un message actionnable.
r = await asJson(await handleMasterTestListPut(
  putReq('/api/v1/masters/test-list', { mac: MASTER, m3u: LIST_F1, gateway_base: 'https://tv.mondomaine.com' }), env));
assert.equal(r.status, 400);
assert.equal(r.body.error, 'bad_facade');
assert.ok(/EXEMPLE/i.test(r.body.message));
ok('façade mondomaine.com REFUSÉE à l’enregistrement (message clair)');

// =========================================================
//  2) TEST À A PAR MAC, À B PAR CODE
// =========================================================
r = await asJson(await handleMasterTestGrant(
  jsonReq('/api/v1/masters/test-grant', { master_mac: MASTER, guest_mac: MAC_A, hours: 24 }), env, ACTOR));
assert.equal(r.status, 200);
const codeA = r.body.code;
assert.ok(r.body.guest_until > Date.now());
ok('test 24 h attribué à A par MAC (licence + liste poussées)');

r = await asJson(await handleMasterTestCode(
  jsonReq('/api/v1/masters/test-code', { master_mac: MASTER, hours: 5 }), env, ACTOR));
assert.equal(r.status, 200);
const codeB = r.body.code;
assert.match(codeB, /^\d{6}$/);
ok('code 6 chiffres généré pour B (valable 48 h)');

// B « tape son code dans l'app » : le redeem assigne la source de test via
// copyMasterSourceForTest (la décision pure du redeem est déjà verrouillée
// par invite_master.smoke.mjs) + le registre est marqué consommé.
assert.equal(await copyMasterSourceForTest(env, MASTER, MAC_B, ORIGIN), true);
{
  const iv = env.DB._tables.app_invites.find((x) => x.code === codeB);
  iv.redeemer_mac = MAC_B; iv.redeemed_at = Date.now();
  iv.guest_until = Date.now() + 5 * 3600 * 1000;
}
ok('B consomme son code → liste de test assignée par référence opaque');

// =========================================================
//  3) SIMULATEUR : A et B reçoivent la liste, 1re chaîne JOIGNABLE (green)
// =========================================================
async function simulate(mac) {
  const resp = await handleMasterSimulate(getReq('/api/v1/masters/simulate?mac=' + encodeURIComponent(mac)), env);
  return (await asJson(resp)).body;
}
const simA = await simulate(MAC_A);
const simB = await simulate(MAC_B);
for (const [label, sim] of [['A', simA], ['B', simB]]) {
  assert.equal(sim.has_source, true, label + ' doit avoir une source');
  assert.equal(sim.kind, 'curated', label + ' doit recevoir la liste curée');
  assert.equal(sim.list_count, 2, label + ' doit voir 2 chaînes');
  assert.equal(sim.verdict, 'green', label + ' doit être GREEN : ' + JSON.stringify(sim.checks));
  assert.ok(!/mondomaine/i.test(JSON.stringify(sim)), label + ' ne doit jamais voir mondomaine');
  assert.equal(sim.host, 'f2.gw.tld2', label + ' lit via la façade COURANTE (F2)');
}
ok('A (par MAC) et B (par code) reçoivent la liste opaque — 1re chaîne SONDÉE green, via F2');

// La sonde « Chaîne jouable » NOMME l'hôte de lecture dans son détail.
const playA = simA.checks.find((c) => c.key === 'play');
assert.ok(playA && playA.detail.includes('f2.gw.tld2'));
ok('le contrôle « Chaîne jouable » nomme l’hôte réellement sondé');

// =========================================================
//  4) SONDE PARALLÈLE (les « 2 téléphones » lisent AU MÊME INSTANT) +
//     MUTUALISATION (même chaîne = même URL = 1 connexion fournisseur)
// =========================================================
async function firstStreamUrl(mac) {
  const src = env.DB._tables.device_sources.find((x) => x.mac === mac);
  const items = JSON.parse(src.sources_json);
  const m3uResp = await fetch(items[0].m3u_url);
  const text = await m3uResp.text();
  return text.split(/\r?\n/).find((l) => l.trim() && !l.startsWith('#')).trim();
}
const urlA = await firstStreamUrl(MAC_A);
const urlB = await firstStreamUrl(MAC_B);
assert.equal(urlA, urlB);
ok('MUTUALISATION : A et B sur la même chaîne → MÊME URL → 1 seule connexion fournisseur (gateway)');

probeLog.length = 0; maxInFlight = 0;
const t0 = Date.now();
const [pa, pb] = await Promise.all([fetch(urlA), fetch(urlB)]);
assert.equal(pa.status, 200);
assert.equal(pb.status, 200);
assert.ok(maxInFlight >= 2, 'les 2 sondes doivent être réellement simultanées');
for (const p of probeLog) {
  assert.equal(p.host, 'f2.gw.tld2');
  console.log(`    [sonde parallèle] hôte=${p.host} statut=${p.status} latence=${p.ms}ms`);
}
console.log(`    [sonde parallèle] 2 flux verts en ${Date.now() - t0}ms (simultanés, octets reçus)`);
ok('SONDE PARALLÈLE : les 2 testeurs lisent EN MÊME TEMPS (HTTP 200 + octets), journal hôte/statut/latence');

// =========================================================
//  5) LISTE HÉRITÉE « mondomaine » → simulateur ROUGE qui NOMME l'hôte,
//     puis réparation par ré-enregistrement avec une vraie façade
// =========================================================
const M2 = 'MK:22:22:22:22:22';
const MAC_C = 'MK:CC:CC:CC:CC:03';
env.DB._tables.app_masters.push({ mac: M2, note: 'legacy', created_at: 1 });
// Données HÉRITÉES (enregistrées avant le verrou) : façade ET URLs mondomaine.
env.DB._tables.master_test_list.push({
  mac: M2,
  m3u: '#EXTM3U\n#EXTINF:-1,Ch\nhttps://tv.mondomaine.com/live/u/p/9.ts',
  gateway_base: 'https://tv.mondomaine.com', gateway_user: null, gateway_pass: null, updated_at: 1,
});
r = await asJson(await handleMasterTestGrant(
  jsonReq('/api/v1/masters/test-grant', { master_mac: M2, guest_mac: MAC_C, hours: 1 }), env, ACTOR));
assert.equal(r.status, 200);
const simC = await simulate(MAC_C);
assert.equal(simC.verdict, 'red');
const playC = simC.checks.find((c) => c.key === 'play');
assert.ok(/mondomaine/i.test(playC.detail) || /EXEMPLE/i.test(playC.detail));
const hostC = simC.checks.find((c) => c.key === 'host');
assert.ok(/tv\.mondomaine\.com/.test(hostC.detail));
ok('liste héritée mondomaine → verdict ROUGE, hôte fautif NOMMÉ, cause + geste expliqués');

// Réparation : le maître pose sa VRAIE façade et ré-enregistre — les URLs
// d'exemple sont reconstruites, le test de C redevient vert AU SERVICE même.
const legacyRow = env.DB._tables.master_test_list.find((x) => x.mac === M2);
r = await asJson(await handleMasterTestListPut(
  putReq('/api/v1/masters/test-list', { mac: M2, m3u: legacyRow.m3u, gateway_base: F2 }), env));
assert.equal(r.status, 200);
assert.equal(r.body.rebuilt, 1);
const simC2 = await simulate(MAC_C);
assert.equal(simC2.verdict, 'green');
assert.equal(simC2.host, 'f2.gw.tld2');
ok('vraie façade posée + ré-enregistrement → URLs reconstruites, C repasse GREEN');

// =========================================================
//  6) FAÇADE VIDE → lecture DIRECTE fournisseur, joignable
// =========================================================
const M3 = 'MK:33:33:33:33:33';
const MAC_D = 'MK:DD:DD:DD:DD:04';
env.DB._tables.app_masters.push({ mac: M3, note: null, created_at: 1 });
r = await asJson(await handleMasterTestListPut(
  putReq('/api/v1/masters/test-list', {
    mac: M3,
    m3u: '#EXTM3U\n#EXTINF:-1,Direct\nhttp://fournisseur.tld9:8080/live/ju/jp/1.ts',
    gateway_base: '',
  }), env));
assert.equal(r.status, 200);
r = await asJson(await handleMasterTestGrant(
  jsonReq('/api/v1/masters/test-grant', { master_mac: M3, guest_mac: MAC_D, hours: 1 }), env, ACTOR));
assert.equal(r.status, 200);
const simD = await simulate(MAC_D);
assert.equal(simD.verdict, 'green');
assert.equal(simD.host, 'fournisseur.tld9:8080');
ok('façade VIDE → URLs direct fournisseur servies telles quelles, sonde green');

// =========================================================
//  7) LISTE VIDÉE → repli BOUQUET COMPLET
// =========================================================
const M4 = 'MK:44:44:44:44:44';
const MAC_E = 'MK:EE:EE:EE:EE:05';
env.DB._tables.app_masters.push({ mac: M4, note: null, created_at: 1 });
env.DB._tables.device_sources.push({
  mac: M4, type: 'xtream', label: 'Ligne 4', server_url: 'http://fournisseur.tld9:8080',
  username: 'u4', password: 'p4', m3u_url: null, epg_url: null, sources_json: null,
  origin: 'panel', updated_at: 1,
});
r = await asJson(await handleMasterTestGrant(
  jsonReq('/api/v1/masters/test-grant', { master_mac: M4, guest_mac: MAC_E, hours: 1 }), env, ACTOR));
assert.equal(r.status, 200);
const simE = await simulate(MAC_E);
assert.equal(simE.kind, 'bouquet');
assert.equal(simE.verdict, 'green');
ok('AUCUNE liste curée → repli bouquet complet servi (kind bouquet, joignable)');

// =========================================================
//  8) INVISIBILITÉ : maître + testeurs HORS stats clients
// =========================================================
const NOW = Date.now();
await recordPresence(env, MASTER, '1.2.3.4', 'FR', NOW, 'Foot 1'); // maître
await recordPresence(env, MAC_A, '5.6.7.8', 'BE', NOW, 'Foot 1');  // testeur actif
await recordPresence(env, MAC_B, '9.9.9.9', 'MA', NOW, 'Foot 2');  // testeur actif
await recordPresence(env, 'MK:0F:0F:0F:0F:0F', '2.2.2.2', 'FR', NOW, 'Ciné'); // vrai client
const clientRows = env.DB._tables.presence || [];
const adminRows = env.DB._tables.admin_presence || [];
assert.ok(!clientRows.some((p) => [MASTER, MAC_A, MAC_B].includes(p.mac)),
  'maître/testeurs ne doivent JAMAIS être dans presence (stats clients)');
assert.ok(clientRows.some((p) => p.mac === 'MK:0F:0F:0F:0F:0F'), 'le vrai client, lui, y est');
assert.ok([MASTER, MAC_A, MAC_B].every((m) => adminRows.some((p) => p.mac === m)));
ok('INVISIBILITÉ : maître + A + B détournés vers admin_presence, le client normal reste en stats');

// Admin Monitoring : kind 'master' pour le maître, 'test' pour les testeurs.
r = await asJson(await handleAdminMonitorGet(env));
const kinds = Object.fromEntries(r.body.items.map((it) => [it.mac, it.kind]));
assert.equal(kinds[MASTER], 'master');
assert.equal(kinds[MAC_A], 'test');
assert.equal(kinds[MAC_B], 'test');
ok('Admin Monitoring : kind=master pour le maître, kind=test pour A et B');

// =========================================================
//  9) PROLONGER / RÉVOQUER
// =========================================================
const beforeExtend = env.DB._tables.app_invites.find((x) => x.code === codeA).guest_until;
r = await asJson(await handleMasterTestExtend(
  jsonReq('/api/v1/masters/test-extend', { code: codeA, hours: 24 }), env, ACTOR));
assert.equal(r.status, 200);
assert.ok(r.body.guest_until > beforeExtend);
ok('PROLONGER : l’échéance du test de A avance bien (+24 h)');

r = await asJson(await handleMasterTestRevoke(
  jsonReq('/api/v1/masters/test-revoke', { code: codeA }), env, ACTOR));
assert.equal(r.status, 200);
const devA = env.DB._tables.devices.find((d) => d.mac === MAC_A);
const licA = env.DB._tables.licenses.find((l) => l.device_id === devA.id);
assert.equal(licA.status, 'expired');
assert.ok(licA.expires_at <= Date.now());
ok('RÉVOQUER : la licence de A expire immédiatement (accès coupé)');

// Aucune requête SQL n'est passée à travers l'interpréteur sans être comprise
// dans les chemins critiques ? On les liste pour information (jamais bloquant).
if (env.DB._unknown.length) {
  console.log('  (requêtes SQL non interprétées, réponses vides best-effort :', env.DB._unknown.length + ')');
}

console.log(`\n${n} assertions OK — parcours maître BOUT-EN-BOUT validé (A par MAC, B par code, sonde parallèle, invisibilité, prolonger/révoquer).`);
