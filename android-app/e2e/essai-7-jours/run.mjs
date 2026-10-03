// =========================================================
//  Essai 7 jours — suite locale Worker + miniflare + D1
// =========================================================
//  Rien n'est déployé. Horloge du téléphone simulée par un champ
//  envoyé dans le heartbeat (le serveur doit l'ignorer). Les dates
//  d'essai sont posées dans D1 (first_seen + ancre).
//
//    node run.mjs
// =========================================================
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Miniflare } from 'miniflare';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLOUDFLARE = resolve(HERE, '../../cloudflare');
const DAY = 24 * 60 * 60 * 1000;
const SECRET = 'essai-local-secret';

let pass = 0;
let fail = 0;
const failures = [];

function check(name, ok, detail = '') {
  if (ok) {
    pass++;
    console.log('OK   ', name, detail ? '— ' + detail : '');
  } else {
    fail++;
    failures.push(name);
    console.log('ECHEC', name, detail ? '— ' + detail : '');
  }
  return ok;
}

async function applySql(db, file) {
  const raw = readFileSync(file, 'utf8');
  const noComments = raw
    .split('\n')
    .filter((l) => !l.trim().startsWith('--'))
    .join('\n');
  const parts = noComments.split(';').map((s) => s.trim()).filter(Boolean);
  for (const stmt of parts) {
    try {
      await db.exec(stmt);
    } catch (e) {
      const msg = String(e && e.message ? e.message : e);
      if (/duplicate column|already exists/i.test(msg)) continue;
      try {
        await db.prepare(stmt).run();
      } catch (e2) {
        const msg2 = String(e2 && e2.message ? e2.message : e2);
        if (/duplicate column|already exists/i.test(msg2)) continue;
        throw e2;
      }
    }
  }
}

async function boot(enforced) {
  const mf = new Miniflare({
    modules: true,
    scriptPath: resolve(CLOUDFLARE, 'worker.js'),
    modulesRoot: CLOUDFLARE,
    modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }],
    compatibilityDate: '2025-05-01',
    d1Databases: { DB: enforced ? 'essai-on' : 'essai-off' },
    bindings: {
      ADMIN_SECRET: SECRET,
      TRIAL_ENFORCEMENT: enforced ? '1' : '0',
    },
  });
  const db = await mf.getD1Database('DB');
  await applySql(db, resolve(CLOUDFLARE, 'schema.sql'));
  await applySql(db, resolve(CLOUDFLARE, 'migrations/003_reseller_hierarchy.sql'));
  await applySql(db, resolve(CLOUDFLARE, 'migrations/008_device_sources.sql'));
  return { mf, db };
}

async function api(mf, method, path, { body, token } = {}) {
  const headers = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = 'Bearer ' + token;
  const res = await mf.dispatchFetch('https://essai.local' + path, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
  return { status: res.status, json };
}

function mac(n) {
  const hex = n.toString(16).toUpperCase().padStart(10, '0');
  return `MK:${hex.slice(0, 2)}:${hex.slice(2, 4)}:${hex.slice(4, 6)}:${hex.slice(6, 8)}:${hex.slice(8, 10)}`;
}

async function beat(mf, id, extra = {}) {
  return api(mf, 'POST', '/api/heartbeat', { body: { mac: id, ...extra } });
}

async function setStart(db, id, started) {
  await db.prepare('UPDATE devices SET first_seen_at = ? WHERE mac = ?').bind(started, id).run();
  await db.prepare(
    'INSERT INTO trial_anchors (mac, android_id, started_at) VALUES (?, NULL, ?) '
    + 'ON CONFLICT(mac) DO UPDATE SET started_at = excluded.started_at',
  ).bind(id, started).run();
}

async function balanceOf(db, id) {
  const row = await db.prepare('SELECT credit_balance FROM resellers WHERE id = ?').bind(id).first();
  return row ? row.credit_balance : null;
}

async function licenseCount(db, id) {
  const row = await db.prepare(
    'SELECT COUNT(*) AS n FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?',
  ).bind(id).first();
  return row ? row.n : 0;
}

async function loginAdmin(mf) {
  const r = await api(mf, 'POST', '/api/v1/auth/login', {
    body: { email: 'admin', password: SECRET },
  });
  return r;
}

async function makeReseller(mf, token, email, credits) {
  const r = await api(mf, 'POST', '/api/v1/resellers', {
    token,
    body: { email, password: 'revendeur-test', name: email, credit_balance: credits },
  });
  return r;
}

async function main() {
  console.log('=== Essai 7 jours (miniflare, interrupteur ALLUMÉ) ===');
  const on = await boot(true);
  const { mf, db } = on;
  try {
    const admin = await loginAdmin(mf);
    check('admin se connecte', admin.status === 200 && admin.json && admin.json.token, 'HTTP ' + admin.status);
    const token = admin.json && admin.json.token;

    const pricing0 = await api(mf, 'GET', '/api/v1/pricing', { token });
    check('lien de paiement vide par défaut',
      pricing0.status === 200 && (pricing0.json.payUrl || '') === '' && pricing0.json.trialEnforced === true,
      JSON.stringify({ payUrl: pricing0.json && pricing0.json.payUrl, trialEnforced: pricing0.json && pricing0.json.trialEnforced }));

    const id = mac(1);
    let r = await beat(mf, id, { androidId: 'box-stable-1', now: Date.now() + 10 * 365 * DAY, device_time: 0 });
    const t0 = Date.now();
    check('jour 0 : essai ouvert, horloge du téléphone ignorée',
      r.status === 200 && r.json.expired === false && r.json.paid === false
      && r.json.plan === 'trial' && r.json.days_left === 7 && r.json.trial_enforced === true
      && r.json.trial_until > t0 + 6 * DAY,
      `days_left=${r.json && r.json.days_left} expired=${r.json && r.json.expired} until=${r.json && r.json.trial_until}`);

    const anchor0 = await db.prepare('SELECT started_at FROM trial_anchors WHERE mac = ?').bind(id).first();
    const seen0 = await db.prepare('SELECT first_seen_at FROM devices WHERE mac = ?').bind(id).first();
    r = await beat(mf, id, { androidId: 'box-stable-1' });
    const anchor1 = await db.prepare('SELECT started_at FROM trial_anchors WHERE mac = ?').bind(id).first();
    const seen1 = await db.prepare('SELECT first_seen_at FROM devices WHERE mac = ?').bind(id).first();
    check('réinstallation : même MAC, l’ancre ne repart pas',
      anchor0 && anchor1 && anchor0.started_at === anchor1.started_at
      && seen0.first_seen_at === seen1.first_seen_at
      && r.json.expired === false && r.json.days_left === 7,
      `ancre ${anchor0 && anchor0.started_at} → ${anchor1 && anchor1.started_at}`);

    const start6 = Date.now() - 6 * DAY;
    await setStart(db, id, start6);
    r = await beat(mf, id, { now: Date.now() - 3 * DAY });
    check('jour 6 : encore ouvert, 1 jour restant',
      r.json.expired === false && r.json.days_left === 1 && r.json.plan === 'trial',
      `days_left=${r.json.days_left} expired=${r.json.expired}`);

    const startJustBefore = Date.now() - 7 * DAY + 3000;
    await setStart(db, id, startJustBefore);
    r = await beat(mf, id);
    check('juste avant 7×24h : encore ouvert',
      r.json.expired === false && r.json.days_left === 1,
      `days_left=${r.json.days_left}`);

    const start7 = Date.now() - 7 * DAY;
    await setStart(db, id, start7);
    r = await beat(mf, id, { now: Date.now() - 20 * DAY, device_time: 0 });
    check('jour 7 pile (début du 8e jour) : bloqué, horloge reculée ignorée',
      r.json.expired === true && r.json.paid === false && r.json.days_left === 0
      && r.json.status === 'expired' && r.json.trial_until === 0 && r.json.plan === 'expired',
      `status=${r.json.status} trial_until=${r.json.trial_until} expired=${r.json.expired}`);

    const start8 = Date.now() - 8 * DAY;
    await setStart(db, id, start8);
    r = await beat(mf, id, { now: Date.now() + 365 * DAY });
    check('jour 8 : toujours bloqué, horloge avancée ignorée',
      r.json.expired === true && r.json.status === 'expired' && r.json.trial_until === 0,
      `status=${r.json.status}`);

    const dev = await db.prepare('SELECT id FROM devices WHERE mac = ?').bind(id).first();
    const del = await api(mf, 'DELETE', '/api/v1/devices/' + dev.id, { token });
    r = await beat(mf, id, { androidId: 'box-stable-1' });
    check('suppression puis réapparition : l’essai ne redémarre pas',
      del.status === 200 && r.json.expired === true && r.json.trial_enforced === true,
      `delete HTTP ${del.status} expired=${r.json && r.json.expired}`);

    const idB = mac(2);
    r = await beat(mf, idB, { androidId: 'box-stable-1' });
    check('autre MAC, même identifiant Android : pas un nouvel essai',
      r.json.expired === true && r.json.paid === false,
      `expired=${r.json.expired} plan=${r.json.plan}`);

    const listed = await api(mf, 'GET', '/api/v1/devices?q=' + encodeURIComponent(idB), { token });
    const rowB = (listed.json.items || []).find((d) => d.mac === idB);
    check('panel : essai expiré visible',
      listed.json.trial_enforced === true && rowB && rowB.access === 'expired'
      && String(rowB.access_label).includes('expiré'),
      rowB && rowB.access_label);

    const fresh = mac(3);
    r = await beat(mf, fresh, { androidId: 'box-fresh' });
    const listedFresh = await api(mf, 'GET', '/api/v1/devices?q=' + encodeURIComponent(fresh), { token });
    const rowF = (listedFresh.json.items || []).find((d) => d.mac === fresh);
    check('panel : essai en cours, jours restants',
      rowF && rowF.access === 'trial' && rowF.access_days_left === 7
      && String(rowF.access_label).includes('7'),
      rowF && rowF.access_label);

    const reseller = await makeReseller(mf, token, 'r1@essai.local', 10);
    check('revendeur créé avec 10 crédits', reseller.status === 201, 'HTTP ' + reseller.status + ' ' + JSON.stringify(reseller.json && reseller.json.id));
    const rid = reseller.json && reseller.json.id;

    const act = await api(mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: fresh, plan: 'yearly', reseller_id: rid },
    });
    const balAfterYear = await balanceOf(db, rid);
    const expectedEnd = Date.now() + 365 * DAY;
    const delta = act.json && act.json.expires_at ? Math.abs(act.json.expires_at - expectedEnd) : 999999;
    check('activation pendant l’essai : 1 crédit, fin à +365 jours',
      act.status === 201 && act.json.credits_charged === 1 && balAfterYear === 9 && delta < 20000,
      `HTTP ${act.status} charged=${act.json && act.json.credits_charged} solde=${balAfterYear} écart_ms=${delta}`);

    r = await beat(mf, fresh);
    check('après activation : payé, plus en essai',
      r.json.paid === true && r.json.expired === false && r.json.plan === 'paid',
      `paid=${r.json.paid} plan=${r.json.plan} days=${r.json.days_left}`);

    const listedPaid = await api(mf, 'GET', '/api/v1/devices?q=' + encodeURIComponent(fresh), { token });
    const rowP = (listedPaid.json.items || []).find((d) => d.mac === fresh);
    check('panel : activé avec une date de fin',
      rowP && rowP.access === 'activated' && String(rowP.access_label).startsWith('Activé'),
      rowP && rowP.access_label);

    await db.prepare(
      'UPDATE licenses SET expires_at = ? WHERE device_id = (SELECT id FROM devices WHERE mac = ?)',
    ).bind(Date.now() - 1000, fresh).run();
    await db.prepare(
      'INSERT INTO device_sources (mac, type, m3u_url, updated_at) VALUES (?, ?, ?, ?) '
      + 'ON CONFLICT(mac) DO UPDATE SET m3u_url = excluded.m3u_url',
    ).bind(fresh, 'm3u', 'http://127.0.0.1/e2e/liste.m3u', Date.now()).run();
    r = await beat(mf, fresh);
    const src = await api(mf, 'GET', '/api/device-source/' + fresh);
    check('expiration après activation : l’app est bloquée et la source ne part plus',
      r.json.paid === false && r.json.expired === true && r.json.status === 'expired'
      && src.status === 200 && src.json && src.json.blocked === 'expired' && src.json.source == null
      && !JSON.stringify(src.json).includes('127.0.0.1'),
      `paid=${r.json.paid} expired=${r.json.expired} blocked=${src.json && src.json.blocked}`);

    const lifeMac = mac(4);
    await beat(mf, lifeMac);
    const life = await api(mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: lifeMac, plan: 'lifetime', reseller_id: rid },
    });
    const balLife = await balanceOf(db, rid);
    check('à vie : 2 crédits, pas de date de fin',
      life.status === 201 && life.json.credits_charged === 2 && life.json.expires_at == null && balLife === 7,
      `charged=${life.json && life.json.credits_charged} solde=${balLife} exp=${life.json && life.json.expires_at}`);
    const life2 = await api(mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: lifeMac, plan: 'lifetime', reseller_id: rid },
    });
    const balLife2 = await balanceOf(db, rid);
    check('à vie une deuxième fois : 0 crédit',
      life2.json && life2.json.already_lifetime === true && life2.json.credits_charged === 0 && balLife2 === 7,
      `charged=${life2.json && life2.json.credits_charged} solde=${balLife2} flag=${life2.json && life2.json.already_lifetime}`);
    await setStart(db, lifeMac, Date.now() - 400 * DAY);
    r = await beat(mf, lifeMac);
    check('client déjà à vie, vu depuis 400 jours : pas bloqué',
      r.json.paid === true && r.json.expired === false && r.json.plan === 'lifetime',
      `paid=${r.json.paid} expired=${r.json.expired} plan=${r.json.plan}`);
    const listedLife = await api(mf, 'GET', '/api/v1/devices?q=' + encodeURIComponent(lifeMac), { token });
    const rowL = (listedLife.json.items || []).find((d) => d.mac === lifeMac);
    check('panel : activé à vie',
      rowL && rowL.access === 'lifetime' && String(rowL.access_label).includes('vie'),
      rowL && rowL.access_label);

    const broke = await makeReseller(mf, token, 'r0@essai.local', 0);
    const brokeId = broke.json && broke.json.id;
    const poorMac = mac(5);
    await beat(mf, poorMac);
    const denied = await api(mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: poorMac, plan: 'yearly', reseller_id: brokeId },
    });
    const bal0 = await balanceOf(db, brokeId);
    const nlic = await licenseCount(db, poorMac);
    r = await beat(mf, poorMac);
    check('revendeur sans crédits : refus, solde 0, pas de licence, essai inchangé',
      denied.status === 402 && denied.json.error === 'insufficient_credits'
      && bal0 === 0 && nlic === 0 && r.json.paid === false && r.json.plan === 'trial',
      `HTTP ${denied.status} solde=${bal0} licences=${nlic} plan=${r.json.plan}`);

    const saved = await api(mf, 'PUT', '/api/v1/pricing', {
      token,
      body: {
        currency: '€', lifetime: '9,9', yearly: '4,9', trialDays: 7,
        promoEnabled: false, promoMessage: '',
        blockTitleFr: 'Titre essai panel',
        blockBodyFr: 'Texte essai panel',
        blockTitleEn: 'Panel trial title',
        blockBodyEn: 'Panel trial text',
        payUrl: '',
      },
    });
    await setStart(db, poorMac, Date.now() - 8 * DAY);
    r = await beat(mf, poorMac);
    check('message d’écran modifiable, lien de paiement toujours vide',
      saved.status === 200 && (saved.json.payUrl || '') === ''
      && r.json.block_title_fr === 'Titre essai panel'
      && r.json.block_body_en === 'Panel trial text'
      && (r.json.pay_url || '') === '',
      `title=${r.json && r.json.block_title_fr} pay=${r.json && r.json.pay_url}`);
  } finally {
    await mf.dispose();
  }

  console.log('\n=== Interrupteur COUPÉ (comportement actuel) ===');
  const off = await boot(false);
  try {
    const admin = await loginAdmin(off.mf);
    const token = admin.json.token;
    await api(off.mf, 'PUT', '/api/v1/pricing', {
      token,
      body: {
        currency: '€', lifetime: '9,9', yearly: '4,9', trialDays: 30,
        promoEnabled: false, promoMessage: '',
      },
    });
    const id = mac(9);
    await beat(off.mf, id);
    await setStart(off.db, id, Date.now() - 8 * DAY);
    const r = await beat(off.mf, id);
    check('coupé : 8 jours avec essai panel de 30 j ne bloque pas',
      r.json.expired === false && r.json.trial_enforced !== true && r.json.days_left >= 21,
      `expired=${r.json.expired} days=${r.json.days_left} enforced=${r.json.trial_enforced}`);

    const reseller = await makeReseller(off.mf, token, 'off@essai.local', 10);
    const rid = reseller.json.id;
    const lifeMac = mac(8);
    await beat(off.mf, lifeMac);
    await api(off.mf, 'POST', '/api/v1/activate', {
      token, body: { mac: lifeMac, plan: 'lifetime', reseller_id: rid },
    });
    await api(off.mf, 'POST', '/api/v1/activate', {
      token, body: { mac: lifeMac, plan: 'lifetime', reseller_id: rid },
    });
    const bal = await balanceOf(off.db, rid);
    check('coupé : une 2e activation à vie redébite encore (ancien comportement)',
      bal === 6, 'solde=' + bal);
    const st = await beat(off.mf, lifeMac);
    check('coupé : le client à vie reste ouvert',
      st.json.paid === true && st.json.expired === false,
      `paid=${st.json.paid}`);
  } finally {
    await off.mf.dispose();
  }

  console.log(`\nBILAN  ${pass} réussis, ${fail} échoués`);
  if (failures.length) console.log('ÉCHECS:', failures.join(' | '));
  process.exit(fail ? 1 : 0);
}

main().catch((e) => {
  console.error('ERREUR SUITE', e && e.stack ? e.stack : e);
  process.exit(1);
});
