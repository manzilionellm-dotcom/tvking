// =========================================================
//  run.mjs — Parcours de bout en bout, en local uniquement
// =========================================================
//
//  Trois processus, comme en vrai, mais rien ne quitte la machine :
//    1. Worker Cloudflare  → `wrangler dev --local` (miniflare + D1)
//    2. Panel admin        → Vite, qui proxifie /api vers le Worker
//    3. Box simulée        → les mêmes appels HTTP que l'app TV
//       (heartbeat, status, device-source, announcement)
//
//  Le mot de passe admin est tiré au hasard au lancement, écrit dans
//  cloudflare/.dev.vars (gitignoré) et jamais affiché. Les liens M3U
//  sont des adresses 127.0.0.1 : on ne télécharge aucune liste.
//
//  Lancement : npm install && npx playwright install chromium && npm run e2e
// =========================================================

import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { chromium } from 'playwright';

const HERE = dirname(fileURLToPath(import.meta.url));
const CLOUDFLARE = resolve(HERE, '../../cloudflare');
const PANEL = resolve(HERE, '../../admin-panel');
const WRANGLER = resolve(HERE, 'node_modules/wrangler/bin/wrangler.js');
const VITE = resolve(PANEL, 'node_modules/vite/bin/vite.js');

const WORKER_PORT = 8787;
const PANEL_PORT = 5173;
const WORKER = `http://127.0.0.1:${WORKER_PORT}`;
const PANEL_ORIGIN = `http://127.0.0.1:${PANEL_PORT}`;
const PERSIST = resolve(HERE, '.state');

// Adresses factices. Elles ne sont jamais téléchargées.
const M3U_A = 'http://127.0.0.1/e2e/liste-a.m3u';
const M3U_B = 'http://127.0.0.1/e2e/liste-b.m3u';
const MESSAGE_TITLE = 'Essai message instantane';
const MESSAGE_BODY = 'Texte de demonstration local';
const CHANNEL = 'Demo-locale';
const CUSTOMER = 'Client Essai Local';

const secret = randomBytes(24).toString('hex');
const failures = [];
const children = [];

function redact(text) {
  let s = String(text);
  if (secret) s = s.split(secret).join('[masque]');
  s = s.replace(/Bearer\s+[A-Za-z0-9._\-]+/gi, 'Bearer [masque]');
  s = s.replace(/"(token|password|password_hash|authorization)"\s*:\s*"[^"]*"/gi, '"$1":"[masque]"');
  s = s.replace(/https?:\/\/(?!127\.0\.0\.1|localhost)[^\s"'<>]+/gi, '[url-masquee]');
  return s;
}

function log(line) {
  process.stdout.write(redact(line) + '\n');
}

function check(name, ok, detail = '') {
  const mark = ok ? 'OK   ' : 'ECHEC';
  log(`${mark}  ${name}${detail ? ' — ' + detail : ''}`);
  if (!ok) failures.push(name);
  return ok;
}

function scrub(value) {
  if (!value || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(scrub);
  const out = {};
  for (const [k, v] of Object.entries(value)) {
    if (/password|token|secret|authorization/i.test(k)) out[k] = '[masque]';
    else if (typeof v === 'string' && /^https?:\/\//.test(v) && !v.startsWith('http://127.0.0.1') && !v.startsWith('http://localhost')) {
      out[k] = '[url-masquee]';
    } else if (v && typeof v === 'object') out[k] = scrub(v);
    else out[k] = v;
  }
  return out;
}

function brief(value) {
  try { return JSON.stringify(scrub(value)); }
  catch { return '[non-serialisable]'; }
}

function randomMac() {
  const hex = [...randomBytes(5)].map((b) => b.toString(16).toUpperCase().padStart(2, '0'));
  return `MK:${hex.join(':')}`;
}

function childEnv() {
  const env = { ...process.env, WRANGLER_SEND_METRICS: 'false', CI: '1' };
  for (const key of Object.keys(env)) {
    if (/CLOUDFLARE|CF_API|CF_TOKEN|ADMIN_SECRET|WRANGLER_API/i.test(key)) delete env[key];
  }
  return env;
}

function start(cmd, args, cwd, label) {
  const child = spawn(cmd, args, {
    cwd,
    env: childEnv(),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const tail = [];
  const push = (buf) => {
    const text = redact(buf.toString());
    for (const line of text.split('\n')) {
      if (!line) continue;
      tail.push(line);
      if (tail.length > 80) tail.shift();
    }
  };
  child.stdout.on('data', push);
  child.stderr.on('data', push);
  child.label = label;
  child.tail = tail;
  children.push(child);
  return child;
}

function stopAll() {
  for (const child of children) {
    if (child.exitCode == null && child.pid) {
      try { child.kill('SIGTERM'); } catch { /* déjà arrêté */ }
    }
  }
  const devVars = resolve(CLOUDFLARE, '.dev.vars');
  try { rmSync(devVars, { force: true }); } catch { /* rien */ }
}

async function waitHttp(url, label, timeoutMs) {
  const started = Date.now();
  let last = 'aucune réponse';
  while (Date.now() - started < timeoutMs) {
    try {
      const resp = await fetch(url, { method: 'GET' });
      log(`PRET  ${label} HTTP ${resp.status} (${url})`);
      return;
    } catch (e) {
      last = e && e.message ? e.message : String(e);
      await delay(400);
    }
  }
  throw new Error(`${label} injoignable après ${timeoutMs} ms (${redact(last)})`);
}

async function jsonFetch(url, opts = {}) {
  const headers = { Accept: 'application/json', ...(opts.headers || {}) };
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json';
  const resp = await fetch(url, {
    method: opts.method || 'GET',
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });
  const text = await resp.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text.slice(0, 180) }; }
  return { status: resp.status, json };
}

/// Appel fait DEPUIS la page du panel (même origine, proxy Vite, jeton
/// du localStorage). C'est le chemin réseau du fichier src/lib/api.ts.
async function panel(page, path, opts = {}) {
  return page.evaluate(async ({ path, opts }) => {
    const headers = { Accept: 'application/json', 'Content-Type': 'application/json' };
    if (!opts.noAuth) {
      const token = localStorage.getItem('auth_token');
      if (token) headers.Authorization = 'Bearer ' + token;
    }
    const resp = await fetch(path, {
      method: opts.method || 'GET',
      headers,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    });
    const text = await resp.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text.slice(0, 180) }; }
    return { status: resp.status, json };
  }, { path, opts });
}

/// Client box : mêmes routes publiques que l'app Flutter.
async function box(method, path, body) {
  return jsonFetch(WORKER + path, { method, body });
}

async function applySchema() {
  // Base neuve à chaque lancement : sinon le client du run précédent
  // reste en D1 et la liste Clients compte deux fois le même nom.
  rmSync(PERSIST, { recursive: true, force: true });
  mkdirSync(PERSIST, { recursive: true });
  const devVars = resolve(CLOUDFLARE, '.dev.vars');
  writeFileSync(devVars, `ADMIN_SECRET=${secret}\n`, { mode: 0o600 });
  log('SCHEMA  application de schema.sql sur le D1 local (sortie masquée)');
  await new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [
      WRANGLER, 'd1', 'execute', 'tvking_licensing',
      '--local', '--persist-to', PERSIST,
      '--file', 'schema.sql',
    ], { cwd: CLOUDFLARE, env: childEnv(), stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    child.stdout.on('data', (b) => { out += b.toString(); });
    child.stderr.on('data', (b) => { out += b.toString(); });
    child.on('exit', (code) => {
      if (code === 0) resolvePromise();
      else reject(new Error('schema.sql a échoué (code ' + code + ')\n' + redact(out).slice(-2000)));
    });
  });
}

async function run() {
  if (!existsSync(WRANGLER)) {
    throw new Error('wrangler absent. Lance npm install dans android-app/e2e/panel-box.');
  }
  if (!existsSync(VITE)) {
    throw new Error('vite absent. Lance npm ci dans android-app/admin-panel.');
  }

  log('=== Suite panel + box (local, sans déploiement) ===');
  await applySchema();

  // `wrangler dev` est local par défaut (miniflare). On n'ajoute JAMAIS
  // `--remote` : ça parlerait au Worker de production.
  start(process.execPath, [
    WRANGLER, 'dev', '--port', String(WORKER_PORT),
    '--ip', '127.0.0.1', '--persist-to', PERSIST,
    '--log-level', 'warn',
  ], CLOUDFLARE, 'worker');
  await waitHttp(WORKER + '/api/v1/auth/login', 'worker', 90000);

  start(process.execPath, [
    VITE, '--host', '127.0.0.1', '--port', String(PANEL_PORT), '--strictPort',
  ], PANEL, 'panel');
  await waitHttp(PANEL_ORIGIN + '/login', 'panel', 40000);

  const anon = await jsonFetch(PANEL_ORIGIN + '/api/v1/customers');
  check(
    'sans jeton, le panel refuse /customers',
    anon.status === 401,
    `HTTP ${anon.status} ${brief(anon.json)}`,
  );

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(20000);

  try {
    await parcours(page);
  } finally {
    await browser.close();
  }

  log('');
  log('=== Ce que cette simulation ne prouve pas ===');
  for (const line of LIMITES) log('  - ' + line);

  if (failures.length) {
    log('');
    log(`BILAN  ${failures.length} échec(s) : ${failures.join(' | ')}`);
    for (const child of children) {
      if (child.tail && child.tail.length) {
        log(`--- journal ${child.label} (masqué, 20 dernières lignes) ---`);
        for (const line of child.tail.slice(-20)) log(line);
      }
    }
    process.exitCode = 1;
  } else {
    log('');
    log('BILAN  tous les contrôles locaux sont passés');
  }
}

const LIMITES = [
  'La vraie box (APK / Android TV) n\'a pas tourné : pas de lecture vidéo, pas de décodage M3U, pas de cache local effacé à l\'écran.',
  'Le code de l\'app (remote_source_repository.dart) garde la liste déjà en mémoire quand le serveur renvoie source=null. L\'effacement prouvé ici est celui du serveur, pas celui de l\'écran.',
  'Le pays, l\'IP Cloudflare et le ciblage géographique des annonces ne sont pas fournis par miniflare.',
  'L\'expiration est provoquée en écrivant expires_at dans le passé (PATCH licence). On n\'a pas attendu l\'horloge réelle.',
  'Aucun flux et aucune playlist n\'ont été contactés. Le panel public en ligne n\'a pas été ouvert.',
  'L\'installation Downloader, le cast, le lecteur 4K et les releases zuno-tv / phone-latest ne sont pas couverts.',
];

async function parcours(page) {
  const mac = randomMac();
  const macExpire = randomMac();
  log(`MAC    activation UI ${mac}`);
  log(`MAC    expiration    ${macExpire}`);

  // ----- Connexion admin (écran réel) -----
  await page.goto(PANEL_ORIGIN + '/login');
  await page.getByRole('button', { name: 'Se connecter' }).waitFor();
  await page.locator('input[type="password"]').fill('mot-de-passe-incorrect');
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.getByText('Invalid credentials').waitFor();
  check('connexion refusée si le mot de passe est faux', true, 'écran login, HTTP via le proxy du panel');

  await page.locator('input[type="password"]').fill(secret);
  await page.getByRole('button', { name: 'Se connecter' }).click();
  await page.getByRole('heading', { name: 'Tableau de bord' }).waitFor();
  const me = await panel(page, '/api/v1/auth/me');
  check(
    'connexion admin acceptée',
    me.status === 200 && me.json && me.json.user && me.json.user.role === 'super_admin',
    `HTTP ${me.status} role=${me.json && me.json.user ? me.json.user.role : '?'}`,
  );

  // ----- Création + activation depuis l'écran, SANS lien M3U -----
  await page.goto(PANEL_ORIGIN + '/activate');
  await page.getByRole('heading', { name: "Activer l'application" }).waitFor();
  await page.getByPlaceholder('MK:XX:XX:XX:XX:XX').fill(mac);
  await page.getByPlaceholder('Ex. Salon de Karim').fill(CUSTOMER);
  await page.getByRole('button', { name: /Activer l.application/ }).click();
  await page.getByText('Application activée').waitFor();
  check('écran d\'activation : appareil créé sans source', true, mac);

  await page.goto(PANEL_ORIGIN + '/customers');
  await page.getByPlaceholder('Nom, e-mail, téléphone…').fill(CUSTOMER);
  const clientCell = page.getByRole('cell', { name: CUSTOMER, exact: true });
  await clientCell.first().waitFor();
  const clientCount = await clientCell.count();
  check('le client apparaît dans la liste du panel', clientCount === 1, `lignes=${clientCount}`);

  const licences = await panel(page, '/api/v1/licenses');
  const lic = licences.json && Array.isArray(licences.json.items)
    ? licences.json.items.find((row) => row.device_mac === mac)
    : null;
  check(
    'une licence active est liée à la MAC',
    licences.status === 200 && lic && lic.status === 'active' && lic.plan === 'monthly' && typeof lic.expires_at === 'number',
    lic ? `plan=${lic.plan} status=${lic.status}` : brief(licences.json),
  );
  const expiresBefore = lic ? lic.expires_at : null;

  const before = await box('GET', '/api/status/' + mac);
  check(
    'la box lit un abonnement encore valide',
    before.status === 200 && before.json && before.json.paid === true && before.json.expired === false,
    brief(before.json),
  );
  const src0 = await box('GET', '/api/device-source/' + mac);
  check(
    'la box n\'a pas de liste tant que le panel n\'en a pas poussé',
    src0.status === 200 && src0.json && src0.json.source == null,
    brief(src0.json),
  );

  // ----- Ajout puis modification du M3U, SANS repasser par /activate -----
  const putA = await panel(page, '/api/v1/sources/' + encodeURIComponent(mac), {
    method: 'PUT',
    body: { source: { type: 'm3u', m3u_url: M3U_A, label: 'Liste A' } },
  });
  check('ajout du lien M3U (endpoint séparé de l\'activation)', putA.status === 200 && putA.json && putA.json.ok === true, brief(putA.json));

  const seenA = await box('GET', '/api/device-source/' + mac);
  const urlA = seenA.json && seenA.json.source ? seenA.json.source.m3u_url : null;
  check('la box reçoit le premier lien', seenA.status === 200 && urlA === M3U_A, `m3u_url=${urlA}`);

  const putB = await panel(page, '/api/v1/sources/' + encodeURIComponent(mac), {
    method: 'PUT',
    body: { source: { type: 'm3u', m3u_url: M3U_B, label: 'Liste B' } },
  });
  check('modification du lien M3U', putB.status === 200 && putB.json && putB.json.count === 1, brief(putB.json));

  const seenB = await box('GET', '/api/device-source/' + mac);
  const urlB = seenB.json && seenB.json.source ? seenB.json.source.m3u_url : null;
  check(
    'la box reçoit le lien modifié et plus l\'ancien',
    seenB.status === 200 && urlB === M3U_B && urlB !== M3U_A,
    `m3u_url=${urlB}`,
  );

  const licences2 = await panel(page, '/api/v1/licenses');
  const lic2 = licences2.json && licences2.json.items
    ? licences2.json.items.find((row) => row.device_mac === mac)
    : null;
  check(
    'changer le M3U ne prolonge pas la licence',
    !!lic2 && lic2.expires_at === expiresBefore,
    `expires_at identique=${lic2 ? lic2.expires_at === expiresBefore : false}`,
  );

  // ----- Message instantané (écran Annonces → box) -----
  await page.goto(PANEL_ORIGIN + '/notifications');
  await page.getByRole('heading', { name: 'Annonces' }).waitFor();
  await page.getByPlaceholder('Ex. De nouvelles chaînes sont arrivées 🎬').fill(MESSAGE_TITLE);
  await page.getByPlaceholder('Ex. Profite des nouvelles chaînes sport et cinéma, bon visionnage !').fill(MESSAGE_BODY);
  await page.getByRole('button', { name: 'Publier à tous' }).click();
  await page.getByText('Annonce publiée pour TOUT LE MONDE').waitFor();
  const ann = await box('GET', '/api/announcement');
  check(
    'la box lit le message instantané',
    ann.status === 200 && ann.json && ann.json.title === MESSAGE_TITLE && ann.json.body === MESSAGE_BODY,
    brief(ann.json),
  );

  // ----- Effacement de liste -----
  const wiped = await panel(page, '/api/v1/sources/' + encodeURIComponent(mac), { method: 'DELETE' });
  check('effacement de la liste côté panel', wiped.status === 200 && wiped.json && wiped.json.ok === true, brief(wiped.json));
  const srcGone = await box('GET', '/api/device-source/' + mac);
  check(
    'la box ne reçoit plus de liste',
    srcGone.status === 200 && srcGone.json && srcGone.json.source == null,
    brief(srcGone.json),
  );
  const stillPaid = await box('GET', '/api/status/' + mac);
  check(
    'effacer la liste ne coupe pas l\'abonnement',
    stillPaid.status === 200 && stillPaid.json && stillPaid.json.paid === true && stillPaid.json.expired === false,
    brief(stillPaid.json),
  );

  // ----- État de la box (heartbeat → page En ligne) -----
  const beat = await box('POST', '/api/heartbeat', {
    mac,
    model: 'simulateur-e2e',
    platform: 'tv',
    channel: CHANNEL,
    appVersion: 'e2e',
    sources: [{ type: 'm3u', name: 'Liste B', server: M3U_B, username: '', channels: 0, active: false }],
  });
  check(
    'heartbeat de la box accepté',
    beat.status === 200 && beat.json && beat.json.ok === true && beat.json.paid === true,
    brief(beat.json),
  );

  let online = null;
  for (let i = 0; i < 10; i++) {
    online = await panel(page, '/api/v1/online');
    const hit = online.json && Array.isArray(online.json.items)
      && online.json.items.some((row) => row.mac === mac && row.channel === CHANNEL);
    if (online.status === 200 && hit) break;
    await delay(300);
  }
  const onlineHit = online && online.json && Array.isArray(online.json.items)
    ? online.json.items.find((row) => row.mac === mac)
    : null;
  check(
    'le panel voit la box en ligne et la chaîne annoncée',
    !!onlineHit && onlineHit.channel === CHANNEL,
    brief(onlineHit || online.json),
  );

  await page.goto(PANEL_ORIGIN + '/online');
  await page.getByRole('heading', { name: 'En ligne' }).waitFor();
  await page.getByText(mac).waitFor();
  await page.getByText(CHANNEL).waitFor();
  check('l\'écran En ligne affiche la MAC et la chaîne', true, mac);

  await page.goto(PANEL_ORIGIN + '/devices');
  await page.getByPlaceholder('MAC, nom, client…').fill(mac);
  await page.locator('tbody').getByText(mac, { exact: true }).waitFor();
  check('la fiche appareils retrouve la MAC', true);

  // ----- Expiration : autre client, lien posé, puis échéance dans le passé -----
  const created = await panel(page, '/api/v1/activate', {
    method: 'POST',
    body: { mac: macExpire, plan: 'monthly', customer_name: 'Client Echeance' },
  });
  check(
    'second client activé pour le test d\'échéance',
    created.status === 201 && created.json && created.json.license_id && typeof created.json.expires_at === 'number',
    `HTTP ${created.status} plan=${created.json && created.json.plan}`,
  );
  const putExp = await panel(page, '/api/v1/sources/' + encodeURIComponent(macExpire), {
    method: 'PUT',
    body: { source: { type: 'm3u', m3u_url: M3U_A, label: 'Liste echeance' } },
  });
  check('lien M3U posé avant l\'échéance', putExp.status === 200, brief(putExp.json));
  const open = await box('GET', '/api/device-source/' + macExpire);
  check(
    'avant l\'échéance la box reçoit encore le lien',
    open.status === 200 && open.json && open.json.source && open.json.source.m3u_url === M3U_A,
    brief(open.json && open.json.source ? { m3u_url: open.json.source.m3u_url } : open.json),
  );

  if (!created.json || !created.json.license_id) {
    check('suite échéance ignorée : pas d\'identifiant de licence', false, brief(created.json));
    return;
  }
  const past = Date.now() - 60 * 1000;
  const patched = await panel(page, '/api/v1/licenses/' + created.json.license_id, {
    method: 'PATCH',
    body: { expires_at: past },
  });
  check('échéance placée dans le passé', patched.status === 200 && patched.json && patched.json.updated === 1, brief(patched.json));

  const expired = await box('GET', '/api/status/' + macExpire);
  check(
    'la box voit l\'abonnement expiré',
    expired.status === 200 && expired.json && expired.json.expired === true && expired.json.paid === false && expired.json.days_left === 0,
    brief(expired.json),
  );
  const hidden = await box('GET', '/api/device-source/' + macExpire);
  check(
    'la box expirée ne reçoit plus le lien',
    hidden.status === 200 && hidden.json && hidden.json.source == null && hidden.json.blocked === 'expired',
    brief(hidden.json),
  );
  const adminStill = await panel(page, '/api/v1/sources/' + encodeURIComponent(macExpire));
  const adminUrl = adminStill.json && adminStill.json.source ? adminStill.json.source.m3u_url : null;
  check(
    'le panel garde le lien, seule la box est coupée',
    adminStill.status === 200 && adminUrl === M3U_A,
    `m3u_url=${adminUrl}`,
  );
}

process.on('SIGINT', () => { stopAll(); process.exit(1); });
process.on('SIGTERM', () => { stopAll(); process.exit(1); });

run()
  .catch((e) => {
    log('ERREUR ' + (e && e.stack ? e.stack : e));
    for (const child of children) {
      if (child.tail && child.tail.length) {
        log(`--- journal ${child.label} (masqué) ---`);
        for (const line of child.tail.slice(-30)) log(line);
      }
    }
    process.exitCode = 1;
  })
  .finally(() => {
    stopAll();
  });
