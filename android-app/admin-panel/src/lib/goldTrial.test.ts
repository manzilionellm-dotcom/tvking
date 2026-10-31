import test from 'node:test';
import assert from 'node:assert/strict';
import { historyRows, pollTrials, trialDate, trialMac } from './goldTrial.ts';

test('MAC et dates couvrent les deux apps et les formats du contrat existant', () => {
  assert.equal(trialMac('mk-11-22-33-44-55'), 'MK:11:22:33:44:55');
  assert.equal(trialMac('00:11:22:33:44:55'), '00:11:22:33:44:55');
  assert.equal(trialMac('invalide'), null);
  assert.equal(trialDate(1793102400), trialDate(1793102400000));
  assert.equal(trialDate('invalide'), '—');
});
test('historique : projection des champs utiles, sans données fournisseur brutes', () => {
  const rows = historyRows([{ id: 1, event: 'created', line_id: '123', created_at: 1793102400,
    ip: '192.0.2.1', app_version: '109', api_key: 'never-render', url: 'https://private.example' }], 'test');
  assert.equal(rows[0].line, '123'); assert.equal(rows[0].version, '109');
  assert.doesNotMatch(JSON.stringify(rows), /never-render|private.example/);
});
test('polling : une lecture lente ne crée pas de requêtes concurrentes ; arrêt annule', async () => {
  let calls = 0; let signal: AbortSignal | undefined; let finish: (() => void) | undefined;
  const stop = pollTrials(async current => {
    signal = current; calls++;
    await new Promise<void>(resolve => { finish = resolve; });
  }, 2);
  await new Promise(resolve => setTimeout(resolve, 15));
  assert.equal(calls, 1); stop(); assert.equal(signal?.aborted, true); finish?.();
  await new Promise(resolve => setTimeout(resolve, 10)); assert.equal(calls, 1);
});
