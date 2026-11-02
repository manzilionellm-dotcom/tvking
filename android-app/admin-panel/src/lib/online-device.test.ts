import assert from 'node:assert/strict';
import { test } from 'node:test';
import { normalizeOnlineMac, readOnlineDeviceMetadata, summaryForOnlineDevice } from './online-device.ts';

const mac = 'MK:11:22:33:44:55';
const other = 'MK:11:22:33:44:56';

test('ZUNO sur téléphone reste Android, jamais TV par son namespace produit', () => {
  const result = summaryForOnlineDevice({ mac }, {
    mac, platform: 'tv', device_model: 'SM-S938B', android_release: '16', app_version: '113',
  });
  assert.equal(result.kind, 'android');
  assert.equal(result.model, 'SM-S938B');
  assert.equal(result.os, 'Android 16');
  assert.equal(result.appVersion, '113');
  assert.match(result.label, /type non communiqué/);
});

test('modèles TV explicites, sans confondre les tablettes des mêmes fabricants', () => {
  for (const model of ['SHIELD Android TV', 'NVIDIA SHIELD TV Pro', 'Google TV Streamer']) {
    assert.equal(summaryForOnlineDevice({ mac, deviceModel: model }).kind, 'android_tv');
  }
  for (const model of ['AFTMM', 'AFTB', 'Fire TV Stick 4K']) {
    assert.equal(summaryForOnlineDevice({ mac, deviceModel: model }).kind, 'fire_tv');
  }
  assert.equal(summaryForOnlineDevice({ mac, deviceModel: 'Fire HD 10' }).kind, 'android_tablet');
  assert.equal(summaryForOnlineDevice({ mac, deviceModel: 'SHIELD Tablet K1' }).kind, 'android_tablet');
  const fireTablet = summaryForOnlineDevice({ mac }, {
    mac, manufacturer: 'Amazon', device_model: 'KFTUWI', android_release: '11', platform: 'tv',
  });
  assert.equal(fireTablet.kind, 'android');
});

test('type matériel explicite prioritaire, futures réponses en camel ou snake case', () => {
  assert.equal(summaryForOnlineDevice({ mac, deviceKind: 'android_phone', deviceModel: 'AFTMM' }).kind, 'android_phone');
  assert.equal(summaryForOnlineDevice({ mac }, { mac, device_kind: 'android_tablet', platform: 'tv' }).kind, 'android_tablet');
  assert.equal(summaryForOnlineDevice({ mac, deviceKind: 'tv' }).kind, 'unknown');
});

test('jointure MAC complète normalisée, aucune fuite depuis une autre fiche', () => {
  assert.equal(normalizeOnlineMac(' 11-22-33-44-55 '), mac);
  assert.equal(normalizeOnlineMac('mk:11:22:33:44:55'), mac);
  assert.equal(normalizeOnlineMac('xx11:22:33:44:55'), '');
  assert.equal(normalizeOnlineMac('44:55'), '');
  const result = summaryForOnlineDevice({ mac }, { mac: other, device_model: 'AFTMM' });
  assert.equal(result.kind, 'unknown');
  assert.equal(result.model, '');
});

test('champs malformés et informations absentes restent présentables', () => {
  for (const bad of [undefined, null, [], 123, 'phone']) {
    assert.equal(summaryForOnlineDevice(bad, bad).kind, 'unknown');
  }
  const result = summaryForOnlineDevice({ mac, deviceModel: {}, androidRelease: [], deviceKind: 'unknown' }, {
    mac, device_model: '  Modèle\u0000\n ' + 'x'.repeat(120), android_release: ' 14 ',
  });
  assert.equal(result.kind, 'android');
  assert.equal(result.model.length, 80);
  assert.equal(result.os, 'Android 14');
});

test('pagination respecte le plafond renvoyé par le serveur et s’arrête une fois trouvé', async () => {
  const calls: number[] = [];
  const result = await readOnlineDeviceMetadata([mac, other], async ({ offset, limit }) => {
    calls.push(offset);
    assert.equal(limit, 500);
    if (offset === 0) return { items: [{ mac }, { mac: 'MK:00:00:00:00:01' }], total: 6, limit: 2 };
    return { items: [{ mac: other, device_model: 'AFTMM' }, { mac: 'MK:00:00:00:00:02' }], total: 6, limit: 2 };
  });
  assert.deepEqual(calls, [0, 2]);
  assert.equal(result.complete, true);
  assert.equal(result.failed, false);
  assert.equal(result.devices.get(other)?.deviceModel, 'AFTMM');
});

test('cache de métadonnées limité aux appareils demandés et aux champs autorisés', async () => {
  const result = await readOnlineDeviceMetadata([mac.toLowerCase()], async () => ({ items: [
    { mac: other, device_model: 'autre client' },
    { mac, device_model: 'SHIELD Android TV', device_secret: 'secret', local_sources_json: 'private', customer_email: 'private' },
  ] }));
  assert.equal(result.devices.size, 1);
  assert.deepEqual(Object.keys(result.devices.get(mac)!).sort(), [
    'androidRelease', 'appVersion', 'deviceKind', 'deviceModel', 'mac', 'manufacturer',
  ]);
});

test('registre partiel, panne et ancien serveur répétant une page ne perdent pas les fiches reçues', async () => {
  let calls = 0;
  const partial = await readOnlineDeviceMetadata([mac, other], async () => {
    if (++calls === 1) return { items: [{ mac, device_model: 'AFTMM' }], total: 2 };
    throw new Error('réseau');
  });
  assert.equal(partial.devices.size, 1);
  assert.equal(partial.failed, true);
  assert.equal(partial.complete, false);
  calls = 0;
  const repeated = await readOnlineDeviceMetadata([other], async () => {
    calls++; return { items: [{ mac }], total: 1000 };
  });
  assert.equal(calls, 2);
  assert.equal(repeated.complete, false);
  assert.equal(repeated.failed, false);
  const malformed = await readOnlineDeviceMetadata([mac], async () => ({ items: {} }));
  assert.equal(malformed.failed, true);
});

test('parcours plafonné à 20 pages et 10 000 lignes', async () => {
  let calls = 0;
  const result = await readOnlineDeviceMetadata([mac], async ({ offset }) => {
    calls++;
    return { items: Array.from({ length: 500 }, (_, i) => ({
      mac: `MK:${(offset + i).toString(16).padStart(10, '0').match(/../g)!.join(':')}`,
    })), total: 20000 };
  });
  assert.equal(calls, 20);
  assert.equal(result.complete, false);
});

test('annulation avant ou pendant la lecture ne rend jamais un ancien résultat', async () => {
  const aborted = new AbortController();
  aborted.abort();
  let calls = 0;
  await assert.rejects(readOnlineDeviceMetadata([mac], async () => { calls++; return {}; }, aborted.signal), { name: 'AbortError' });
  assert.equal(calls, 0);
  const controller = new AbortController();
  await assert.rejects(readOnlineDeviceMetadata([mac], async () => {
    controller.abort(); return { items: [{ mac }] };
  }, controller.signal), { name: 'AbortError' });
});

test('aucun appareil valide demandé : aucune requête registre', async () => {
  const result = await readOnlineDeviceMetadata(['invalid', null], async () => { throw new Error('ne pas appeler'); });
  assert.equal(result.complete, true);
  assert.equal(result.devices.size, 0);
});
