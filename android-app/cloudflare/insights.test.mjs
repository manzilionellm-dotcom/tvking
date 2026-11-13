// =========================================================
//  insights.test.mjs — Pilotage du panel (lecture seule)
// =========================================================
//  node --experimental-sqlite --test insights.test.mjs
//  Base SQLite en mémoire (même harnais que les autres tests). MAC et
//  noms factices.
// =========================================================
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createD1 } from './test_support/d1_sqlite.mjs';
import { maskId, outageAlert, readInsights } from './insights.js';

const DAY = 86400000;
const NOW = 1_800_000_000_000;

function seed() {
  const t = createD1({ extraSql: [
    'ALTER TABLE devices ADD COLUMN android_id TEXT',
    'ALTER TABLE devices ADD COLUMN app_version TEXT',
    'CREATE TABLE IF NOT EXISTS presence (mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT, quality INTEGER)',
  ] });
  const db = t.db;
  db.exec("INSERT INTO apps (id, name, package_name, created_at, updated_at) VALUES ('app', 'Zuno', 'pkg.test', 1, 1)");
  db.exec("INSERT INTO resellers (id, email, password_hash, name, created_at) VALUES ('r1', 'r1@example.test', 'x', 'Revendeur Un', 1)");
  const dev = db.prepare('INSERT INTO devices (id, customer_id, mac, first_seen_at, last_seen_at, android_id, app_version) VALUES (?, ?, ?, ?, ?, ?, ?)');
  const cust = db.prepare('INSERT INTO customers (id, name, created_at, updated_at) VALUES (?, ?, 1, 1)');
  const lic = db.prepare('INSERT INTO licenses (id, customer_id, device_id, app_id, status, plan, started_at, expires_at, reseller_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
  const pres = db.prepare('INSERT INTO presence (mac, ip, country, last_seen, channel, quality) VALUES (?, ?, ?, ?, ?, ?)');
  for (let i = 1; i <= 8; i++) {
    cust.run(`c${i}`, `Client ${i}`);
    // Les box 7 et 8 partagent le même identifiant matériel.
    dev.run(`d${i}`, `c${i}`, `MK:00:00:00:00:0${i}`, 1, NOW, i >= 7 ? 'abcdef123456' : `id-unique-${i}`, i <= 4 ? '117' : '116');
  }
  const L = (id, d, plan, exp, created, res = null) =>
    lic.run(id, `c${d}`, `d${d}`, 'app', 'active', plan, created, exp, res, created, created);
  L('l1', 1, 'yearly', NOW + 3 * DAY, NOW - 2 * DAY, 'r1');   // expire bientôt
  L('l2', 2, 'monthly', NOW - 40 * DAY, NOW - 70 * DAY);       // perdu
  L('l3', 3, 'yearly', NOW + 300 * DAY, NOW - 400 * DAY, 'r1'); // ancien, renouvelé (même ligne)
  L('l4', 4, 'trial', NOW + 2 * DAY, NOW - 1 * DAY);           // essai : jamais une vente
  L('l5', 5, 'lifetime', null, NOW - 5 * DAY);
  L('l6', 6, 'monthly', NOW - 3 * DAY, NOW - 33 * DAY);        // fini depuis peu : ni bientôt, ni perdu
  const led = db.prepare("INSERT INTO credit_ledger (id, reseller_id, delta, reason, balance_after, created_at) VALUES (?, 'r1', -1, ?, 0, ?)");
  led.run('k1', 'activation', NOW - 2 * DAY);
  led.run('k2', 'renew', NOW - 9 * DAY);
  led.run('k3', 'renew', NOW - 60 * DAY);
  led.run('k4', 'issue', NOW - 1 * DAY);
  // Six box regardent ; trois ont une mauvaise qualité.
  pres.run('MK:00:00:00:00:01', '', 'SE', NOW - 1000, 'Sport 1', 98);
  pres.run('MK:00:00:00:00:02', '', 'SE', NOW - 1000, 'Sport 1', 40);
  pres.run('MK:00:00:00:00:03', '', 'FR', NOW - 1000, 'Sport 1', 50);
  pres.run('MK:00:00:00:00:04', '', 'FR', NOW - 1000, 'Info', 95);
  pres.run('MK:00:00:00:00:05', '', 'FR', NOW - 1000, 'Info', 60);
  pres.run('MK:00:00:00:00:06', '', 'CA', NOW - 1000, 'Info', 100);
  pres.run('MK:00:00:00:00:07', '', 'CA', NOW - 1000, '', null);        // ne regarde rien
  pres.run('MK:00:00:00:00:08', '', 'CA', NOW - 60 * 60000, 'Info', 5); // hors ligne
  return t;
}

test('règles pures : alerte, masque', () => {
  assert.equal(outageAlert(4, 4), false, 'moins de 5 box : pas une panne');
  assert.equal(outageAlert(10, 3), false);
  assert.equal(outageAlert(10, 4), true);
  assert.equal(maskId('abcdef123456'), 'abc…456');
  assert.equal(maskId(''), '');
});

test('santé : seulement les box en ligne qui regardent', async () => {
  const t = seed();
  const out = await readInsights({ DB: t.DB }, NOW);
  assert.deepEqual(out.unavailable, []);
  assert.equal(out.health.watching, 6);
  assert.equal(out.health.bad, 3);
  assert.equal(out.health.alert, true);
  const sport = out.health.byChannel.find((c) => c.key === 'Sport 1');
  assert.deepEqual(sport, { key: 'Sport 1', count: 3, quality: 63 });
  assert.equal(out.health.byVersion.find((v) => v.key === '117').count, 4);
  assert.equal(out.health.byCountry.find((c) => c.key === 'FR').count, 3);
});

test('argent : nouveaux abonnés, expirations, perdus, journal des revendeurs', async () => {
  const t = seed();
  const { money } = await readInsights({ DB: t.DB }, NOW);
  // Payées créées dans les 30 jours : l1 et l5 (pas l'essai, pas les anciennes).
  assert.equal(money.newPaid30, 2);
  assert.equal(money.paidActive, 3);   // l1, l3, l5
  assert.equal(money.paidExpired, 2);  // l2, l6
  assert.deepEqual(money.expiring.map((p) => p.mac), ['MK:00:00:00:00:01']);
  assert.equal(money.expiring[0].reseller, 'Revendeur Un');
  // Perdu = fini depuis plus de 30 jours (l6, fini il y a 3 jours, n'y est pas).
  assert.deepEqual(money.lost.map((p) => p.mac), ['MK:00:00:00:00:02']);
  assert.equal(money.resellerActivations30, 1);
  assert.equal(money.resellerRenewals30, 1);
  assert.equal(money.byReseller.find((r) => r.key === 'Revendeur Un').count, 1);
});

test('fraude : la même box sous plusieurs MAC, identifiant masqué', async () => {
  const t = seed();
  const { fraud } = await readInsights({ DB: t.DB }, NOW);
  assert.equal(fraud.sameBox.length, 1);
  assert.equal(fraud.sameBox[0].count, 2);
  assert.equal(fraud.sameBox[0].id, 'abc…456');
  assert.deepEqual(fraud.sameBox[0].macs.sort(), ['MK:00:00:00:00:07', 'MK:00:00:00:00:08']);
});

test('base absente ou incomplète : la page reste debout', async () => {
  const none = await readInsights({}, NOW);
  assert.deepEqual(none.unavailable, ['health', 'money', 'fraud']);
  const t = createD1({});
  const out = await readInsights({ DB: t.DB }, NOW);
  // Pas de table presence, pas de colonne android_id : blocs vides, pas d'exception.
  assert.ok(out.unavailable.includes('health'));
  assert.equal(out.health.watching, 0);
  assert.equal(out.money.newPaid30, 0);
});
