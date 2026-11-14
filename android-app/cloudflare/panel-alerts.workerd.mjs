// Entrée exacte enveloppant la baseline déployée, D1/DO locaux. Les alertes
// ne doivent jamais altérer débit, idempotence, ACK ou réassociation.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';
import { Miniflare, Log, LogLevel } from 'miniflare';
import { ensurePanelAlertsSchema, collectConfirmedOrderFailures } from './panel-alerts.js';
import { buildPanelAlertsMigration } from './prepare_panel_alerts_migration.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const candidate = resolve(process.argv[2] || join(here, '../../../novatube-recovery-evidence/panel-alert-release/novatube4k-live-entry.js'));
const pair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
const publicKey = Buffer.from(await crypto.subtle.exportKey('raw', pair.publicKey)).toString('base64url');
const secret = randomBytes(32).toString('hex'), key = randomBytes(32).toString('hex'), rawMac = 'AABBCCDDEEA1';
const outbound = [], prefix = '/api/v1/panel-alerts';
let passed = 0, current = 'startup';
const mf = new Miniflare({ host:'127.0.0.1',port:0,cf:false,modules:true,scriptPath:candidate,modulesRoot:dirname(candidate),
  modulesRules:[{type:'ESModule',include:['**/*.js']}],compatibilityDate:'2025-05-01',compatibilityFlags:[],
  d1Databases:{DB:'panel-alerts-business-fixture'},durableObjects:{RT_HUB:{className:'RealtimeHub',useSQLite:true}},
  bindings:{ADMIN_SECRET:secret,SECRETS_KEY:randomBytes(32).toString('hex'),ACCOUNT_ENCRYPTION_KEY:randomBytes(32).toString('hex'),
    DEVICE_TOKEN_SECRET:randomBytes(32).toString('hex'),DEFAULT_SERVERS:'[]',PANEL_PUSH_PUBLIC_KEY:publicKey,
    PANEL_ORIGINS:'https://panel.fixture.test'},
  outboundService:async()=>{outbound.push(true);return Response.json({error:'fixture_network_denied'},{status:503});},
  log:new Log(LogLevel.WARN),
});
async function step(name,fn){current=name;const result=await fn();passed++;console.log('PASS '+name);return result;}
async function api(method,path,{token,body,headers={}}={}){
  const h={'content-type':'application/json','cf-connecting-ip':'192.0.2.92',...headers};if(token)h.authorization='Bearer '+token;
  const r=await mf.dispatchFetch('https://fixture.test'+path,{method,headers:h,body:body===undefined?undefined:JSON.stringify(body)});
  const text=await r.text();let data;try{data=JSON.parse(text)}catch{data=null}
  return {status:r.status,data,text};
}
function device(action,body={},deviceKey=key){return api('POST','/api/novatube4k/'+action,{body:{raw_mac:rawMac,...body},headers:{'X-Device-Key':deviceKey}});}
function status(r,value){assert.equal(r.status,value,'HTTP error='+(r.data?.error||'none'));}

try{
  console.log(JSON.stringify({candidate,candidate_sha256:createHash('sha256').update(readFileSync(candidate)).digest('hex'),runtime:'workerd',external_network:'denied'}));
  await mf.ready;const DB=await mf.getD1Database('DB');
  await step('schéma D1 local et comparaison changes() contre meta.changes',async()=>{
    for(const sql of readFileSync(join(here,'schema.sql'),'utf8').split(/;\s*(?:\n|$)/).map(s=>s.replace(/^\s*--.*$/gm,'').trim()).filter(Boolean))await DB.prepare(sql).run();
    try{await DB.prepare('ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT').run()}catch{}
    await DB.batch([
      DB.prepare('CREATE TABLE fixture_meta_business(id TEXT PRIMARY KEY,state TEXT)'),
      DB.prepare('CREATE TABLE fixture_meta_alerts(id INTEGER PRIMARY KEY,kind TEXT)'),
      DB.prepare("INSERT INTO fixture_meta_business VALUES('a','sent')"),
      DB.prepare("CREATE TRIGGER fixture_meta_trigger AFTER UPDATE ON fixture_meta_business WHEN NEW.state='failed' BEGIN INSERT INTO fixture_meta_alerts(kind) VALUES('problem'); END"),
    ]);
    const result=await DB.batch([
      DB.prepare("UPDATE fixture_meta_business SET state='failed' WHERE id='a'"),DB.prepare('SELECT changes() n'),
    ]);
    assert.equal(result[0].meta.changes,2,'D1 compte aussi le trigger');assert.equal(result[1].results[0].n,1,'SQL changes conserve la ligne métier');
  });
  await step('migration additive exacte, rejouable sans données métier ou événements inventés',async()=>{
    // La production 318 a déjà ses tables dynamiques. Les initialiser avec
    // une autre box de fixture AVANT la migration, sans aucune alerte.
    const oldRaw='AABBCCDDEEAF';
    status(await device('register',{raw_mac:oldRaw}),200);
    status(await device('panel',{raw_mac:oldRaw}),200);
    const protectedTables=['apps','customers','devices','licenses','novatube4k_devices'];
    const before=await Promise.all(protectedTables.map(async name=>(await DB.prepare('SELECT * FROM '+name+' ORDER BY 1').all()).results));
    const migration=buildPanelAlertsMigration();
    await DB.batch(migration.statements.map(sql=>DB.prepare(sql)));
    const installed=(await DB.prepare('SELECT installed_at FROM panel_alert_meta WHERE id=1').first()).installed_at;
    await DB.batch(migration.statements.map(sql=>DB.prepare(sql)));
    assert.equal((await DB.prepare('SELECT installed_at FROM panel_alert_meta WHERE id=1').first()).installed_at,installed);
    const after=await Promise.all(protectedTables.map(async name=>(await DB.prepare('SELECT * FROM '+name+' ORDER BY 1').all()).results));
    assert.deepEqual(after,before);
    for(const name of ['panel_alert_events','novatube4k_recovery_requests']){
      assert.equal((await DB.prepare('SELECT COUNT(*) n FROM '+name).first()).n,0);
    }
    assert.equal((await DB.prepare("SELECT COUNT(*) n FROM sqlite_master WHERE type='trigger' AND name LIKE 'panel_alert_%'").first()).n,6);
  });
  const token=await step('auth historique et API owner active sans permission Push implicite',async()=>{
    const login=await api('POST','/api/v1/auth/login',{body:{email:'admin',password:secret}});status(login,200);
    status(await api('GET',prefix+'/events'),401);
    status(await api('GET',prefix+'/preferences',{token:login.data.token,headers:{Origin:'https://evil.test'}}),403);
    const p=await api('GET',prefix+'/preferences',{token:login.data.token});status(p,200);assert.equal(p.data.enabled,false);assert.equal(p.data.public_key,publicKey);
    return login.data.token;
  });
  const mac=await step('trigger premier enrôlement, jamais activation de licence inactive',async()=>{
    const first=await device('register');status(first,200);assert.equal(first.data.active,false);status(await device('register'),200);
    const rows=(await DB.prepare('SELECT type,mac FROM panel_alert_events').all()).results;
    assert.deepEqual(rows,[{type:'new_device',mac:first.data.mac}]);return first.data.mac;
  });
  const reseller=await step('compte revendeur de fixture avec crédit et authentification réelle',async()=>{
    const email='fixture@example.test',password='Fixture9Aa!'+randomBytes(12).toString('hex');
    const made=await api('POST','/api/v1/resellers',{token,body:{email,password,name:'Fixture',credit_balance:100}});status(made,201);
    const login=await api('POST','/api/v1/auth/reseller/login',{body:{email,password}});status(login,200);
    status(await api('GET',prefix+'/events',{token:login.data.token}),403);return {id:made.data.id,token:login.data.token};
  });
  await step('activation et débit unique avec triggers, rejeu Idempotency-Key inchangé',async()=>{
    const before=await DB.prepare('SELECT credit_balance FROM resellers WHERE id=?').bind(reseller.id).first();
    const body={mac,plan:'yearly'},headers={'Idempotency-Key':'fixture-push-activation-001'};
    const first=await api('POST','/api/v1/activate',{token:reseller.token,body,headers});status(first,201);
    const replay=await api('POST','/api/v1/activate',{token:reseller.token,body,headers});status(replay,201);
    assert.equal((await DB.prepare('SELECT credit_balance FROM resellers WHERE id=?').bind(reseller.id).first()).credit_balance,before.credit_balance-first.data.credits_charged);
    assert.equal((await DB.prepare("SELECT COUNT(*) n FROM panel_alert_events WHERE type='activation'").first()).n,1);
    assert.equal((await DB.prepare("SELECT COUNT(*) n FROM credit_ledger WHERE reseller_id=? AND delta<0").bind(reseller.id).first()).n,1);
    const marker=await DB.prepare('SELECT committed_at FROM idempotency_keys WHERE k LIKE ?').bind('%fixture-push-activation-001').first();assert.ok(marker.committed_at);
  });
  await step('activation sans clé d’idempotence et route renouvellement également capturées',async()=>{
    status(await api('POST','/api/v1/activate',{token,body:{mac,plan:'yearly'}}),201);
    const licence=await DB.prepare('SELECT id FROM licenses WHERE app_id=? AND device_id=(SELECT id FROM devices WHERE mac=?)').bind('app_novatube4k',mac).first();
    status(await api('POST','/api/v1/licenses/'+licence.id+'/renew',{token,body:{plan:'yearly'}}),200);
    assert.equal((await DB.prepare("SELECT COUNT(*) n FROM panel_alert_events WHERE type='activation'").first()).n,3);
  });
  await step('rollback D1 annule aussi une alerte, sans modifier durée ou crédits',async()=>{
    const before=await DB.prepare('SELECT id,expires_at FROM licenses WHERE device_id=(SELECT id FROM devices WHERE mac=?)').bind(mac).first();
    const count=await DB.prepare('SELECT COUNT(*) n FROM panel_alert_events').first();
    await assert.rejects(DB.batch([
      DB.prepare('UPDATE licenses SET expires_at=expires_at+1000,updated_at=? WHERE id=?').bind(Date.now(),before.id),
      DB.prepare('INSERT INTO fixture_nonexistent VALUES(1)'),
    ]));
    assert.equal((await DB.prepare('SELECT expires_at FROM licenses WHERE id=?').bind(before.id).first()).expires_at,before.expires_at);
    assert.equal((await DB.prepare('SELECT COUNT(*) n FROM panel_alert_events').first()).n,count.n);
  });
  await step('ACK failed garde changed=true et marque la source rejetée, collecte ensuite une seule alerte',async()=>{
    status(await api('PUT','/api/v1/sources/'+mac,{token,body:{sources:[{type:'m3u',label:'Fixture',m3u_url:'https://fixture.test/list.m3u?token=fixture'}]}}),200);
    const panel=await device('panel');status(panel,200);const command=panel.data.commands.find(c=>c.kind==='source');assert.ok(command);
    const ack=await device('orders-ack',{orders:[{order_id:command.order_id,state:'failed',error_code:'fixture_refused',error_message:'Fixture refusal',applied_at:Date.now()}]});
    status(ack,200);assert.equal(ack.data.results[0].changed,true);assert.equal(ack.data.results[0].state,'failed');
    assert.equal((await DB.prepare('SELECT state FROM source_revisions WHERE mac=? AND rev=?').bind(mac,command.config_rev).first()).state,'rejected_by_box');
    assert.equal((await collectConfirmedOrderFailures({DB})).inserted,1);assert.equal((await collectConfirmedOrderFailures({DB})).inserted,0);
  });
  await step('blackbox authentifiée persistée produit uniquement incident fixe récent',async()=>{
    const stamp=new Date(Date.now()-1000).toISOString().slice(0,19).replace('T',' ');
    const text='NovaTube — journal de la box\nMAC Atlas : '+mac+'\nÉvénements récents (UTC) :\n'+stamp+'  provider.http_auth\n';
    status(await device('blackbox',{text},randomBytes(32).toString('hex')),401);
    status(await device('blackbox',{text}),200);status(await device('blackbox',{text}),200);
    assert.equal((await DB.prepare("SELECT COUNT(*) n FROM panel_alert_events WHERE source_kind='novatube_blackbox'").first()).n,1);
  });
  await step('recovery candidates dédupliqués et clé inchangée avant approbation',async()=>{
    const first=await device('register',{},randomBytes(32).toString('hex'));status(first,409);
    await ensurePanelAlertsSchema({DB});
    status(await device('register',{},randomBytes(32).toString('hex')),409);
    const rows=(await DB.prepare("SELECT * FROM panel_alert_events WHERE source_kind='recovery'").all()).results;
    assert.equal(rows.length,1);assert.ok(!JSON.stringify(rows).includes(first.data.recovery.code));
    status(await device('state'),200);
  });
  await step('opt-in explicite et clés valides conservés sans exposer le secret de souscription',async()=>{
    const prefs={enabled:true,types:{new_device:true,activation:true,problem:true}};
    status(await api('PUT',prefix+'/preferences',{token,body:prefs}),200);
    const auth=randomBytes(16).toString('base64url'),endpoint='https://fcm.googleapis.com/fcm/send/fixture-private';
    const r=await api('POST',prefix+'/subscriptions',{token,body:{endpoint,keys:{p256dh:publicKey,auth},expirationTime:null,label:'Fixture',consent:true,permission:'granted'}});
    status(r,201);assert.equal(r.data.delivery_confirmed,false);assert.ok(r.data.expires_at>Date.now());
    const listed=await api('GET',prefix+'/subscriptions',{token});status(listed,200);
    assert.ok(!listed.text.includes(endpoint));assert.ok(!listed.text.includes(auth));assert.ok(!listed.text.includes(publicKey));
    status(await api('DELETE',prefix+'/subscriptions/'+r.data.id,{token}),200);
    assert.equal((await DB.prepare('SELECT enabled FROM panel_push_subscriptions WHERE id=?').bind(r.data.id).first()).enabled,0);
  });
  await step('inbox privée et lecture sans publication d’annonces client',async()=>{
    const inbox=await api('GET',prefix+'/events',{token});status(inbox,200);assert.ok(inbox.data.items.length>=6);
    assert.ok(inbox.data.items.every(e=>e.url.startsWith('/devices?mac=')||e.url.startsWith('/blackbox?mac=')));
    assert.ok(!inbox.text.includes(rawMac));assert.ok(!inbox.text.includes(key));assert.ok(!inbox.text.includes('https://fixture.test/list'));
    status(await api('POST',prefix+'/read',{token,body:{event_ids:inbox.data.items.map(e=>e.event_id)}}),200);
    assert.equal((await api('GET',prefix+'/events',{token})).data.unread_count,0);
    assert.deepEqual(outbound,[]);
  });
  console.log(JSON.stringify({result:'PASS',checks:passed,runtime:'workerd',outbound_requests:outbound.length,compatibility_date:'2025-05-01',compatibility_flags:[]}));
}catch(error){console.error(JSON.stringify({result:'FAIL',step:current,checks_passed:passed,message:String(error.message)}));process.exitCode=1}
finally{await mf.dispose()}
