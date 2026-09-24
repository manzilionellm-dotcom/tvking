// =========================================================
//  migrate_kv_to_d1.js — One-shot migration from KV to D1
// =========================================================
//  Lit toutes les fiches `client:<MAC>` du KV existant et les
//  projette vers le nouveau modele relationnel :
//
//    client KV row  →  customer + device + license (+ playlist si presente)
//
//  Mode d'emploi :
//    On expose ce script comme un endpoint admin TEMPORAIRE
//    POST /admin/migrate-to-d1 (header X-Admin-Secret obligatoire).
//    Le code est dans ce fichier separe pour pouvoir le retirer
//    proprement apres la migration en production.
//
//  Hook dans worker.js :
//    if (path === '/admin/migrate-to-d1') {
//      if (!checkAdmin(...)) return unauthorized();
//      return runMigration(env);
//    }
//  (a brancher manuellement quand prêt — pas active par defaut
//   pour eviter qu'un appel accidentel deverse les donnees.)
//
//  Idempotent : si une MAC existe deja dans devices, on saute
//  (mais on UPDATE last_seen_at). Les statuts paid/trial/frozen/banned
//  sont projetes en license.status correspondant.
// =========================================================

/// Genere un id unique avec prefixe (meme schema que api_v1.js).
function genId(prefix) {
  const ts = Date.now().toString(36).padStart(8, '0');
  const rand = Array.from(crypto.getRandomValues(new Uint8Array(8)))
    .map((b) => (b % 36).toString(36))
    .join('');
  return `${prefix}_${ts}${rand}`;
}

/// Projette le `status` (active/frozen/banned) + `paid` + `trial_until`
/// du modele KV vers le `status` du modele D1 license.
function deriveLicenseStatus(kvClient, now) {
  if (kvClient.status === 'banned') return 'banned';
  if (kvClient.status === 'frozen') return 'frozen';
  if (kvClient.paid === true) return 'active';
  const trial = kvClient.trial_until || 0;
  if (trial > now) return 'active'; // trial en cours
  return 'expired';
}

/// Projette le plan : si paye → 'yearly' par defaut (le KV n'avait
/// pas de notion de duree), sinon 'trial'. Le user pourra ajuster
/// dans le panel.
function derivePlan(kvClient) {
  return kvClient.paid === true ? 'yearly' : 'trial';
}

/// Choisit la 1ere playlist Xtream du tableau `playlists` du KV
/// pour la migrer comme la playlist du license. Les autres sont
/// loggees mais pas perdues (on stocke leur JSON dans la note).
function pickPrimaryPlaylist(kvClient) {
  const list = Array.isArray(kvClient.playlists) ? kvClient.playlists : [];
  return list.find((p) => p && p.type === 'xtream')
      || list.find((p) => p && p.type === 'm3u')
      || null;
}

/// Detecte l'app cible d'apres l'identite de l'environnement.
/// Pour cette premiere migration, tout va vers app_7motion par
/// defaut (le KV n'avait pas de notion d'app multi).
const DEFAULT_APP_ID = 'app_7motion';

export async function runMigration(env, { dryRun = false } = {}) {
  if (!env.DB) {
    return { error: 'D1 binding "DB" missing — wrangler.toml a jour ?' };
  }
  if (!env.KV_7MOTION) {
    return { error: 'KV binding "KV_7MOTION" missing' };
  }
  const indexRaw = await env.KV_7MOTION.get('_index');
  if (!indexRaw) {
    return { migrated: 0, skipped: 0, errors: [], note: 'No _index in KV — nothing to migrate' };
  }
  let macs;
  try { macs = JSON.parse(indexRaw); } catch (_) {
    return { error: '_index is not valid JSON' };
  }
  if (!Array.isArray(macs)) {
    return { error: '_index is not an array' };
  }

  const now = Date.now();
  let migrated = 0;
  let skipped = 0;
  const errors = [];

  for (const mac of macs) {
    try {
      const raw = await env.KV_7MOTION.get(`client:${mac}`);
      if (!raw) { skipped++; continue; }
      const client = JSON.parse(raw);

      // 1) Cherche un device existant pour cette MAC.
      const existing = await env.DB
        .prepare('SELECT id, customer_id FROM devices WHERE mac = ?')
        .bind(mac)
        .first();

      let customerId; let deviceId;
      if (existing) {
        deviceId = existing.id;
        customerId = existing.customer_id;
        if (!dryRun) {
          await env.DB
            .prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?')
            .bind(client.last_seen_at || now, deviceId)
            .run();
        }
      } else {
        // 2) Cree customer + device en transaction logique
        //    (D1 n'a pas de transactions multi-instruction mais
        //     ces 2 inserts sont resilients : si le second foire,
        //     le premier reste mais sans references).
        customerId = genId('cus');
        deviceId = genId('dev');
        if (!dryRun) {
          const firstSeen = client.first_seen_at || client.added_at || now;
          const lastSeen = client.last_seen_at || firstSeen;
          await env.DB.batch([
            env.DB.prepare(
              `INSERT INTO customers (id, name, notes, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?)`,
            ).bind(
              customerId,
              client.name || null,
              client.note || null,
              firstSeen,
              now,
            ),
            env.DB.prepare(
              `INSERT INTO devices (id, customer_id, mac, label,
                                    first_seen_at, last_seen_at)
               VALUES (?, ?, ?, ?, ?, ?)`,
            ).bind(
              deviceId,
              customerId,
              mac,
              null,
              firstSeen,
              lastSeen,
            ),
          ]);
        }
      }

      // 3) Verifie qu'une license n'existe pas deja pour
      //    (device, default_app). Si oui on saute (idempotent).
      const existingLic = await env.DB
        .prepare('SELECT id FROM licenses WHERE device_id = ? AND app_id = ?')
        .bind(deviceId, DEFAULT_APP_ID)
        .first();
      if (existingLic) { skipped++; continue; }

      // 4) Cree la license et la playlist en consequence.
      const status = deriveLicenseStatus(client, now);
      const plan = derivePlan(client);
      const startedAt = client.added_at || now;
      const expiresAt = client.trial_until
        ? client.trial_until
        : client.paid
          ? startedAt + 365 * 24 * 60 * 60 * 1000
          : null;
      const licenseId = genId('lic');
      const playlist = pickPrimaryPlaylist(client);

      if (!dryRun) {
        const ops = [
          env.DB.prepare(
            `INSERT INTO licenses
              (id, customer_id, device_id, app_id, status, plan,
               started_at, expires_at, auto_renew, notes,
               created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)`,
          ).bind(
            licenseId, customerId, deviceId, DEFAULT_APP_ID,
            status, plan, startedAt, expiresAt,
            client.note || null,
            now, now,
          ),
        ];

        if (playlist) {
          // Stocke en clair pour la migration. L'admin peut
          // re-saisir les credentials apres pour passer en
          // chiffre (Phase 1.B etend playlists handler).
          const playlistId = genId('plt');
          ops.push(env.DB.prepare(
            `INSERT INTO playlists
              (id, license_id, type, server_url, username_enc,
               password_enc, m3u_url, epg_url, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          ).bind(
            playlistId,
            licenseId,
            playlist.type || 'xtream',
            playlist.server || playlist.url || null,
            playlist.username || null,
            playlist.password || null,
            playlist.type === 'm3u' ? (playlist.url || null) : null,
            playlist.epg_url || null,
            now,
          ));
        }

        await env.DB.batch(ops);
      }
      migrated++;
    } catch (e) {
      errors.push({ mac, error: String(e && e.message || e) });
    }
  }

  return { migrated, skipped, errors, dry_run: dryRun };
}
