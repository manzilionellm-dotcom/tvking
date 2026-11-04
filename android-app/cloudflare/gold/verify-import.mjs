// Contrôle hors ligne : aucune requête Cloudflare, aucune exécution de route.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root=new URL('./',import.meta.url);
const deployment=JSON.parse(readFileSync(new URL('config/deployment.json',root)));
assert.equal(deployment.active_deployment.versions[0].version_id,'a3f55171-173c-4a91-bfa9-1a347db085a4');
for(const {name,sha256} of deployment.modules) {
  assert.ok(['gold.js','worker.js'].includes(name));
  const path=new URL(name,root),bytes=readFileSync(path);
  assert.equal(createHash('sha256').update(bytes).digest('hex'),sha256,`${name} diffère de l'export`);
  execFileSync(process.execPath,['--check',fileURLToPath(path)]);
}
const source=readFileSync(new URL('gold.js',root),'utf8');
assert.match(source,/from ['"]\.\/worker\.js['"]/);
const config=readFileSync(new URL('wrangler.toml',root),'utf8');
assert.match(config,/^main = "gold\.js"/m);
assert.match(config,/binding = "DB"/);
assert.match(config,/database_name = "tvking_licensing"/);
assert.match(config,/name = "RT_HUB"/);
assert.match(config,/class_name = "RealtimeHub"/);
assert.doesNotMatch(config,/^\[\[migrations\]\]/m);
const {bindings}=JSON.parse(readFileSync(new URL('config/bindings.json',root)));
for(const binding of bindings.filter(item=>item.type==='secret_text'))assert.equal(binding.value,`<<SECRET_REDACTED:${binding.name}>>`);
const runtime=await import('./gold.js');
assert.equal(typeof runtime.default.fetch,'function');
assert.equal(typeof runtime.RealtimeHub,'function');
console.log('PASS : sources SHA-256 identiques, syntaxe, exports, entrée Gold et bindings vérifiés ; aucun réseau.');
