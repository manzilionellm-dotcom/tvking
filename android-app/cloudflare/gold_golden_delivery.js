// Livraison d'une ligne déjà créée. Cette reprise n'appelle jamais Strong.
// On conserve toutes les listes existantes ; une modification concurrente ou
// une suppression depuis l'app gagne sur la livraison Golden.
const plans = {1:'monthly',3:'quarterly',6:'biannual',12:'yearly'};

export function createGoldenDelivery({original,tokenFor,notifyBox}) {
  return async function deliver(env,ctx,row) {
    const db=env.DB,trace=`golden:${row.id}`;
    let current=await db.prepare('SELECT * FROM device_sources WHERE mac=?').bind(row.mac).first();
    if (!row.source_saved_at) {
      const clear=await db.prepare('SELECT cleared_at FROM device_source_clears WHERE mac=?').bind(row.mac).first();
      if ((current?Number(current.version):-1)!==row.expected_source_version||Number(clear?.cleared_at||0)!==row.expected_clear_at)
        throw new Error('source_changed');
      const source=JSON.parse(row.source_enc);
      const prior=current?(current.sources_json?JSON.parse(current.sources_json):[current]):[];
      if (!Array.isArray(prior)||prior.length>=3) throw new Error('source_full');
      const encoded=JSON.stringify([source,...prior]),at=Date.now();
      // L'INSERT/UPDATE et la révision sont une seule transaction D1. La
      // version et la suppression sont revalidées au moment de l'écriture.
      const write=current?db.prepare(`UPDATE device_sources SET type=?,label=?,server_url=?,username=?,password=?,
        m3u_url=?,epg_url=NULL,sources_json=?,origin='panel',updated_at=?,version=version+1
        WHERE mac=? AND version=? AND COALESCE((SELECT cleared_at FROM device_source_clears WHERE mac=?),0)=?`)
        .bind(source.type,source.label,source.server_url??null,source.username??null,source.password??null,source.m3u_url??null,encoded,at,row.mac,
          row.expected_source_version,row.mac,row.expected_clear_at)
        :db.prepare(`INSERT INTO device_sources(mac,type,label,server_url,username,password,m3u_url,sources_json,origin,updated_at,version)
          SELECT ?,?,?,?,?,?,?,?,'panel',?,1
          WHERE COALESCE((SELECT cleared_at FROM device_source_clears WHERE mac=?),0)=?
          ON CONFLICT(mac) DO NOTHING`)
          .bind(row.mac,source.type,source.label,source.server_url??null,source.username??null,source.password??null,source.m3u_url??null,encoded,at,row.mac,row.expected_clear_at);
      const result=await db.batch([
        write,
        db.prepare(`INSERT INTO source_revisions(mac,rev,state,panel_json,item_count,hosts,trace_id,actor_type,actor_id,published_at,created_at)
          SELECT ?,COALESCE((SELECT MAX(rev) FROM source_revisions WHERE mac=?),0)+1,'published',?,?,'[]',?,'admin',?,?,?
          WHERE changes()=1`)
          .bind(row.mac,row.mac,encoded,prior.length+1,trace,row.actor_id,at,at),
        db.prepare(`UPDATE golden_orders SET source_rev=(SELECT rev FROM source_revisions WHERE mac=? AND trace_id=? ORDER BY rev DESC LIMIT 1),
          source_saved_at=? WHERE id=? AND EXISTS(SELECT 1 FROM source_revisions WHERE mac=? AND trace_id=?)`)
          .bind(row.mac,trace,at,row.id,row.mac,trace),
      ]);
      if (!result[0].meta.changes) throw new Error('source_changed');
      row=await db.prepare('SELECT * FROM golden_orders WHERE id=?').bind(row.id).first();
      current=await db.prepare('SELECT * FROM device_sources WHERE mac=?').bind(row.mac).first();
    }
    // Ne jamais republier une liste supprimée, y compris après une panne.
    const revision=await db.prepare('SELECT panel_json FROM source_revisions WHERE mac=? AND rev=?').bind(row.mac,row.source_rev).first();
    if (!current||current.sources_json!==revision?.panel_json) throw new Error('source_changed');
    if (!row.license_order_id) {
      const token=await tokenFor(env);
      const lifetime=await db.prepare(`SELECT id FROM licenses WHERE device_id=? AND app_id='app_7motion' AND expires_at IS NULL`).bind(row.device_id).first();
      const response=await original.fetch(new Request('https://internal/api/v1/activate',{
        method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',
          'Idempotency-Key':`golden_${row.id}`,'X-Request-Id':trace},body:JSON.stringify({mac:row.mac,plan:lifetime?'lifetime':plans[row.sub]})}),env,ctx);
      const result=await response.json();
      if (!response.ok||!result.ok) throw new Error('license_pending');
      // Le cas « déjà à vie » peut ne pas créer de nouvel ordre ; pousser un
      // contrôle de licence assure quand même une confirmation de l'appareil.
      row.license_order_id=result.order_id||await notifyBox(env,row.mac,'activate',{traceId:trace});
      if (!row.license_order_id) throw new Error('license_pending');
      await db.prepare('UPDATE golden_orders SET license_order_id=? WHERE id=?').bind(row.license_order_id,row.id).run();
    }
    if (!row.source_order_id) {
      const order=await notifyBox(env,row.mac,'source',{configRev:row.source_rev,traceId:trace,t0:row.provider_created_at});
      if (!order) throw new Error('notification_pending');
      await db.prepare('UPDATE golden_orders SET source_order_id=? WHERE id=?').bind(order,row.id).run();
    }
  };
}
