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
import { pickBestLicense, licensePlayableRank, bestLicenseOrderSql } from './license_pick.js';

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
const expiredYear = { lstatus: 'active', expires_at: now - 1000 };
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
ok(sql.includes('expires_at > ?'), 'ORDER BY SQL bind now via ?');
ok(bestLicenseOrderSql('l', now).includes(`l.expires_at > ${now}`),
  'alias + now interpolé (sous-requêtes panel)');
ok(!bestLicenseOrderSql('l', 'DROP TABLE').includes('DROP'),
  'nowExpr non numérique → 0, pas d\'injection');

// Invariant anti-freeloader : une ligne expirée / inactive n'est
// JAMAIS classée jouable. Le bug c'est l'inverse (payant resté bloqué).
ok(licensePlayableRank({ lstatus: 'active', expires_at: now }, now) === 1,
  'expires_at == now → pas encore / plus jouable (strict)');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
