import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createHash,createHmac } from 'node:crypto';
import '../prepare_gold_runtime.mjs';
import { historicalEligibility,trialKeyMetadata,legacyHistory,legacyExpiration } from '../gold_trial_runtime.js';
import { enrollProductionDevice,verifyProductionDevice } from '../gold_trial_device.js';
import { createTrialDelivery,saveTrialReceipt,openTrialReceipt } from '../gold_trial_delivery.js';
import { createGoldTrialHandler } from '../gold_trial_policy.js';
import { activationDeliveryState } from '../gold_activation_delivery.js';
const production=await import('../production/worker.runtime.js');
const gold=(await import('../gold.js')).default;
const mac='MK:11:22:33:44:55',secondMac='MK:11:22:33:44:66';
const androidId='android-fixture',secret='fixture-device-secret-32-characters-only';
const adminSecret='fixture-admin-secret-not-a-real-key-64-characters';
const now=()=>Date.now();
const file=path=>readFileSync(new URL(path,import.meta.url),'utf8');

function fixture({migrated=true}={}) {
  const sql=new DatabaseSync(':memory:');
  sql.exec(file('../production/schema.sql'));
  sql.exec("INSERT INTO customers(id,created_at,updated_at) VALUES ('customer',1,1)");
  sql.prepare('INSERT INTO devices(id,customer_id,mac,first_seen_at,last_seen_at,android_id) VALUES (?,?,?,?,?,?)')
    .run('device','customer',mac,1,1,androidId);
  sql.prepare('INSERT INTO trial_anchors(mac,android_id,started_at) VALUES (?,?,?)').run(mac,androidId,now());
  sql.exec("INSERT INTO admin_users(id,email,password_hash,role,is_active,created_at) VALUES ('admin','fixture@example.invalid','unused','super_admin',1,1)");
  const originalTables=sql.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all().map(r=>r.name);
  const originalCounts=Object.fromEntries(originalTables.map(n=>[n,sql.prepare(`SELECT COUNT(*) AS n FROM ${n}`).get().n]));
  if (migrated) {
    sql.exec(file('../migrations/20261028_gold_trial_policy.sql'));
    sql.exec(file('../migrations/20261028_gold_trial_runtime.sql'));
  }
  const db={prepare(query) {
    let args=[];
    const stmt={bind(...values){args=values;return stmt;},
      async first(){return sql.prepare(query).get(...args)??null;},
      async all(){return {results:sql.prepare(query).all(...args)};},
      async run(){
        const prepared=sql.prepare(query);
        if (/\bRETURNING\b/i.test(query)) {const results=prepared.all(...args);return {results,meta:{changes:sql.prepare('SELECT changes() AS n').get().n}};}
        return {results:[],meta:{changes:Number(prepared.run(...args).changes)}};
      }};return stmt;
    },async batch(statements){sql.exec('BEGIN');try{const results=[];for(const stmt of statements)results.push(await stmt.run());sql.exec('COMMIT');return results;}catch(e){sql.exec('ROLLBACK');throw e;}}};
  const env={DB:db,ADMIN_SECRET:adminSecret,GOLD_TRIAL_POLICY_READY:'true'};
  const ctx={waitUntil(promise){promise.catch(()=>{});}};
  return {sql,db,env,ctx,originalTables,originalCounts};
}
function req(path='/api/gold-trial',{method='POST',body,headers={}}={}) {
  return new Request(`https://worker.example${path}`,{method,
    headers:{'CF-Connecting-IP':'192.0.2.10','X-Device-Secret':secret,'Content-Type':'application/json',...headers},
    ...(method==='POST'||method==='PUT'?{body:JSON.stringify(body??{mac,android_id:androidId,app_version:'109'})}:{})});
}
async function enroll(f) {
  const r=await enrollProductionDevice(req('/api/device-proof',{body:{mac,androidId,secret}}),f.env);
  assert.equal(r.status,200);return r;
}
function jwt(role='super_admin') {
  const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
  const h=enc({alg:'HS256',typ:'JWT'}),p=enc({sub:'admin',role,iat:Math.floor(now()/1000),exp:Math.floor(now()/1000)+3600});
  return `${h}.${p}.${createHmac('sha256',adminSecret).update(`${h}.${p}`).digest('base64url')}`;
}
function addLegacy(f,{device=mac,id='old-line',kind='trial',status='active',error=null,aid=androidId}={}) {
  f.sql.prepare(`INSERT INTO gold_lines(id,mac,kind,status,android_id,error,created_at,updated_at)
    VALUES (?,?,?,?,?,?,?,?)`).run(id,device,kind,status,aid,error,now(),now());
}
async function receipt(f,{label='Zuno TV Essai'}={}) {
  const result={line_id:'fixture-line',key_id:'fixture-key',expire:now()+86_400_000,
    credentials:{server_url:'https://source.example.invalid',username:'fixture-user',password:'fixture-line-password'}};
  await saveTrialReceipt(f.env,mac,result,{label});
  f.sql.prepare(`INSERT INTO gold_trial_claims_v2(mac,android_id,request_id,state,created_at,expire,line_id,ip,app_version)
    VALUES (?,?,'request','created',?,?,?,'192.0.2.10','109')`).run(mac,androidId,now(),result.expire,result.line_id);
  return result;
}
const bridge={sealSource:production.goldSealSource,openSourceList:production.goldOpenSourceList,notifyBox:async()=>{}};

test('suivi d’activation : authentification, isolation MAC/trace et aucune donnée fournisseur',async()=>{
  const f=fixture(),trace='trace-fixture123';
  f.sql.prepare(`INSERT INTO gold_history(id,mac,event,detail_json,created_at) VALUES (?,?,?, ?,?)`)
    .run('h1',mac,'activation.delivery',JSON.stringify({trace_id:trace,stage:'source_saved',order_id:'ord_fixture123',password:'must-not-leak',message:'private-provider-response'}),now());
  const path=`/api/v1/activation-delivery?mac=${mac}&trace=${trace}`;
  assert.equal((await gold.fetch(req(path,{method:'GET'}),f.env,f.ctx)).status,401);
  const r=await gold.fetch(req(path,{method:'GET',headers:{Authorization:`Bearer ${jwt()}`,Origin:'https://atlas-console-k7q2.vercel.app'}}),f.env,f.ctx);
  assert.equal(r.status,200);
  assert.equal(r.headers.get('Access-Control-Allow-Origin'),'https://atlas-console-k7q2.vercel.app');
  const value=await r.json();
  assert.equal(value.stage,'source_saved');assert.equal(value.order_id,'ord_fixture123');
  assert.doesNotMatch(JSON.stringify(value),/must-not-leak|private-provider|password/);
  assert.equal((await activationDeliveryState(f.env,secondMac,trace)).stage,'waiting');
  assert.equal((await activationDeliveryState(f.env,mac,'other-trace')).stage,'waiting');
});

test('suivi fournisseur : un résultat final gagne sur preparing à la même milliseconde',async()=>{
  const f=fixture(),trace='trace-fixture123',at=now();
  for(const [id,stage] of [['z-preparing','preparing'],['a-final','failed']]) {
    f.sql.prepare('INSERT INTO gold_history(id,mac,event,detail_json,created_at) VALUES (?,?,?,?,?)')
      .run(id,mac,'activation.delivery',JSON.stringify({trace_id:trace,stage}),at);
  }
  assert.equal((await activationDeliveryState(f.env,mac,trace)).stage,'failed');
});

test('suivi d’activation : le revendeur ne peut lire que son propre appareil',async()=>{
  const f=fixture();
  f.sql.exec("INSERT INTO resellers(id,email,password_hash,status,created_at) VALUES ('admin','reseller@example.invalid','unused','active',1)");
  const path=`/api/v1/activation-delivery?mac=${mac}&trace=trace-fixture123`;
  const request=()=>req(path,{method:'GET',headers:{Authorization:`Bearer ${jwt('reseller')}`}});
  assert.equal((await gold.fetch(request(),f.env,f.ctx)).status,403);
  f.sql.exec("UPDATE devices SET reseller_id='admin'");
  assert.equal((await gold.fetch(request(),f.env,f.ctx)).status,200);
  f.sql.exec("INSERT INTO resellers(id,email,password_hash,status,created_at) VALUES ('another-reseller','other@example.invalid','unused','active',1)");
  f.sql.exec("UPDATE devices SET reseller_id='another-reseller'");
  assert.equal((await gold.fetch(request(),f.env,f.ctx)).status,403);
  f.sql.exec("UPDATE resellers SET status='suspended'");
  assert.equal((await gold.fetch(request(),f.env,f.ctx)).status,401);
});

test('export complet : trois empreintes exactes et runtime limité à trois exports',()=>{
  const meta=JSON.parse(file('../production/provenance.json'));
  for(const [name,hash] of Object.entries(meta.sha256)) assert.equal(createHash('sha256').update(file(`../production/${name}`)).digest('hex'),hash);
  assert.ok(file('../production/worker.runtime.js').startsWith(file('../production/worker.js')));
  assert.match(file('../wrangler.toml'),/main = "gold.js"/);
  assert.equal(typeof production.RealtimeHub,'function');
});
test('les deux migrations passent sur les 61 tables exportées sans modifier leurs lignes',()=>{
  const f=fixture();
  for(const name of f.originalTables) assert.equal(f.sql.prepare(`SELECT COUNT(*) AS n FROM ${name}`).get().n,f.originalCounts[name],name);
  assert.equal(f.sql.prepare('SELECT gold_trial_enabled FROM gold_trial_settings_v2').get().gold_trial_enabled,0);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM gold_trial_receipts_v2').get().n,0);
});
test('premier secret, répétition et rotation avec preuve ; Android ID seul ne remplace rien',async()=>{
  const f=fixture();await enroll(f);await enroll(f);
  const saved=f.sql.prepare('SELECT * FROM device_secrets').get();
  assert.notEqual(saved.secret_hash,secret);
  const denied=await enrollProductionDevice(req('/api/device-proof',{body:{mac,androidId,secret:'attacker-secret-32-characters-minimum'},headers:{'X-Device-Secret':''}}),f.env);
  assert.equal(denied.status,403);assert.equal(f.sql.prepare('SELECT secret_hash FROM device_secrets').get().secret_hash,saved.secret_hash);
  const rotated=await enrollProductionDevice(req('/api/device-proof',{body:{mac,androidId,secret:'new-valid-secret-32-characters-minimum'}}),f.env);
  assert.equal(rotated.status,200);
  assert.equal(await verifyProductionDevice(f.db,req(),{mac,android_id:androidId}),'device_mismatch');
});
test('enrôlement refuse appareil inconnu, mauvaise ancre, banni et MAC réattribuée',async()=>{
  for(const change of ["DELETE FROM trial_anchors","UPDATE trial_anchors SET android_id='other'","UPDATE devices SET block_status='banned'","UPDATE devices SET superseded_by='other'"]){
    const f=fixture();f.sql.exec(change);
    assert.equal((await enrollProductionDevice(req('/api/device-proof',{body:{mac,androidId,secret}}),f.env)).status,403);
  }
});
test('essai historique sur autre MAC / clé et ligne expirée restent utilisés',async()=>{
  const f=fixture();addLegacy(f,{device:secondMac,status:'expired'});
  assert.equal((await historicalEligibility(f.db,mac,androidId)).trial_used,true);
  f.sql.exec("UPDATE gold_lines SET status='failed',error='network timeout'");
  assert.equal((await historicalEligibility(f.db,mac,androidId)).in_progress,true);
  f.sql.exec("UPDATE gold_lines SET error='Subscription Package not found.'");
  assert.equal((await historicalEligibility(f.db,mac,androidId)).in_progress,false);
});
test('historique immuable retrouve une création même si la ligne ne porte plus active',async()=>{
  const f=fixture();f.sql.prepare("INSERT INTO gold_history(id,mac,event,created_at) VALUES ('old',?,'demo.create',1)").run(mac);
  assert.equal((await historicalEligibility(f.db,mac,androidId)).trial_used,true);
});
test('licence payante et source préexistante bloquent ; absence Android ID ne relie pas toutes les MAC',async()=>{
  const f=fixture();addLegacy(f,{device:secondMac,aid:''});
  assert.equal((await historicalEligibility(f.db,mac,'')).trial_used,false);
  f.sql.prepare("INSERT INTO device_sources(mac,type,updated_at) VALUES (?,'m3u',1)").run(mac);
  assert.equal((await historicalEligibility(f.db,mac,androidId)).already_customer,true);
  const g=fixture();g.sql.exec("INSERT INTO apps(id,name,package_name,created_at,updated_at) VALUES ('app','fixture','fixture.app',1,1)");
  g.sql.exec("INSERT INTO licenses(id,customer_id,device_id,app_id,status,plan,started_at,created_at,updated_at) VALUES ('paid','customer','device','app','active','yearly',1,1,1)");
  assert.equal((await historicalEligibility(g.db,mac,androidId)).already_customer,true);
});
test('manzi10 NULL dans l’export passe avant Manzi8, métadonnées sans déchiffrement',async()=>{
  const f=fixture();f.sql.exec(`INSERT INTO gold_keys(id,enc,fp,reseller,trial_priority,created_at) VALUES
    ('gk_mvpkambcp22tk5','not-decryptable','fp10',NULL,20,1),('key8','not-decryptable','fp8','Manzi8',1,1)`);
  const rows=await trialKeyMetadata(f.db);
  assert.deepEqual(rows.map(r=>r.label),['manzi10','Manzi8']);
  assert.ok(rows.every(r=>r.demo_tickets===null && !('enc' in r)));
  assert.equal(f.sql.prepare("SELECT trial_priority FROM gold_keys WHERE id='key8'").get().trial_priority,1);
});
test('routes réelles : contrat non vérifié bloque même READY=true et interrupteur forcé',async t=>{
  const f=fixture();await enroll(f);f.sql.exec('UPDATE gold_trial_settings_v2 SET gold_trial_enabled=1');
  let network=0;t.mock.method(globalThis,'fetch',async()=>{network++;throw new Error('No real network allowed');});
  for(const path of ['/api/gold-trial','/api/v1/device/trial']) {
    const response=await gold.fetch(req(path),f.env,f.ctx);assert.equal(response.status,503);
    assert.doesNotMatch(await response.text(),/cms-8k|Strong|secret|99|api_key/i);
  }
  assert.equal(network,0);assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM gold_trial_claims_v2').get().n,0);
});
test('ancienne route démo admin et configuration sub=99 ne contournent pas le verrou',async t=>{
  const f=fixture();let network=0;t.mock.method(globalThis,'fetch',async()=>{network++;throw new Error('No network');});
  const headers={Authorization:`Bearer ${jwt()}`};
  assert.equal((await gold.fetch(req('/api/v1/gold/provision',{body:{mac,demo:true},headers}),f.env,f.ctx)).status,503);
  assert.equal((await gold.fetch(req('/api/v1/gold/config',{body:{gold_trial_sub:99},headers}),f.env,f.ctx)).status,409);
  assert.equal(network,0);
});
test('panel réel : JWT vérifié, rôle actuel, CORS atlas et activation impossible',async()=>{
  const f=fixture(),path='/api/v1/gold/trial-control';
  assert.equal((await gold.fetch(req(path,{method:'GET',headers:{Authorization:'Bearer forged'}}),f.env,f.ctx)).status,403);
  const headers={Authorization:`Bearer ${jwt()}`,Origin:'https://atlas-console-k7q2.vercel.app'};
  const read=await gold.fetch(req(path,{method:'GET',headers}),f.env,f.ctx);
  assert.equal(read.status,200);assert.equal(read.headers.get('Access-Control-Allow-Origin'),headers.Origin);
  const data=await read.json();assert.equal(data.integration_ready,false);assert.equal(data.blockers.length,1);
  assert.equal((await gold.fetch(req(path,{method:'PUT',headers,body:{gold_trial_enabled:true,daily_cap:20,revision:0}}),f.env,f.ctx)).status,409);
  f.sql.exec("UPDATE admin_users SET role='support'");
  assert.equal((await gold.fetch(req(path,{method:'GET',headers}),f.env,f.ctx)).status,403);
  const pre=await gold.fetch(req(path,{method:'OPTIONS',headers}),f.env,f.ctx);
  assert.equal(pre.status,204);assert.match(pre.headers.get('Access-Control-Allow-Headers'),/X-Device-Secret/);
  const evil=await gold.fetch(req(path,{method:'OPTIONS',headers:{Origin:'https://attacker.invalid'}}),f.env,f.ctx);
  assert.equal(evil.headers.get('Access-Control-Allow-Origin'),null);
});
test('historique paginé stable sur dates identiques, IP/version/ligne, pas de secrets',async()=>{
  const f=fixture();
  for(let n=0;n<205;n++) f.sql.prepare(`INSERT INTO gold_history(id,mac,event,gold_line_id,ip,app_version,detail_json,created_at)
    VALUES (?,?,'activation','fixture-line','192.0.2.1','109','{"password":"DO_NOT_RETURN"}',1)`).run(`history_${String(n).padStart(3,'0')}`,mac);
  let cursor=null,all=[];
  do {const response=await legacyHistory(req(`/api/v1/gold/history?mac=${mac}${cursor?`&before=${cursor}`:''}`,{method:'GET'}),f.env);
    const body=await response.json();assert.doesNotMatch(JSON.stringify(body),/DO_NOT_RETURN/);all.push(...body.history);cursor=body.next_before;
  }while(cursor);
  assert.equal(all.length,205);assert.equal(new Set(all.map(r=>r.id)).size,205);assert.equal(all[0].line_id,'fixture-line');
});
test('activations payantes avant Gold : audit existant avec date, expiration, IP, sans JSON privé',async()=>{
  const f=fixture();
  for(let n=0;n<105;n++) f.sql.prepare(`INSERT INTO audit_logs
    (id,actor_type,actor_id,action,target_type,target_id,ip,after_json,created_at)
    VALUES (?,'admin','admin','activate.renew','license','lic-fixture','192.0.2.9',?,2)`)
    .run(`old_${String(n).padStart(3,'0')}`,JSON.stringify({mac,expires_at:1794000000000,password:'DO_NOT_EXPOSE'}));
  const first=await (await legacyHistory(req(`/api/v1/gold/history?mac=${mac}`,{method:'GET'}),f.env)).json();
  const next=await (await legacyHistory(req(`/api/v1/gold/history?mac=${mac}&before=${first.next_before}`,{method:'GET'}),f.env)).json();
  assert.equal(first.history.length+next.history.length,105);
  assert.equal(first.history[0].expire,1794000000000);assert.equal(first.history[0].ip,'192.0.2.9');
  assert.doesNotMatch(JSON.stringify(first),/DO_NOT_EXPOSE/);
});
test('JSON d’audit invalide ne casse pas la recherche et ne fuit pas dans la réponse',async()=>{
  const f=fixture();
  f.sql.exec("INSERT INTO audit_logs(id,actor_type,action,target_type,target_id,after_json,created_at) VALUES ('bad','admin','activate.create','license','missing','{invalid secret',2)");
  const response=await legacyHistory(req(`/api/v1/gold/history?mac=${mac}`,{method:'GET'}),f.env);
  assert.equal(response.status,200);assert.doesNotMatch(await response.text(),/invalid secret/);
});
test('reçu AES-GCM lié à la MAC et ligne ; mauvais secret et substitution sont refusés',async()=>{
  const f=fixture(),result=await receipt(f),row=f.sql.prepare('SELECT * FROM gold_trial_receipts_v2').get();
  assert.doesNotMatch(JSON.stringify(row),/source\.example|fixture-user|fixture-line-password/);
  assert.deepEqual(await openTrialReceipt(f.env,row),result.credentials);
  await assert.rejects(openTrialReceipt({...f.env,ADMIN_SECRET:'a-different-secret-of-at-least-32-characters'},row));
  await assert.rejects(openTrialReceipt(f.env,{...row,mac:secondMac}));
});
test('livraison réelle chiffrée : CAS, révision source et polling du bundle conservé',async()=>{
  const f=fixture(),result=await receipt(f);await enroll(f);
  let notified=0;const delivery=createTrialDelivery({...bridge,notifyBox:async()=>{notified++;}});
  assert.equal(await delivery(f.env,f.ctx,mac),true);
  const stored=f.sql.prepare('SELECT * FROM device_sources').get();
  assert.match(stored.password,/^enc1\./);assert.doesNotMatch(stored.sources_json,/fixture-line-password/);
  assert.equal(stored.label,'Zuno TV Essai');assert.equal(notified,1);
  assert.equal(await delivery(f.env,f.ctx,mac),true);assert.equal(notified,1);
  const publicSource=await gold.fetch(req(`/api/device-source/${mac}`,{method:'GET'}),f.env,f.ctx);
  assert.equal(publicSource.status,200);
  const data=await publicSource.json();assert.equal(data.source.password,result.credentials.password);assert.equal(data.rev,1);
});
test('pas de secret : la source de nouvel essai ne peut pas être lue par sa MAC',async()=>{
  const f=fixture();await receipt(f);await enroll(f);
  for(const prefix of ['/api/device-source','/config','/api/backup','/api/self-source'])
    assert.equal((await gold.fetch(req(`${prefix}/${mac}`,{method:'GET',headers:{'X-Device-Secret':''}}),f.env,f.ctx)).status,403);
});
test('ancienne ligne créée : reprise chiffrée sans recréation ni réécriture de l’historique',async t=>{
  const f=fixture();await enroll(f);addLegacy(f);
  const expire=now()+3_600_000;
  f.sql.prepare("UPDATE gold_lines SET username='legacy-user',password='legacy-password',url='https://legacy.example.invalid/get.php?username=legacy-user&password=legacy-password',expire=?")
    .run(new Date(expire).toISOString());
  const original={...f.sql.prepare('SELECT * FROM gold_lines').get()};
  let network=0;t.mock.method(globalThis,'fetch',async()=>{network++;throw new Error('Forbidden supplier call');});
  const response=await gold.fetch(req('/api/gold-trial/delivery',{headers:{'X-App-Brand':'zuno'}}),f.env,f.ctx);
  assert.equal(response.status,200);assert.equal((await response.json()).delivered,true);
  assert.deepEqual({...f.sql.prepare('SELECT * FROM gold_lines').get()},original);assert.equal(network,0);
  assert.equal(f.sql.prepare('SELECT expire FROM gold_trial_receipts_v2').get().expire,expire);
  assert.equal(f.sql.prepare('SELECT label FROM device_sources').get().label,'Zuno TV Essai');
  assert.equal(f.sql.prepare('SELECT extended_until FROM trial_anchors').get().extended_until,expire);
});
test('expiration ancienne : secondes, millisecondes, ISO explicite ; aucun fuseau deviné',()=>{
  assert.equal(legacyExpiration(1793214000),1793214000000);
  assert.equal(legacyExpiration('1793214000000'),1793214000000);
  assert.equal(legacyExpiration('2026-10-28T19:00:00Z'),Date.parse('2026-10-28T19:00:00Z'));
  assert.equal(legacyExpiration('2026-10-28 19:00:00'),null);
});
test('réannonce valide sans épuiser les 5 inscriptions/minute/IP ; imposteur limité',async()=>{
  const f=fixture();for(let n=0;n<12;n++)await enroll(f);
  for(let n=0;n<4;n++) assert.equal((await enrollProductionDevice(req('/api/device-proof',{body:{mac,androidId,secret:'other-secret-that-is-long-enough-32'},headers:{'X-Device-Secret':''}}),f.env)).status,403);
  assert.equal((await enrollProductionDevice(req('/api/device-proof',{body:{mac,androidId,secret:'other-secret-that-is-long-enough-32'},headers:{'X-Device-Secret':''}}),f.env)).status,429);
});
test('panne pendant livraison puis récupération : une seule ligne, même reçu, pas de réseau fournisseur',async()=>{
  const f=fixture();await receipt(f);let fail=true,clock=now();
  const delivery=createTrialDelivery({...bridge,sealSource:async(...args)=>{if(fail)throw new Error('offline');return bridge.sealSource(...args);}}, {now:()=>clock});
  await assert.rejects(delivery(f.env,f.ctx,mac));fail=false;clock+=3100;
  assert.equal(await delivery(f.env,f.ctx,mac),true);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM gold_trial_receipts_v2').get().n,1);
  assert.equal(f.sql.prepare('SELECT delivery_attempts FROM gold_trial_receipts_v2').get().delivery_attempts,2);
});
test('panne après publication de source : reprise sans nouvelle révision ni bail bloqué 30 s',async()=>{
  const f=fixture();await receipt(f);let clock=now(),batches=0;
  const realBatch=f.db.batch.bind(f.db);
  f.db.batch=async statements=>{if(++batches===2)throw new Error('temporary receipt write failure');return realBatch(statements);};
  const delivery=createTrialDelivery(bridge,{now:()=>clock});
  await assert.rejects(delivery(f.env,f.ctx,mac));
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM device_sources').get().n,1);
  assert.equal(f.sql.prepare('SELECT delivered_at FROM gold_trial_receipts_v2').get().delivered_at,null);
  clock+=3100;assert.equal(await delivery(f.env,f.ctx,mac),true);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM source_revisions').get().n,1);
});
test('notification lente : le reçu et le droit de lecture sont finalisés sans attendre le push',async()=>{
  const f=fixture();await receipt(f);let release,background;
  const push=new Promise(r=>{release=r;});
  const delivery=createTrialDelivery({...bridge,notifyBox:()=>push});
  assert.equal(await delivery(f.env,{waitUntil(p){background=p;}},mac),true);
  assert.ok(f.sql.prepare('SELECT delivered_at FROM gold_trial_receipts_v2').get().delivered_at);
  release();await background;
});
test('deux reprises concurrentes : un bail et une seule révision',async()=>{
  const f=fixture();await receipt(f);let release;
  const gate=new Promise(resolve=>{release=resolve;});let entered=false;
  const delivery=createTrialDelivery({...bridge,sealSource:async(...args)=>{entered=true;await gate;return bridge.sealSource(...args);}});
  const a=delivery(f.env,f.ctx,mac);while(!entered) await new Promise(r=>setImmediate(r));
  assert.equal(await delivery(f.env,f.ctx,mac),false);release();assert.equal(await a,true);
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM source_revisions').get().n,1);
});
test('une liste client ou une suppression concurrente gagne : aucun écrasement',async()=>{
  for(const conflict of ['source','tombstone']) {
    const f=fixture();await receipt(f);
    const delivery=createTrialDelivery({...bridge,sealSource:async(...args)=>{
      if(conflict==='source') f.sql.prepare("INSERT INTO device_sources(mac,type,label,updated_at) VALUES (?,'m3u','Liste client',?)").run(mac,now());
      else f.sql.prepare('INSERT INTO device_source_clears(mac,cleared_at) VALUES (?,?)').run(mac,now()+1000);
      return bridge.sealSource(...args);
    }});
    assert.equal(await delivery(f.env,f.ctx,mac),false);
    assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM source_revisions').get().n,0);
    if(conflict==='source')assert.equal(f.sql.prepare('SELECT label FROM device_sources').get().label,'Liste client');
    else assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM device_sources').get().n,0);
  }
});
test('suppression après livraison et expiration ne réinstallent jamais la liste',async()=>{
  const f=fixture();await receipt(f);const delivery=createTrialDelivery(bridge);
  await delivery(f.env,f.ctx,mac);f.sql.exec('DELETE FROM device_sources');
  await delivery(f.env,f.ctx,mac);assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM device_sources').get().n,0);
  const g=fixture();await receipt(g);g.sql.exec('UPDATE gold_trial_receipts_v2 SET expire=1');
  assert.equal(await delivery(g.env,g.ctx,mac),false);
});
test('routes hors Gold conservées : même réponse sans accès D1 nouveau',async()=>{
  const f=fixture({migrated:false}),request=new Request('https://worker.example/robots.txt');
  const a=await gold.fetch(request,f.env,f.ctx),b=await production.default.fetch(request,f.env,f.ctx);
  assert.equal(a.status,b.status);assert.equal(await a.text(),await b.text());
});
test('même Android ID sur deux MAC concurrentes : une seule réservation et création',async()=>{
  const f=fixture();f.sql.exec('UPDATE gold_trial_settings_v2 SET gold_trial_enabled=1');let release,started=false,count=0;
  const pending=new Promise(r=>{release=r;});
  const handle=createGoldTrialHandler({verifyDevice:async()=> 'ok',eligibility:async()=>({trial_used:false,already_customer:false}),
    listDemoKeys:async()=>[{label:'manzi10'}],createDemo24h:async()=>{count++;started=true;await pending;return {isDemo:true,paidCreditsUsed:0,expire:now()+86_400_000,line_id:'one'};},deliverSource:async()=>true});
  const first=handle(req(),f.env);while(!started)await new Promise(r=>setImmediate(r));
  const other=await handle(req('/api/gold-trial',{body:{mac:secondMac,android_id:androidId,app_version:'109'}}),f.env);
  assert.equal(other.status,409);release();assert.equal((await first).status,201);assert.equal(count,1);
});
