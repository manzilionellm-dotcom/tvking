// Aucun accès réseau ni migration distante : chaque cas possède sa SQLite.
import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { enrollProductionDevice, verifyProductionDevice } from '../gold_trial_device.js';

const read = name => readFileSync(new URL(`../migrations/${name}`, import.meta.url), 'utf8');
const mac = 'MK:11:22:33:44:55', androidId = 'fixture-android';
const secret = 'fixture-first-device-secret-long-enough-32';
const nextSecret = 'fixture-next-device-secret-long-enough-32';

function fixture(order) {
  const sql = new DatabaseSync(':memory:');
  sql.exec(`CREATE TABLE devices(mac TEXT PRIMARY KEY,android_id TEXT,block_status TEXT,superseded_by TEXT);
    CREATE TABLE trial_anchors(mac TEXT PRIMARY KEY,android_id TEXT);
    INSERT INTO devices VALUES ('${mac}','${androidId}','active',NULL);
    INSERT INTO trial_anchors VALUES ('${mac}','${androidId}');`);
  for (const name of order) sql.exec(read(name));
  const db = { prepare(query) {
    let args=[];
    const statement = { bind(...values) { args=values; return statement; },
      async first() { return sql.prepare(query).get(...args) ?? null; },
      async all() { return { results: sql.prepare(query).all(...args) }; },
      async run() { return { meta: { changes: Number(sql.prepare(query).run(...args).changes) } }; },
    }; return statement;
  } };
  return {sql, db};
}

const policy = '20261028_gold_trial_policy.sql';
const runtime = '20261028_gold_trial_runtime.sql';
const device = '20261029_device_secrets.sql';
for (const [name, order] of [
  ['runtime puis device', [policy, runtime, device]],
  ['device déjà présent puis runtime', [device, policy, runtime]],
]) {
  test(`preuve appareil : ${name}, enrôlement et rotation autorisée sans réécriture du schéma`, async () => {
    const {sql,db} = fixture(order);
    try {
      const schemaBefore = sql.prepare("SELECT sql FROM sqlite_master WHERE name='device_secrets'").get().sql;
      const request = (value, previous) => new Request('https://worker.example/api/device-proof', {
        method: 'POST', headers: { 'CF-Connecting-IP':'192.0.2.10', 'Content-Type':'application/json',
          ...(previous ? { 'X-Device-Secret':previous } : {}) },
        body: JSON.stringify({mac,androidId,secret:value}),
      });
      assert.equal((await enrollProductionDevice(request(secret),{DB:db})).status,200);
      const before = sql.prepare('SELECT * FROM device_secrets').get();
      assert.equal((await enrollProductionDevice(request(secret),{DB:db})).status,200);
      assert.deepEqual(sql.prepare('SELECT * FROM device_secrets').get(),before,'répétition idempotente');
      assert.equal((await enrollProductionDevice(request(nextSecret),{DB:db})).status,403,'aucune rotation sans preuve');
      assert.deepEqual(sql.prepare('SELECT * FROM device_secrets').get(),before,'refus sans écriture de la preuve');
      assert.equal((await enrollProductionDevice(request(nextSecret,secret),{DB:db})).status,200);
      const after = sql.prepare('SELECT * FROM device_secrets').get();
      assert.notEqual(after.secret_hash,before.secret_hash);
      if ('enrolled_at' in before) assert.equal(after.enrolled_at,before.enrolled_at);
      assert.equal(await verifyProductionDevice(db,request(nextSecret,nextSecret),{mac,android_id:androidId}),'ok');
      assert.equal(await verifyProductionDevice(db,request(secret,secret),{mac,android_id:androidId}),'device_mismatch');
      assert.equal(sql.prepare("SELECT sql FROM sqlite_master WHERE name='device_secrets'").get().sql,schemaBefore);
      assert.equal(sql.prepare('SELECT gold_trial_enabled FROM gold_trial_settings_v2 WHERE id=1').get().gold_trial_enabled,0);
    } finally { sql.close(); }
  });
}
