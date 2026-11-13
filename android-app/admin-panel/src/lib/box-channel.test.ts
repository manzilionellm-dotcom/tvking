// Canal du panel : délai de sondage et lecture des messages.
// Aucune adresse de flux, aucun mot de passe réel.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { panelPollInterval, PANEL_POLL_MS, PANEL_POLL_SLOW_MS } from './live-sync.ts';
import { isChannelHello, parseChannelEvent } from './box-channel-core.ts';

test('repli coupé : le sondage ralentit quand le canal est ouvert', () => {
  assert.equal(panelPollInterval(false), PANEL_POLL_MS);
  assert.equal(panelPollInterval(true), PANEL_POLL_SLOW_MS);
  assert.equal(PANEL_POLL_MS, 2000);
});

test('les reçus du Worker sans seq, avec ou sans v1, gardent leur ordre exact', () => {
  const receipt = {
    type: 'receipt', mac: 'MK:AA:BB:CC:DD:EE', at: 1234,
    order_id: 'order-current', kind: 'source_clear', state: 'applied',
    config_rev: 12, applied_rev: 12, elapsed_ms: 214,
  };
  for (const raw of [receipt, { v: 1, ...receipt }]) {
    assert.deepEqual(parseChannelEvent(JSON.stringify(raw)), { v: 1, ...receipt });
  }
  assert.equal(parseChannelEvent(JSON.stringify({ ...receipt, order_id: '' })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ ...receipt, kind: '' })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ ...receipt, state: 'unknown' })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ ...receipt, applied_rev: -1 })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ ...receipt, v: 2 })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ ...receipt, nested: { password: 'secret' } })), null);
  const nullable = parseChannelEvent(JSON.stringify({
    ...receipt, state: 'received', applied_rev: null, elapsed_ms: null,
  }));
  assert.equal(nullable?.applied_rev, null);
});

test('les présences sans seq sont acceptées sans inventer de séquence', () => {
  const presence = {
    type: 'presence', mac: 'MK:AA:BB:CC:DD:EE', online: true,
    last_seen_at: 1000, at: 1234,
  };
  assert.deepEqual(parseChannelEvent(JSON.stringify(presence)), { v: 1, ...presence });
  assert.equal(parseChannelEvent(JSON.stringify({ ...presence, online: 'true' })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ ...presence, last_seen_at: -1 })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ ...presence, type: 'other' })), null);
});

test('les anciens signaux séquencés conservent ordre et trace sans accepter les secrets', () => {
  const signal = {
    v: 1, seq: 4, type: 'source', mac: 'MK:AA:BB:CC:DD:EE', at: 10,
    order_id: 'order-current', trace_id: 'trace-current',
  };
  assert.deepEqual(parseChannelEvent(JSON.stringify(signal)), signal);
  for (const secret of ['token', 'ticket', 'authorization', 'device_secret']) {
    assert.equal(parseChannelEvent(JSON.stringify({ ...signal, [secret]: 'private' })), null);
  }
  assert.equal(parseChannelEvent(JSON.stringify({ ...signal, seq: 1.5 })), null);
});

test('seul le hello v1 valide confirme le protocole', () => {
  assert.equal(isChannelHello('{"v":1,"type":"hello"}'), true);
  for (const raw of ['bad json', '[]', '{"type":"hello"}', '{"v":2,"type":"hello"}',
    '{"v":1,"type":"hello","ticket":"private"}', '{"v":1,"type":"source"}']) {
    assert.equal(isChannelHello(raw), false);
  }
});

test('un message de liste est lu, un message avec secret est rejeté', () => {
  const ok = parseChannelEvent(JSON.stringify({
    v: 1,
    seq: 3,
    type: 'source',
    mac: 'MK:AA:BB:CC:DD:EE',
    at: 10,
  }));
  assert.equal(ok?.type, 'source');
  assert.equal(ok?.seq, 3);
  assert.equal(parseChannelEvent('pas du json'), null);
  assert.equal(parseChannelEvent(JSON.stringify({
    v: 1, seq: 1, type: 'source', mac: 'MK:AA:BB:CC:DD:EE', password: 'x',
  })), null);
  assert.equal(parseChannelEvent(JSON.stringify({
    v: 1, seq: 1, type: 'source', mac: 'MK:AA:BB:CC:DD:EE', m3u_url: 'http://exemple.invalid/a',
  })), null);
  assert.equal(parseChannelEvent(JSON.stringify({ v: 1, type: 'hello' })), null);
});
