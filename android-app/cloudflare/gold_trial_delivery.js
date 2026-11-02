const bytes = value => new TextEncoder().encode(value);
const b64 = data => btoa(String.fromCharCode(...new Uint8Array(data))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
const un64 = data => Uint8Array.from(atob(data.replaceAll('-','+').replaceAll('_','/')+'='.repeat((4-data.length%4)%4)),c=>c.charCodeAt(0));

// La production exportée sait déjà déchiffrer enc1. Le repli est stable et
// séparé des clés du pool. Ne pas changer ce secret sans réencrypter les sources.
export function sourceEncryptionEnv(env) {
  if (env.SOURCE_ENCRYPTION_KEY || env.SECRETS_KEY) return env;
  if (String(env.ADMIN_SECRET || '').length < 32) return env;
  return { ...env, SOURCE_ENCRYPTION_KEY: `gold-source-v2:${env.ADMIN_SECRET}` };
}

async function receiptKey(env) {
  if (String(env.ADMIN_SECRET || '').length < 32) throw new Error('Receipt encryption unavailable');
  const raw = await crypto.subtle.digest('SHA-256',bytes(`gold-receipt-v2:${env.ADMIN_SECRET}`));
  return crypto.subtle.importKey('raw',raw,'AES-GCM',false,['encrypt','decrypt']);
}

export async function saveTrialReceipt(env, mac, result, { label }) {
  const creds = result.credentials;
  if (!creds || !['http:','https:'].includes(new URL(creds.server_url).protocol) ||
      !creds.username || !creds.password || !['7 MOTION Essai','Zuno TV Essai'].includes(label)) throw new Error('Invalid receipt');
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name:'AES-GCM',iv,additionalData:bytes(`${mac}:${result.line_id}`) },
    await receiptKey(env),bytes(JSON.stringify({ server_url:creds.server_url,username:creds.username,password:creds.password })));
  await env.DB.prepare(`INSERT INTO gold_trial_receipts_v2(mac,line_id,key_id,expire,credentials_enc,label,created_at)
    VALUES (?,?,?,?,?,?,?) ON CONFLICT(mac) DO NOTHING`)
    .bind(mac,String(result.line_id),result.key_id || null,result.expire,`${b64(iv)}.${b64(encrypted)}`,label,result.created_at ?? Date.now()).run();
  const saved = await env.DB.prepare('SELECT line_id FROM gold_trial_receipts_v2 WHERE mac=?').bind(mac).first();
  if (saved?.line_id !== String(result.line_id)) throw new Error('Receipt conflict');
}

export async function openTrialReceipt(env, row) {
  const [iv,ct] = row.credentials_enc.split('.');
  const raw = await crypto.subtle.decrypt({ name:'AES-GCM',iv:un64(iv),additionalData:bytes(`${row.mac}:${row.line_id}`) },
    await receiptKey(env),un64(ct));
  return JSON.parse(new TextDecoder().decode(raw));
}

// Les trois fonctions injectées viennent du bundle de production vérifié.
// Cette insertion ajoute UNE source sur un appareil vide. Un changement panel
// concurrent ou une suppression explicite gagne : aucune liste n'est écrasée.
export function createTrialDelivery({ sealSource, openSourceList, notifyBox }, { now=Date.now }={}) {
  return async function deliver(env, ctx, mac) {
    const at = now(), token = crypto.randomUUID();
    const row = await env.DB.prepare('SELECT * FROM gold_trial_receipts_v2 WHERE mac=?').bind(mac).first();
    if (!row || row.expire<=at) return false;
    const claim=await env.DB.prepare(`SELECT line_id FROM gold_trial_claims_v2
      WHERE mac=? AND state!='failed'`).bind(mac).first();
    if (!claim || (claim.line_id && claim.line_id!==row.line_id)) return false;
    // Ne jamais réinstaller une source que le client a supprimée après livraison.
    if (row.delivered_at) return true;
    const lease = await env.DB.prepare(`UPDATE gold_trial_receipts_v2 SET lease_until=?,lease_token=?,delivery_attempts=delivery_attempts+1
      WHERE mac=? AND delivered_at IS NULL AND lease_until<=?`)
      .bind(at+30_000,token,mac,at).run();
    if (!lease.meta.changes) return false;
    let delivered = false, finalized = false, notification = null;
    try {
      const creds = await openTrialReceipt(env,row);
      const source = { type:'xtream',label:row.label,...creds,origin:'panel' };
      const protectedEnv = sourceEncryptionEnv(env);
      const sealed = await sealSource(protectedEnv,source);
      // Refus avant stockage si la primitive du bundle n'a pas chiffré.
      if (sealed.password===source.password || !sealed.password?.startsWith('enc1.')) throw new Error('Source encryption unavailable');
      const encoded = JSON.stringify([sealed]);
      const out = await env.DB.batch([
        env.DB.prepare(`INSERT INTO device_sources
          (mac,type,label,server_url,username,password,m3u_url,epg_url,sources_json,origin,updated_at,version)
          SELECT ?,?,?,?,?,?,NULL,NULL,?,'panel',?,1 WHERE NOT EXISTS (
            SELECT 1 FROM device_source_clears WHERE mac=? AND cleared_at>=?)
          ON CONFLICT(mac) DO NOTHING`)
          .bind(mac,sealed.type,sealed.label,sealed.server_url,sealed.username,sealed.password,encoded,at,mac,row.created_at),
        env.DB.prepare(`INSERT INTO source_revisions
          (mac,rev,state,panel_json,item_count,hosts,trace_id,actor_type,actor_id,published_at,created_at)
          SELECT ?,COALESCE((SELECT MAX(rev) FROM source_revisions WHERE mac=?),0)+1,
            'published',?,1,'[]',?,'system','gold-trial',?,? WHERE changes()=1 RETURNING rev`)
          .bind(mac,mac,encoded,`trial:${row.line_id}`,at,at),
      ]);
      if (out[0].meta.changes===1) {
        // Une panne de notification n'annule pas la source : le polling existant
        // la lit immédiatement. Aucun nouvel achat ne répare cette notification.
        notification = { configRev:out[1].results?.[0]?.rev,traceId:`trial:${row.line_id}` };
        delivered = true;
      } else {
        const stored = await env.DB.prepare('SELECT * FROM device_sources WHERE mac=?').bind(mac).first();
        if (stored) {
          const list = stored.sources_json ? JSON.parse(stored.sources_json) : [stored];
          const opened = await openSourceList(protectedEnv,list);
          delivered = opened.some(s=>s.server_url===creds.server_url && s.username===creds.username && s.password===creds.password);
        }
      }
      if (delivered) await env.DB.batch([
        // Le lecteur a aussi son ancien essai d'application. Une démo valide
        // doit rester lisible si cette fenêtre est terminée. On prolonge
        // seulement l'ancre du demandeur jusqu'à la fin du reçu, jamais une
        // licence payante ni la date de début historique.
        env.DB.prepare(`UPDATE trial_anchors SET extended_until=MAX(COALESCE(extended_until,0),?)
          WHERE mac=? AND android_id=(SELECT android_id FROM gold_trial_claims_v2 WHERE mac=?)`)
          .bind(row.expire,mac,mac),
        env.DB.prepare(`UPDATE gold_trial_receipts_v2 SET delivered_at=?,lease_until=0,lease_token=NULL
          WHERE mac=? AND lease_token=?`).bind(at,mac,token),
        env.DB.prepare(`UPDATE gold_trial_claims_v2 SET state='delivered',line_id=?,expire=?
          WHERE mac=? AND (line_id IS NULL OR line_id=?) AND state IN ('reserved','uncertain','created','delivered')`)
          .bind(row.line_id,row.expire,mac,row.line_id),
        env.DB.prepare(`INSERT INTO gold_trial_events_v2(mac,event,created_at,expire,line_id,ip,app_version)
          SELECT mac,'delivery_recovered',?,expire,line_id,ip,app_version FROM gold_trial_claims_v2 WHERE mac=?`)
          .bind(at,mac),
      ]);
      finalized=delivered;
      if (notification) {
        // L'app n'attend pas le réseau du Durable Object : la source et son
        // droit d'accès sont déjà durables, lisibles par le polling immédiat.
        const pushed=Promise.resolve().then(()=>notifyBox(protectedEnv,mac,'source',notification)).catch(()=>{});
        if (ctx?.waitUntil) ctx.waitUntil(pushed); else await pushed;
      }
      return delivered;
    } finally {
      if (!finalized) await env.DB.prepare(`UPDATE gold_trial_receipts_v2 SET lease_until=?,lease_token=NULL
        WHERE mac=? AND lease_token=?`).bind(now()+3_000,mac,token).run();
    }
  };
}
