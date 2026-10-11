import test from 'node:test';
import assert from 'node:assert/strict';
import { campaignState, parseLocalDate, toLocalInput, type Campaign } from './campaigns.ts';

const item = { status: 'scheduled', starts_at: 1000, ends_at: 3000, broadcast_id: null } as Campaign;
test('états honnêtes : début, fin, pause et retrait réel', () => {
  assert.equal(campaignState(item, 999), 'scheduled');
  assert.equal(campaignState(item, 1000), 'ready');
  assert.equal(campaignState(item, 3000), 'ended');
  assert.equal(campaignState({ ...item, status: 'draft' }, 2000), 'draft');
  assert.equal(campaignState({ ...item, status: 'paused' }, 2000), 'paused');
  assert.equal(campaignState({ ...item, broadcast_id: 1, delivery_active: null }, 2000), 'removed');
  assert.equal(campaignState({ ...item, broadcast_id: 1, delivery_active: 1 }, 2000), 'available');
  assert.equal(campaignState({ ...item, broadcast_id: 1, delivery_active: 0 }, 2000), 'paused');
});
test('date locale : aller-retour à la minute et rejet des dates normalisées', () => {
  const expected = new Date(2026, 9, 11, 19, 30).getTime();
  assert.equal(parseLocalDate('2026-10-11T19:30'), expected);
  assert.equal(toLocalInput(expected), '2026-10-11T19:30');
  assert.throws(() => parseLocalDate('2026-02-31T19:30'));
  assert.throws(() => parseLocalDate(''));
});
