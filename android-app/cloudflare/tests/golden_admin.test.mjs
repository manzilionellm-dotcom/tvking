import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createHash,createHmac,randomBytes,createCipheriv } from 'node:crypto';
import '../prepare_gold_runtime.mjs';
import gold from '../gold.js';
import { enrollProductionDevice } from '../gold_trial_device.js';

// Toutes les clés et lignes sont fictives ; aucun appel réseau réel.
const mac='MK:11:22:33:44:55',secret='fixture-device-secret-golden-32-characters';
const adminSecret='fixture-admin-secret-golden-not-a-real-key-64-characters';
const providerUrl='https://provider.example.invalid/get.php?username=fixture-user&password=fixture-password&type=m3u_plus';
const file=name=>readFileSync(new URL(name,import.meta.url),'utf8');
function jwt(role='super_admin',sub='admin') {
  const enc=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
  const h=enc({alg:'HS256',typ:'JWT'}),p=enc({sub,role,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600});
  return `${h}.${p}.${createHmac('sha256',adminSecret).update(`${h}.${p}`).digest('base64url')}`;
}
function sealKey(value) {
  const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',createHash('sha256').update('gold-key-v1:'+adminSecret).digest(),iv);
  return `${iv.toString('base64url')}.${Buffer.concat([cipher.update(value),cipher.final(),cipher.getAuthTag()]).toString('base64url')}`;
}
async function fixture(t) {
  const sql=new DatabaseSync(':memory:');
  for(const name of ['../production/schema.sql','../migrations/20261028_gold_trial_policy.sql','../migrations/20261028_gold_trial_runtime.sql','../migrations/20261029_golden_admin.sql'])sql.exec(file(name));
  sql.exec(`INSERT INTO customers(id,created_at,updated_at) VALUES ('customer',1,1);
    INSERT INTO apps(id,name,package_name,created_at,updated_at) VALUES ('app_7motion','Fixture','fixture.app',1,1);
    INSERT INTO admin_users(id,email,password_hash,role,is_active,created_at) VALUES ('admin','fixture@example.invalid','unused','super_admin',1,1);
    INSERT INTO app_config(key,value) VALUES ('gold_enabled','1'),('gold_cost_per_month','1'),('gold_min_credits','5'),('gold_max_per_day','5');`);
  sql.prepare('INSERT INTO devices(id,customer_id,mac,first_seen_at,last_seen_at,android_id) VALUES (?,?,?,1,1,?)').run('device','customer',mac,'fixture-android');
  sql.prepare('INSERT INTO trial_anchors(mac,android_id,started_at) VALUES (?,?,?)').run(mac,'fixture-android',Date.now());
  for(const [id,label,priority] of [['key8','Manzi8',99],['key10','manzi10',0]])sql.prepare(`INSERT INTO gold_keys(id,enc,fp,reseller,use_for_paid,trial_priority,created_at) VALUES (?,?,?,?,1,?,1)`)
    .run(id,sealKey(`fixture-${id}-not-a-real-api-key`),id,label,priority);
  const db={prepare(query){let args=[];const stmt={bind(...values){args=values;return stmt;},async first(){return sql.prepare(query).get(...args)??null;},async all(){return {results:sql.prepare(query).all(...args)};},async run(){const prepared=sql.prepare(query);if(/\bRETURNING\b/i.test(query)){const results=prepared.all(...args);return {results,meta:{changes:sql.prepare('SELECT changes() AS n').get().n}};}return {results:[],meta:{changes:Number(prepared.run(...args).changes)}};}};return stmt;},async batch(stmts){sql.exec('BEGIN');try{const results=[];for(const stmt of stmts)results.push(await stmt.run());sql.exec('COMMIT');return results;}catch(e){sql.exec('ROLLBACK');throw e;}}};
  const env={DB:db,ADMIN_SECRET:adminSecret,GOLD_TRIAL_POLICY_READY:'true'};
  const pending=[],ctx={waitUntil(p){pending.push(p.catch(()=>{}));}};
  t.after(async()=>{await Promise.all(pending);sql.close();});
  const calls=[],balances={key8:100,key10:100};let failCreate=false,afterCreate=null;
  t.mock.method(globalThis,'fetch',async input=>{
    const url=new URL(typeof input==='string'?input:input.url);
    assert.equal(url.origin,'https://cms-8k.net');
    const params=url.searchParams,key=params.get('api_key')?.includes('key8')?'key8':'key10',action=params.get('action');
    calls.push({key,action,sub:params.get('sub'),pack:params.get('pack')});
    if(action==='reseller')return Response.json({status:true,credits:balances[key]});
    if(action==='bouquet')return Response.json([{id:'84802',name:'France fixture'}]);
    assert.equal(action,'new');
    if(failCreate)throw new Error('timeout containing a private-provider-secret');
    if(afterCreate)afterCreate();
    return Response.json({status:true,user_id:'fixture-line',url:providerUrl});
  });
  async function request(path,{method='POST',body,role='super_admin',headers={}}={}) {
    return gold.fetch(new Request('https://worker.example'+path,{method,headers:{Authorization:`Bearer ${jwt(role)}`,'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.10',...headers},...(method==='GET'?{}:{body:JSON.stringify(body||{})})}),env,ctx);
  }
  assert.equal((await enrollProductionDevice(new Request('https://worker.example/api/device-proof',{method:'POST',headers:{'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.10'},body:JSON.stringify({mac,androidId:'fixture-android',secret})}),env)).status,200);
  const quote=async (extra={})=>{const r=await request('/api/v1/gold/golden/quote',{body:{mac,sub:3,bouquet_id:'84802',...extra}});return {status:r.status,...await r.json()};};
  const confirm=async (order,extra={})=>{const r=await request('/api/v1/gold/golden/confirm',{body:{quote_id:order.id,confirmed:true,confirmed_cost:order.cost,...extra}});return {status:r.status,...await r.json()};};
  return {sql,env,ctx,request,quote,confirm,calls,balances,setFailCreate(value){failCreate=value;},setAfterCreate(fn){afterCreate=fn;},flush:()=>Promise.all(pending)};
}

test('Golden : devis sans achat, confirmation précise, Manzi8 prioritaire, stockage chiffré et deux ordres',async t=>{
  const f=await fixture(t),q=await f.quote();assert.equal(q.status,200);assert.equal(q.order.cost,3);assert.equal(q.order.key_label,'Manzi8');
  assert.equal(f.calls.filter(c=>c.action==='new').length,0);
  assert.equal((await f.confirm(q.order,{confirmed:false})).status,400);
  assert.equal((await f.confirm(q.order,{confirmed_cost:4})).status,400);
  const result=await f.confirm(q.order);assert.equal(result.status,201);
  assert.equal(result.order.state,'delivered');
  assert.ok(result.order.source_order_id);assert.ok(result.order.license_order_id);
  assert.deepEqual(f.calls.filter(c=>c.action==='new'),[{key:'key8',action:'new',sub:'3',pack:'84802'}]);
  assert.doesNotMatch(JSON.stringify(result),/fixture-password|fixture-user|api_key|private-provider/);
  const row=f.sql.prepare('SELECT * FROM golden_orders').get();assert.doesNotMatch(row.source_enc,/fixture-password|provider\.example/);
  assert.match(JSON.parse(row.source_enc).m3u_url,/^enc1\./);
  assert.equal(f.sql.prepare('SELECT plan FROM licenses').get().plan,'quarterly');
  const replay=await f.confirm(q.order);assert.equal(replay.order.id,q.order.id);assert.equal(f.calls.filter(c=>c.action==='new').length,1);
  assert.equal((await f.quote()).error,'existing_line');
  const path=`/api/device-source/${mac}`;
  assert.equal((await f.request(path,{method:'GET'})).status,403);
  const source=await f.request(path,{method:'GET',headers:{'X-Device-Secret':secret}});assert.equal(source.status,200);assert.match(await source.text(),/fixture-password/);
  await f.flush();
});

test('Golden : manzi10 uniquement si Manzi8 manque de crédits avant création',async t=>{
  const f=await fixture(t);f.balances.key8=7;const q=await f.quote();assert.equal(q.order.key_label,'manzi10');
  assert.equal((await f.confirm(q.order)).order.state,'delivered');
  assert.deepEqual(f.calls.filter(c=>c.action==='new').map(c=>c.key),['key10']);await f.flush();
});

test('Golden : résultat incertain bloque définitivement la MAC et la clé, sans deuxième achat',async t=>{
  const f=await fixture(t),q=await f.quote();f.setFailCreate(true);
  const result=await f.confirm(q.order);assert.equal(result.status,202);assert.equal(result.order.state,'uncertain');
  assert.doesNotMatch(JSON.stringify(result),/private-provider-secret/);
  assert.equal((await f.confirm(q.order)).order.state,'uncertain');assert.equal((await f.quote()).error,'existing_line');
  const retry=await f.request('/api/v1/gold/golden/deliver',{body:{order_id:q.order.id}});assert.equal((await retry.json()).order.state,'uncertain');
  assert.equal(f.calls.filter(c=>c.action==='new').length,1);assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM golden_key_locks').get().n,1);
});

test('Golden : durée/template invalides, essai fermé, refus des comptes non administrateurs',async t=>{
  const f=await fixture(t);
  for(const sub of [0,2,24,99,'1'])assert.equal((await f.quote({sub})).status,400);
  assert.equal((await f.quote({bouquet_id:'999999'})).error,'no_key_available');
  f.sql.exec("UPDATE admin_users SET role='admin'");
  assert.equal((await f.request('/api/v1/gold/golden/templates',{method:'GET',role:'admin'})).status,403);
  f.sql.exec("UPDATE admin_users SET role='super_admin'");
  const trial=await f.request('/api/gold-trial',{body:{mac,android_id:'fixture-android',app_version:'109'},headers:{'X-Device-Secret':secret}});assert.equal(trial.status,403);
  assert.equal(f.sql.prepare('SELECT gold_trial_enabled FROM gold_trial_settings_v2').get().gold_trial_enabled,0);
  assert.equal(f.calls.filter(c=>c.action==='new').length,0);
});

test('Golden : devis expiré, tarif modifié, listes concurrentes et budget quotidien refusés avant achat',async t=>{
  const f=await fixture(t);
  let q=await f.quote();f.sql.prepare('UPDATE golden_orders SET quote_until=1 WHERE id=?').run(q.order.id);assert.equal((await f.confirm(q.order)).error,'quote_expired');
  q=await f.quote();f.sql.exec("UPDATE app_config SET value='2' WHERE key='gold_cost_per_month'");assert.equal((await f.confirm(q.order)).error,'quote_changed');
  q=await f.quote();f.sql.prepare("INSERT INTO device_sources(mac,type,version,updated_at) VALUES (?,'m3u',1,1)").run(mac);assert.equal((await f.confirm(q.order)).error,'source_changed');
  f.sql.exec('DELETE FROM device_sources');f.sql.exec("UPDATE app_config SET value='0' WHERE key='gold_max_per_day'");
  q=await f.quote();assert.equal((await f.confirm(q.order)).error,'daily_cap_reached');assert.equal(f.calls.filter(c=>c.action==='new').length,0);
});

test('Golden : deux devis simultanés et double confirmation ne créent qu’une ligne',async t=>{
  const f=await fixture(t),q1=await f.quote(),q2=await f.quote();
  const results=await Promise.all([f.confirm(q1.order),f.confirm(q1.order),f.confirm(q2.order)]);
  assert.equal(results.filter(r=>r.order?.state==='delivered').length,1);
  assert.equal(f.calls.filter(c=>c.action==='new').length,1);await f.flush();
});

test('Golden : suppression après achat ne ressuscite pas la source et livraison ne rachète jamais',async t=>{
  const f=await fixture(t),q=await f.quote();
  f.setAfterCreate(()=>f.sql.prepare('INSERT INTO device_source_clears(mac,cleared_at) VALUES (?,?)').run(mac,Date.now()));
  assert.equal((await f.confirm(q.order)).order.state,'created');
  const retry=await f.request('/api/v1/gold/golden/deliver',{body:{order_id:q.order.id}});assert.equal((await retry.json()).order.state,'created');
  assert.equal(f.sql.prepare('SELECT COUNT(*) AS n FROM device_sources').get().n,0);assert.equal(f.calls.filter(c=>c.action==='new').length,1);await f.flush();
});

test('activation classique et ancien provisionnement ne créent plus automatiquement chez Strong',async t=>{
  const f=await fixture(t);
  assert.equal((await f.request('/api/v1/activate',{body:{mac,plan:'monthly'}})).status,201);await f.flush();
  assert.equal((await f.request('/api/v1/gold/provision',{body:{mac,kind:'paid',sub:1}})).status,409);
  assert.equal(f.calls.length,0);
});

test('Golden conserve la licence à vie et les autres listes lors de l’ajout',async t=>{
  const f=await fixture(t);
  await f.request('/api/v1/activate',{body:{mac,plan:'lifetime'}});await f.flush();
  const prior={type:'m3u',label:'Liste personnelle',m3u_url:'https://fixture.example.invalid/list.m3u'};
  f.sql.prepare("INSERT INTO device_sources(mac,type,sources_json,version,updated_at) VALUES (?,'m3u',?,1,1)").run(mac,JSON.stringify([prior]));
  const q=await f.quote(),result=await f.confirm(q.order);assert.equal(result.order.state,'delivered');
  assert.equal(f.sql.prepare('SELECT plan FROM licenses').get().plan,'lifetime');
  const saved=JSON.parse(f.sql.prepare('SELECT sources_json FROM device_sources').get().sources_json);
  assert.equal(saved.length,2);assert.deepEqual(saved[1],prior);
  assert.equal(f.calls.filter(c=>c.action==='new').length,1);await f.flush();
});

test('Golden exige un tarif explicite et une identité appareil toujours valable',async t=>{
  const f=await fixture(t);f.sql.exec("DELETE FROM app_config WHERE key='gold_cost_per_month'");
  assert.equal((await f.quote()).error,'invalid_tariff');
  f.sql.exec("INSERT INTO app_config(key,value) VALUES ('gold_cost_per_month','1')");
  f.sql.exec("UPDATE trial_anchors SET android_id='another-device'");
  assert.equal((await f.quote()).error,'device_unavailable');assert.equal(f.calls.length,0);
});
