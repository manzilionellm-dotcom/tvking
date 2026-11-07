import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.js';
import { createD1 } from './test_support/d1_sqlite.mjs';
import { totp } from './account_security.js';
const password = 'Fixture9Passphrase!';
function fixture() {
  const t = createD1({extraSql:['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT']});
  return {...t, env:{DB:t.DB, ADMIN_SECRET:password, ACCOUNT_ENCRYPTION_KEY:crypto.randomUUID(), SECRETS_KEY:crypto.randomUUID()}};
}
async function api(env, method, path, {token,body,cookie,origin,ip='192.0.2.1'}={}) {
  const headers = {'Content-Type':'application/json','CF-Connecting-IP':ip};
  if(token) headers.Authorization='Bearer '+token;
  if(cookie) headers.Cookie=cookie;
  if(origin) headers.Origin=origin;
  const r = await worker.fetch(new Request('https://worker.test/api/v1/'+path,{method,headers,...(body===undefined?{}:{body:JSON.stringify(body)})}),env,{waitUntil(){}});
  return {status:r.status, headers:r.headers, cookie:r.headers.get('Set-Cookie')?.split(';')[0], body:await r.json()};
}
const login = (env,body={email:'admin',password},options={}) => api(env,'POST','auth/login',{body,...options});
test('account API: TOTP, single-use recovery, password rotation, refresh replay and logout-all', async () => {
  const {env,db} = fixture();
  const one = await login(env); const two = await login(env);
  assert.equal(one.status,200);
  const jwt = JSON.parse(Buffer.from(one.body.token.split('.')[1],'base64url'));
  assert.equal(jwt.exp-jwt.iat,900); assert.ok(jwt.sid);
  const setup = await api(env,'POST','me/2fa/setup',{token:one.body.token,body:{password}});
  assert.equal(setup.status,200);
  const code = await totp(setup.body.secret,Math.floor(Date.now()/30000));
  const confirm = await api(env,'POST','me/2fa/confirm',{token:one.body.token,body:{password,code}});
  assert.equal(confirm.status,200); assert.equal(confirm.body.recovery_codes.length,10);
  assert.equal((await api(env,'GET','auth/me',{token:two.body.token})).status,401);
  db.prepare('UPDATE admin_users SET last_login_at=1').run();
  assert.equal((await login(env)).status,401);
  assert.equal(db.prepare('SELECT last_login_at FROM admin_users').get().last_login_at,1);
  const recovery=confirm.body.recovery_codes;
  const three=await login(env,{email:'admin',password,code:recovery[0],recovery:true});
  assert.equal(three.status,200);
  assert.equal((await login(env,{email:'admin',password,code:recovery[0],recovery:true})).status,401);
  const next='Different9Passphrase!';
  assert.equal((await api(env,'POST','me/password',{token:three.body.token,body:{current_password:'wrong',new_password:next}})).status,401);
  assert.equal((await api(env,'POST','me/password',{token:three.body.token,body:{current_password:password,new_password:next}})).status,200);
  assert.equal((await api(env,'GET','auth/me',{token:one.body.token})).status,401);
  const renewed=await api(env,'POST','auth/refresh',{cookie:three.cookie}); assert.equal(renewed.status,200);
  assert.equal((await api(env,'POST','auth/refresh',{cookie:three.cookie})).status,401);
  assert.equal((await api(env,'GET','auth/me',{token:renewed.body.token})).status,200);
  assert.equal((await api(env,'POST','me/logout-all',{token:renewed.body.token})).status,200);
  assert.equal((await api(env,'GET','auth/me',{token:renewed.body.token})).status,401);
  assert.equal((await api(env,'POST','auth/refresh',{cookie:renewed.cookie})).status,401);
  const four=await login(env,{email:'admin',password:next,code:recovery[1],recovery:true}); assert.equal(four.status,200);
  assert.equal((await api(env,'POST','me/2fa/disable',{token:four.body.token,body:{password:next,code:recovery[2],recovery:true}})).status,200);
  assert.equal((await login(env,{email:'admin',password:next})).status,200);
  assert.equal((await login(env)).status,401); // ancien secret maître désactivé par défaut
  const audit=JSON.stringify(db.prepare('SELECT * FROM audit_logs').all());
  assert.ok(audit.includes('session.logout_all'));
  assert.equal(audit.includes(next),false); assert.equal(audit.includes(setup.body.secret),false);
});
test('admin API: persistent per-identity lockout, strict origin and malformed input', async()=>{
  const {env}=fixture();
  assert.equal((await login(env,undefined,{origin:'https://evil.invalid'})).status,403);
  for(let i=0;i<5;i++) assert.equal((await login(env,{email:'missing',password:'wrong'})).status,401);
  assert.equal((await login(env,{email:'missing',password:'wrong'})).status,429);
  assert.equal((await login(env,{email:123,password})).status,400);
  const allowed=await login(env,undefined,{origin:'https://atlas-console-k7q2.vercel.app'});
  assert.equal(allowed.status,200); assert.equal(allowed.headers.get('Access-Control-Allow-Origin'),'https://atlas-console-k7q2.vercel.app');
  assert.match(allowed.headers.get('Cache-Control'),/no-store/);
});
test('reseller API: limits owner-only, password reset and suspension revoke sessions', async()=>{
  const {env}=fixture(); const owner=await login(env); const token=owner.body.token;
  const created=await api(env,'POST','resellers',{token,body:{email:'reseller@example.invalid',password,name:'Reseller'}}); assert.equal(created.status,201);
  const id=created.body.id;
  const signed=await api(env,'POST','auth/reseller/login',{body:{email:'reseller@example.invalid',password}}); assert.equal(signed.status,200);
  assert.equal((await api(env,'PUT',`resellers/${id}/limits`,{token:signed.body.token,body:{max_activations:10}})).status,403);
  assert.equal((await api(env,'PUT','theme',{token:signed.body.token,body:{name:'light'}})).status,403);
  assert.equal((await api(env,'PUT',`resellers/${id}/limits`,{token,body:{max_activations:0,allowed_plans:['yearly'],expires_at:null,max_sub_resellers:0}})).status,200);
  const next='Reset9Passphrase!';
  assert.equal((await api(env,'PATCH',`resellers/${id}`,{token,body:{password:next}})).status,200);
  assert.equal((await api(env,'GET','auth/me',{token:signed.body.token})).status,401);
  const again=await api(env,'POST','auth/reseller/login',{body:{email:'reseller@example.invalid',password:next}}); assert.equal(again.status,200);
  assert.equal((await api(env,'PATCH',`resellers/${id}`,{token,body:{status:'suspended'}})).status,200);
  assert.equal((await api(env,'GET','auth/me',{token:again.body.token})).status,401);
  assert.equal((await api(env,'DELETE',`resellers/${id}`,{token,body:{confirm:'wrong'}})).status,400);
  assert.equal((await api(env,'DELETE',`resellers/${id}`,{token,body:{confirm:id}})).status,200);
});
