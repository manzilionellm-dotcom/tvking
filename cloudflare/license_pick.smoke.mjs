// =========================================================
//  license_pick.smoke.mjs — quelle licence déverrouille ?
// =========================================================
//  Verrouille le trou Lionel : une lifetime INACTIVE ne doit plus
//  gagner contre un annuel tout juste activé (panel vert / tablette
//  verrouillée).
//
//  Lancer : node cloudflare/license_pick.smoke.mjs
// =========================================================
import assert from 'node:assert/strict';
import { pickBestLicense, licensePlayableRank, bestLicenseOrderSql, expiryDayEndMs, paidLicenseExpired, paidLicenseDaysLeft, utcDayStartMs } from './license_pick.js';

const now = 1_800_000_000_000;
let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

const yearly = { lstatus: 'active', expires_at: now + 365 * 86400000 };
const deadLife = { lstatus: 'inactive', expires_at: null };
const revokedLife = { status: 'revoked', expires_at: null };
const expiredYear = { lstatus: 'active', expires_at: now - 2 * 86400000 };
const lifeOk = { lstatus: 'active', expires_at: null };

ok(licensePlayableRank(yearly, now) === 0, 'annuel actif → jouable');
ok(licensePlayableRank(deadLife, now) === 1, 'lifetime inactive → pas jouable');
ok(licensePlayableRank(expiredYear, now) === 1, 'actif mais expires_at passé → pas jouable');
ok(licensePlayableRank(lifeOk, now) === 0, 'lifetime active → jouable');

ok(pickBestLicense([], now) === null, 'liste vide → null');
ok(pickBestLicense(null, now) === null, 'null → null');

const picked = pickBestLicense([deadLife, yearly, expiredYear], now);
ok(picked === yearly, 'annuel actif gagne contre lifetime inactive + expiré');

const picked2 = pickBestLicense([revokedLife, yearly], now);
ok(picked2 === yearly, 'annuel actif gagne contre lifetime révoquée (champ status)');

const picked3 = pickBestLicense([deadLife, expiredYear], now);
ok(picked3 === deadLife, 'aucune jouable → lifetime (plus « longue ») en dernier recours');

const picked4 = pickBestLicense([yearly, lifeOk], now);
ok(picked4 === lifeOk, 'deux jouables → lifetime prime');

const sql = bestLicenseOrderSql();
ok(sql.includes("status = 'active'"), 'ORDER BY SQL préfère status=active');
ok(sql.includes('expires_at >= ?'), 'ORDER BY SQL bind dayStart via ?');
const dayStart = utcDayStartMs(now);
ok(bestLicenseOrderSql('l', now).includes(`l.expires_at >= ${dayStart}`),
  'alias + now interpolé en début de jour UTC (sous-requêtes panel)');
ok(!bestLicenseOrderSql('l', 'DROP TABLE').includes('DROP'),
  'nowExpr non numérique → 0, pas d\'injection');

// Dernier jour INCLUS : expires_at = aujourd'hui 00:00 UTC reste jouable.
ok(licensePlayableRank({ lstatus: 'active', expires_at: now }, now) === 0,
  'expires_at == now (minuit du jour) → encore jouable (jour inclus)');

const DAY = 86400000;
const d16 = Date.UTC(2026, 8, 16, 0, 0, 0, 0); // 16/09/2026 00:00 UTC
ok(expiryDayEndMs(d16) === Date.UTC(2026, 8, 17, 0, 0, 0, 0),
  'expiryDayEndMs(16/09 00:00) → 17/09 00:00');
ok(!paidLicenseExpired(d16, Date.UTC(2026, 8, 16, 0, 0, 0, 0)),
  '16/09 00:00 → pas expiré (début du dernier jour)');
ok(!paidLicenseExpired(d16, Date.UTC(2026, 8, 16, 23, 59, 59, 999)),
  '16/09 23:59 → pas expiré (fin du dernier jour)');
ok(paidLicenseExpired(d16, Date.UTC(2026, 8, 17, 0, 0, 0, 0)),
  '17/09 00:00 → expiré');
ok(paidLicenseDaysLeft(d16, Date.UTC(2026, 8, 16, 12, 0, 0, 0), DAY) >= 1,
  '16/09 midi → days_left >= 1');
ok(paidLicenseDaysLeft(d16, Date.UTC(2026, 8, 16, 23, 59, 0, 0), DAY) >= 1,
  '16/09 23:59 → days_left >= 1');
ok(paidLicenseDaysLeft(d16, Date.UTC(2026, 8, 17, 0, 0, 0, 0), DAY) === 0,
  '17/09 00:00 → days_left = 0');
ok(licensePlayableRank({ lstatus: 'active', expires_at: d16 }, Date.UTC(2026, 8, 16, 18, 0, 0, 0)) === 0,
  'actif expires_at=16/09, le 16 à 18h → jouable');
ok(licensePlayableRank({ lstatus: 'active', expires_at: d16 }, Date.UTC(2026, 8, 17, 0, 0, 0, 1)) === 1,
  'actif expires_at=16/09, le 17 → plus jouable');
ok(paidLicenseExpired(null, now) === false, 'lifetime (null) → pas expiré');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
