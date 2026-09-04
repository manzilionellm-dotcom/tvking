// =========================================================
//  family_multi_mac.smoke.mjs — Ligne M3U unique (multi-MAC)
// =========================================================
//  Vérifie les helpers purs + le contrat toggle OFF = pas d'intercept
//  (zéro régression sur le 302 actuel). Aucun réseau réel.
//
//    node cloudflare/family_multi_mac.smoke.mjs
// =========================================================
import assert from 'node:assert/strict';
import {
  parseBulkMacs,
  normalizeFamilyMac,
  MULTI_MAC_MAX,
  interceptFamilyProfile,
  isMultiMacEnabled,
  sharedM3uSource,
  parseFamilySource,
  upstreamM3uUrlFromSource,
  earliestTokenExpiryMs,
  isUpstreamCacheFresh,
  refreshUpstreamIfExpired,
  buildMultiMacM3u,
  enableSharedM3uLine,
  rewriteM3uThroughProxy,
  familyStreamUpstreamUrl,
  sharedUpstreamFetch,
  _clearSharedUpstream,
  _sharedUpstreamOpens,
  familyMediaShareKey,
  m3uFromLiveStreams,
  UPSTREAM_TTL_MS,
  _clearUpstreamCache,
  _cacheGet,
} from './family_multi_mac.js';

let n = 0;
const ok = (m) => { n++; console.log('  ✓', m); };

// --- parseBulkMacs / normalizeFamilyMac --------------------------------

assert.equal(normalizeFamilyMac('mk:aa:bb:cc:dd:ee'), 'MK:AA:BB:CC:DD:EE');
assert.equal(normalizeFamilyMac('AA:BB:CC:DD:EE'), 'MK:AA:BB:CC:DD:EE');
assert.equal(normalizeFamilyMac('aabbccddee'), 'MK:AA:BB:CC:DD:EE');
assert.equal(normalizeFamilyMac('AA-BB-CC-DD-EE'), 'MK:AA:BB:CC:DD:EE');
assert.equal(normalizeFamilyMac('AA:BB:CC:DD:EE:FF'), null); // 6 octets ≠ format MK
assert.equal(normalizeFamilyMac('pas-une-mac'), null);
assert.equal(normalizeFamilyMac(''), null);
ok('normalizeFamilyMac : MK / sans préfixe / sans deux-points / tirets');

let p = parseBulkMacs('MK:AA:BB:CC:DD:01, MK:AA:BB:CC:DD:02');
assert.equal(p.ok, true);
assert.deepEqual(p.macs, ['MK:AA:BB:CC:DD:01', 'MK:AA:BB:CC:DD:02']);
ok('CSV virgules → 2 MAC');

p = parseBulkMacs('MK:AA:BB:CC:DD:01\nMK:AA:BB:CC:DD:02; aabbccddee');
assert.equal(p.ok, true);
assert.equal(p.macs.length, 3);
assert.equal(p.macs[2], 'MK:AA:BB:CC:DD:EE');
ok('séparateurs mixtes (newline, point-virgule, hex nu)');

p = parseBulkMacs('MK:AA:BB:CC:DD:01, MK:AA:BB:CC:DD:01, mk:aa:bb:cc:dd:01');
assert.equal(p.ok, true);
assert.equal(p.macs.length, 1);
ok('déduplication (casse + doublons)');

p = parseBulkMacs('');
assert.equal(p.ok, true);
assert.deepEqual(p.macs, []);
ok('CSV vide → ok (toggle sans nouvelles MAC)');

p = parseBulkMacs('nimp, MK:AA:BB:CC:DD:01');
assert.equal(p.ok, false);
assert.equal(p.error, 'bad_mac');
ok('MAC invalide dans le CSV → bad_mac');

const tooMany = Array.from({ length: MULTI_MAC_MAX + 1 }, (_, i) => {
  const h = (i + 1).toString(16).padStart(2, '0').toUpperCase();
  return `MK:AA:BB:CC:DD:${h}`;
}).join(', ');
p = parseBulkMacs(tooMany);
assert.equal(p.ok, false);
assert.equal(p.error, 'too_many_macs');
ok(`plafond ${MULTI_MAC_MAX} MAC`);

// --- interceptFamilyProfile : OFF = zéro régression --------------------

assert.equal(isMultiMacEnabled(null), false);
assert.equal(isMultiMacEnabled({}), false);
assert.equal(isMultiMacEnabled({ multi_mac_enabled: 0 }), false);
assert.equal(isMultiMacEnabled({ multi_mac_enabled: '0' }), false);
assert.equal(isMultiMacEnabled({ multi_mac_enabled: 1 }), true);
ok('isMultiMacEnabled : seule la valeur 1 allume');

const famOff = { id: 'fam_1', multi_mac_enabled: 0 };
const famOn = { id: 'fam_1', multi_mac_enabled: 1 };
const reqM3u = { url: 'https://app.example/api/m3u/abc123' };
const reqOther = { url: 'https://app.example/api/backup/MK:AA:BB:CC:DD:EE' };
const reqPlayer = { url: 'https://gw.example/player_api.php?username=a' };

assert.equal(interceptFamilyProfile(reqM3u, famOff).intercept, false);
assert.equal(interceptFamilyProfile(reqM3u, famOff).reason, 'toggle_off');
assert.equal(interceptFamilyProfile(reqM3u, null).intercept, false);
assert.equal(interceptFamilyProfile(reqM3u, {}).intercept, false);
ok('OFF / colonnes absentes → pas d\'intercept (302 actuel conservé)');

assert.equal(interceptFamilyProfile(reqM3u, famOn).intercept, true);
assert.equal(interceptFamilyProfile(reqM3u, famOn).reason, 'family_m3u');
assert.equal(interceptFamilyProfile(null, famOn).intercept, true);
assert.equal(interceptFamilyProfile(reqPlayer, famOn).intercept, true);
assert.equal(interceptFamilyProfile(reqOther, famOn).reason, 'not_profile_route');
assert.equal(interceptFamilyProfile(reqOther, famOn).intercept, false);
ok('ON + /api/m3u ou player_api → intercept ; autre route → non');

// --- sharedM3uSource : PAS get.php direct ------------------------------

const src = sharedM3uSource('https://app.example/', 'tok123', 'Famille K');
assert.equal(src.type, 'm3u');
assert.equal(src.m3u_url, 'https://app.example/api/m3u/tok123');
assert.equal(src.username, null);
assert.equal(src.password, null);
assert.ok(!/get\.php/i.test(src.m3u_url));
ok('sharedM3uSource pointe vers /api/m3u/{token}, jamais get.php');

const xt = parseFamilySource('{"type":"xtream","server_url":"http://s.tv:80","username":"u","password":"p"}');
assert.equal(xt.type, 'xtream');
assert.equal(
  upstreamM3uUrlFromSource(xt),
  'http://s.tv:80/get.php?username=u&password=p&type=m3u_plus&output=ts',
);
ok('upstream Xtream → UN get.php (une session amont)');

assert.equal(
  upstreamM3uUrlFromSource({ type: 'm3u', m3u_url: 'http://cdn/list.m3u' }),
  'http://cdn/list.m3u',
);
ok('upstream M3U → URL telle quelle');

// --- tokens expirés ----------------------------------------------------

const now = 1_700_000_000_000;
const m3uFresh = '#EXTM3U\n#EXTINF:-1,A\nhttp://cdn/live.ts?token=abc&expires=' + Math.floor((now + 3600_000) / 1000);
const m3uStale = '#EXTM3U\n#EXTINF:-1,A\nhttp://cdn/live.ts?exp=' + Math.floor((now - 10_000) / 1000);
assert.ok(earliestTokenExpiryMs(m3uFresh) > now);
assert.ok(earliestTokenExpiryMs(m3uStale) < now);
assert.equal(earliestTokenExpiryMs('#EXTM3U\nhttp://s/live/u/p/1.ts'), null);
ok('earliestTokenExpiryMs : token futur / expiré / absent');

assert.equal(isUpstreamCacheFresh({ m3u: 'x', fetchedAt: now, expiresAt: now + 60_000 }, now), true);
assert.equal(isUpstreamCacheFresh({ m3u: 'x', fetchedAt: now - UPSTREAM_TTL_MS - 1, expiresAt: now + 99_000 }, now), false);
assert.equal(isUpstreamCacheFresh({ m3u: 'x', fetchedAt: now, expiresAt: now }, now), false);
ok('cache : frais / TTL dépassé / token à l\'échéance → refetch');

// --- refreshUpstreamIfExpired (fetch injecté) --------------------------

let fetches = 0;
const playlist = '#EXTM3U\n#EXTINF:-1,Demo\nhttp://cdn/a.ts\n';
const fakeFetch = async (url) => {
  fetches += 1;
  return {
    ok: true,
    status: 200,
    text: async () => playlist,
    url,
  };
};

_clearUpstreamCache();
let r = await refreshUpstreamIfExpired(
  { type: 'xtream', server_url: 'http://s', username: 'u', password: 'p' },
  null,
  now,
  fakeFetch,
);
assert.equal(r.refreshed, true);
assert.equal(r.m3u, playlist);
assert.equal(fetches, 1);
ok('pas de cache → fetch amont');

r = await refreshUpstreamIfExpired(
  { type: 'xtream', server_url: 'http://s', username: 'u', password: 'p' },
  { m3u: playlist, fetchedAt: now, expiresAt: now + UPSTREAM_TTL_MS },
  now + 1000,
  fakeFetch,
);
assert.equal(r.refreshed, false);
assert.equal(fetches, 1);
ok('cache frais → pas de refetch');

fetches = 0;
r = await refreshUpstreamIfExpired(
  { type: 'm3u', m3u_url: 'http://cdn/list.m3u' },
  { m3u: 'OLD', fetchedAt: now - UPSTREAM_TTL_MS - 5, expiresAt: now - 1 },
  now,
  fakeFetch,
);
assert.equal(r.refreshed, true);
assert.equal(r.m3u, playlist);
assert.equal(fetches, 1);
ok('cache périmé → refetch automatique');

fetches = 0;
const boom = async () => { fetches += 1; throw new Error('network'); };
r = await refreshUpstreamIfExpired(
  { type: 'm3u', m3u_url: 'http://cdn/list.m3u' },
  { m3u: 'STALE_OK', fetchedAt: 1, expiresAt: 1 },
  now,
  boom,
);
assert.equal(r.m3u, 'STALE_OK');
assert.equal(r.stale, true);
ok('amont down + cache → on sert le stale (pas de 502)');

// --- buildMultiMacM3u : une session, cache par famille -----------------

_clearUpstreamCache();
fetches = 0;
const fam = {
  id: 'fam_x',
  source_json: JSON.stringify({
    type: 'xtream', server_url: 'http://s.tv', username: 'u', password: 'p',
  }),
};
const b1 = await buildMultiMacM3u(null, fam, { now, fetchFn: fakeFetch });
const b2 = await buildMultiMacM3u(null, fam, { now: now + 500, fetchFn: fakeFetch });
assert.equal(b1.m3u, playlist);
assert.equal(b2.m3u, playlist);
assert.equal(fetches, 1);
assert.ok(_cacheGet('fam_x'));
ok('buildMultiMacM3u : 2 lectures = 1 fetch amont (session unique)');

// --- enableSharedM3uLine : OFF n'active rien / ON pousse le M3U partagé

function fakeDb(store) {
  return {
    prepare(sql) {
      const q = String(sql);
      const exec = {
        async first() {
          if (/SELECT \* FROM families/.test(q) || /SELECT id, reseller_id/.test(q)) {
            return store.family || null;
          }
          if (/SELECT token FROM family_links/.test(q)) {
            return store.token ? { token: store.token } : null;
          }
          return null;
        },
        async all() {
          if (/family_members/.test(q)) {
            return { results: store.members || [] };
          }
          return { results: [] };
        },
        async run(...args) {
          // D1 : prepare().bind(a,b).run() OU prepare().run() (ALTER sans params).
          const a = args.length ? args : (this._binds || []);
          if (/UPDATE families/.test(q)) {
            store.family = {
              ...(store.family || {}),
              multi_mac_enabled: a[0],
              multi_macs: a[1],
            };
          }
          if (/INSERT INTO family_links/.test(q)) {
            store.token = a[2];
          }
          return { success: true };
        },
      };
      return {
        bind(...args) {
          exec._binds = args;
          return exec;
        },
        first: () => exec.first(),
        all: () => exec.all(),
        run: () => exec.run(),
      };
    },
  };
}

const pushed = [];
const activated = [];
const envOff = { DB: fakeDb({ family: { id: 'fam_1', name: 'K', source_json: '{}' } }) };
const off = await enableSharedM3uLine(envOff, {
  familyId: 'fam_1',
  macCsv: 'MK:AA:BB:CC:DD:01, MK:AA:BB:CC:DD:02',
  multiMacEnabled: false,
  origin: 'https://app.example',
  deps: {
    upsertDeviceSource: async (_e, mac, sources) => { pushed.push({ mac, sources }); },
    activateMember: async (mac) => { activated.push(mac); return { status: 201 }; },
    genId: (p) => `${p}_test`,
  },
});
assert.equal(off.ok, true);
assert.equal(off.multi_mac_enabled, false);
assert.equal(off.token, null);
assert.equal(pushed.length, 0);
assert.equal(activated.length, 0);
ok('toggle OFF → persist le flag, n\'active aucune MAC, n\'écrase aucune source');

pushed.length = 0;
activated.length = 0;
const storeOn = {
  family: { id: 'fam_1', name: 'K', source_json: '{}' },
  members: [{ mac: 'MK:11:22:33:44:55' }],
  token: null,
};
const envOn = { DB: fakeDb(storeOn) };
const on = await enableSharedM3uLine(envOn, {
  familyId: 'fam_1',
  macCsv: 'MK:AA:BB:CC:DD:01',
  multiMacEnabled: true,
  origin: 'https://app.example',
  deps: {
    upsertDeviceSource: async (_e, mac, sources) => { pushed.push({ mac, sources }); },
    activateMember: async (mac) => { activated.push(mac); return { status: 201 }; },
    genId: (p) => `${p}_test`,
  },
});
assert.equal(on.ok, true);
assert.equal(on.multi_mac_enabled, true);
assert.ok(on.token);
assert.ok(on.m3u_url.endsWith('/api/m3u/' + on.token));
assert.ok(!/get\.php/i.test(on.m3u_url));
assert.deepEqual(activated, ['MK:AA:BB:CC:DD:01']);
// CSV + membre déjà là → 2 upsert vers le M3U partagé
assert.equal(pushed.length, 2);
assert.equal(pushed[0].sources[0].type, 'm3u');
assert.ok(pushed[0].sources[0].m3u_url.includes('/api/m3u/'));
ok('toggle ON → activateMember (chemin existant) + source = /api/m3u/{token}');

// --- Réécriture proxy : plus d'hôte fournisseur dans le M3U ON -------------

const PROVIDER = 'tv.business-cloud-8.ru';
const rawProv =
  '#EXTM3U\n' +
  '#EXTINF:-1,A\n' +
  `http://${PROVIDER}:80/live/u/p/101.ts\n` +
  '#EXTINF:-1,B\n' +
  `http://${PROVIDER}:80/live/u/p/202.m3u8\n`;

const rwWorker = rewriteM3uThroughProxy(rawProv, {
  proxyBase: 'https://app.example',
  token: 'tokabc',
  mode: 'worker',
});
assert.ok(!rwWorker.includes(PROVIDER), 'hôte fournisseur absent (mode worker)');
assert.ok(rwWorker.includes('https://app.example/api/m3u/tokabc/live/101.ts'));
assert.ok(rwWorker.includes('https://app.example/api/m3u/tokabc/live/202.m3u8'));
assert.ok(!/\/live\/u\/p\//.test(rwWorker), 'creds fournisseur absents des chemins');
ok('rewrite worker : URLs sur notre hôte /api/m3u/{token}/live/…');

const rwGw = rewriteM3uThroughProxy(rawProv, {
  proxyBase: 'https://gw.example',
  token: 'aabbccddeeff00112233445566778899',
  mode: 'gateway',
});
assert.ok(!rwGw.includes(PROVIDER), 'hôte fournisseur absent (mode gateway)');
assert.ok(rwGw.includes('https://gw.example/live/aabbccddeeff00112233445566778899/aabbccddeeff00112233445566778899/101.ts'));
ok('rewrite gateway : /live/{token}/{token}/{id}.ts (parseStreamPath + hub)');

const up = familyStreamUpstreamUrl(
  { type: 'xtream', server_url: `http://${PROVIDER}`, username: 'u', password: 'p' },
  'live', '101', 'ts',
);
assert.equal(up, `http://${PROVIDER}/live/u/p/101.ts`);
ok('familyStreamUpstreamUrl reconstruit le live amont (côté proxy seulement)');

const synth = m3uFromLiveStreams(
  [{ stream_id: 7, name: 'Demo' }],
  { server_url: `http://${PROVIDER}`, username: 'u', password: 'p' },
);
assert.ok(synth.includes('#EXTM3U'));
assert.ok(synth.includes(`/live/u/p/7.ts`));
ok('m3uFromLiveStreams : repli player_api → M3U (ensuite réécrit)');

_clearUpstreamCache();
const famProv = {
  id: 'fam_proxy',
  source_json: JSON.stringify({
    type: 'xtream',
    server_url: `http://${PROVIDER}`,
    username: 'u',
    password: 'p',
  }),
};
const fakeProvM3u = async () => ({
  ok: true, status: 200, text: async () => rawProv,
});
const builtOn = await buildMultiMacM3u(null, famProv, {
  now: Date.now(),
  fetchFn: fakeProvM3u,
  token: 'tokabc',
  proxyBase: 'https://app.example',
  proxyMode: 'worker',
});
assert.ok(!builtOn.m3u.includes(PROVIDER), 'M3U servi : pas d\'hôte fournisseur');
assert.ok(builtOn.m3u.includes('https://app.example/api/m3u/tokabc/live/101.ts'));
assert.ok(builtOn.raw.includes(PROVIDER), 'M3U brut amont conservé en cache interne');
ok('buildMultiMacM3u ON + proxyBase → playlist sur notre hôte');

// --- Fan-out segments : N clients concurrents = 1 fetch amont --------------

_clearSharedUpstream();
let segFetches = 0;
const openSeg = async () => {
  segFetches += 1;
  return {
    status: 200,
    headers: { 'content-type': 'video/mp2t', 'content-length': '6' },
    arrayBuffer: async () => new Uint8Array([1, 2, 3, 4, 5, 6]).buffer,
  };
};
const key = familyMediaShareKey('fam_proxy', 'live', '101', 'ts');
const nClients = 8;
const results = await Promise.all(
  Array.from({ length: nClients }, () => sharedUpstreamFetch(key, openSeg)),
);
assert.equal(results.length, nClients);
assert.equal(segFetches, 1, 'N pulls concurrents → 1 openFn');
assert.equal(_sharedUpstreamOpens(key), 1);
assert.ok(results.every((r) => r.status === 200 && r.body && r.body.byteLength === 6));
ok('N requêtes segment concurrentes = 1 fetch amont (fan-out)');

const again = await sharedUpstreamFetch(key, openSeg);
assert.equal(segFetches, 1, 'dans la fenêtre TTL : toujours 1');
assert.equal(again.body.byteLength, 6);
ok('rejeu dans le TTL : toujours 1 fetch amont');

console.log(`\n${n} assertions OK — ligne M3U unique (multi-MAC) validée.`);
