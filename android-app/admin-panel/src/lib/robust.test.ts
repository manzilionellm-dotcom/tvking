// =========================================================
//  robust.test.ts — défauts du panel, reproduits sans navigateur
// =========================================================
//    node --experimental-strip-types --test src/lib/robust.test.ts
//  (lancé depuis admin-panel/)
// =========================================================
import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  agoLabel,
  calendarDaysUntil,
  createGeneration,
  createSingleFlight,
  expiryPhrase,
  flagEmoji,
  formatDateTime,
  interpretHttpResult,
  listQuery,
  onlineView,
  readListPage,
  referenceMatches,
  serializeBackup,
  toEpochMs,
} from './robust.ts';

const noonUtc = Date.UTC(2026, 5, 15, 12, 0, 0); // 15 juin 2026 12:00 UTC = 14:00 Paris

test('formatDateTime affiche Paris, pas le fuseau de la machine', () => {
  const label = formatDateTime(noonUtc);
  assert.match(label, /14:00/);
  assert.match(label, /2026/);
  assert.equal(formatDateTime(Math.floor(noonUtc / 1000)), label);
  assert.equal(formatDateTime(null), '—');
  assert.equal(formatDateTime(0), '—');
  assert.equal(formatDateTime('pas-une-date'), '—');
});

test('jours restants : meme jour civil a Paris, pas un ceil sur 86400000', () => {
  // 3 oct 2026 22:30 UTC = 4 oct 00:30 Paris
  // 4 oct 2026 00:30 UTC = 4 oct 02:30 Paris
  const now = Date.UTC(2026, 9, 3, 22, 30, 0);
  const exp = Date.UTC(2026, 9, 4, 0, 30, 0);
  const rawCeil = Math.ceil((exp - now) / 86400000);
  assert.equal(rawCeil, 1);
  assert.equal(calendarDaysUntil(exp, now), 0);
  assert.match(expiryPhrase(exp, now), /aujourd'hui/);
  assert.equal(expiryPhrase(null, now), 'À vie');
});

test('flagEmoji ne fabrique pas un caractere pour un pays inconnu', () => {
  assert.equal(flagEmoji('??'), '🏳️');
  assert.equal(flagEmoji(''), '🏳️');
  assert.equal(flagEmoji('12'), '🏳️');
  assert.equal(flagEmoji('fr'), '🇫🇷');
});

test('agoLabel comprend une date en secondes', () => {
  const now = Date.UTC(2026, 5, 15, 12, 0, 0);
  assert.equal(agoLabel(Math.floor(now / 1000) - 30, now), 'il y a 30s');
  assert.equal(agoLabel(0, now), '—');
});

test('readListPage survit a un corps vide et tronque 3000 lignes', () => {
  const empty = readListPage(null);
  assert.deepEqual(empty.items, []);
  assert.equal(empty.total, 0);
  const huge = readListPage({
    items: Array.from({ length: 3000 }, (_, i) => ({ id: i })),
    total: 3000,
  });
  assert.equal(huge.items.length, 200);
  assert.equal(huge.dropped, 2800);
  assert.equal(huge.truncated, true);
  assert.equal(huge.total, 3000);
  const missing = readListPage({ ok: true });
  assert.deepEqual(missing.items, []);
});

test('onlineView ne jette pas si byCountry ou items manquent', () => {
  const view = onlineView({ onlineCount: 3 });
  assert.equal(view.onlineCount, 3);
  assert.deepEqual(view.items, []);
  assert.deepEqual(view.byCountry, []);
  const mixed = onlineView({
    byCountry: { '??': 4, FR: 2, '12': 1 },
    items: [{ mac: 'MK:AA:BB:CC:DD:EE', country: '' }, null],
  });
  assert.deepEqual(mixed.byCountry, [['FR', 2]]);
  assert.equal(mixed.items[0].country, '');
  assert.equal(mixed.items[1].mac, '');
  assert.doesNotThrow(() => onlineView(null));
});

test('referenceMatches tolere une ligne incomplete', () => {
  assert.equal(referenceMatches({ mac: null }, 'aa'), false);
  assert.equal(referenceMatches({ mac: 'MK:AA:BB:CC:DD:EE', usernames: undefined, servers: null }, 'aa'), true);
  assert.doesNotThrow(() => referenceMatches(null, 'x'));
});

test('interpretHttpResult : 200 vide ou HTML n est pas un succes', () => {
  const empty = interpretHttpResult(200, '');
  assert.equal(empty.ok, false);
  assert.equal(empty.code, 'bad_response');
  const html = interpretHttpResult(200, '<html>cloudflare</html>');
  assert.equal(html.ok, false);
  const err = interpretHttpResult(502, 'upstream');
  assert.equal(err.ok, false);
  assert.match(err.message, /HTTP 502/);
  const auth = interpretHttpResult(401, '{"error":"bad_token","message":"Invalid"}');
  assert.equal(auth.clearToken, true);
  assert.equal(auth.message, 'Invalid');
  const ok = interpretHttpResult(200, '{"items":[]}');
  assert.equal(ok.ok, true);
});

test('generation : une reponse tardive est perimee', () => {
  const g = createGeneration();
  const first = g.next();
  const second = g.next();
  assert.equal(g.isCurrent(first), false);
  assert.equal(g.isCurrent(second), true);
});

test('singleFlight ignore le double-clic', async () => {
  const gate = createSingleFlight();
  let calls = 0;
  const slow = gate.run(async () => {
    calls += 1;
    await new Promise((r) => setTimeout(r, 30));
    return 'ok';
  });
  const dup = gate.run(async () => {
    calls += 1;
    return 'non';
  });
  const [a, b] = await Promise.all([slow, dup]);
  assert.equal(calls, 1);
  assert.equal(a, 'ok');
  assert.equal(b, undefined);
  assert.equal(gate.pending, false);
});

test('listQuery encode la page sans poser de secret', () => {
  assert.equal(
    listQuery('/api/v1/devices', 'MK:AA', { limit: 100, offset: 200 }),
    '/api/v1/devices?q=MK%3AAA&limit=100&offset=200',
  );
});

test('serializeBackup reste compact', () => {
  const raw = serializeBackup({ tables: { devices: [{ id: 'd1' }, { id: 'd2' }] } });
  assert.equal(raw.includes('\n'), false);
  assert.equal(toEpochMs('1710000000000'), 1710000000000);
});
