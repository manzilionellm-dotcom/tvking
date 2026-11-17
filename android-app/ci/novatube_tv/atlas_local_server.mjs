// =========================================================
//  atlas_local_server.mjs — Atlas NovaTube LOCAL pour tester l'app TV
// =========================================================
//  Lance le VRAI code du Worker (novatube4k-entry.js : routes
//  /api/novatube4k/* + routes admin historiques) dans workerd/Miniflare,
//  avec une base D1 locale vide et AUCUN accès réseau sortant. Sert au test
//  d'intégration test/novatube_tv/atlas_local_integration_test.dart.
//
//  Usage (depuis un checkout qui contient android-app/cloudflare/novatube4k*.js
//  et ses node_modules, par exemple la branche des PR serveur NovaTube) :
//      node atlas_local_server.mjs <dossier_cloudflare> <fichier_info.json>
//  Le fichier d'info reçoit { url, adminSecret } quand le serveur est prêt.
//  Arrêt : Ctrl+C (ou kill). Rien n'est envoyé à la production.
// =========================================================
import { randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';

const cloudflare = resolve(process.argv[2] || '.');
const infoPath = resolve(process.argv[3] || 'atlas-local.json');
// Miniflare est installé dans le dossier du Worker, pas ici.
const require = createRequire(join(cloudflare, 'package.json'));
const { Miniflare, Log, LogLevel } = require('miniflare');

const adminSecret = randomBytes(32).toString('hex');
const outbound = [];
const mf = new Miniflare({
  host: '127.0.0.1',
  // Port fixe pour l'émulateur (adb reverse), sinon un port libre.
  port: Number(process.env.ATLAS_PORT || 0),
  modules: true,
  modulesRules: [{ type: 'ESModule', include: ['**/*.js'] }],
  scriptPath: join(cloudflare, 'novatube4k-entry.js'),
  modulesRoot: cloudflare,
  cf: false,
  compatibilityDate: '2025-05-01',
  compatibilityFlags: [],
  d1Databases: { DB: 'novatube-tv-local-' + Date.now() },
  durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
  bindings: {
    ADMIN_SECRET: adminSecret,
    SECRETS_KEY: randomBytes(32).toString('hex'),
    ACCOUNT_ENCRYPTION_KEY: randomBytes(32).toString('hex'),
    DEVICE_TOKEN_SECRET: randomBytes(32).toString('hex'),
    GOLD_PANEL_API_KEY: 'fixtureOnlyKeyNeverUsedOnTheNetwork1234',
    DEFAULT_SERVERS: '[]',
    PANEL_ORIGINS: 'https://atlas-console-k7q2.vercel.app',
  },
  // Toute requête sortante du Worker est refusée AVANT le réseau.
  outboundService: async (request) => {
    outbound.push(new URL(request.url).host);
    return new Response('{"error":"external_network_forbidden_in_fixture"}', {
      status: 503, headers: { 'Content-Type': 'application/json' },
    });
  },
  log: new Log(LogLevel.WARN),
});

const url = await mf.ready;
const db = await mf.getD1Database('DB');
const schema = readFileSync(join(cloudflare, 'schema.sql'), 'utf8');
for (const statement of schema.split(/;\s*(?:\n|$)/)
  .map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean)) {
  await db.prepare(statement).run();
}
try { await db.prepare('ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT').run(); } catch (_) {}

writeFileSync(infoPath, JSON.stringify({ url: String(url).replace(/\/$/, ''), adminSecret }));
console.log('PRÊT ' + String(url));
const stop = async () => {
  console.log('requêtes sortantes refusées : ' + outbound.length);
  await mf.dispose();
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
setInterval(() => {}, 1 << 30);
