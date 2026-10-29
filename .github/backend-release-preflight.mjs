// Lecture seule de la production avant/après déploiement. Aucun appel de
// mutation Cloudflare, aucune migration SQL et aucune valeur de secret sortie.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const workerName = 'seven-motion-backend';
export const databaseId = '67303737-a50b-4258-86de-662fb9aba6e7';
export const requiredMigrations = [
  '20261028_gold_trial_policy.sql', '20261028_gold_trial_runtime.sql',
  '20261029_device_secrets.sql', '20261029_golden_admin.sql',
];

const requiredColumns = {
  gold_trial_settings_v2: ['gold_trial_enabled', 'revision'],
  gold_trial_claims_v2: ['mac', 'android_id', 'state', 'request_id'],
  gold_trial_events_v2: ['id', 'mac', 'event'],
  gold_trial_rate_v2: ['request_id', 'ip', 'at'],
  gold_trial_receipts_v2: ['mac', 'credentials_enc', 'lease_token', 'delivery_attempts'],
  gold_device_proof_rate_v2: ['request_id', 'ip', 'at'],
  device_secrets: ['mac', 'android_id', 'secret_hash'],
  golden_orders: ['id', 'state', 'key_id', 'source_order_id', 'license_order_id', 'delivery_lease_until'],
  golden_key_locks: ['key_id', 'order_id'],
};

export function validateProduction({ configuration, provenance, evidence, previous = null }) {
  assert.equal(configuration.name, workerName, 'Worker cible différent');
  assert.equal(configuration.main, 'gold.js', 'Le wrapper Gold doit être le point d’entrée');
  assert.equal(configuration.build?.command, 'node prepare_gold_runtime.mjs', 'Build du bundle vérifié requis');
  assert.equal(configuration.compatibility_date, '2025-05-01', 'Date de compatibilité différente');
  assert.ok(Array.isArray(configuration.compatibility_flags ?? []), 'Flags de compatibilité locaux invalides');
  assert.equal(evidence.compatibilityDate, configuration.compatibility_date, 'La date de compatibilité active doit être conservée');
  assert.ok(Array.isArray(evidence.compatibilityFlags), 'Flags de compatibilité actifs non attestés');
  assert.deepEqual([...evidence.compatibilityFlags].sort(), [...(configuration.compatibility_flags ?? [])].sort(),
    'Les flags de compatibilité actifs doivent être conservés');
  assert.equal(configuration.workers_dev, true, 'Endpoint workers.dev requis par le panel');
  assert.equal(configuration.migrations?.length ?? 0, 0, 'Aucune migration DO n’est autorisée dans ce lot');
  assert.deepEqual(configuration.d1_databases, [{ binding: 'DB', database_name: 'tvking_licensing', database_id: databaseId }]);
  assert.deepEqual(configuration.durable_objects?.bindings, [{ name: 'RT_HUB', class_name: 'RealtimeHub' }]);
  assert.ok(!configuration.env && !configuration.services && !configuration.kv_namespaces && !configuration.r2_buckets,
    'Toute extension de bindings doit être revue séparément');

  assert.ok(evidence.version && evidence.deployment, 'Version et déploiement actifs obligatoires');
  if (previous) {
    assert.notEqual(evidence.version, previous.version, 'Aucune nouvelle version active');
    for (const field of ['database', 'namespace', 'storage', 'migrationTag', 'compatibilityDate', 'compatibilityFlags', 'domains', 'secretNames']) {
      assert.deepEqual(evidence[field], previous[field], `Configuration modifiée après déploiement : ${field}`);
    }
  } else {
    assert.equal(evidence.version, provenance.version,
      'La production a changé depuis l’export : exporter et réconcilier avant publication');
  }
  assert.equal(evidence.database, databaseId, 'D1 différent de celui exporté');
  assert.ok(typeof evidence.namespace === 'string' && evidence.namespace.length > 0, 'Namespace RT_HUB non prouvé');
  assert.ok(['sqlite', 'legacy-kv'].includes(evidence.storage), 'Type du DO non prouvé');
  assert.equal(evidence.migrationTag, 'v1-rt-hub', 'Historique DO différent : revue nécessaire');
  const localDomains = (configuration.routes || []).map(route => {
    assert.equal(route.custom_domain, true, 'Les routes de zone doivent être revues séparément');
    return route.pattern;
  }).sort();
  assert.deepEqual(evidence.domains, localDomains, 'Le déploiement changerait les domaines existants');
  assert.equal(evidence.workersDev, true, 'workers.dev doit déjà être actif');
  assert.equal(evidence.schedules, 0, 'Des tâches planifiées existantes doivent être préservées explicitement');
  assert.ok(evidence.secretNames.includes('ADMIN_SECRET'), 'Binding ADMIN_SECRET absent');
  assert.deepEqual(evidence.unmanagedBindings, [], 'Un binding existant serait perdu');
  assert.deepEqual(configuration.vars, { DEFAULT_SERVERS: '[]' }, 'Variables locales inattendues');
  assert.equal(evidence.defaultServersEmpty, true, 'DEFAULT_SERVERS ne doit pas être remplacé');
  for (const name of requiredMigrations) {
    assert.ok(evidence.migrations.includes(name), `Migration non attestée dans D1 : ${name}`);
  }
  for (const [table, names] of Object.entries(requiredColumns)) {
    for (const name of names) assert.ok(evidence.columns[table]?.includes(name), `Colonne absente : ${table}.${name}`);
  }
  const device = evidence.columns.device_secrets;
  assert.ok(device.includes('updated_at') || device.includes('enrolled_at'), 'Schéma device_secrets inconnu');
  assert.equal(evidence.trialEnabled, 0, 'L’essai fournisseur doit rester OFF');
  return true;
}

// La liste des requêtes est fixe. Le POST D1 n’exécute que SELECT/PRAGMA.
export async function readProduction(api) {
  const deployments = (await api(`/workers/scripts/${workerName}/deployments`)).deployments;
  assert.ok(Array.isArray(deployments) && deployments.length, 'Liste des déploiements manquante');
  const active = [...deployments].sort((a,b) => Date.parse(b.created_on)-Date.parse(a.created_on))[0];
  assert.equal(active.versions?.length, 1, 'Déploiement progressif actif : arrêter la publication');
  assert.equal(active.versions[0].percentage, 100, 'Une seule version doit servir 100 % du trafic');
  const version = active.versions[0].version_id;
  assert.match(version, /^[a-f0-9-]{36}$/);
  const metadata = await api(`/workers/scripts/${workerName}/versions/${version}`);
  const settings = await api(`/workers/scripts/${workerName}/settings`);
  const bindings = settings.bindings;
  assert.ok(Array.isArray(bindings), 'Bindings Cloudflare absents');
  const database = bindings.find(item => item.name === 'DB' && item.type === 'd1');
  const hub = bindings.find(item => item.name === 'RT_HUB' && item.type === 'durable_object_namespace');
  assert.equal(database?.id, databaseId, 'Binding D1 incompatible');
  assert.equal(hub?.class_name, 'RealtimeHub', 'Classe RT_HUB différente');
  assert.ok(!hub.script_name || hub.script_name === workerName, 'Namespace appartenant à un autre Worker');
  const namespaces = await api('/workers/durable_objects/namespaces', undefined, true);
  const namespace = namespaces.find(item => item.id === hub.namespace_id);
  assert.equal(namespace?.script, workerName, 'Namespace absent ou rattaché à un autre script');
  assert.equal(namespace?.class, 'RealtimeHub', 'Classe du namespace non concordante');
  assert.equal(typeof namespace.use_sqlite, 'boolean', 'Le type de stockage DO doit être lu, jamais deviné');
  const domains = (await api('/workers/domains', undefined, true))
    .filter(item => item.service === workerName).map(item => item.hostname).sort();
  const subdomain = await api(`/workers/scripts/${workerName}/subdomain`);
  const schedules = await api(`/workers/scripts/${workerName}/schedules`);
  const query = async sql => {
    assert.match(sql, /^(SELECT|PRAGMA) /, 'Requête D1 non autorisée');
    const result = await api(`/d1/database/${databaseId}/query`, { sql });
    assert.equal(result?.length, 1, 'Une seule lecture D1 attendue');
    assert.equal(result[0].success, true, 'Lecture D1 refusée');
    return result[0].results;
  };
  const tables = await query("SELECT name FROM sqlite_master WHERE type='table'");
  const migrationLedger = tables.some(row => row.name === 'd1_migrations');
  const migrations = migrationLedger ? (await query('SELECT name FROM d1_migrations')).map(row => row.name) : [];
  const columns = {};
  for (const table of Object.keys(requiredColumns)) columns[table] = (await query(`PRAGMA table_info(${table})`)).map(row => row.name);
  const trialEnabled = columns.gold_trial_settings_v2.includes('gold_trial_enabled')
    ? (await query('SELECT gold_trial_enabled FROM gold_trial_settings_v2 WHERE id=1'))[0]?.gold_trial_enabled : null;
  const vars = Object.fromEntries(bindings.filter(row => row.type === 'plain_text').map(row => [row.name,row.text]));
  return {
    observedAt: new Date().toISOString(), deployment: active.id, version,
    database: database.id, namespace: namespace.id,
    storage: namespace.use_sqlite ? 'sqlite' : 'legacy-kv',
    migrationTag: metadata.resources?.script_runtime?.migration_tag,
    compatibilityDate: metadata.resources?.script_runtime?.compatibility_date,
    compatibilityFlags: metadata.resources?.script_runtime?.compatibility_flags ?? [],
    domains, workersDev: subdomain.enabled, schedules: schedules.schedules?.length,
    secretNames: bindings.filter(row => row.type === 'secret_text').map(row => row.name).sort(),
    unmanagedBindings: bindings.filter(row => !['secret_text','plain_text','json'].includes(row.type) &&
      !(row.type === 'd1' && row.name === 'DB') &&
      !(row.type === 'durable_object_namespace' && row.name === 'RT_HUB')).map(row => ({name:row.name,type:row.type})),
    // Aucune valeur de variable n’est conservée : DEFAULT_SERVERS pourrait
    // contenir une URL privée dans une autre configuration de production.
    defaultServersEmpty: vars.DEFAULT_SERVERS === '[]', migrationLedger, migrations, columns, trialEnabled,
  };
}

async function main() {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const audit = process.argv[2] === 'audit';
  let configuration, provenance;
  if (!audit) {
    const cloudflare = join(root, 'android-app/cloudflare');
    configuration = JSON.parse(execFileSync('python3', ['-c',
      'import json,sys,tomllib;json.dump(tomllib.load(open(sys.argv[1],"rb")),sys.stdout)', join(cloudflare,'wrangler.toml')], {encoding:'utf8'}));
    provenance = JSON.parse(readFileSync(join(cloudflare,'production/provenance.json'),'utf8'));
    for (const [file, hash] of Object.entries(provenance.sha256)) {
      assert.equal(createHash('sha256').update(readFileSync(join(cloudflare,'production',file))).digest('hex'),hash,'Export modifié');
    }
  }
  const account = process.env.CLOUDFLARE_ACCOUNT_ID;
  const token = process.env.CLOUDFLARE_API_TOKEN;
  assert.match(account || '', /^[a-f0-9]{32}$/);
  assert.ok(token, 'Jeton Cloudflare absent');
  const request = async (path, body) => {
    const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}${path}`, {
      method: body ? 'POST' : 'GET', redirect: 'error', signal: AbortSignal.timeout(20_000),
      headers: { Authorization:`Bearer ${token}`, 'Content-Type':'application/json' },
      ...(body ? {body:JSON.stringify(body)} : {}),
    });
    assert.ok(response.ok, `Lecture Cloudflare refusée : HTTP ${response.status}`);
    const data = await response.json();
    assert.equal(data.success, true, 'Lecture Cloudflare sans résultat confirmé');
    return data;
  };
  const api = async (path, body, paginated=false) => {
    if (!paginated) return (await request(path,body)).result;
    const items=[];
    for (let page=1;page<=100;page++) {
      const data=await request(`${path}?page=${page}&per_page=100`);
      assert.ok(Array.isArray(data.result));
      items.push(...data.result);
      if (data.result_info?.total_pages ? page>=data.result_info.total_pages : data.result.length<100) return items;
    }
    throw new Error('Pagination Cloudflare incomplète');
  };
  const previousPath = process.argv[2] === 'after' ? process.argv[3] : null;
  assert.ok(audit || process.argv[2] === 'before' || previousPath, 'Usage : audit | before | after <rapport-avant>');
  const evidence = await readProduction(api);
  const previous = previousPath ? JSON.parse(readFileSync(previousPath,'utf8')) : null;
  if (!audit) validateProduction({configuration,provenance,evidence,previous});
  const output = audit ? 'backend-audit.json' : previous ? 'backend-after.json' : 'backend-before.json';
  writeFileSync(join(root,output),JSON.stringify(evidence,null,2)+'\n',{mode:0o600});
  console.log(audit
    ? `Audit en lecture seule terminé : ${evidence.version}; DO ${evidence.namespace} (${evidence.storage}); aucune autorisation de publication déduite.`
    : `Précontrôle ${previous ? 'après' : 'avant'} validé : ${evidence.version}; DO ${evidence.namespace} (${evidence.storage}); quatre migrations attestées, essai OFF.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(`::error::${error.message}`); process.exitCode=1; });
}
