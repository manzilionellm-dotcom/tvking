import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash, randomBytes } from 'node:crypto';

const [source, dependencies, ready] = process.argv.slice(2).map(x=>resolve(x));
const {Miniflare,Log,LogLevel} = createRequire(join(dependencies,'package.json'))('miniflare');
const worker = new Miniflare({host:'127.0.0.1',port:18787,cf:false,modules:true,
  compatibilityDate:'2025-05-01',modulesRules:[{type:'ESModule',include:['**/*.js']}],
  scriptPath:join(source,'worker.js'),modulesRoot:source,d1Databases:{DB:'zuno-qa-isolated'},
  kvNamespaces:['KV_7MOTION'],bindings:{ADMIN_SECRET:process.env.ZUNO_QA_PASS,
    SOURCE_ENCRYPTION_KEY:randomBytes(32).toString('hex')},
  outboundService:async()=>new Response('synthetic offline lab',{status:503}),
  log:new Log(LogLevel.ERROR)});
await worker.ready;
const db=await worker.getD1Database('DB');
for(const file of ['schema.sql','migrations/003_reseller_hierarchy.sql']){
  const sql=readFileSync(join(source,file),'utf8').replace(/^\s*--.*$/gm,'');
  for(const stmt of sql.split(/;\s*(?:\n|$)/).map(x=>x.trim()).filter(Boolean)){
    try {await db.prepare(stmt).run()} catch(e){if(!String(e).includes('duplicate column'))throw e}
  }
}
writeFileSync(ready,JSON.stringify({local:true,worker_entry_sha256:createHash('sha256').update(readFileSync(join(source,'worker.js'))).digest('hex')}));
process.on('SIGTERM',async()=>{await worker.dispose();process.exit(0)});
