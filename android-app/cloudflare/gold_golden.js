// Golden admin : devis durable, confirmation exacte et création unique.
// Le fournisseur est injecté depuis gold.js. Aucun secret ni texte brut de
// Strong ne figure dans les réponses, les erreurs ou les journaux de ce module.
import { normalizeTrialMac, readSmallJson } from './gold_trial_policy.js';
import { verifyProductionDevice, knownTrialDevice } from './gold_trial_device.js';

const DAY = 86_400_000;
const MONTHS = new Set([1,3,6,12]);
const json = (data,status=200) => Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
const errors = {
  forbidden:'Golden est réservé à l’administrateur.', invalid_request:'Vérifiez la MAC, la durée et le template.',
  device_unavailable:'L’appareil doit être enregistré et actif avant Golden.',
  gold_disabled:'Les créations Golden sont désactivées dans les réglages administrateur.',
  existing_line:'Une ligne ou une création existe déjà pour cet appareil. Consultez son état.',
  source_full:'Trois listes sont déjà affectées à cet appareil.',
  source_changed:'Les listes de l’appareil ont changé. Rechargez le devis.',
  no_key_available:'Aucun compte autorisé ne dispose du template et des crédits nécessaires.',
  invalid_tariff:'Le tarif en crédits doit être configuré avant Golden.',
  quote_expired:'Ce devis a expiré. Demandez un nouveau devis.',
  quote_changed:'Le coût ou la configuration a changé. Confirmez un nouveau devis.',
  confirmation_required:'Confirmez le coût du devis avant la création.',
  daily_cap_reached:'Le plafond quotidien des créations est atteint.',
  key_busy:'Ce compte traite une autre création. Rechargez le devis.',
  preflight_failed:'Les vérifications ont échoué avant la création. Rechargez le devis.',
  unavailable:'Golden est indisponible pour le moment.',
};
const reject = (code,status=409) => json({error:code,message:errors[code] || errors.unavailable},status);
const label = key => String(key.reseller || key.label ||
  (key.id==='gk_mvpkambcp22tk5'?'manzi10':'')).trim();
export function orderedGoldenKeys(keys) {
  const rank = key => ({manzi8:0,manzi10:1})[label(key).toLowerCase()];
  return keys.filter(k=>rank(k)!==undefined && k.enabled!==false && Number(k.enabled??1)!==0 &&
    k.use_for_paid!==false && Number(k.use_for_paid??1)!==0)
    .slice().sort((a,b)=>rank(a)-rank(b));
}

// Accepte les listes et dictionnaires renvoyés par action=bouquet, mais jamais
// un identifiant saisi librement comme preuve de l'existence d'un template.
export function goldenTemplates(raw) {
  const data = raw?.bouquets ?? raw?.data ?? raw;
  const rows = Array.isArray(data) ? data : data && typeof data==='object'
    ? Object.entries(data).filter(([id])=>/^\d+$/.test(id)).map(([id,name])=>({id,name})) : [];
  const out = new Map();
  for (const row of rows) {
    const id = String(row?.id ?? row?.bouquet_id ?? '');
    const name = row?.name ?? row?.bouquet_name;
    if (/^[1-9][0-9]{0,12}$/.test(id) && typeof name==='string' && name.trim() && name.length<=160)
      out.set(id,{id,name:name.trim()});
  }
  return [...out.values()];
}
export function publicGoldenOrder(row) {
  if (!row) return null;
  return {id:row.id,mac:row.mac,sub:row.sub,bouquet_id:row.bouquet_id,bouquet_name:row.bouquet_name,
    key_label:row.key_label,cost:row.cost,cost_basis:'configured_tariff',credits_before:row.credits_before,
    credits_after:row.credits_after,quote_until:row.quote_until,state:row.state,
    provider_created_at:row.provider_created_at,delivered_at:row.delivered_at,
    source_order_id:row.source_order_id,license_order_id:row.license_order_id,error_code:row.error_code};
}

export async function protectGoldenSource(request,env) {
  const route=/^\/(?:api\/(?:device-source|backup|self-source)|config)\/([^/]+)$/.exec(new URL(request.url).pathname);
  if (!route||request.method==='OPTIONS') return null;
  let mac;try {mac=normalizeTrialMac(decodeURIComponent(route[1]));}catch{return reject('invalid_request',400);}
  if (!mac) return reject('invalid_request',400);
  const installed=await env.DB.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='golden_orders'").first();
  if (!installed) return null;
  const receipt=await env.DB.prepare('SELECT id FROM golden_orders WHERE mac=? AND source_enc IS NOT NULL LIMIT 1').bind(mac).first();
  if (!receipt) return null;
  const proof=await env.DB.prepare('SELECT android_id FROM device_secrets WHERE mac=?').bind(mac).first();
  if (!proof||await verifyProductionDevice(env.DB,request,{mac,android_id:proof.android_id})!=='ok')
    return json({error:'device_secret_required'},403);
  return null;
}

export function createGoldenRoutes(a,{now=Date.now,uuid=()=>crypto.randomUUID()}={}) {
  const get = (env,id)=>env.DB.prepare('SELECT * FROM golden_orders WHERE id=?').bind(id).first();
  const latest = (env,mac)=>env.DB.prepare("SELECT * FROM golden_orders WHERE mac=? AND state NOT IN ('quoted','refused') ORDER BY created_at DESC LIMIT 1").bind(mac).first();
  async function deviceState(env,mac) {
    const device=await env.DB.prepare(`SELECT d.id,d.android_id,d.block_status,s.android_id AS proof_android,s.secret_hash
      FROM devices d LEFT JOIN device_secrets s ON s.mac=d.mac WHERE d.mac=?`).bind(mac).first();
    if (!device || ['banned','frozen'].includes(device.block_status)||!device.secret_hash||!device.proof_android||
        device.proof_android!==device.android_id||await knownTrialDevice(env.DB,mac,device.android_id)!=='ok') throw new Error('device_unavailable');
    const source=await env.DB.prepare('SELECT * FROM device_sources WHERE mac=?').bind(mac).first();
    const clear=await env.DB.prepare('SELECT cleared_at FROM device_source_clears WHERE mac=?').bind(mac).first();
    const list=source ? (source.sources_json ? JSON.parse(source.sources_json) : [source]) : [];
    if (!Array.isArray(list) || list.length>=3) throw new Error('source_full');
    return {id:device.id,version:source ? Number(source.version): -1,clear:Number(clear?.cleared_at||0)};
  }
  async function eligible(env,mac) {
    if (await latest(env,mac)) throw new Error('existing_line');
    // Ne pas recréer une ligne historique, même si son ancien statut est ambigu.
    if (await env.DB.prepare("SELECT id FROM gold_lines WHERE mac=? AND kind='paid' LIMIT 1").bind(mac).first())
      throw new Error('existing_line');
    return deviceState(env,mac);
  }
  function tariff(cfg,sub) {
    const unit=Number(cfg.gold_cost_per_month),floor=Number(cfg.gold_min_credits),cap=Number(cfg.gold_max_per_day);
    const cost=Math.round(unit*sub*1000)/1000;
    if (!Number.isFinite(cost)||cost<=0||!Number.isFinite(floor)||floor<0||!Number.isInteger(cap)||cap<0)
      throw new Error('invalid_tariff');
    return {cost,floor,cap};
  }
  async function quote(env,actor,body) {
    const mac=normalizeTrialMac(body?.mac),sub=body?.sub,bouquet=String(body?.bouquet_id||'');
    if (!mac || !/^MK(?::[0-9A-F]{2}){5}$/.test(mac) || !MONTHS.has(sub) || !/^[1-9][0-9]{0,12}$/.test(bouquet)) return reject('invalid_request',400);
    const cfg=await a.config(env);
    if (cfg.gold_enabled!=='1') return reject('gold_disabled',403);
    const price=tariff(cfg,sub),device=await eligible(env,mac);
    const keys=orderedGoldenKeys(await a.keys(env));
    for (const key of keys) {
      if (await env.DB.prepare('SELECT order_id FROM golden_key_locks WHERE key_id=?').bind(key.id).first()) continue;
      let credits,templates;
      try { [credits,templates]=await Promise.all([a.balance(env,key),a.templates(env,key)]); } catch { continue; }
      const selected=templates.find(item=>item.id===bouquet);
      if (!selected||!Number.isFinite(credits)||credits-price.cost<price.floor) continue;
      const id=uuid(),at=now();
      await env.DB.prepare(`INSERT INTO golden_orders(id,actor_id,mac,device_id,sub,bouquet_id,bouquet_name,
        key_id,key_label,cost,credit_floor,credits_before,state,created_at,quote_until,
        expected_source_version,expected_clear_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,'quoted',?,?,?,?)`)
        .bind(id,actor,mac,device.id,sub,bouquet,selected.name,key.id,label(key),price.cost,price.floor,
          credits,at,at+180_000,device.version,device.clear).run();
      return json({order:publicGoldenOrder(await get(env,id))});
    }
    return reject('no_key_available',503);
  }
  async function deliver(env,ctx,row) {
    if (!['created','delivering'].includes(row.state)) return row;
    const claimed=await env.DB.prepare(`UPDATE golden_orders SET state='delivering',delivery_lease_until=?
      WHERE id=? AND state IN ('created','delivering') AND delivery_lease_until<=?`)
      .bind(now()+30_000,row.id,now()).run();
    if (!claimed.meta.changes) return get(env,row.id);
    try {
      await a.deliver(env,ctx,await get(env,row.id));
      await env.DB.prepare("UPDATE golden_orders SET state='delivered',delivered_at=?,delivery_lease_until=0,error_code=NULL WHERE id=?")
        .bind(now(),row.id).run();
    } catch {
      await env.DB.prepare("UPDATE golden_orders SET state='created',delivery_lease_until=0,error_code='delivery_pending' WHERE id=?")
        .bind(row.id).run();
    }
    return get(env,row.id);
  }
  async function confirm(env,ctx,actor,body) {
    const row=typeof body?.quote_id==='string'?await get(env,body.quote_id):null;
    if (!row||row.actor_id!==actor) return reject('invalid_request',400);
    if (body.confirmed!==true||body.confirmed_cost!==row.cost) return reject('confirmation_required',400);
    // Le même devis ne peut jamais déclencher un second appel, même après un
    // redémarrage du Worker ou une réponse HTTP perdue.
    if (row.state!=='quoted') return json({order:publicGoldenOrder(row)});
    if (row.quote_until<now()) return reject('quote_expired');
    const cfg=await a.config(env),price=tariff(cfg,row.sub);
    if (cfg.gold_enabled!=='1') return reject('gold_disabled',403);
    if (price.cost!==row.cost||price.floor!==row.credit_floor) return reject('quote_changed');
    const device=await eligible(env,row.mac);
    if (device.id!==row.device_id||device.version!==row.expected_source_version||device.clear!==row.expected_clear_at)
      return reject('source_changed');
    const day=now()-now()%DAY;
    let claimed;
    try {
      claimed=await env.DB.prepare(`UPDATE golden_orders SET state='preparing',confirmed_at=? WHERE id=? AND state='quoted'
        AND (SELECT COUNT(*) FROM golden_orders WHERE state NOT IN ('quoted','refused') AND confirmed_at>=?)
          +(SELECT COUNT(*) FROM gold_lines WHERE kind='paid' AND status IN ('active','pending') AND created_at>=?)<?`)
        .bind(now(),row.id,day,day,price.cap).run();
    } catch { return reject('existing_line'); }
    if (!claimed.meta.changes) {
      const current=await get(env,row.id);
      return current.state==='quoted'?reject('daily_cap_reached',429):json({order:publicGoldenOrder(current)});
    }
    let locked=false,started=false,stored=false;
    try {
      const lock=await env.DB.prepare('INSERT INTO golden_key_locks(key_id,order_id) VALUES (?,?) ON CONFLICT(key_id) DO NOTHING')
        .bind(row.key_id,row.id).run();
      if (!lock.meta.changes) throw new Error('key_busy');
      locked=true;
      const key=orderedGoldenKeys(await a.keys(env)).find(k=>k.id===row.key_id);
      if (!key) throw new Error('preflight_failed');
      const [credits,templates]=await Promise.all([a.balance(env,key),a.templates(env,key)]);
      if (!Number.isFinite(credits)||credits-row.cost<row.credit_floor||!templates.some(t=>t.id===row.bouquet_id))
        throw new Error('preflight_failed');
      const current=await deviceState(env,row.mac);
      if (current.id!==row.device_id||current.version!==row.expected_source_version||current.clear!==row.expected_clear_at)
        throw new Error('source_changed');
      // Vérifier le chiffrement AVANT l'achat, avec un marqueur sans accès.
      await a.seal(env,{m3u_url:'golden-encryption-preflight'});
      await env.DB.prepare("UPDATE golden_orders SET state='creating',credits_before=? WHERE id=?").bind(credits,row.id).run();
      started=true;
      // UN seul appel de création. Toute réponse incomplète ou perdue reste
      // incertaine : ni clé suivante, ni réessai après un délai arbitraire.
      const created=await a.create(env,key,{sub:row.sub,bouquet:row.bouquet_id,mac:row.mac,id:row.id});
      const at=now(),sealed=await a.seal(env,created.credentials);
      await env.DB.prepare(`UPDATE golden_orders SET state='created',source_enc=?,provider_user_id=?,provider_created_at=? WHERE id=?`)
        .bind(JSON.stringify(sealed),String(created.user_id||''),at,row.id).run();
      stored=true;
      await env.DB.prepare('DELETE FROM golden_key_locks WHERE order_id=?').bind(row.id).run();locked=false;
      const delivered=await deliver(env,ctx,await get(env,row.id));
      // La consultation du solde ne ralentit ni la licence ni l'envoi RT_HUB.
      const balance=Promise.resolve().then(()=>a.balance(env,key)).then(value=>Number.isFinite(value)
        ?env.DB.prepare('UPDATE golden_orders SET credits_after=? WHERE id=?').bind(value,row.id).run():undefined).catch(()=>{});
      if (ctx?.waitUntil) ctx.waitUntil(balance); else await balance;
      return json({order:publicGoldenOrder(delivered)},201);
    } catch (error) {
      const code=stored?'delivery_pending':!started && Object.hasOwn(errors,error?.message)?error.message:started?'creation_uncertain':'preflight_failed';
      await env.DB.prepare('UPDATE golden_orders SET state=?,error_code=? WHERE id=?')
        .bind(stored?'created':started?'uncertain':'refused',code,row.id).run();
      if (locked&&(!started||stored)) await env.DB.prepare('DELETE FROM golden_key_locks WHERE order_id=?').bind(row.id).run();
      return json({order:publicGoldenOrder(await get(env,row.id))},202);
    }
  }
  return async function golden(request,env,ctx) {
    const url=new URL(request.url);
    if (!url.pathname.startsWith('/api/v1/gold/golden')) return null;
    const actor=await a.authenticate(request,env,ctx);
    if (!actor) return reject('forbidden',request.headers.get('Authorization')?403:401);
    try {
      if (url.pathname==='/api/v1/gold/golden/templates'&&request.method==='GET') {
        const rows=new Map();
        const catalogues=await Promise.allSettled(orderedGoldenKeys(await a.keys(env)).map(key=>a.templates(env,key)));
        for (const result of catalogues) if(result.status==='fulfilled')
          for(const template of result.value) if(!rows.has(template.id))rows.set(template.id,template);
        return json({items:[...rows.values()]});
      }
      if (url.pathname==='/api/v1/gold/golden'&&request.method==='GET') {
        const mac=normalizeTrialMac(url.searchParams.get('mac'));
        if (!mac) return reject('invalid_request',400);
        return json({order:publicGoldenOrder(await latest(env,mac))});
      }
      if (request.method!=='POST') return reject('invalid_request',405);
      const body=await readSmallJson(request);if(!body)return reject('invalid_request',400);
      if (url.pathname==='/api/v1/gold/golden/quote') return await quote(env,actor.sub||actor.id,body);
      if (url.pathname==='/api/v1/gold/golden/confirm') return await confirm(env,ctx,actor.sub||actor.id,body);
      if (url.pathname==='/api/v1/gold/golden/deliver') {
        const row=typeof body.order_id==='string'?await get(env,body.order_id):null;
        if (!row) return reject('invalid_request',400);
        return json({order:publicGoldenOrder(await deliver(env,ctx,row))});
      }
      return reject('invalid_request',404);
    } catch(error) { return reject(Object.hasOwn(errors,error?.message)?error.message:'unavailable',503); }
  };
}
