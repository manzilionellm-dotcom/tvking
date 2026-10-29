import { acceptableDeviceSecret, hashDeviceSecret, secretMatches } from './device_guard.js';
import { normalizeTrialMac, readSmallJson } from './gold_trial_policy.js';

const json = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
const denied = () => json({ error: 'device_mismatch', message: 'Cet appareil ne peut pas être vérifié. Contactez notre assistance.' }, 403);

// Deux migrations additives historiques ont donné deux noms différents aux
// horodatages. On lit uniquement le schéma et on conserve les colonnes et
// preuves présentes ; aucune DDL, rotation implicite ou remise à zéro.
const secretSchemas = new WeakMap();
async function secretTimestamps(db) {
  let pending = secretSchemas.get(db);
  if (!pending) {
    pending = (async () => {
      const result = await db.prepare('PRAGMA table_info(device_secrets)').all();
      const columns = new Set(result.results.map(row => row.name));
      if (!['mac', 'android_id', 'secret_hash'].every(name => columns.has(name)) ||
          !(columns.has('updated_at') || columns.has('enrolled_at'))) {
        throw new Error('device_secret_schema_unknown');
      }
      return {
        insert: ['updated_at', 'enrolled_at'].filter(name => columns.has(name)),
        rotate: ['updated_at', 'rotated_at'].filter(name => columns.has(name)),
      };
    })();
    secretSchemas.set(db, pending);
    // Un schéma incomplet ne reste pas mémorisé après une migration revue.
    pending.catch(() => { if (secretSchemas.get(db) === pending) secretSchemas.delete(db); });
  }
  return pending;
}

// Le premier enregistrement doit retrouver le même Android ID dans devices
// ET dans l'ancre durable. Cette liaison est ensuite indépendante du heartbeat.
// Ce n'est pas une attestation matérielle : un Android ID seul est déclaratif.
export async function knownTrialDevice(db, mac, androidId) {
  const row = await db.prepare(`SELECT d.android_id,d.block_status,d.superseded_by,
    a.android_id AS anchor_android_id FROM devices d
    LEFT JOIN trial_anchors a ON a.mac=d.mac WHERE d.mac=?`).bind(mac).first();
  if (!row) return 'unknown_device';
  if (row.superseded_by || ['banned','frozen'].includes(row.block_status) ||
      row.android_id !== androidId || row.anchor_android_id !== androidId) return 'device_mismatch';
  return 'ok';
}

export async function verifyProductionDevice(db, request, identity) {
  const known = await knownTrialDevice(db, identity.mac, identity.android_id);
  if (known !== 'ok') return known;
  const row = await db.prepare('SELECT android_id,secret_hash FROM device_secrets WHERE mac=?').bind(identity.mac).first();
  if (!row || row.android_id !== identity.android_id) return 'device_mismatch';
  return await secretMatches(request.headers.get('X-Device-Secret'), row.secret_hash) ? 'ok' : 'device_mismatch';
}

export async function enrollProductionDevice(request, env) {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const ip = request.headers.get('CF-Connecting-IP');
  if (!ip) return denied();
  const at = Date.now();
  const body = await readSmallJson(request);
  const mac = normalizeTrialMac(body?.mac), androidId = body?.androidId;
  const valid = mac && typeof androidId === 'string' && androidId.trim() && androidId.length<=128 && acceptableDeviceSecret(body?.secret);
  const existing = valid ? await env.DB.prepare('SELECT android_id,secret_hash FROM device_secrets WHERE mac=?').bind(mac).first() : null;
  // Le synchroniseur réannonce régulièrement la même preuve. Une répétition
  // valide ne doit pas épuiser le quota d'inscription des autres box du foyer.
  if (existing && existing.android_id===androidId && await secretMatches(body.secret,existing.secret_hash) &&
      await knownTrialDevice(env.DB,mac,androidId)==='ok') return json({ok:true,mac,enrolled:true});
  const rate = await env.DB.prepare(`INSERT INTO gold_device_proof_rate_v2(request_id,ip,at)
    SELECT ?,?,? WHERE (SELECT COUNT(*) FROM gold_device_proof_rate_v2 WHERE ip=? AND at>?)<5`)
    .bind(crypto.randomUUID(),ip,at,ip,at-60_000).run();
  if (!rate.meta.changes) return json({ error: 'rate_limited', message: 'Patientez une minute avant de réessayer.' }, 429);
  if (!valid) return denied();
  if (await knownTrialDevice(env.DB,mac,androidId) !== 'ok') return denied();
  const hash = await hashDeviceSecret(body.secret);
  // Pas de rotation sur la seule connaissance d'un Android ID. Une ancienne
  // preuve valide est nécessaire ; une réinstallation passe par l'assistance.
  if (existing && (existing.android_id !== androidId ||
      !(await secretMatches(body.secret,existing.secret_hash) ||
        await secretMatches(request.headers.get('X-Device-Secret'),existing.secret_hash)))) return denied();
  if (!existing) {
    const times = (await secretTimestamps(env.DB)).insert;
    await env.DB.prepare(`INSERT INTO device_secrets(mac,android_id,secret_hash,${times.join(',')})
      VALUES (?,?,?,${times.map(() => '?').join(',')}) ON CONFLICT(mac) DO NOTHING`)
      .bind(mac,androidId,hash,...times.map(() => at)).run();
  } else if (hash !== existing.secret_hash) {
    const times = (await secretTimestamps(env.DB)).rotate;
    await env.DB.prepare(`UPDATE device_secrets SET secret_hash=?${times.map(name => `,${name}=?`).join('')}
      WHERE mac=? AND secret_hash=?`).bind(hash,...times.map(() => at),mac,existing.secret_hash).run();
  }
  const saved = await env.DB.prepare('SELECT android_id,secret_hash FROM device_secrets WHERE mac=?').bind(mac).first();
  return saved?.android_id===androidId && await secretMatches(body.secret,saved.secret_hash)
    ? json({ ok: true, mac, enrolled: true }) : denied();
}
