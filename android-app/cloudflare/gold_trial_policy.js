// Politique partagée 7 MOTION / Zuno. AUCUN appel fournisseur dans ce module.
// Le branchement réutilise les fonctions de gold.js : voir docs/gold-trial-24h.md.
// Ne pas remplacer le gold.js déployé par ce fichier.
import { secretMatches } from './device_guard.js';

const DAY = 86_400_000;
const messages = {
  activated: 'Votre essai gratuit de 24 h est activé.',
  trial_already_used: 'Vous avez déjà utilisé votre essai gratuit',
  already_customer: 'Votre appareil possède déjà un abonnement.',
  in_progress: 'Activation de votre essai…',
  trial_disabled: 'Les essais gratuits sont désactivés pour le moment.',
  unknown_device: 'Votre appareil doit terminer son inscription. Réessayez dans un instant.',
  device_mismatch: 'Cet appareil ne peut pas être vérifié. Contactez notre assistance.',
  daily_cap_reached: 'Le plafond des essais du jour est atteint. Réessayez demain.',
  rate_limited: 'Trop de demandes. Patientez une minute avant de réessayer.',
  unavailable: 'Aucun essai gratuit disponible pour le moment.',
  invalid_request: 'La demande est incomplète. Réessayez.',
  internal_error: 'Activation indisponible pour le moment. Réessayez plus tard.',
};

export function normalizeTrialMac(value) {
  if (typeof value !== 'string') return null;
  const mac = value.trim().replaceAll('-', ':').toUpperCase();
  return /^(?:MK|[0-9A-F]{2})(?::[0-9A-F]{2}){5}$/.test(mac) ? mac : null;
}

export function orderDemoKeys(keys) {
  const rank = key => ({ manzi10: 0, manzi8: 1 })[String(key.label).trim().toLowerCase()] ?? 2;
  return keys.filter(k => k.enabled !== false && k.demo_tickets !== 0)
    .slice().sort((a, b) => rank(a) - rank(b) ||
      (Number(a.trial_priority) || 0) - (Number(b.trial_priority) || 0));
}

// À utiliser UNIQUEMENT si le fournisseur confirme qu'aucune ligne n'a été
// créée (ticket épuisé, rejet explicite). Un timeout n'est pas cette erreur.
export class DemoUnavailable extends Error {}

// Réutilise les empreintes et l'enrôlement existants. L'offre n'inscrit ni
// ne réattribue une MAC : elle vérifie uniquement l'identité déjà enregistrée.
export async function verifyTrialDevice(db, request, identity) {
  const device = await db.prepare(`SELECT d.android_id,d.block_status,
    s.android_id AS enrolled_android_id,s.secret_hash FROM devices d
    LEFT JOIN device_secrets s ON s.mac=d.mac WHERE d.mac=?`).bind(identity.mac).first();
  if (!device) return 'unknown_device';
  if (['banned', 'frozen'].includes(device.block_status) ||
      !device.enrolled_android_id || device.enrolled_android_id !== identity.android_id ||
      (device.android_id && device.android_id !== identity.android_id)) return 'device_mismatch';
  return await secretMatches(request.headers.get('X-Device-Secret'), device.secret_hash)
    ? 'ok' : 'device_mismatch';
}

function reply(code, status, extra = {}) {
  return Response.json({ ...extra, ...(status < 400 ? { ok: true } : { error: code }), message: messages[code] }, {
    status, headers: { 'Cache-Control': 'no-store' },
  });
}

async function record(db, row, event, reason = null, result = {}) {
  await db.prepare(`INSERT INTO gold_trial_events_v2
    (mac,event,reason,created_at,expire,line_id,ip,app_version) VALUES (?,?,?,?,?,?,?,?)`)
    .bind(row.mac, event, reason, row.now, result.expire ?? null,
      result.line_id ?? null, row.ip, row.version).run();
}

export async function trialSettings(db) {
  const row = await db.prepare('SELECT * FROM gold_trial_settings_v2 WHERE id=1').first();
  if (!row) throw new Error('Trial migration missing');
  return { gold_trial_enabled: row.gold_trial_enabled === 1, daily_cap: row.daily_cap,
    updated_at: row.updated_at, revision: row.revision };
}

/**
 * Points d'intégration EXPLICITES, à relier au gold.js réel, jamais à inventer :
 * verifyDevice(request, identity) : 'ok' | 'unknown_device' | 'device_mismatch'
 *   exige android_id enregistré ET X-Device-Secret si enrôlé ; refuse les bannis.
 * eligibility(mac) : { trial_used, already_customer } depuis TOUT l'historique.
 * listDemoKeys() : métadonnées (sans exposer les clés chiffrées à ce module).
 * createDemo24h(key, {mac, requestId, demoOnly:true, durationHours:24}) :
 *   {isDemo:true, paidCreditsUsed:0, expire(ms), line_id} ; jamais de route payante.
 * deliverSource(mac, result) : canal source existant, idempotent, aucune URL UI.
 * L'absence d'un raccordement bloque la construction, pas de faux succès.
 */
export function createGoldTrialHandler(adapters, { now = Date.now, uuid = () => crypto.randomUUID() } = {}) {
  for (const name of ['eligibility', 'listDemoKeys', 'createDemo24h', 'deliverSource']) {
    if (typeof adapters?.[name] !== 'function') throw new Error(`Missing gold.js adapter: ${name}`);
  }
  return async function goldTrial(request, env) {
    const path = new URL(request.url).pathname;
    if (!['/api/gold-trial', '/api/v1/device/trial'].includes(path)) return null;
    if (request.method !== 'POST') return reply('invalid_request', 405);
    const db = env.DB;
    const row = { mac: null, now: now(), ip: request.headers.get('CF-Connecting-IP') || '', version: '' };
    const id = uuid();
    let reserved = false;
    let providerStarted = false;
    const reject = async (code, status) => {
      await record(db, row, 'refused', code);
      return reply(code, status);
    };
    try {
      // On compte également les corps invalides. Sans IP fiable, refus fermé.
      if (!row.ip) return reply('invalid_request', 400);
      const rate = await db.prepare(`INSERT INTO gold_trial_rate_v2(request_id,ip,at)
        SELECT ?,?,? WHERE (SELECT COUNT(*) FROM gold_trial_rate_v2 WHERE ip=? AND at>?) < 5`)
        .bind(id, row.ip, row.now, row.ip, row.now - 60_000).run();
      // Bornage avant décodage pour ne pas accepter un corps arbitrairement gros.
      const raw = await request.text();
      if (raw.length > 4096) return reject('invalid_request', 400);
      let body;
      try { body = JSON.parse(raw); } catch { return reject('invalid_request', 400); }
      row.mac = normalizeTrialMac(body?.mac);
      row.version = typeof body?.app_version === 'string' ? body.app_version.trim().slice(0, 100) : '';
      if (!rate.meta.changes) return reject('rate_limited', 429);
      if (!row.mac || !row.version || typeof body?.android_id !== 'string' ||
          !body.android_id.trim() || body.android_id.length > 128) return reject('invalid_request', 400);
      const identity = { mac: row.mac, android_id: body.android_id.trim(), app_version: row.version };
      const verified = adapters.verifyDevice
        ? await adapters.verifyDevice(request, identity)
        : await verifyTrialDevice(db, request, identity);
      if (verified !== 'ok') return reject(verified === 'unknown_device' ? verified : 'device_mismatch', 403);
      const settings = await trialSettings(db);
      if (!settings.gold_trial_enabled) return reject('trial_disabled', 403);
      // Obligatoire : conserve les essais effectués AVANT cette migration,
      // avec une autre clé ou une autre application. Une panne ne vaut pas « non ».
      const eligibility = await adapters.eligibility(row.mac);
      if (typeof eligibility?.trial_used !== 'boolean' || typeof eligibility?.already_customer !== 'boolean') {
        throw new Error('Unknown historical eligibility');
      }
      if (eligibility.trial_used) return reject('trial_already_used', 409);
      if (eligibility.already_customer) return reject('already_customer', 409);
      const day = Math.floor(row.now / DAY) * DAY; // plafond journalier UTC
      // Une seule instruction SQL arbitre doublon, interrupteur et plafond.
      // Aucun SELECT suivi d'un INSERT vulnérable aux appels simultanés.
      const claim = await db.prepare(`INSERT INTO gold_trial_claims_v2
        (mac,request_id,state,created_at,ip,app_version)
        SELECT ?,?,'reserved',?,?,? WHERE EXISTS (
          SELECT 1 FROM gold_trial_settings_v2 WHERE id=1 AND gold_trial_enabled=1
          AND (SELECT COUNT(*) FROM gold_trial_claims_v2 WHERE created_at>=? AND state!='failed') < daily_cap)
        ON CONFLICT(mac) DO UPDATE SET request_id=excluded.request_id,state='reserved',
          created_at=excluded.created_at,ip=excluded.ip,app_version=excluded.app_version
        WHERE gold_trial_claims_v2.state='failed'`)
        .bind(row.mac, id, row.now, row.ip, row.version, day).run();
      if (!claim.meta.changes) {
        const existing = await db.prepare('SELECT state FROM gold_trial_claims_v2 WHERE mac=?').bind(row.mac).first();
        if (existing && existing.state !== 'failed') {
          return reject(['reserved', 'uncertain'].includes(existing.state) ? 'in_progress' : 'trial_already_used', 409);
        }
        return reject((await trialSettings(db)).gold_trial_enabled ? 'daily_cap_reached' : 'trial_disabled',
          (await trialSettings(db)).gold_trial_enabled ? 429 : 403);
      }
      reserved = true;
      await record(db, row, 'requested');
      for (const key of orderDemoKeys(await adapters.listDemoKeys())) {
        let result;
        try {
          providerStarted = true;
          result = await adapters.createDemo24h(key, {
            mac: row.mac, requestId: id, demoOnly: true, durationHours: 24,
          });
        } catch (error) {
          if (!(error instanceof DemoUnavailable)) throw error;
          providerStarted = false;
          await record(db, row, 'key_skipped', 'demo_unavailable');
          continue;
        }
        // Ce contrôle détecte une erreur d'adaptateur, il ne remplace PAS la
        // vérification préalable de l'API démo. Une réponse ambiguë ne se retente pas.
        if (result?.isDemo !== true || result.paidCreditsUsed !== 0 ||
            !Number.isSafeInteger(result.expire) || !result.line_id ||
            result.expire <= row.now || result.expire > now() + DAY + 60_000) throw new Error('Invalid demo receipt');
        const receipt = { expire: result.expire, line_id: String(result.line_id) };
        await db.batch([
          db.prepare("UPDATE gold_trial_claims_v2 SET state='created',expire=?,line_id=? WHERE mac=? AND request_id=?")
            .bind(receipt.expire, receipt.line_id, row.mac, id),
          db.prepare(`INSERT INTO gold_trial_events_v2
            (mac,event,created_at,expire,line_id,ip,app_version) VALUES (?,'created',?,?,?,?,?)`)
            .bind(row.mac, row.now, receipt.expire, receipt.line_id, row.ip, row.version),
        ]);
        // La création est définitive même si la livraison échoue. On ne refait
        // jamais de POST fournisseur pour « réparer » une livraison de source.
        let delivered = false;
        try { delivered = await adapters.deliverSource(row.mac, result) === true; } catch { /* reprise par le canal existant */ }
        if (delivered) {
          await db.prepare("UPDATE gold_trial_claims_v2 SET state='delivered' WHERE mac=? AND request_id=?")
            .bind(row.mac, id).run();
        }
        await record(db, row, delivered ? 'delivered' : 'delivery_pending', null, receipt);
        return reply('activated', 201, { expire: new Date(receipt.expire).toISOString(), delivered });
      }
      await db.prepare("UPDATE gold_trial_claims_v2 SET state='failed' WHERE mac=? AND request_id=?").bind(row.mac, id).run();
      return reject('unavailable', 503);
    } catch {
      // Ne jamais exposer une exception (elle peut contenir une URL ou une clé).
      if (reserved) {
        try {
          await db.prepare("UPDATE gold_trial_claims_v2 SET state=? WHERE mac=? AND request_id=? AND state='reserved'")
            .bind(providerStarted ? 'uncertain' : 'failed', row.mac, id).run();
          await record(db, row, 'failed', providerStarted ? 'provider_uncertain' : 'internal_error');
        } catch { /* La réservation initiale reste fermée, même si D1 tombe. */ }
      }
      return reply(providerStarted ? 'in_progress' : 'internal_error', providerStarted ? 409 : 503);
    }
  };
}
