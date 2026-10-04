// Canal du panel : délai de sondage et lecture des messages.
// Aucune adresse de flux, aucun mot de passe réel.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { panelPollInterval, PANEL_POLL_MS, PANEL_POLL_SLOW_MS } from './live-sync.ts';
import { parseChannelEvent } from './box-channel-core.ts';

test('repli coupé : le sondage ralentit quand le canal est ouvert', () => {
  assert.equal(panelPollInterval(false), PANEL_POLL_MS);
  assert.equal(panelPollInterval(true), PANEL_POLL_SLOW_MS);
  assert.equal(PANEL_POLL_MS, 2000);
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
