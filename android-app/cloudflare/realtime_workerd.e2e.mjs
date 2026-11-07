import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare } from 'miniflare';

test('workerd: real WS upgrade, one-use tickets and global/targeted fanout', async () => {
  const mf = new Miniflare({modules:true, scriptPath:new URL('./dist/worker.js',import.meta.url).pathname, compatibilityDate:'2025-05-01',durableObjects:{RT_HUB:{className:'RealtimeHub',useSQLite:true}},d1Databases:{DB:'local-test'}});
  const sockets=[];
  try {
    const ns=await mf.getDurableObjectNamespace('RT_HUB'); const hub=ns.get(ns.idFromName('devices-v1'));
    async function open(mac) {
      const t=await hub.fetch('https://hub/device-ticket',{method:'POST',body:JSON.stringify({mac,exp:Date.now()+60000})});
      assert.equal(t.status,200); const {ticket}=await t.json();
      const r=await mf.dispatchFetch('https://worker.test/api/device-rt/ws?ticket='+ticket,{headers:{Upgrade:'websocket'}});
      assert.equal(r.status,101); const ws=r.webSocket; assert.ok(ws); ws.accept(); sockets.push(ws);
      assert.equal((await mf.dispatchFetch('https://worker.test/api/device-rt/ws?ticket='+ticket,{headers:{Upgrade:'websocket'}})).status,401);
      return ws;
    }
    const a=await open('MK:BB:CC:DD:EE:01'); const b=await open('MK:BB:CC:DD:EE:02');
    const seenA=[],seenB=[];
    a.addEventListener('message',e=>seenA.push(JSON.parse(e.data))); b.addEventListener('message',e=>seenB.push(JSON.parse(e.data)));
    const next = ws => new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('push_timeout')),2000);
      const handler=e=>{const value=JSON.parse(e.data); if(value.type==='hello')return; clearTimeout(timeout);ws.removeEventListener('message',handler);resolve(value);};
      ws.addEventListener('message',handler);
    });
    const first=next(a);
    await hub.fetch('https://hub/device-notify',{method:'POST',body:JSON.stringify({type:'source',mac:'MK:BB:CC:DD:EE:01'})});
    assert.equal((await first).type,'source');
    const both=Promise.all([next(a),next(b)]);
    await hub.fetch('https://hub/device-notify',{method:'POST',body:JSON.stringify({type:'theme'})});
    assert.deepEqual((await both).map(e=>e.type),['theme','theme']);
    assert.equal(seenB.some(e=>e.type==='source'),false);
    assert.equal(seenA.filter(e=>e.version).every(e=>Object.keys(e).every(k=>['v','type','mac','version','at'].includes(k))),true);
  } finally {for(const ws of sockets) ws.close(); await mf.dispose();}
});
