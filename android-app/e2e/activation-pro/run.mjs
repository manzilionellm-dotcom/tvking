// =========================================================
//  Activation pro — tests locaux (miniflare + D1)
//  Rien n'est déployé. node run.mjs
// =========================================================
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Miniflare } from 'miniflare';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLOUDFLARE = resolve(HERE, '../../cloudflare');
const PANEL = resolve(HERE, '../../admin-panel/src/pages');
const DAY = 24 * 60 * 60 * 1000;
const SECRET = 'activation-pro-secret';

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
}

function mac(n) {
  const hex = n.toString(16).toUpperCase().padStart(10, '0');
  return `MK:${hex.slice(0, 2)}:${hex.slice(2, 4)}:${hex.slice(4, 6)}:${hex.slice(6, 8)}:${hex.slice(8, 10)}`;
}

function screenHasNoClone() {
  const files = ['ActivatePage.tsx', 'FamiliesPage.tsx'];
  const banned = [/familial/i, /clonage/i, /\bclone/i, /\bpapa\b/i];
  for (const file of files) {
    const text = readFileSync(resolve(PANEL, file), 'utf8');
    for (const re of banned) {
      if (re.test(text)) return { ok: false, detail: `${file} contient ${re}` };
    }
  }
  const act = readFileSync(resolve(PANEL, 'ActivatePage.tsx'), 'utf8');
  const need = ['Activation 1 an', 'Activation à vie', 'Ajouter des jours', '3', '7', '14', '30'];
  for (const s of need) {
    if (!act.includes(s)) return { ok: false, detail: `il manque « ${s} »` };
  }
  if (act.includes('9,90') || act.includes('35 €') || act.includes('35€')) {
    return { ok: false, detail: 'prix inventé dans l’écran' };
  }
  return { ok: true, detail: 'écran sans clonage, sans prix inventé' };
}

async function applySql(db, file) {
  const raw = readFileSync(file, 'utf8');
  const noComments = raw.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
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
        throw new Error(msg2 + '\nSQL: ' + stmt.slice(0, 180));
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
    d1Databases: { DB: enforced ? 'act-on' : 'act-off' },
    bindings: {
      ADMIN_SECRET: SECRET,
      TRIAL_ENFORCEMENT: enforced ? '1' : '0',
    },
  });
  const db = await mf.getD1Database('DB');
  await applySql(db, resolve(CLOUDFLARE, 'schema.sql'));
  await applySql(db, resolve(CLOUDFLARE, 'migrations/003_reseller_hierarchy.sql'));
  await applySql(db, resolve(CLOUDFLARE, 'migrations/008_device_sources.sql'));
  await applySql(db, resolve(CLOUDFLARE, 'migrations/009_credit_model.sql'));
  return { mf, db };
}

async function api(mf, method, path, { body, token, secret } = {}) {
  const headers = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = 'Bearer ' + token;
  if (secret) headers['X-Admin-Secret'] = secret;
  const res = await mf.dispatchFetch('https://activation.local' + path, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
  return { status: res.status, json };
}

async function loginAdmin(mf) {
  return api(mf, 'POST', '/api/v1/auth/login', {
    body: { email: 'admin', password: SECRET },
  });
}

async function makeReseller(mf, token, email, credits) {
  return api(mf, 'POST', '/api/v1/resellers', {
    token,
    body: { email, password: 'revendeur-test', name: email, credit_balance: credits },
  });
}

async function balanceOf(db, id) {
  const row = await db.prepare('SELECT credit_balance FROM resellers WHERE id = ?').bind(id).first();
  return row ? row.credit_balance : null;
}

async function main() {
  const screen = screenHasNoClone();
  check('écran : pas de clonage, libellés pro, pas de prix inventé', screen.ok, screen.detail);

  console.log('\n=== Interrupteur TRIAL_ENFORCEMENT coupé (défaut) ===');
  const off = await boot(false);
  try {
    const admin = await loginAdmin(off.mf);
    check('admin se connecte', admin.status === 200 && !!admin.json.token, 'HTTP ' + admin.status);
    const token = admin.json.token;

    const rich = await makeReseller(off.mf, token, 'riche@test.local', 5);
    const rid = rich.json && (rich.json.id || (rich.json.reseller && rich.json.reseller.id));
    check('revendeur créé avec 5 crédits', rich.status === 201 && !!rid, JSON.stringify(rich.json));

    const yearMac = mac(11);
    const year = await api(off.mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: yearMac, plan: 'yearly', reseller_id: rid },
    });
    const balYear = await balanceOf(off.db, rid);
    const yearEnd = year.json && year.json.expires_at;
    const yearDelta = yearEnd ? Math.abs(yearEnd - (Date.now() + 365 * DAY)) : 1e15;
    check('1 an : 1 crédit, fin dans 365 jours',
      year.status === 201 && year.json.credits_charged === 1 && balYear === 4 && yearDelta < 20000,
      `HTTP ${year.status} charged=${year.json && year.json.credits_charged} solde=${balYear} écart=${yearDelta}`);

    const lifeMac = mac(12);
    const life = await api(off.mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: lifeMac, plan: 'lifetime', reseller_id: rid },
    });
    const balLife = await balanceOf(off.db, rid);
    check('à vie : 2 crédits, pas de date de fin',
      life.status === 201 && life.json.credits_charged === 2 && life.json.expires_at == null && balLife === 2,
      `charged=${life.json && life.json.credits_charged} solde=${balLife} exp=${life.json && life.json.expires_at}`);

    const broke = await makeReseller(off.mf, token, 'fauche@test.local', 0);
    const brokeId = broke.json && (broke.json.id || (broke.json.reseller && broke.json.reseller.id));
    const poorMac = mac(13);
    await api(off.mf, 'POST', '/api/heartbeat', { body: { mac: poorMac } });
    const denied = await api(off.mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: poorMac, plan: 'yearly', reseller_id: brokeId },
    });
    const balBroke = await balanceOf(off.db, brokeId);
    const licPoor = await off.db.prepare(
      'SELECT COUNT(*) AS n FROM licenses l JOIN devices d ON d.id = l.device_id WHERE d.mac = ?',
    ).bind(poorMac).first();
    check('revendeur à 0 crédit : refus, pas de licence',
      denied.status === 402 && denied.json.error === 'insufficient_credits' && balBroke === 0 && licPoor.n === 0,
      `HTTP ${denied.status} solde=${balBroke} licences=${licPoor && licPoor.n}`);

    const trialMac = mac(21);
    await api(off.mf, 'POST', '/api/heartbeat', { body: { mac: trialMac } });
    const old = Date.now() - 30 * DAY;
    await off.db.prepare('UPDATE devices SET first_seen_at = ? WHERE mac = ?').bind(old, trialMac).run();
    let st = await api(off.mf, 'GET', '/api/status/' + trialMac);
    check('essai dépassé : appareil bloqué',
      st.status === 200 && st.json.expired === true && st.json.paid === false,
      `HTTP ${st.status} ${JSON.stringify(st.json)}`);

    const ext = await api(off.mf, 'POST', '/api/v1/trial-extend', {
      secret: SECRET,
      body: { mac: trialMac, days: 7 },
    });
    const extUntil = ext.json && ext.json.trial_until;
    check('ajout 7 jours : nouvelle fin renvoyée',
      ext.status === 200 && ext.json.ok === true && ext.json.days === 7
      && extUntil > Date.now() + 6 * DAY && extUntil < Date.now() + 8 * DAY,
      `HTTP ${ext.status} until=${extUntil}`);

    const log = await off.db.prepare(
      'SELECT days, actor_type, actor_id, created_at, new_until FROM trial_extensions WHERE mac = ?',
    ).bind(trialMac).first();
    check('journal : qui, quand, combien',
      log && log.days === 7 && log.actor_type === 'admin' && log.actor_id === 'admin_secret'
      && Number(log.created_at) > 0 && Number(log.new_until) === extUntil,
      JSON.stringify(log));

    st = await api(off.mf, 'GET', '/api/status/' + trialMac);
    check('après ajout : la prochaine vérification débloque',
      st.json.expired === false && st.json.paid === false && st.json.plan === 'trial'
      && st.json.trial_until === extUntil,
      `expired=${st.json.expired} plan=${st.json.plan} until=${st.json.trial_until}`);

    const again = await api(off.mf, 'POST', '/api/v1/trial-extend', {
      token,
      body: { mac: trialMac, days: 3 },
    });
    const stacked = again.json && again.json.trial_until;
    check('second ajout : part de la fin actuelle, pas de maintenant',
      again.status === 200 && Math.abs(stacked - (extUntil + 3 * DAY)) < 2000,
      `écart=${stacked - (extUntil + 3 * DAY)}`);

    const cases = [
      ['MAC invalide', { mac: 'PAS-UNE-MAC', days: 3 }, 400, 'bad_mac'],
      ['MAC inconnue', { mac: mac(99), days: 3 }, 404, 'unknown_mac'],
      ['0 jour', { mac: trialMac, days: 0 }, 400, 'bad_days'],
      ['négatif', { mac: trialMac, days: -5 }, 400, 'bad_days'],
      ['énorme', { mac: trialMac, days: 99999 }, 400, 'bad_days'],
      ['texte', { mac: trialMac, days: 'abc' }, 400, 'bad_days'],
      ['décimal', { mac: trialMac, days: 1.5 }, 400, 'bad_days'],
    ];
    for (const [label, body, status, code] of cases) {
      const r = await api(off.mf, 'POST', '/api/v1/trial-extend', { secret: SECRET, body });
      check('refus ' + label, r.status === status && r.json.error === code,
        `HTTP ${r.status} ${r.json && r.json.error}`);
    }

    const noAuth = await api(off.mf, 'POST', '/api/v1/trial-extend', {
      body: { mac: trialMac, days: 3 },
    });
    check('sans secret : refus', noAuth.status === 401, 'HTTP ' + noAuth.status);
    const badSecret = await api(off.mf, 'POST', '/api/v1/trial-extend', {
      secret: 'mauvais',
      body: { mac: trialMac, days: 3 },
    });
    check('mauvais secret : refus', badSecret.status === 401, 'HTTP ' + badSecret.status);

    const rlogin = await api(off.mf, 'POST', '/api/v1/auth/reseller/login', {
      body: { email: 'riche@test.local', password: 'revendeur-test' },
    });
    const rtoken = rlogin.json && rlogin.json.token;
    const asReseller = await api(off.mf, 'POST', '/api/v1/trial-extend', {
      token: rtoken,
      body: { mac: trialMac, days: 3 },
    });
    check('revendeur ne peut pas ajouter des jours', asReseller.status === 403,
      'HTTP ' + asReseller.status);

    const famMac = mac(31);
    const famAct = await api(off.mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: famMac, plan: 'yearly', customer_name: 'Ancienne famille' },
    });
    const listed = await api(off.mf, 'GET', '/api/v1/families', { token });
    await off.db.prepare(
      'INSERT INTO families (id, name, source_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    ).bind('fam_old', 'Ancienne', '{}', Date.now(), Date.now()).run();
    await off.db.prepare(
      'INSERT INTO family_members (id, family_id, mac, label, created_at) VALUES (?, ?, ?, ?, ?)',
    ).bind('fm_old', 'fam_old', famMac, 'salon', Date.now()).run();
    const famStatus = await api(off.mf, 'GET', '/api/status/' + famMac);
    const cols = await off.db.prepare('PRAGMA table_info(family_members)').all();
    const colNames = (cols.results || []).map((c) => c.name);
    check('ancien appareil familial toujours valide, colonnes gardées',
      famAct.status === 201 && famStatus.json.paid === true && famStatus.json.expired === false
      && colNames.includes('mac') && colNames.includes('family_id'),
      `paid=${famStatus.json && famStatus.json.paid} cols=${colNames.join(',')}`);

    const createFam = await api(off.mf, 'POST', '/api/v1/families', {
      token,
      body: { name: 'Nouvelle', source: { type: 'm3u', m3u_url: 'https://example.invalid/a.m3u' } },
    });
    check('on ne crée plus de clonage',
      createFam.status === 403 && createFam.json.error === 'family_clone_disabled',
      'HTTP ' + createFam.status + ' ' + (createFam.json && createFam.json.error));
    check('la liste des familles existantes reste lisible',
      listed.status === 200 && Array.isArray(listed.json.items),
      'HTTP ' + listed.status);
  } finally {
    await off.mf.dispose();
  }

  console.log('\n=== Interrupteur ALLUMÉ (règle 7 jours, comme la PR #91) ===');
  const on = await boot(true);
  try {
    const admin = await loginAdmin(on.mf);
    const token = admin.json.token;
    const rich = await makeReseller(on.mf, token, 'riche-on@test.local', 4);
    const rid = rich.json.id;
    const lifeMac = mac(41);
    const life = await api(on.mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: lifeMac, plan: 'lifetime', reseller_id: rid },
    });
    const life2 = await api(on.mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: lifeMac, plan: 'lifetime', reseller_id: rid },
    });
    const bal = await balanceOf(on.db, rid);
    check('à vie une 2e fois : 0 crédit de plus',
      life.status === 201 && life.json.credits_charged === 2
      && life2.json && life2.json.already_lifetime === true && life2.json.credits_charged === 0
      && bal === 2,
      `solde=${bal} charged2=${life2.json && life2.json.credits_charged}`);

    const broke = await makeReseller(on.mf, token, 'fauche-on@test.local', 0);
    const denied = await api(on.mf, 'POST', '/api/v1/activate', {
      token,
      body: { mac: mac(42), plan: 'yearly', reseller_id: broke.json.id },
    });
    check('interrupteur allumé : 0 crédit toujours refusé',
      denied.status === 402 && denied.json.error === 'insufficient_credits',
      'HTTP ' + denied.status);

    const id = mac(43);
    await api(on.mf, 'POST', '/api/heartbeat', { body: { mac: id } });
    const start = Date.now() - 8 * DAY;
    await on.db.prepare('UPDATE devices SET first_seen_at = ? WHERE mac = ?').bind(start, id).run();
    await on.db.prepare(
      'INSERT INTO trial_anchors (mac, android_id, started_at) VALUES (?, NULL, ?) '
      + 'ON CONFLICT(mac) DO UPDATE SET started_at = excluded.started_at',
    ).bind(id, start).run();
    let st = await api(on.mf, 'GET', '/api/status/' + id);
    check('jour 8 avec verrou : bloqué',
      st.json.expired === true && st.json.trial_enforced === true,
      `expired=${st.json.expired} enforced=${st.json.trial_enforced}`);
    const ext = await api(on.mf, 'POST', '/api/v1/trial-extend', {
      token,
      body: { mac: id, days: 3 },
    });
    st = await api(on.mf, 'GET', '/api/status/' + id);
    check('verrou allumé : 3 jours rouvrent l’essai',
      ext.status === 200 && st.json.expired === false && st.json.trial_until === ext.json.trial_until,
      `expired=${st.json.expired}`);
  } finally {
    await on.mf.dispose();
  }

  console.log(`\n${pass} réussis, ${fail} échoués`);
  if (failures.length) console.log(failures.join('\n'));
  process.exit(fail ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
