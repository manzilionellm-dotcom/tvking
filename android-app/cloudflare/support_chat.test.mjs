// Preuves par les vraies routes HTTP et SQLite, sans simuler le stockage.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, randomBytes } from 'node:crypto';
import worker from './worker.js';
import { createHash } from 'node:crypto';
import { createD1 } from './test_support/d1_sqlite.mjs';

const NOW = Date.UTC(2026, 9, 11, 18);
const ctx = { waitUntil() {}, passThroughOnException() {} };

function setup(t) {
  t.mock.timers.enable({ apis: ['Date'], now: NOW });
  const db = createD1();
  t.after(() => db.db.close());
  const env = { DB: db.DB, ADMIN_SECRET: randomBytes(32).toString('hex') };
  for (const [id, role] of [['owner', 'super_admin'], ['staff', 'admin']]) {
    db.db.prepare('INSERT INTO admin_users (id,email,password_hash,role,created_at) VALUES (?,?,?,?,?)')
      .run(id, `${id}@panel.invalid`, 'fixture', role, NOW);
  }
  function auth(id) {
    const h = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const p = Buffer.from(JSON.stringify({ sub: id, role: id === 'owner' ? 'super_admin' : 'admin', iat: NOW / 1000, exp: NOW / 1000 + 86400 })).toString('base64url');
    return `${h}.${p}.${createHmac('sha256', env.ADMIN_SECRET).update(`${h}.${p}`).digest('base64url')}`;
  }
  async function call(path, { method = 'GET', body, user = 'owner', country = '', legacyAdmin = false, deviceSecret } = {}) {
    const headers = { 'Content-Type': 'application/json', 'CF-IPCountry': country };
    if (user) headers.Authorization = `Bearer ${auth(user)}`;
    if (deviceSecret) headers['X-Support-Token'] = deviceSecret;
    if (legacyAdmin) headers['X-Admin-Secret'] = env.ADMIN_SECRET;
    const res = await worker.fetch(new Request(`https://panel.invalid${path}`, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    }), env, ctx);
    return { status: res.status, data: await res.json() };
  }
  return { ...db, env, call };
}


const SECRET_A = Buffer.alloc(32,1).toString('base64url');
const SECRET_B = Buffer.alloc(32,2).toString('base64url');
const MAC_A = createHash('sha256').update(SECRET_A).digest('hex');
const MAC_B = createHash('sha256').update(SECRET_B).digest('hex');
const msg = (body = 'Bonjour, une question.') => ({ client_id: crypto.randomUUID(), body });

test('confidentialité réelle : la MAC seule, un autre appareil et un employé sont refusés', async t => {
 const s=setup(t);
 const a='/api/support/'+MAC_A;
 const sent=await s.call(a,{method:'POST',body:msg(),deviceSecret:SECRET_A,user:null});
 assert.equal(sent.status,201);
 for(const method of ['GET','POST','PATCH']) {
   const body=method==='GET'?undefined:method==='POST'?msg():{read_through:sent.data.item.seq};
   assert.equal((await s.call(a,{method,body,user:null})).status,401);
   assert.equal((await s.call(a,{method,body,user:null,deviceSecret:SECRET_B})).status,401);
   assert.equal((await s.call('/api/v1/support/'+MAC_A,{method,body,user:'staff'})).status,403);
 }
 assert.equal((await s.call('/api/support/'+MAC_B,{user:null,deviceSecret:SECRET_B})).data.items.length,0);
 assert.equal((await s.call(a,{user:null,deviceSecret:SECRET_A})).data.items.length,1);
});

test('envoi idempotent, réponse propriétaire et accusés de lecture véridiques',async t=>{
 const s=setup(t); const body=msg(); const path='/api/support/'+MAC_A;
 const replies=await Promise.all(Array.from({length:8},()=>s.call(path,{method:'POST',body,user:null,deviceSecret:SECRET_A})));
 assert.ok(replies.every(r=>[200,201].includes(r.status))); assert.equal(new Set(replies.map(r=>r.data.item.seq)).size,1);
 assert.equal((await s.call('/api/v1/support')).data.items[0].unread,1);
 const clientSeq=replies[0].data.item.seq;
 await s.call('/api/v1/support/'+MAC_A,{method:'PATCH',body:{read_through:clientSeq}});
 assert.equal((await s.call('/api/v1/support')).data.items[0].unread,0);
 const response=await s.call('/api/v1/support/'+MAC_A,{method:'POST',body:msg('Bonjour, comment vous aider ?')});
 const read=await s.call(path,{user:null,deviceSecret:SECRET_A});
 assert.equal(read.data.unread,1); assert.equal(read.data.client_read_seq,0); assert.equal(read.data.items.at(-1).sender,'owner');
 await s.call(path,{method:'PATCH',body:{read_through:response.data.item.seq},user:null,deviceSecret:SECRET_A});
 assert.equal((await s.call(path+'?summary=1',{user:null,deviceSecret:SECRET_A})).data.unread,0);
 assert.equal((await s.call(path,{method:'POST',body:{...body,body:'Autre texte'},user:null,deviceSecret:SECRET_A})).status,409);
});

test('une lecture ne peut pas viser le curseur d’un autre client',async t=>{
 const s=setup(t);
 const b=await s.call('/api/support/'+MAC_B,{method:'POST',body:msg(),user:null,deviceSecret:SECRET_B});
 assert.equal((await s.call('/api/support/'+MAC_A,{method:'PATCH',body:{read_through:b.data.item.seq},user:null,deviceSecret:SECRET_A})).status,400);
});

test('anti-abus atomique et validation avant stockage',async t=>{
 const s=setup(t);const path='/api/support/'+MAC_A;
 assert.equal((await s.call(path,{method:'POST',body:msg('x'.repeat(11000)),user:null,deviceSecret:SECRET_A})).status,413);
 for(const body of [msg(''),msg('x'.repeat(2001)),{client_id:'bad',body:'a'}]) assert.equal((await s.call(path,{method:'POST',body,user:null,deviceSecret:SECRET_A})).status,400);
 const rs=await Promise.all(Array.from({length:25},()=>s.call(path,{method:'POST',body:msg(),user:null,deviceSecret:SECRET_A})));
 assert.equal(rs.filter(r=>r.status===201).length,20);assert.equal(rs.filter(r=>r.status===429).length,5);
 assert.equal((await s.call(path+'?after=-1',{user:null,deviceSecret:SECRET_A})).status,400);
});

test('pagination sans perte, texte non interprété et absence de contenu dans les journaux d’audit',async t=>{
 const s=setup(t);const path='/api/support/'+MAC_A;
 for(let i=0;i<105;i++){ t.mock.timers.tick(4000);await s.call(path,{method:'POST',body:msg('<script>test '+i+'</script>'),user:null,deviceSecret:SECRET_A}); }
 const page=await s.call(path,{user:null,deviceSecret:SECRET_A});assert.equal(page.data.items.length,100);assert.equal(page.data.more,true);
 const older=await s.call(path+'?before='+page.data.items[0].seq,{user:null,deviceSecret:SECRET_A});assert.equal(older.data.items.length,5);
 const forward=await s.call(path+'?after='+older.data.items[0].seq,{user:null,deviceSecret:SECRET_A});
 assert.equal(forward.data.items.length,100);assert.equal(forward.data.more,true);
 const rest=await s.call(path+'?after='+forward.data.items.at(-1).seq,{user:null,deviceSecret:SECRET_A});
 assert.equal(rest.data.items.length,4);assert.equal(new Set([...forward.data.items,...rest.data.items].map(m=>m.seq)).size,104);
 assert.ok(page.data.items.at(-1).body.includes('<script>'));
 assert.equal(s.db.prepare('SELECT COUNT(*) AS n FROM audit_logs').get().n,0);
});


test('le propriétaire retrouve un ancien client au-delà des 100 fils récents', async t=>{
 const s=setup(t);
 await s.call('/api/support/'+MAC_A,{method:'POST',body:{...msg(),device_label:'MK:AB:11:22:33:44'},user:null,deviceSecret:SECRET_A});
 for(let i=1;i<=101;i++)s.db.prepare('INSERT INTO support_threads(mac, updated_at) VALUES (?, ?)').run(String(i).padStart(64,'0'),NOW+i);
 const recent=await s.call('/api/v1/support');
 assert.equal(recent.data.items.length,100);assert.equal(recent.data.items.some(t=>t.mac===MAC_A),false);
 const found=await s.call('/api/v1/support?q=MK%3AAB%3A11');
 assert.equal(found.data.items.length,1);assert.equal(found.data.items[0].mac,MAC_A);
});
