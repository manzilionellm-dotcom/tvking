// Raccordement au schéma RÉEL du gold-export vérifié. Les anciennes tables
// restent la référence historique ; aucune clé ni ligne n'est remise à zéro.
import { createGoldTrialHandler, normalizeTrialMac, orderDemoKeys, readSmallJson } from './gold_trial_policy.js';
import { goldTrialAdmin } from './gold_trial_admin.js';
import { enrollProductionDevice, verifyProductionDevice } from './gold_trial_device.js';
import { saveTrialReceipt, createTrialDelivery } from './gold_trial_delivery.js';
import { demoContract, createVerifiedDemo24h } from './gold_trial_provider.js';

const json = (body,status=200) => Response.json(body,{status,headers:{'Cache-Control':'no-store'}});
const identityClause = `(UPPER(mac)=? OR android_id=? OR mac IN
  (SELECT mac FROM devices WHERE android_id=? UNION SELECT mac FROM trial_anchors WHERE android_id=?))`;

export async function historicalEligibility(db,mac,androidId='') {
  androidId=androidId || '\u0000'; // Un Android ID absent ne relie pas les appareils inconnus.
  const args = [mac,androidId,androidId,androidId];
  const lines = (await db.prepare(`SELECT kind,status,gold_user_id,username,password,url,error FROM gold_lines
    WHERE ${identityClause}`).bind(...args).all()).results;
  const trials = lines.filter(l=>['trial','demo'].includes(l.kind));
  const created = l=>!!(l.gold_user_id || l.username || l.password || l.url) ||
    ['active','expired','disabled','used','delivered'].includes(l.status);
  // Un ancien timeout est ambigu, même si l'ancien code le marquait "failed".
  // Le seul refus observé dans l'archive prouve l'absence de paquet disponible.
  const ambiguous = trials.some(l=>!created(l) &&
    !(l.status==='failed' && l.error==='Subscription Package not found.'));
  const events = await db.prepare(`SELECT 1 FROM gold_history WHERE
    (UPPER(mac)=? OR mac IN (SELECT mac FROM devices WHERE android_id=? UNION
      SELECT mac FROM trial_anchors WHERE android_id=? UNION SELECT mac FROM gold_lines WHERE android_id=?))
    AND event IN ('trial.create','demo.create') LIMIT 1`).bind(...args).first();
  const claim = await db.prepare(`SELECT state FROM gold_trial_claims_v2
    WHERE (mac=? OR android_id=?) AND state!='failed' LIMIT 1`).bind(mac,androidId).first();
  const paid = await db.prepare(`SELECT 1 FROM licenses l JOIN devices d ON d.id=l.device_id
    WHERE (d.mac=? OR (?!='' AND d.android_id=?)) AND l.plan NOT LIKE 'trial%'
      AND l.status IN ('active','frozen','banned') LIMIT 1`).bind(mac,androidId,androidId).first();
  const source = await db.prepare('SELECT 1 FROM device_sources WHERE mac=?').bind(mac).first();
  return {
    trial_used: trials.some(created) || !!events || !!(claim && ['created','delivered','used'].includes(claim.state)),
    already_customer: !!paid || !!source || lines.some(l=>l.kind==='paid' && l.status==='active'),
    in_progress: ambiguous || !!(claim && ['reserved','uncertain'].includes(claim.state)),
  };
}

// Le rapport de l'export relie cet ID au compte manzi10 par l'audit gold.key.set.
// On corrige l'ordre effectif sans modifier le compte, sa clé ni son usage payant.
const exportedKeyLabels = Object.freeze({gk_mvpkambcp22tk5:'manzi10'});
export async function trialKeyMetadata(db, at=Date.now()) {
  const rows = (await db.prepare(`SELECT id,reseller,trial_priority,trial_cap_per_day,enabled
    FROM gold_keys`).all()).results;
  const day = Math.floor(at/86_400_000)*86_400_000;
  const keys = [];
  for (const row of rows) {
    const usage = await db.prepare(`SELECT COUNT(*) AS n FROM gold_lines WHERE key_id=?
      AND kind IN ('trial','demo') AND created_at>=? AND status!='failed'`)
      .bind(row.id,day).first();
    const receipts = await db.prepare(`SELECT COUNT(*) AS n FROM gold_trial_receipts_v2
      WHERE key_id=? AND created_at>=? AND line_id NOT IN (SELECT id FROM gold_lines)`)
      .bind(row.id,day).first();
    keys.push({...row,label:row.reseller || exportedKeyLabels[row.id] || 'Compte non identifié',
      demo_tickets:null,trials_today:usage.n+receipts.n});
  }
  return orderDemoKeys(keys).map((k,i)=>({...k,effective_priority:i+1,contract_verified:false}));
}

function pageCursor(value) {
  if (!value) return null;
  const parts = value.split(':');
  if (parts.length!==2 || !/^\d{1,16}$/.test(parts[0]) || !/^[a-zA-Z0-9_-]{1,100}$/.test(parts[1])) throw new Error('Invalid cursor');
  return {at:Number(parts[0]),id:parts[1]};
}

export async function legacyHistory(request,env) {
  const url = new URL(request.url), mac=normalizeTrialMac(url.searchParams.get('mac'));
  if (!mac) return json({error:'bad_mac'},400);
  let before;
  try { before=pageCursor(url.searchParams.get('before')); } catch {return json({error:'invalid_cursor'},400);}
  const lines = (await env.DB.prepare(`SELECT id,id AS line_id,mac,kind,status,gold_user_id,sub,expire,ip,app_version,created_at,updated_at
    FROM gold_lines WHERE UPPER(mac)=? ORDER BY created_at DESC`).bind(mac).all()).results;
  const events = (await env.DB.prepare(`SELECT id,mac,event,gold_line_id AS line_id,gold_user_id,sub,expire,ip,app_version,actor,created_at
    FROM gold_history WHERE UPPER(mac)=? AND (created_at<? OR (created_at=? AND id<?))
    ORDER BY created_at DESC,id DESC LIMIT 101`).bind(mac,before?.at??Number.MAX_SAFE_INTEGER,before?.at??Number.MAX_SAFE_INTEGER,before?.id??'~').all()).results;
  const history=events.slice(0,100), last=history.at(-1);
  const device=await env.DB.prepare('SELECT android_id FROM devices WHERE mac=?').bind(mac).first();
  const eligibility=await historicalEligibility(env.DB,mac,device?.android_id || '');
  return json({mac,trial_used:eligibility.trial_used,lines,history,next_before:events.length>100?`${last.created_at}:${last.id}`:null});
}

// Une date sans fuseau n'est pas devinée. Elle exige une confirmation de
// l'expiration, pas la création d'un autre essai. Le délai n'est jamais remis
// à 24 h lors d'une reprise d'une ligne ancienne.
export function legacyExpiration(raw) {
  if (typeof raw==='number' || (typeof raw==='string' && /^\d+$/.test(raw))) {
    const n=Number(raw), ms=n<100_000_000_000?n*1000:n;
    return Number.isSafeInteger(ms) && ms>0?ms:null;
  }
  if (typeof raw!=='string' || !/T.*(?:Z|[+-]\d{2}:\d{2})$/i.test(raw)) return null;
  const parsed=Date.parse(raw);return Number.isFinite(parsed)?parsed:null;
}

async function recoverLegacyReceipt(env,request,mac) {
  const existing=await env.DB.prepare('SELECT expire FROM gold_trial_receipts_v2 WHERE mac=?').bind(mac).first();
  if (existing) return existing;
  if (!request.headers.get('X-Device-Secret')) return null;
  const line=await env.DB.prepare(`SELECT * FROM gold_lines WHERE UPPER(mac)=?
    AND kind IN ('trial','demo') AND status='active' ORDER BY created_at LIMIT 1`).bind(mac).first();
  if (!line) return null;
  const proof=await env.DB.prepare('SELECT android_id FROM device_secrets WHERE mac=?').bind(mac).first();
  if (!proof || await verifyProductionDevice(env.DB,request,{mac,android_id:proof.android_id})!=='ok' ||
      (line.android_id && line.android_id!==proof.android_id)) return null;
  const expire=legacyExpiration(line.expire);
  if (!expire || expire<=Date.now() || expire>line.created_at+86_460_000) return null;
  let url;try {url=new URL(line.url);}catch{return null;}
  const username=line.username || url.searchParams.get('username'),password=line.password || url.searchParams.get('password');
  if (!username || !password) return null;
  await env.DB.prepare(`INSERT INTO gold_trial_claims_v2
    (mac,android_id,request_id,state,created_at,expire,line_id,ip,app_version)
    VALUES (?,?,?,'created',?,?,?,?,?) ON CONFLICT(mac) DO NOTHING`)
    .bind(mac,proof.android_id,`legacy:${line.id}`,line.created_at,expire,line.id,line.ip||'',line.app_version||'legacy').run();
  const claim=await env.DB.prepare('SELECT line_id FROM gold_trial_claims_v2 WHERE mac=?').bind(mac).first();
  if (claim?.line_id!==line.id) return null;
  await saveTrialReceipt(env,mac,{line_id:line.id,key_id:line.key_id,expire,created_at:line.created_at,
    credentials:{server_url:url.origin,username,password}},
    {label:request.headers.get('X-App-Brand')==='zuno'?'Zuno TV Essai':'7 MOTION Essai'});
  return {expire};
}

export function createTrialRuntime({authenticate,sealSource,openSourceList,notifyBox}) {
  const deliver=createTrialDelivery({sealSource,openSourceList,notifyBox});
  return async function route(request,env,ctx) {
    const url=new URL(request.url), path=url.pathname;
    const trial=['/api/gold-trial','/api/v1/device/trial'].includes(path);
    const control=path==='/api/v1/gold/trial-control' || path==='/api/v1/gold/trial-control/history';
    const history=path==='/api/v1/gold/history' && url.searchParams.has('mac');
    const recovery=path==='/api/gold-trial/delivery';
    if (path==='/api/device-proof') return enrollProductionDevice(request,env);
    if (control || history) {
      const user=await authenticate(request,env,ctx,['super_admin','admin']);
      if (!user) return json({error:'forbidden',message:'Accès administrateur requis.'},request.headers.has('Authorization')?403:401);
      if (history) return request.method==='GET'?legacyHistory(request,env):json({error:'method_not_allowed'},405);
      // Une configuration seule ne peut lever le verrou de contrat inconnu.
      const guardedEnv={...env,GOLD_TRIAL_POLICY_READY:demoContract.verified?'true':'false'};
      const result=await goldTrialAdmin(request,guardedEnv,user);
      if (request.method==='GET' && path.endsWith('trial-control') && result.ok) {
        const data=await result.json();
        const previous=(await env.DB.prepare(`SELECT mac,status AS state,created_at,expire,id AS line_id,ip,app_version
          FROM gold_lines WHERE kind IN ('trial','demo') AND status IN ('active','expired','disabled','used')
          ORDER BY created_at DESC LIMIT 50`).all()).results;
        const combined=[...data.recent,...previous].sort((a,b)=>b.created_at-a.created_at);
        const seen=new Set(), recent=combined.filter(r=>!seen.has(r.mac) && seen.add(r.mac)).slice(0,50);
        return json({...data,recent,blockers:demoContract.verified?[]:[demoContract.message],keys:await trialKeyMetadata(env.DB)});
      }
      return result;
    }
    if (trial) {
      return createGoldTrialHandler({
        verifyDevice:(req,identity)=>verifyProductionDevice(env.DB,req,identity),
        eligibility:(mac,id)=>historicalEligibility(env.DB,mac,id),
        isReady:async()=>demoContract.verified && String(env.ADMIN_SECRET||'').length>=32,
        listDemoKeys:async()=>(await trialKeyMetadata(env.DB)).filter(k=>k.trial_cap_per_day==null || k.trials_today<k.trial_cap_per_day),
        legacyDailyUsage:async day=>(await env.DB.prepare(`SELECT COUNT(*) AS n FROM gold_lines
          WHERE kind IN ('trial','demo') AND status!='failed' AND created_at>=?
          AND mac NOT IN (SELECT mac FROM gold_trial_claims_v2 WHERE created_at>=? AND state!='failed')`).bind(day,day).first()).n,
        createDemo24h:createVerifiedDemo24h,
        persistReceipt:(mac,result,options)=>saveTrialReceipt(env,mac,result,options),
        deliverSource:mac=>deliver(env,ctx,mac),
      })(request,env);
    }
    if (recovery) {
      if (request.method!=='POST') return json({error:'method_not_allowed'},405);
      const body=await readSmallJson(request), mac=normalizeTrialMac(body?.mac);
      if (!mac || typeof body?.android_id!=='string' ||
          await verifyProductionDevice(env.DB,request,{mac,android_id:body.android_id})!=='ok') {
        return json({error:'device_mismatch',message:'Cet appareil ne peut pas être vérifié. Contactez notre assistance.'},403);
      }
      const receipt=await recoverLegacyReceipt(env,request,mac);
      if (!receipt) return json({error:'no_trial',message:'Aucun essai à reprendre sur cet appareil.'},404);
      return json({ok:true,delivered:await deliver(env,ctx,mac),expire:new Date(receipt.expire).toISOString(),
        message:'Votre demande de chargement a été prise en compte.'});
    }
    // Le polling existant relance aussi une livraison interrompue ; le bail
    // durable sérialise les tentatives, même entre plusieurs isolates.
    const source=/^\/(?:api\/(?:device-source|backup|self-source)|config)\/([^/]+)$/.exec(path);
    if (source && request.method!=='OPTIONS') {
      let mac; try {mac=normalizeTrialMac(decodeURIComponent(source[1]));} catch {return json({error:'bad_mac'},400);}
      if (!mac) return null;
      // Avant migration il n'existe aucun nouveau reçu : ne pas casser les
      // appareils historiques. Une vraie panne D1, elle, n'ouvre pas l'accès.
      const installed=await env.DB.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='gold_trial_receipts_v2'").first();
      if (!installed) return null;
      const receipt=await recoverLegacyReceipt(env,request,mac);
      if (!receipt) return null; // Compatibilité des appareils antérieurs.
      const proof=await env.DB.prepare('SELECT android_id,secret_hash FROM device_secrets WHERE mac=?').bind(mac).first();
      if (!proof || await verifyProductionDevice(env.DB,request,{mac,android_id:proof.android_id})!=='ok') return json({error:'device_secret_required'},403);
      if (path.startsWith('/api/device-source/') && request.method==='GET' && receipt.expire>Date.now()) await deliver(env,ctx,mac);
    }
    return null;
  };
}
