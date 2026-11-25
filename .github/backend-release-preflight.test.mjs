import test from 'node:test';
import assert from 'node:assert/strict';
import { validateProduction, readProduction, requiredMigrations, databaseId } from './backend-release-preflight.mjs';

const version = 'a3f55171-173c-4a91-bfa9-1a347db085a4';
const base = () => ({
  configuration: {name:'seven-motion-backend',main:'gold.js',compatibility_date:'2025-05-01',workers_dev:true,
    build:{command:'node prepare_gold_runtime.mjs'},vars:{DEFAULT_SERVERS:'[]'},
    routes:[{pattern:'api.zuno8k.com',custom_domain:true}],
    d1_databases:[{binding:'DB',database_name:'tvking_licensing',database_id:databaseId}],
    durable_objects:{bindings:[{name:'RT_HUB',class_name:'RealtimeHub'}]}},
  provenance:{version},
  evidence:{version,deployment:'fixture-deployment',database:databaseId,namespace:'fixture-existing-namespace',
    storage:'sqlite',migrationTag:'v1-rt-hub',domains:['api.zuno8k.com'],workersDev:true,schedules:0,
    secretNames:['ADMIN_SECRET'],unmanagedBindings:[],defaultServersEmpty:true,
    migrations:[...requiredMigrations],migrationLedger:true,trialEnabled:0,
    columns:{gold_trial_settings_v2:['gold_trial_enabled','revision'],
      gold_trial_claims_v2:['mac','android_id','state','request_id'],gold_trial_events_v2:['id','mac','event'],
      gold_trial_rate_v2:['request_id','ip','at'],gold_trial_receipts_v2:['mac','credentials_enc','lease_token','delivery_attempts'],
      gold_device_proof_rate_v2:['request_id','ip','at'],device_secrets:['mac','android_id','secret_hash','updated_at'],
      golden_orders:['id','state','key_id','source_order_id','license_order_id','delivery_lease_until'],
      golden_key_locks:['key_id','order_id']},
  },
});

test('précontrôle : version, namespace et quatre migrations attestés ; les deux schémas appareil sont acceptés', () => {
  const f=base();assert.equal(validateProduction(f),true);
  f.evidence.columns.device_secrets=['mac','android_id','secret_hash','enrolled_at','rotated_at'];
  f.evidence.storage='legacy-kv';assert.equal(validateProduction(f),true);
});

for (const [name, mutate] of [
  ['ancien point d’entrée',f=>{f.configuration.main='worker.js';}],
  ['nouvelle migration DO',f=>{f.configuration.migrations=[{tag:'v2',new_classes:['RealtimeHub']}];}],
  ['version production plus récente',f=>{f.evidence.version='different';}],
  ['namespace inconnu',f=>{f.evidence.namespace='';}],
  ['type DO inconnu',f=>{f.evidence.storage=null;}],
  ['binding non porté',f=>{f.evidence.unmanagedBindings=[{name:'ASSETS',type:'kv_namespace'}];}],
  ['autre domaine historique',f=>{f.evidence.domains.push('app.7themotion.com');}],
  ['ancienne variable de serveurs',f=>{f.evidence.defaultServersEmpty=false;}],
  ['migration absente',f=>{f.evidence.migrations.pop();}],
  ['colonne Android ID absente',f=>{f.evidence.columns.gold_trial_claims_v2=[];}],
  ['essai fournisseur ON',f=>{f.evidence.trialEnabled=1;}],
  ['horodatages appareil absents',f=>{f.evidence.columns.device_secrets=['mac','android_id','secret_hash'];}],
]) test(`publication refusée : ${name}`,()=>{const f=base();mutate(f);assert.throws(()=>validateProduction(f));});

test('après publication : namespace, type, bindings et domaines doivent rester identiques',()=>{
  const f=base();f.previous=structuredClone(f.evidence);f.evidence.version='next-reviewed-version';
  assert.equal(validateProduction(f),true);
  f.evidence.namespace='new-namespace';assert.throws(()=>validateProduction(f),/Configuration modifiée/);
});

test('audit : uniquement GET et lectures D1 ; aucune valeur de secret ou serveur dans le rapport',async()=>{
  const f=base();const calls=[];let unmigrated=false;
  const api=async(path,body)=>{
    calls.push({path,body});
    if(path.endsWith('/deployments'))return{deployments:[{id:'fixture-deployment',created_on:'2026-10-26T17:59:53Z',versions:[{version_id:version,percentage:100}]}]};
    if(path.includes('/versions/'))return{resources:{script_runtime:{migration_tag:'v1-rt-hub'}}};
    if(path.endsWith('/settings'))return{bindings:[
      {name:'DB',type:'d1',id:databaseId},
      {name:'RT_HUB',type:'durable_object_namespace',class_name:'RealtimeHub',namespace_id:'fixture-existing-namespace'},
      {name:'ADMIN_SECRET',type:'secret_text',text:'must-never-be-saved'},
      {name:'DEFAULT_SERVERS',type:'plain_text',text:'https://private:password@private.example.invalid'},
    ]};
    if(path==='/workers/durable_objects/namespaces')return[{id:'fixture-existing-namespace',script:'seven-motion-backend',class:'RealtimeHub',use_sqlite:true}];
    if(path==='/workers/domains')return[{hostname:'api.zuno8k.com',service:'seven-motion-backend'}];
    if(path.endsWith('/subdomain'))return{enabled:true};
    if(path.endsWith('/schedules'))return{schedules:[]};
    assert.equal(path,`/d1/database/${databaseId}/query`);
    assert.match(body.sql,/^(SELECT|PRAGMA) /);
    let results=[];
    if(body.sql.includes('sqlite_master'))results=unmigrated ? [] : [{name:'d1_migrations'}];
    else if(body.sql==='SELECT name FROM d1_migrations')results=requiredMigrations.map(name=>({name}));
    else if(body.sql.startsWith('PRAGMA'))results=unmigrated ? [] : f.evidence.columns[/\(([^)]+)\)/.exec(body.sql)[1]].map(name=>({name}));
    else if(body.sql.includes('gold_trial_enabled'))results=[{gold_trial_enabled:0}];
    else assert.fail('Requête inconnue');
    return[{success:true,results}];
  };
  const evidence=await readProduction(api);
  assert.equal(evidence.defaultServersEmpty,false);
  assert.doesNotMatch(JSON.stringify(evidence),/must-never-be-saved|private:password|private\.example/);
  assert.equal(evidence.storage,'sqlite');
  assert.equal(evidence.migrations.length,4);
  assert.ok(calls.some(call=>call.body?.sql === 'SELECT name FROM d1_migrations'));
  assert.throws(()=>validateProduction({...f,evidence}),/DEFAULT_SERVERS/);
  unmigrated=true;calls.length=0;
  const empty=await readProduction(api);
  assert.deepEqual(empty.migrations,[]);
  assert.equal(empty.trialEnabled,null);
  assert.equal(empty.migrationLedger,false);
  assert.ok(!calls.some(call=>call.body?.sql === 'SELECT name FROM d1_migrations'));
  assert.ok(!calls.some(call=>call.body?.sql?.startsWith('SELECT gold_trial_enabled')));
});
