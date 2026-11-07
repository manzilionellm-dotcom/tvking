import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createD1 } from './test_support/d1_sqlite.mjs';
import { totp, strongPassword, startFactor, confirmFactor, verifyFactor, disableFactor, createSession, sessionValid, sessionCookie, refreshSession, revokeSessions, validateWriteBody } from './account_security.js';
import { policySchema, savePolicy, parsePolicy } from './reseller_policy.js';
const user = { sub:'owner', role:'super_admin', email:'test@example.invalid' };
function env() { const { DB } = createD1({schema:false}); return { DB, ADMIN_SECRET:'test-only-encryption-key-not-production' }; }
test('RFC 6238 SHA1 vector, strong passwords and strict JSON bounds', async () => {
  assert.equal(await totp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',1), '287082');
  assert.equal(strongPassword('weak'), false); assert.equal(strongPassword('Strong9Passphrase!'), true);
  assert.equal(validateWriteBody({code:'123456'}), true); assert.equal(validateWriteBody([]), false);
  assert.equal(validateWriteBody(JSON.parse('{"__proto__":{}}')), false);
});
test('TOTP is off by default; encrypted setup, confirm, replay resistance and hashed one-use recovery', async () => {
  const e = env(); assert.equal(await verifyFactor(e,user,''), true);
  const setup = await startFactor(e,user); assert.ok(setup.uri.startsWith('otpauth://'));
  const stored = await e.DB.prepare('SELECT pending FROM auth_factors').first(); assert.equal(stored.pending.includes(setup.secret), false);
  assert.equal(await confirmFactor(e,user,'bad'), null);
  const code = await totp(setup.secret,Math.floor(Date.now()/30000));
  const recovery = await confirmFactor(e,user,code); assert.equal(recovery.length,10);
  assert.equal(await verifyFactor(e,user,code), false); // enrolment code cannot replay
  assert.equal(await verifyFactor(e,user,recovery[0],true), true);
  assert.equal(await verifyFactor(e,user,recovery[0],true), false);
  const rows = (await e.DB.prepare('SELECT code_hash FROM auth_recovery').all()).results;
  assert.equal(JSON.stringify(rows).includes(recovery[1]), false);
  await disableFactor(e,user); assert.equal(await verifyFactor(e,user,''),true);
});
test('short access sessions: hashed rotating refresh, revocation and secure HttpOnly cookie', async () => {
  const e = env(); const s = await createSession(e,user);
  assert.equal(await sessionValid(e,{...user,sid:s.sid}),true);
  const cookie = sessionCookie(s.refresh); for(const flag of ['Secure','HttpOnly','SameSite=Strict','Path=/']) assert.ok(cookie.includes(flag));
  const req = new Request('https://test/auth/refresh',{headers:{Cookie:cookie.split(';')[0]}});
  assert.ok(await refreshSession(e,req)); assert.equal(await refreshSession(e,req),null);
  await revokeSessions(e,user); assert.equal(await sessionValid(e,{...user,sid:s.sid}),false);
});
test('reseller limits reject invalid settings and enforce caps/plans/expiry atomically in SQL', async () => {
  const e = env(); await e.DB.exec('CREATE TABLE resellers (id TEXT PRIMARY KEY,parent_reseller_id TEXT); CREATE TABLE licenses (id TEXT PRIMARY KEY,reseller_id TEXT,status TEXT,plan TEXT,expires_at INTEGER);');
  await policySchema(e);
  assert.equal(parsePolicy({max_activations:-1,allowed_plans:['yearly']}),null);
  await savePolicy(e,'r1',{max_activations:1,allowed_plans:['yearly'],expires_at:null,max_sub_resellers:0});
  await e.DB.prepare("INSERT INTO licenses VALUES ('l1','r1','active','yearly',null)").run();
  await assert.rejects(e.DB.prepare("INSERT INTO licenses VALUES ('l2','r1','active','yearly',null)").run(),/reseller_activation_limit/);
  await assert.rejects(e.DB.prepare("UPDATE licenses SET plan='lifetime' WHERE id='l1'").run(),/reseller_plan_limit/);
  await assert.rejects(e.DB.prepare("INSERT INTO resellers VALUES ('child','r1')").run(),/reseller_child_limit/);
  await savePolicy(e,'r1',{max_activations:10,allowed_plans:['yearly'],expires_at:1,max_sub_resellers:0});
  await assert.rejects(e.DB.prepare("INSERT INTO licenses VALUES ('l2','r1','active','yearly',null)").run(),/reseller_expired/);
});

test('D1 migrations 010-012 are idempotent and include security indexes and policy triggers', async () => {
  const {DB}=createD1({extraSql:['ALTER TABLE resellers ADD COLUMN parent_reseller_id TEXT']});
  for(let round=0;round<2;round++) for(const file of ['010_device_session_keys.sql','011_account_security.sql','012_reseller_limits.sql']) await DB.exec(readFileSync(new URL('./migrations/'+file,import.meta.url),'utf8'));
  const index=await DB.prepare("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_auth_refresh'").first(); assert.ok(index);
  const trigger=await DB.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name='reseller_limit_insert'").first(); assert.ok(trigger);
});
