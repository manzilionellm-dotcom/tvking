import { Miniflare, createFetchMock } from 'miniflare';
import { build } from 'esbuild';
import { readFile } from 'node:fs/promises';
import { createHmac,createHash,createCipheriv,randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import '../prepare_gold_runtime.mjs';

export const fixtureSecret = 'fixture-admin-secret-local-tests-only-64-characters';
export function fixtureJwt(role = 'super_admin', sub = 'fixture-admin') {
  const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const head = enc({ alg: 'HS256', typ: 'JWT' });
  const body = enc({ sub, role, iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 });
  return `${head}.${body}.${createHmac('sha256', fixtureSecret).update(`${head}.${body}`).digest('base64url')}`;
}

export async function startRealtimeFixture(port = 0) {
  let origin;
  const providerCalls=[];
  // Le réseau fournisseur est intercepté : aucune clé ni dépense réelle.
  const fetchMock=createFetchMock();fetchMock.disableNetConnect();
  fetchMock.get('https://cms-8k.net').intercept({method:'GET',path:/^\/api\/api\.php\?/}).reply(options=>{
    const params=new URL(options.path,'https://cms-8k.net').searchParams,action=params.get('action');
    providerCalls.push({action,sub:params.get('sub'),key:params.get('api_key')?.includes('key8')?'Manzi8':'manzi10'});
    const data=action==='reseller'?{status:true,credits:100}:action==='bouquet'?[{id:'84802',name:'France fixture'}]
      :action==='new'?{status:true,user_id:'fixture-line',url:`${origin}/__fixture/golden.m3u?username=fixture-user&password=fixture-password`}:{status:false};
    return {statusCode:200,data:JSON.stringify(data),responseOptions:{headers:{'Content-Type':'application/json'}}};
  }).persist();
  const bundled = await build({ entryPoints: [fileURLToPath(new URL('./realtime_fixture_worker.js', import.meta.url))],
    bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
  const mf = new Miniflare({ modules: true, script: bundled.outputFiles[0].text,
    host: '127.0.0.1', port, compatibilityDate: '2025-05-01',
    durableObjects: { RT_HUB: 'RealtimeHub' }, d1Databases: ['DB'],fetchMock,
    bindings: { ADMIN_SECRET: fixtureSecret, FIXTURE_TOKEN: fixtureJwt(), GOLD_TRIAL_POLICY_READY: 'true',
      PANEL_ORIGINS: 'http://127.0.0.1:4173' } });
  origin = (await mf.ready).origin;
  const db = await mf.getD1Database('DB');
  for (const name of ['../production/schema.sql', '../migrations/20261028_gold_trial_policy.sql', '../migrations/20261028_gold_trial_runtime.sql','../migrations/20261029_golden_admin.sql']) {
    const sql = (await readFile(new URL(name, import.meta.url), 'utf8')).replace(/--[^\n]*/g, '');
    for (const statement of sql.split(';').map(value => value.trim()).filter(Boolean)) await db.prepare(statement).run();
  }
  await db.batch([
    db.prepare("INSERT INTO customers(id,created_at,updated_at) VALUES ('fixture-customer',1,1)"),
    db.prepare("INSERT INTO admin_users(id,email,password_hash,role,created_at) VALUES ('fixture-admin','fixture@example.invalid','unused','super_admin',1)"),
    db.prepare("INSERT INTO apps(id,name,package_name,created_at,updated_at) VALUES ('app_7motion','Fixture','fixture.test',1,1)"),
    db.prepare("INSERT INTO app_config(key,value) VALUES ('gold_enabled','1'),('gold_cost_per_month','1'),('gold_min_credits','5'),('gold_max_per_day','5')"),
  ]);
  for(const [id,reseller] of [['key8','Manzi8'],['key10','manzi10']]) {
    const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',createHash('sha256').update('gold-key-v1:'+fixtureSecret).digest(),iv);
    const enc=`${iv.toString('base64url')}.${Buffer.concat([cipher.update(`fixture-${id}-not-a-real-api-key`),cipher.final(),cipher.getAuthTag()]).toString('base64url')}`;
    await db.prepare('INSERT INTO gold_keys(id,enc,fp,reseller,use_for_paid,created_at) VALUES (?,?,?,?,1,1)').bind(id,enc,id,reseller).run();
  }
  return { mf, db, origin, token: fixtureJwt(),providerCalls, close: () => mf.dispose() };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const fixture = await startRealtimeFixture(Number(process.env.REALTIME_PORT || 8787));
  console.log(`REALTIME_FIXTURE_READY ${fixture.origin}`);
  process.on('SIGTERM', async () => { await fixture.close(); process.exit(0); });
  process.on('SIGINT', async () => { await fixture.close(); process.exit(0); });
}
