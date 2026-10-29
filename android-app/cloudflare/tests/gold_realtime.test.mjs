import test from 'node:test';
import assert from 'node:assert/strict';
import { startRealtimeFixture, fixtureJwt } from './realtime_fixture.mjs';

test('Worker + vrais DO : preuve, présence, reprise, actions et accusés isolés', { timeout: 30_000 }, async () => {
  const f = await startRealtimeFixture();
  const mac = 'MK:11:22:33:44:55', secret = 'fixture-device-secret-long-enough-32';
  const request = async (path, method = 'GET', body, token = f.token) => {
    const response = await f.mf.dispatchFetch(`${f.origin}${path}`, { method,
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    const value = await response.json();
    assert.ok(response.ok, `${path}: ${response.status} ${JSON.stringify(value)}`);
    return value;
  };
  const open = (path, headers = {}) => f.mf.dispatchFetch(`${f.origin}${path}`, { headers: { Upgrade: 'websocket', ...headers } });
  const messages = socket => {
    const items = []; socket.accept();
    socket.addEventListener('message', event => items.push(JSON.parse(event.data)));
    return items;
  };
  const until = async (condition, detail = () => 'événement attendu sous 3 s') => {
    const end = Date.now() + 3000;
    while (!condition() && Date.now() < end) await new Promise(resolve => setTimeout(resolve, 10));
    assert.ok(condition(), detail());
  };
  try {
    await request('/__fixture/register', 'POST', { mac, androidId: 'fixture-android' });
    await request('/api/device-proof', 'POST', { mac, androidId: 'fixture-android', secret });
    assert.equal((await open(`/api/box/ws?mac=${mac}`)).status, 401);
    assert.equal((await open(`/api/box/ws?mac=${mac}`, { 'X-Device-Secret': 'wrong' })).status, 401);
    assert.equal((await open('/api/v1/rt/ws?token=' + f.token)).status, 401);
    const { ticket } = await request('/api/v1/rt/ticket', 'POST', {});
    const panel = (await open(`/api/v1/rt/ws?ticket=${ticket}`)).webSocket;
    assert.ok(panel);
    const events = messages(panel);
    assert.equal((await open(`/api/v1/rt/ws?ticket=${ticket}`)).status, 401, 'ticket consommé une seule fois');
    const device = (await open(`/api/box/ws?mac=${mac}`, { 'X-Device-Secret': secret, 'X-Panel-Role': 'super_admin', 'X-Panel-Id': 'attacker' })).webSocket;
    assert.ok(device);
    const orders = messages(device);
    await until(() => events.some(event => event.type === 'presence' && event.online));
    assert.equal((await request(`/api/v1/boxes/live?mac=${mac}`)).items[0].online, true);
    const actions = [
      ['/api/v1/trial-extend', 'POST', { mac, days: 1 }, 'license'],
      ['/api/v1/activate', 'POST', { mac, plan: 'yearly' }, 'activate'],
      [`/api/v1/sources/${mac}`, 'PUT', { type: 'm3u', label: 'Recette', m3u_url: `${f.origin}/__fixture/list.m3u` }, 'source'],
      [`/api/v1/sources/${mac}`, 'DELETE', undefined, 'source_clear'],
      [`/api/v1/devices/fixture-${mac}`, 'PATCH', { block_status: 'frozen' }, 'suspend'],
      ['/api/v1/announcements', 'POST', { title: 'Recette temps réel', body: 'Message local' }, 'message'],
    ];
    for (const [path, method, body, kind] of actions) {
      const start = Date.now(), index = orders.length;
      await request(path, method, body);
      await until(() => orders.slice(index).some(event => event.type === kind), () => `${kind}: ${JSON.stringify(orders.slice(index))}`);
      const order = orders.slice(index).find(event => event.type === kind);
      assert.ok(Date.now() - start < 2000, `${kind}: poussé sous 2 s`);
      assert.ok(order.order_id);
      const ack = await f.mf.dispatchFetch(`${f.origin}/api/box/ack/${encodeURIComponent(mac)}`, {
        method: 'POST', headers: { 'X-Device-Secret': secret, 'Content-Type': 'application/json' },
        body: JSON.stringify({ orders: [{ order_id: order.order_id, state: 'applied', result: 'refreshed', applied_at: Date.now() }] }),
      });
      assert.equal(ack.status, 200);
      const ackBody = await ack.json();
      assert.equal(ackBody.results[0].state, 'applied', JSON.stringify(ackBody));
      await until(() => events.some(event => event.type === 'receipt' && event.order_id === order.order_id && event.state === 'applied'));
    }
    await request(`/api/v1/devices/fixture-${mac}`,'PATCH',{block_status:'active'});
    const quote=await request('/api/v1/gold/golden/quote','POST',{mac,sub:1,bouquet_id:'84802'});
    assert.equal(f.providerCalls.filter(call=>call.action==='new').length,0);
    const goldenStart=Date.now();
    const {order:golden}=await request('/api/v1/gold/golden/confirm','POST',{
      quote_id:quote.order.id,confirmed:true,confirmed_cost:quote.order.cost});
    assert.equal(golden.state,'delivered');
    for(const id of [golden.license_order_id,golden.source_order_id]) {
      await until(()=>orders.some(item=>item.order_id===id));
      const command=orders.find(item=>item.order_id===id);
      let appliedRev;
      if(command.type==='source') {
        const source=await f.mf.dispatchFetch(`${f.origin}/api/device-source/${mac}`,{headers:{'X-Device-Secret':secret}});
        appliedRev=(await source.json()).rev;assert.ok(appliedRev>0);
      }
      const ack=await f.mf.dispatchFetch(`${f.origin}/api/box/ack/${encodeURIComponent(mac)}`,{
        method:'POST',headers:{'X-Device-Secret':secret,'Content-Type':'application/json'},body:JSON.stringify({orders:[{
          order_id:id,state:'applied',result:'refreshed',applied_at:Date.now(),config_rev:appliedRev}]}),
      });
      assert.equal(ack.status,200);
      await until(()=>events.some(item=>item.type==='receipt'&&item.order_id===id&&item.state==='applied'));
      if(appliedRev)assert.ok(events.find(item=>item.type==='receipt'&&item.order_id===id&&item.state==='applied').applied_rev>=appliedRev);
    }
    assert.ok(Date.now()-goldenStart<2000,'Golden : création simulée et deux accusés sous 2 s');
    assert.deepEqual(f.providerCalls.filter(call=>call.action==='new'),[{action:'new',sub:'1',key:'Manzi8'}]);
    const cursor = orders.filter(event => event.seq).at(-1).seq;
    device.close(1000, 'test');
    await until(() => events.some(event => event.type === 'presence' && event.online === false));
    await request('/api/v1/announcements', 'POST', { title: 'Hors ligne 1' });
    await request('/api/v1/announcements', 'POST', { title: 'Hors ligne 2' });
    const resumed = (await open(`/api/box/ws?mac=${mac}&after=${cursor}`, { 'X-Device-Secret': secret })).webSocket;
    const replay = messages(resumed);
    await until(() => replay.filter(event => event.seq > cursor).length === 2);
    assert.equal(replay.filter(event => event.seq <= cursor).length, 0);
    // Le même JWT signé ne suffit pas à devenir propriétaire d'une autre MAC.
    await f.db.prepare("INSERT INTO resellers(id,email,password_hash,status,created_at) VALUES ('other','other@example.invalid','unused','active',1)").run();
    assert.equal((await request('/api/v1/boxes/live', 'GET', undefined, fixtureJwt('reseller', 'other'))).items.length, 0);
    const resellerTicket = await request('/api/v1/rt/ticket', 'POST', {}, fixtureJwt('reseller', 'other'));
    const reseller = (await open(`/api/v1/rt/ws?ticket=${resellerTicket.ticket}`)).webSocket;
    const privateEvents = messages(reseller);
    await request('/api/v1/announcements', 'POST', { title: 'Pas au revendeur tiers' });
    await until(() => replay.filter(event => event.seq > cursor).length === 3);
    assert.equal(privateEvents.filter(event => event.mac).length, 0);
    assert.doesNotMatch(JSON.stringify(events), /fixture-device-secret|password|m3u_url/);
    resumed.close(); reseller.close(); panel.close();
  } finally { await f.close(); }
});
