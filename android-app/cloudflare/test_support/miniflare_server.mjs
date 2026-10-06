// =========================================================
//  miniflare_server.mjs — Le Worker sur workerd, SANS le proxy de `wrangler dev`
// =========================================================
//  `wrangler dev` place un « ProxyWorker » devant le Worker. Ce proxy
//  perd parfois sa connexion vers le Worker sous forte charge locale
//  (son propre code le réessaie pour GET/HEAD seulement) : un POST perdu
//  y devient une erreur qui n'existe pas en production. Ce serveur lance
//  le MÊME worker.js, la même D1 locale (SQLite) et le même Durable Object
//  via Miniflare, et écoute directement le port demandé.
//
//  Usage (appelé par concurrency.e2e.mjs quand MINIFLARE=chemin vers
//  node_modules/miniflare/dist/src/index.js de miniflare@4) :
//    node test_support/miniflare_server.mjs <port> <dossier_persist> <ADMIN_SECRET> <SECRETS_KEY> <TRIAL_ENFORCEMENT>
//  Écrit « READY » sur la sortie standard quand le Worker répond.
// =========================================================
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const [port, persist, adminSecret, secretsKey, trial] = process.argv.slice(2);
const { Miniflare } = await import(pathToFileURL(process.env.MINIFLARE).href);

// API de Miniflare 4 (paquet `miniflare`, version stable).
const options = (listenPort) => ({
  host: '127.0.0.1',
  port: listenPort,
  modules: true,
  // Le paquet produit par `wrangler deploy --dry-run --outdir <dossier>`
  // (WORKER_BUNDLE=<dossier>/worker.js) : exactement ce qui part en
  // production. L'analyseur de modules de Miniflare ne lit pas api_v1.js
  // tel quel.
  scriptPath: process.env.WORKER_BUNDLE || join(root, 'worker.js'),
  modulesRoot: dirname(process.env.WORKER_BUNDLE || join(root, 'worker.js')),
  compatibilityDate: '2025-05-01',
  d1Databases: { DB: 'tvking_licensing' },
  durableObjects: { RT_HUB: { className: 'RealtimeHub', useSQLite: true } },
  bindings: {
    DEFAULT_SERVERS: '[]',
    ADMIN_SECRET: adminSecret,
    SECRETS_KEY: secretsKey,
    TRIAL_ENFORCEMENT: trial,
  },
  d1Persist: join(persist, 'd1'),
  durableObjectsPersist: join(persist, 'do'),
});

// 1er temps : schéma chargé sur un port quelconque (personne ne connaît ce
// port, donc aucune requête du test ne passe avant le schéma).
const setup = new Miniflare(options(0));
await setup.ready;
const db = await setup.getD1Database('DB');
const schema = readFileSync(join(root, 'schema.sql'), 'utf8');
for (const stmt of schema.split(/;\s*(?:\n|$)/).map((s) => s.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean)) {
  await db.prepare(stmt).run();
}
try { await db.prepare('ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT').run(); } catch (_) { /* déjà là */ }
await setup.dispose();

// 2e temps : le Worker écoute le port demandé, sur la même base.
const mf = new Miniflare(options(Number(port)));
await mf.ready;
process.stdout.write('READY\n');
const stop = async () => { await mf.dispose(); process.exit(0); };
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
