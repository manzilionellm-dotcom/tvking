// Contrats vrais gold.fetch : panne D1 ≠ réglage vide, version publiée ≠
// build autoannoncé. Tous les fetch GitHub sont simulés, aucun client réel.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, createHmac } from 'node:crypto';
import { createD1 } from '../test_support/d1_sqlite.mjs';
import { resetPublishedReleaseForTesting } from '../gold_published_release.js';
import '../prepare_gold_runtime.mjs';
const gold = (await import('../gold.js')).default;
const realFetch = globalThis.fetch;
const publishedBuild = 1793630234;

function fixture() {
  const f = createD1({ schema: false });
  f.db.exec(readFileSync(new URL('../production/schema.sql', import.meta.url), 'utf8'));
  f.db.exec("INSERT INTO admin_users(id,email,password_hash,role,is_active,created_at) VALUES ('admin','fixture@example.invalid','unused','super_admin',1,1)");
  const secret = 'fixture-settings-local-only';
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const h = enc({ alg: 'HS256', typ: 'JWT' });
  const p = enc({ sub: 'admin', role: 'super_admin', iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 });
  const token = `${h}.${p}.${createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url')}`;
  const tasks = [], env = { DB: f.DB, ADMIN_SECRET: secret };
  async function call(path, method = 'GET', body, authorized = true) {
    const response = await gold.fetch(new Request(`https://fixture.example${path}`, {
      method, headers: { 'Content-Type': 'application/json', 'CF-IPCountry': 'SE',
        ...(authorized ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), env, { waitUntil: promise => tasks.push(promise) });
    await Promise.all(tasks.splice(0));
    return { response, body: await response.json() };
  }
  return { ...f, env, call, async close() { await Promise.all(tasks); f.db.close(); } };
}

function mockRelease(options = {}) {
  const calls = [];
  const tag = options.platform === 'mobile' ? 'phone-latest' : 'zuno-tv';
  const apk = options.platform === 'mobile' ? '7motion.apk' : 'zuno-tv.apk';
  const downloadBase = `https://github.com/manzilionellm-dotcom/tvking/releases/download/${tag}/`;
  const manifest = { versionCode: publishedBuild, versionName: 'Fixture',
    url: `${downloadBase}${apk}`, sha256: 'a'.repeat(64), size: 56789,
    ...options.manifest };
  const raw = JSON.stringify(manifest);
  const release = { tag_name: tag, draft: false, prerelease: true, assets: [
    { name: apk, state: 'uploaded', browser_download_url: `${downloadBase}${apk}`,
      size: manifest.size, digest: `sha256:${manifest.sha256}`, ...options.asset },
    { name: 'version.json', state: 'uploaded', browser_download_url: `${downloadBase}version.json`,
      digest: `sha256:${createHash('sha256').update(raw).digest('hex')}`, ...options.manifestAsset },
  ], ...options.release };
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), method: init.method || 'GET' });
    if (String(url) === `https://api.github.com/repos/manzilionellm-dotcom/tvking/releases/tags/${tag}`) {
      return Response.json(release, { status: options.releaseStatus || 200 });
    }
    if (String(url) === `${downloadBase}version.json`) return new Response(raw, { status: options.manifestStatus || 200 });
    if (String(url) === `${downloadBase}${apk}`) {
      assert.equal(init.method, 'HEAD');
      return new Response(null, { status: options.headStatus || 200,
        headers: { 'Content-Length': String(options.headSize ?? manifest.size) } });
    }
    // Un autre canal client absent ne provoque aucun repli sur un tag test.
    assert.match(String(url), /\/(?:phone-latest|zuno-tv)(?:\/version\.json)?$/);
    return new Response('{}', { status: 404 });
  };
  return calls;
}

test.beforeEach(() => { resetPublishedReleaseForTesting(); mockRelease({ releaseStatus: 404 }); });
test.afterEach(() => { resetPublishedReleaseForTesting(); globalThis.fetch = realFetch; });

test('tous les réglages publics : vraie panne D1 →503, puis état vide légitime →200', async () => {
  const cases = [
    ['/api/announcement', /SELECT value FROM app_config WHERE key = 'announcements_enabled'/],
    ['/api/home-layout', /SELECT key, position, enabled, ribbon, featured, updated_at FROM home_layout/],
    ['/api/app-version?platform=tv', /SELECT value FROM app_config WHERE key = \?/],
    ['/api/theme?platform=tv', /SELECT value FROM app_config WHERE key = \?/],
    ['/api/ad', /SELECT value FROM app_config WHERE key = \?/],
    ['/api/featured', /SELECT value FROM app_config WHERE key = 'featured_name'/],
    ['/api/feedback-prompt', /SELECT value FROM app_config WHERE key = 'feedback_enabled'/],
    ['/api/pricing', /SELECT value FROM app_config WHERE key = \?/],
  ];
  for (const [path, match] of cases) {
    const f = fixture();
    try {
      f.faults.add({ match, times: 1 });
      const failed = await f.call(path);
      assert.equal(failed.response.status, 503, path);
      assert.equal(failed.body.error, 'configuration_unavailable', path);
      assert.equal((await f.call(path)).response.status, 200, path);
      delete f.env.DB;
      assert.equal((await f.call(path)).response.status, 503, `sans DB ${path}`);
    } finally { await f.close(); }
  }
});

test('DDL indisponible et automatisation de thème en panne ne deviennent pas un succès', async () => {
  const f = fixture();
  try {
    f.faults.add({ match: /CREATE TABLE IF NOT EXISTS home_layout/, times: 1 });
    assert.equal((await f.call('/api/home-layout')).response.status, 503);
    const originalPrepare = f.DB.prepare.bind(f.DB);
    f.env.DB = { ...f.DB, prepare(sql) {
      const source = originalPrepare(sql);
      const bind = source.bind.bind(source);
      source.bind = (...args) => {
        const statement = bind(...args);
        if (args[0] === 'theme_automations_tv') statement.first = async () => { throw new Error('fixture automation unavailable'); };
        return statement;
      };
      return source;
    } };
    assert.equal((await f.call('/api/theme?platform=tv')).response.status, 503);
  } finally { await f.close(); }
});

test('annonces : HTTP(S) accepté, schémas actifs et identifiants refusés après authentification', async () => {
  const f = fixture();
  try {
    for (const url of ['javascript:alert(1)', 'data:text/html,x', 'https://user:pass@example.invalid/', 'https:///','https:///example.invalid', 'https://example.invalid/a b', 'https:example.invalid', 'https:\\example.invalid']) {
      const bad = await f.call('/api/v1/announcements', 'POST', { title: 'Fixture', url });
      assert.equal(bad.response.status, 400, url);
    }
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM app_broadcasts').get().n, 0);
    const denied = await f.call('/api/v1/announcements', 'POST', { title: 'Fixture', url: 'javascript:alert(1)' }, false);
    assert.ok([401, 403].includes(denied.response.status));
    assert.equal((await f.call('/api/v1/announcements', 'POST', { title: 'Fixture', url: 'https://example.invalid/info' })).response.status, 201);
    assert.equal((await f.call('/api/announcement')).body.url, 'https://example.invalid/info');
  } finally { await f.close(); }
});

test('forcer adopte seulement le build publié vérifié, jamais le build autoannoncé', async () => {
  const f = fixture(); const calls = mockRelease();
  try {
    f.db.exec("INSERT INTO app_config(key,value) VALUES ('latest_build_ts_tv','1999999999'),('min_build_ts_tv','0')");
    const before = await f.call('/api/v1/force-update?platform=tv');
    assert.equal(before.body.canForce, true);
    assert.equal(before.body.publishedBuildTs, publishedBuild);
    assert.equal(before.body.latestBuildTs, publishedBuild);
    assert.equal(before.body.observedLatestBuildTs, 1999999999);
    const count = calls.length;
    const app = await f.call('/api/app-version?platform=tv&build=2147483647');
    assert.equal(calls.length, count, 'le GET app réutilise la preuve bornée en cache');
    assert.equal(app.body.minBuildTs, 0);
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='latest_build_ts_tv'").get().value, '1999999999');
    const forced = await f.call('/api/v1/force-update?platform=tv', 'POST', { action: 'force' });
    assert.equal(forced.response.status, 200); assert.equal(forced.body.ok, true);
    assert.equal(forced.body.minBuildTs, publishedBuild);
    assert.ok(calls.length > count, 'Forcer revalide la disponibilité sans le cache');
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='min_build_ts_tv'").get().value, String(publishedBuild));
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='latest_build_ts_tv'").get().value, '1999999999');
    const audit = f.db.prepare("SELECT after_json FROM audit_logs WHERE action='force_update.on'").get();
    assert.equal(JSON.parse(audit.after_json).min_build_ts, publishedBuild);
    assert.equal((await f.call('/api/app-version?platform=tv')).body.minBuildTs, publishedBuild);
  } finally { await f.close(); }
});

test('aucune preuve publiée : seuil non appliqué, forçage refusé, désactivation possible', async () => {
  const f = fixture(); const calls = mockRelease({ releaseStatus: 404 });
  try {
    f.db.exec("INSERT INTO app_config(key,value) VALUES ('latest_build_ts_tv','1999999999'),('min_build_ts_tv','1999999999')");
    const status = await f.call('/api/v1/force-update?platform=tv');
    assert.equal(status.body.canForce, false); assert.equal(status.body.minBuildTs, 0);
    assert.equal(status.body.configuredMinBuildTs, 1999999999);
    const forced = await f.call('/api/v1/force-update?platform=tv', 'POST', { action: 'force' });
    assert.equal(forced.response.status, 409); assert.equal(forced.body.error, 'published_release_unverified');
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='min_build_ts_tv'").get().value, '1999999999');
    const count = calls.length;
    const disabled = await f.call('/api/v1/force-update?platform=tv', 'POST', { action: 'disable' });
    assert.equal(disabled.response.status, 200); assert.equal(disabled.body.minBuildTs, 0);
    assert.equal(calls.length, count, 'désactiver ne dépend pas de GitHub');
    assert.equal((await f.call('/api/v1/force-update?platform=mobile')).body.canForce, false);
    assert.ok(calls.every(call => !/phone-test|zuno-tv-test|review/.test(call.url)));
  } finally { await f.close(); }
});

test('preuve GET mise en cache : retirer l’APK interdit immédiatement un nouveau forçage', async () => {
  const f = fixture(); mockRelease();
  try {
    f.db.exec("INSERT INTO app_config(key,value) VALUES ('min_build_ts_tv','1999999999')");
    const before = await f.call('/api/v1/force-update?platform=tv');
    assert.equal(before.body.canForce, true);
    assert.equal(before.body.minBuildTs, 0, 'le seuil d’un ancien build test n’est pas imposé');
    assert.equal(before.body.configuredMinBuildTs, 1999999999);
    const calls = mockRelease({ headStatus: 404 });
    assert.equal((await f.call('/api/v1/force-update?platform=tv')).body.canForce, true);
    assert.equal(calls.length, 0, 'GET réutilise la preuve bornée déjà lue');
    const forced = await f.call('/api/v1/force-update?platform=tv', 'POST', { action: 'force' });
    assert.equal(forced.response.status, 409);
    assert.ok(calls.some(call => call.method === 'HEAD'));
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='min_build_ts_tv'").get().value, '1999999999');
    assert.equal((await f.call('/api/app-version?platform=tv')).body.canForce, false);
  } finally { await f.close(); }
});

test('auth refusée : aucune vérification GitHub ni écriture de seuil', async () => {
  const f = fixture(); const calls = mockRelease();
  try {
    for (const method of ['GET', 'POST']) {
      const result = await f.call('/api/v1/force-update?platform=tv', method, method === 'POST' ? { action: 'force' } : undefined, false);
      assert.ok([401, 403].includes(result.response.status));
    }
    assert.equal(calls.length, 0);
    assert.equal(f.db.prepare("SELECT COUNT(*) n FROM app_config WHERE key='min_build_ts_tv'").get().n, 0);
  } finally { await f.close(); }
});

test('mobile préparé : seul phone-latest peut autoriser son seuil, sans changer Zuno', async () => {
  const f = fixture();
  const mobileBuild = 1729;
  const calls = mockRelease({ platform: 'mobile', manifest: {
    versionCode: mobileBuild, packageName: 'com.manzilionellm.tvking.tv_king',
  } });
  try {
    f.db.exec("INSERT INTO app_config(key,value) VALUES ('latest_build_ts','1999999999'),('min_build_ts','0'),('min_build_ts_tv','123')");
    const status = await f.call('/api/v1/force-update?platform=mobile');
    assert.equal(status.body.canForce, true);
    assert.equal(status.body.publishedBuildTs, mobileBuild);
    assert.equal(status.body.publicationSource, 'https://github.com/manzilionellm-dotcom/tvking/releases/download/phone-latest/version.json');
    const forced = await f.call('/api/v1/force-update?platform=mobile', 'POST', { action: 'force' });
    assert.equal(forced.response.status, 200); assert.equal(forced.body.minBuildTs, mobileBuild);
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='min_build_ts'").get().value, String(mobileBuild));
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='min_build_ts_tv'").get().value, '123');
    assert.equal(f.db.prepare("SELECT value FROM app_config WHERE key='latest_build_ts'").get().value, '1999999999');
    assert.ok(calls.some(call => call.url.endsWith('/phone-latest/7motion.apk') && call.method === 'HEAD'));
    assert.ok(calls.every(call => call.url.includes('/phone-latest')));
  } finally { await f.close(); }
});

test('mobile : aucun repli latest/test et aucun forçage avec manifeste incomplet ou package Store', async () => {
  const cases = [
    { manifest: { url: 'https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/7motion.apk' } },
    { manifest: { url: 'https://github.com/manzilionellm-dotcom/tvking/releases/download/phone-test/7motion.apk' } },
    { manifest: { url: 'https://github.com/manzilionellm-dotcom/tvking/releases/download/7motion-test/7motion.apk' } },
    { manifest: { packageName: 'com.manzilionellm.tvking' } },
    { manifest: { sha256: undefined } },
    { manifest: { size: undefined } },
    // Forme réellement observée sur le canal client : buildLabel est un
    // libellé, pas un remplacement de versionCode, SHA-256 ou taille absents.
    { manifest: { versionCode: 1729, versionName: '0.3.4', buildLabel: '1988113',
      sha256: undefined, size: undefined, mandatory: false } },
    { releaseStatus: 404 },
  ];
  for (const item of cases) {
    resetPublishedReleaseForTesting(); const calls = mockRelease({ platform: 'mobile', ...item });
    const f = fixture();
    try {
      const result = await f.call('/api/v1/force-update?platform=mobile', 'POST', { action: 'force' });
      assert.equal(result.response.status, 409, JSON.stringify(item));
      assert.equal(f.db.prepare("SELECT COUNT(*) n FROM app_config WHERE key='min_build_ts'").get().n, 0);
      assert.ok(calls.every(call => call.url.includes('/phone-latest')));
    } finally { await f.close(); }
  }
});

test('build de test, mauvais package/digest/taille ou APK absent : jamais forçable', async () => {
  const cases = [
    { manifest: { url: 'https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/zuno-tv.apk' } },
    { manifest: { packageName: 'com.sevenmotion.tv.seven_tv.essai' } },
    { manifest: { sha256: 'not-a-digest' } },
    { asset: { digest: `sha256:${'b'.repeat(64)}` } },
    { manifestAsset: { digest: `sha256:${'b'.repeat(64)}` } },
    { asset: { size: 123 } },
    { headSize: 123 },
    { headStatus: 404 },
    { release: { draft: true } },
  ];
  for (const item of cases) {
    resetPublishedReleaseForTesting(); mockRelease(item); const f = fixture();
    try {
      const response = await f.call('/api/v1/force-update?platform=tv', 'POST', { action: 'force' });
      assert.equal(response.response.status, 409, JSON.stringify(item));
      assert.equal(f.db.prepare("SELECT COUNT(*) n FROM app_config WHERE key='min_build_ts_tv'").get().n, 0);
    } finally { await f.close(); }
  }
});
