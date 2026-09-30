// Preuve du texte affiché dans le panel, sans navigateur.
//   node --experimental-strip-types src/lib/boxLive.test.ts
import assert from 'node:assert/strict';
import { appliedPhrase, indexByMac, liveSummary } from './boxLive.ts';

const clock = () => '12:03:04';

const applied = liveSummary({
  mac: 'MK:AA:BB:CC:DD:01',
  online: true,
  last_seen_at: 1,
  app_version: '103',
  pending: [],
  last_applied: { id: 4, kind: 'activate', applied_at: 1_700_000_000_000 },
}, clock);
assert.equal(
  applied,
  'en ligne · v103 · appliqué à 12:03:04 · activation',
);

const waiting = liveSummary({
  mac: 'MK:AA:BB:CC:DD:01',
  online: false,
  last_seen_at: 1,
  pending: [{ id: 5, kind: 'suspend' }],
  last_applied: null,
}, clock);
assert.equal(waiting, 'hors ligne · en attente : suspension');

assert.equal(appliedPhrase(0, clock), 'appliqué à 12:03:04');

const indexed = indexByMac([
  { mac: 'MK:AA:BB:CC:DD:01', online: true, last_seen_at: 1 },
  { mac: 'MK:AA:BB:CC:DD:02', online: false, last_seen_at: 2 },
]);
assert.equal(indexed['MK:AA:BB:CC:DD:02'].online, false);
assert.equal(Object.keys(indexed).length, 2);

console.log('PASS panel boxLive');
