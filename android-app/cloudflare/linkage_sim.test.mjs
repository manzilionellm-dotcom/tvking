// Simulation de la liaison panel ↔ app. Aucun secret, aucun flux.
// Exécuter : node --test android-app/cloudflare/linkage_sim.test.mjs
import { createD1 } from './test_support/d1_sqlite.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  ANNOUNCEMENT_PAGE,
  PANEL_POLL_MS,
  PANEL_POLL_MS_BEFORE,
  coerceSourceList,
  heartbeatCreatedFlag,
  heartbeatPresenceVisibility,
  legacyLatestOnly,
  markSourcesCleared,
  readSourceTombstone,
  resolvePublicSource,
  scrubKvPlaylists,
  selectAnnouncements,
  shouldApplyPollResult,
  worstCaseMirrorMs,
} from './linkage.js';

const root = fileURLToPath(new URL('../..', import.meta.url));

function src(rel) {
  return readFileSync(root + '/' + rel, 'utf8');
}

test('présence : waitUntil répond avant l\'écriture (état manquant)', async () => {
  const store = memPresence();
  const deferred = await heartbeatPresenceVisibility(
    store,
    { mac: 'MK:AA:BB:CC:DD:01', channel: 'Info' },
    { defer: true },
  );
  assert.equal(deferred.visibleAtResponse, false);
  assert.equal(deferred.visibleAfterFlush, true);

  const store2 = memPresence();
  const synced = await heartbeatPresenceVisibility(
    store2,
    { mac: 'MK:AA:BB:CC:DD:01', channel: 'Info' },
    { defer: false },
  );
  assert.equal(synced.visibleAtResponse, true);
});

test('panel : 30 s dépasse 2 s, le nouveau sondage tient dans 2 s', () => {
  assert.ok(worstCaseMirrorMs(PANEL_POLL_MS_BEFORE) > 2000);
  assert.equal(worstCaseMirrorMs(PANEL_POLL_MS_BEFORE), 30000);
  assert.ok(worstCaseMirrorMs(PANEL_POLL_MS) <= 2000);
  assert.equal(PANEL_POLL_MS, 2000);
});

test('sondages croisés : une réponse ancienne n\'écrase pas la fraîche', () => {
  let applied = 0;
  const seen = [];
  for (const [seq, label] of [[2, 'frais'], [1, 'périmé']]) {
    if (!shouldApplyPollResult(seq, applied)) continue;
    applied = seq;
    seen.push(label);
  }
  assert.deepEqual(seen, ['frais']);
  assert.equal(shouldApplyPollResult(3, 3), true);
});

test('annonces : l\'ancien « dernière seulement » perd les messages du milieu', () => {
  const now = 1_700_000_000_000;
  const rows = [
    msg(1, 'Un', now),
    msg(2, 'Deux', now),
    msg(3, 'Trois', now),
  ];
  const only = legacyLatestOnly(rows, { now, country: 'FR' });
  assert.equal(only.id, 3);

  const first = selectAnnouncements(rows, { after: 0, now, country: 'FR' });
  assert.deepEqual(first.pending.map((r) => r.id), [1, 2, 3]);
  assert.equal(first.latest.id, 3);

  const cursor = first.pending[first.pending.length - 1].id;
  const again = selectAnnouncements(rows, { after: cursor, now, country: 'FR' });
  assert.deepEqual(again.pending, []);
});

test('annonces : reconnexion, pas de doublon, pays et expiration', () => {
  const now = 1_700_000_000_000;
  const rows = [
    msg(1, 'Global', now),
    msg(2, 'Suède', now, { country: 'SE' }),
    msg(3, 'Expiré', now, { expires_at: now - 1 }),
    msg(4, 'Coupé', now, { active: 0 }),
    msg(2, 'Suède-doublon', now, { country: 'SE' }),
    msg(5, 'Suite', now),
  ];
  const page = selectAnnouncements(rows, { after: 1, now, country: 'FR' });
  assert.deepEqual(page.pending.map((r) => r.id), [5]);
  assert.equal(page.pending.filter((r) => r.id === 5).length, 1);

  const sweden = selectAnnouncements(rows, { after: 0, now, country: 'SE' });
  assert.deepEqual(sweden.pending.map((r) => r.id), [1, 2, 5]);
});

test('annonces : un gros paquet passe en plusieurs lectures sans trou', () => {
  const now = 1_700_000_000_000;
  const rows = [];
  for (let id = 1; id <= ANNOUNCEMENT_PAGE + 10; id++) rows.push(msg(id, 'M' + id, now));
  let after = 0;
  const got = [];
  for (let i = 0; i < 5; i++) {
    const page = selectAnnouncements(rows, { after, now, country: '' });
    if (!page.pending.length) break;
    for (const r of page.pending) got.push(r.id);
    after = page.pending[page.pending.length - 1].id;
  }
  assert.equal(got.length, ANNOUNCEMENT_PAGE + 10);
  assert.deepEqual(got, [...new Set(got)]);
  assert.equal(got[0], 1);
  assert.equal(got[got.length - 1], ANNOUNCEMENT_PAGE + 10);
});

test('effacement : le KV ne ressuscite pas une liste tombstonée', () => {
  const kv = { type: 'm3u', m3u_url: 'https://example.invalid/liste.m3u', label: 'test' };
  const revived = resolvePublicSource({ d1Sources: [], kvSource: kv, clearedAt: 0 });
  assert.equal(revived.from, 'kv');
  const wiped = resolvePublicSource({ d1Sources: [], kvSource: kv, clearedAt: 50 });
  assert.equal(wiped.source, null);
  assert.equal(wiped.cleared, true);
  const reassigned = resolvePublicSource({
    d1Sources: [{ type: 'm3u', m3u_url: 'https://example.invalid/neuf.m3u' }],
    kvSource: kv,
    clearedAt: 50,
  });
  assert.equal(reassigned.from, 'd1');
  assert.equal(reassigned.cleared, false);
});

test('effacement : tombstone D1 + vidage KV', async () => {
  const db = createD1({ schema: false }).DB;
  const kv = memKv({
    'client:MK:AA:BB:CC:DD:02': JSON.stringify({
      playlists: [{ type: 'm3u', url: 'https://example.invalid/old.m3u' }],
      note: 'garder',
    }),
  });
  const env = { DB: db, KV_7MOTION: kv };
  const mac = 'MK:AA:BB:CC:DD:02';
  await markSourcesCleared(env, mac, 99);
  assert.equal(await readSourceTombstone(env, mac), 99);
  const stored = JSON.parse(kv.data.get('client:' + mac));
  assert.deepEqual(stored.playlists, []);
  assert.equal(stored.note, 'garder');
  await scrubKvPlaylists(env, mac);
  assert.deepEqual(JSON.parse(kv.data.get('client:' + mac)).playlists, []);
});

test('activation : un objet source ne doit pas faire planter .map', () => {
  const one = { type: 'm3u', m3u_url: 'https://example.invalid/a.m3u' };
  assert.throws(() => (one || []).map((s) => s.type));
  assert.deepEqual(coerceSourceList(one).map((s) => s.type), ['m3u']);
  assert.equal(coerceSourceList([one, null]).length, 1);
});

test('heartbeat : created seulement à la première fiche', () => {
  assert.equal(heartbeatCreatedFlag(false), true);
  assert.equal(heartbeatCreatedFlag(true), false);
});

test('mesures app : les sondages installés dépassent 2 s (non corrigés ici)', () => {
  const home = src('android-app/lib/features/simple_home/presentation/simple_home_screen.dart');
  const empty = src('android-app/lib/features/channels/presentation/widgets/empty_state.dart');
  const tvAct = src('android-app/lib/features/tv/presentation/tv_activation_screen.dart');
  const tvLive = src('android-app/lib/features/tv/presentation/tv_live_screen.dart');
  const main = src('android-app/lib/main.dart');
  const player = src('android-app/lib/features/player/presentation/video_player_screen.dart');
  const banner = src('android-app/lib/features/simple_home/presentation/widgets/announcement_banner.dart');

  assert.match(home, /Duration\(seconds: 6\)/);
  assert.match(empty, /Duration\(seconds: 6\)/);
  assert.match(tvAct, /Duration\(seconds: 5\)/);
  assert.match(tvLive, /Duration\(seconds: 12\)/);
  assert.match(tvLive, /_kSlowSyncEvery = 25/);
  assert.match(main, /Duration\(hours: 24\)/);
  assert.match(player, /Duration\(minutes: 3\)/);
  assert.doesNotMatch(banner, /Timer\.periodic/);

  const budgets = [
    ['activation téléphone écran vide', 6000],
    ['activation TV écran vide', 12000],
    ['source à chaud TV (25 × 12 s)', 25 * 12000],
    ['re-vérif téléphone avec chaînes', 24 * 3600 * 1000],
    ['keepalive présence', 3 * 60 * 1000],
  ];
  for (const [name, ms] of budgets) {
    assert.ok(ms > 2000, name);
  }
});

test('câblage Worker : présence attendue, annonces en file, tombstone', () => {
  const worker = src('android-app/cloudflare/worker.js');
  const api = src('android-app/cloudflare/api_v1.js');
  assert.match(worker, /await recordPresence\(/);
  assert.doesNotMatch(worker, /defer\(recordPresence/);
  assert.match(worker, /await updateDeviceInfo\(/);
  assert.match(worker, /selectAnnouncements\(/);
  assert.match(worker, /readSourceTombstone\(/);
  assert.match(worker, /resolvePublicSource\(/);
  assert.match(worker, /markSourcesCleared\(/);
  assert.match(api, /coerceSourceList\(/);
  assert.match(api, /markSourcesCleared\(/);
  assert.match(api, /clearSourceTombstone\(/);
  assert.match(worker, /created: !!created/);
});

test('câblage panel : sondage ≤ 2 s et garde d\'ordre', () => {
  const online = src('android-app/admin-panel/src/pages/OnlinePage.tsx');
  const devices = src('android-app/admin-panel/src/pages/DevicesPage.tsx');
  const sync = src('android-app/admin-panel/src/lib/live-sync.ts');
  const channel = src('android-app/admin-panel/src/lib/box-channel.ts');
  assert.match(sync, /export const PANEL_POLL_MS = 2000/);
  assert.match(sync, /shouldApplyPollResult/);
  // Repli sans canal : panelPollInterval rend PANEL_POLL_MS (2 s).
  assert.match(sync, /if \(REALTIME_POLL_LEGACY \|\| !channelUp\) return PANEL_POLL_MS;/);
  assert.match(online, /PANEL_POLL_MS/);
  assert.match(online, /shouldApplyPollResult/);
  assert.doesNotMatch(online, /setInterval\(load,\s*30000\)/);
  // Depuis 516b87f (canal panel → box), la fiche appareil ne sonde plus
  // elle-même : elle passe par bindPanelRefresh, dont le minuteur suit
  // panelPollInterval (≤ 2 s sans canal, plus lent avec canal ouvert).
  // L'ancienne assertion (PANEL_POLL_MS écrit dans DevicesPage) ne
  // correspondait plus au code ; l'invariant « sondage ≤ 2 s sans canal »
  // est vérifié là où il vit.
  assert.match(channel, /export function bindPanelRefresh/);
  assert.match(channel, /panelPollInterval\(panelChannelUp\(\)\)/);
  assert.match(devices, /bindPanelRefresh\(/);
  assert.match(devices, /shouldApplyPollResult/);
  assert.match(devices, /sourcesApi\.clear/);
});

function msg(id, title, now, extra = {}) {
  return {
    id,
    title,
    body: 'corps ' + id,
    url: '',
    kind: 'info',
    cta: '',
    country: '',
    created_at: now,
    expires_at: 0,
    active: 1,
    ...extra,
  };
}

function memPresence() {
  const rows = new Map();
  return {
    async write(event) {
      await new Promise((r) => setTimeout(r, 15));
      rows.set(event.mac, event);
    },
    read(mac) {
      return rows.get(mac) || null;
    },
  };
}

function memKv(initial) {
  const data = new Map(Object.entries(initial || {}));
  return {
    data,
    async get(k) { return data.has(k) ? data.get(k) : null; },
    async put(k, v) { data.set(k, v); },
  };
}
