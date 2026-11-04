// Tests isolés : aucun appel au panel réel, aucun identifiant client.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '..');
function context(files, extra = {}) {
  const ctx = vm.createContext({ document: { addEventListener() {} }, ...extra });
  ctx.window = ctx; ctx.addEventListener = () => {};
  for (const file of files) vm.runInContext(fs.readFileSync(path.join(root, 'shared/js', file), 'utf8'), ctx);
  return ctx;
}
test('les blocages priment sur un statut actif ou payé', () => {
  const {DFT} = context(['app.js']);
  assert.equal(DFT.app.canUse(null), false);
  assert.equal(DFT.app.canUse({paid:true}), true);
  for (const block of [{expired:true}, {frozen:true,paid:true}, {banned:true,paid:true}, {status:'banned',paid:true}, {status:'frozen',paid:true}]) {
    assert.equal(DFT.app.canUse({status:'active',trial_until:Date.now()+60000,...block}), false);
  }
  assert.equal(DFT.app.canUse({status:'active',expired:false,trial_until:Date.now()+60000}), true);
  assert.equal(DFT.app.canUse({status:'active',trial_until:1}), false);
});
test('M3U : noms avec virgules, attributs et schémas interdits', () => {
  const {DFT} = context(['m3u.js']);
  const out = DFT.m3u.parse('#EXTM3U\n#EXTINF:-1 group-title="Info, Monde",Nom, complet\nhttps://example.test/live.m3u8\n#EXTINF:-1,Bad\njavascript:alert(1)');
  assert.equal(out.length, 1); assert.equal(out[0].name,'Nom, complet'); assert.equal(out[0].category,'Info, Monde');
});
test('identifiant conservé sans privilège réseau partenaire', () => {
  const data = {};
  const ctx = context(['device.js'], {DFT:{platform:'tizen'},localStorage:{getItem:k=>data[k],setItem:(k,v)=>data[k]=v}});
  let first, second; ctx.DFT.device.getMac(m=>first=m); ctx.DFT.device.getMac(m=>second=m);
  assert.match(first,/^MK(:[A-F0-9]{2}){5}$/); assert.equal(second,first);
});
test('arrêt pendant prepareAsync : aucun redémarrage tardif', () => {
  let ready, played=0, closed=0;
  const ctx = context(['player.js'],{DFT:{platform:'tizen'},webapis:{avplay:{getState:()=> 'NONE',open(){},setDisplayRect(){},setListener(){},prepareAsync:cb=>ready=cb,play:()=>played++,stop(){throw Error('not playing');},close:()=>closed++}},document:{getElementById:()=>({style:{}})}});
  ctx.DFT.player.play('https://example.test/live'); ctx.DFT.player.stop(); ready();
  assert.equal(played,0); assert.equal(closed,1);
});
test('parcours simulé : panel, sources multiples, lecture, retour et gel', async () => {
  const nodes = {};
  function element() { return {style:{},children:[],classList:{add(){},remove(){}},appendChild(n){this.children.push(n);},setAttribute(){}}; }
  const doc = {hidden:false,addEventListener(){},createElement:element,getElementById:id=>nodes[id]||(nodes[id]=element()),querySelectorAll:()=>[]};
  let back, tick, stopped=0, played;
  const ctx = context(['app.js'],{document:doc,setInterval:fn=>tick=fn});
  Object.assign(ctx.DFT,{
    platform:'tizen',registerKeys(){},
    nav:{init(){},onBack:fn=>back=fn,focusFirst(){}},
    device:{getMac:cb=>cb('MK:01:02:03:04:05'),info:()=>({brand:'Samsung'})},
    api:{heartbeat:()=>Promise.resolve({paid:true}),deviceSource:()=>Promise.resolve({sources:[{type:'m3u'},{type:'xtream'}]}),status:()=>Promise.resolve({paid:true,frozen:true})},
    m3u:{load:()=>Promise.reject(Error('source en panne'))},
    xtream:{load:()=>Promise.resolve({channels:[{name:'<img onerror=bad()>',category:'__proto__',url:'https://example.test/live'}]})},
    player:{play:url=>played=url,stop:()=>stopped++}
  });
  const settle=()=>new Promise(resolve=>setImmediate(resolve));
  ctx.DFT.app.boot();await settle();await settle();
  assert.equal(nodes['screen-live'].style.display,'flex');
  const tile=nodes['chan-grid'].children[0];
  assert.equal(tile.children[1].textContent,'<img onerror=bad()>');
  tile.onclick();assert.equal(played,'https://example.test/live');
  assert.equal(nodes['screen-player'].style.display,'flex');
  back();assert.equal(nodes['screen-live'].style.display,'flex');
  back();assert.equal(nodes['screen-exit'].style.display,'flex');
  ctx.DFT.app.cancelExit();assert.equal(nodes['screen-live'].style.display,'flex');
  tick();await settle();assert.equal(nodes['screen-activation'].style.display,'flex');assert.ok(stopped>=2);
  assert.match(nodes['act-msg'].textContent,/pause/);
});
