// Le transfert historique rencontre une licence UNIQUE(device_id, app_id)
// quand les deux NOVATUBE sont déjà enrôlées. Ce pont traite seulement ce
// cas : identité et clé conservées, licence de destination vierge remplacée,
// listes et révisions déplacées dans la MÊME transaction D1.
import { readNovatubePanelActor } from './novatube4k-panel-admin.js';

const APP = 'app_novatube4k';
const MAC = /^MK(?::[0-9A-F]{2}){5}$/;
const ready = new WeakSet();

function reply(headers, body, status = 200) { return Response.json(body, { headers, status }); }
function failure(headers, error, message, status = 409) { return reply(headers, { error, message }, status); }
function virgin(license) {
  return license && license.app_id === APP && license.status === 'inactive'
    && license.plan === 'custom' && license.expires_at === 0;
}

async function schema(env, deps) {
  if (ready.has(env.DB)) return;
  if (typeof deps.ensureOrderTables !== 'function' || typeof deps.ensureSourcesVersion !== 'function'
    || typeof deps.notifyBox !== 'function') throw new Error('missing_transfer_dependencies');
  await env.DB.batch([
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS device_sources (
      mac TEXT PRIMARY KEY, type TEXT NOT NULL, label TEXT, server_url TEXT,
      username TEXT, password TEXT, m3u_url TEXT, epg_url TEXT, updated_at INTEGER NOT NULL
    )`),
    env.DB.prepare('CREATE TABLE IF NOT EXISTS device_source_clears (mac TEXT PRIMARY KEY, cleared_at INTEGER NOT NULL)'),
    env.DB.prepare('CREATE TABLE IF NOT EXISTS novatube4k_transfer_guard (id TEXT PRIMARY KEY, valid INTEGER NOT NULL CHECK (valid = 1))'),
  ]);
  await deps.ensureSourcesVersion(env);
  await deps.ensureOrderTables(env);
  try { await env.DB.prepare('ALTER TABLE audit_logs ADD COLUMN correlation_id TEXT').run(); }
  catch (error) {
    if (!/duplicate column name:\s*correlation_id\b/i.test(String(error?.message || ''))) throw error;
  }
  ready.add(env.DB);
}

function panelItems(row) {
  if (!row) return [];
  let list;
  if (row.sources_json) {
    list = JSON.parse(row.sources_json);
    if (!Array.isArray(list)) throw new Error('invalid_source_storage');
  }
  if (!list?.length) list = [{
    type: row.type, label: row.label, server_url: row.server_url, username: row.username,
    password: row.password, m3u_url: row.m3u_url, epg_url: row.epg_url, origin: row.origin,
  }];
  return list.filter((item) => item && typeof item === 'object' && item.origin !== 'self');
}

export async function handleNovatube4kTransfer(request, env, ctx, original, deps, body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  const oldMac = typeof body.old_mac === 'string' ? body.old_mac.trim().toUpperCase() : '';
  const newMac = typeof body.new_mac === 'string' ? body.new_mac.trim().toUpperCase() : '';
  if (!MAC.test(oldMac) || !MAC.test(newMac)) return null;
  let linked;
  try {
    linked = (await env.DB.prepare('SELECT mac, device_id FROM novatube4k_devices WHERE mac IN (?, ?)')
      .bind(oldMac, newMac).all()).results || [];
  } catch (error) {
    if (/no such table:\s*novatube4k_devices\b/i.test(String(error?.message || ''))) return null;
    throw error;
  }
  if (!linked.length) return null; // Les anciennes MAC restent sur le chemin original.
  const gate = await readNovatubePanelActor(request, env, ctx, original);
  if (gate.error) return gate.error;
  const { user, headers } = gate;
  if (!user || !['super_admin', 'reseller'].includes(user.role)
    || (user.role === 'reseller' && !user.permissions?.includes('activate'))) {
    return failure(headers, 'forbidden', 'Ton compte n’a pas le droit de transférer.', 403);
  }
  if (oldMac === newMac) return failure(headers, 'same_mac', 'Les deux MAC sont identiques.', 400);
  if (linked.length !== 2) return failure(headers, 'novatube4k_transfer_scope',
    'Les deux appareils doivent être des installations NOVATUBE enregistrées.');
  const rows = (await env.DB.prepare('SELECT id, mac, customer_id, reseller_id, block_status FROM devices WHERE mac IN (?, ?)')
    .bind(oldMac, newMac).all()).results || [];
  const oldDev = rows.find((row) => row.mac === oldMac);
  const newDev = rows.find((row) => row.mac === newMac);
  if (!oldDev || !newDev || linked.some((link) => rows.find((row) => row.mac === link.mac)?.id !== link.device_id)) {
    return failure(headers, 'device_identity_conflict', 'Identité d’appareil incohérente.');
  }
  if (user.role === 'reseller' && [oldDev, newDev].some((dev) => dev.reseller_id && dev.reseller_id !== user.sub)) {
    return failure(headers, 'forbidden', 'Un des appareils appartient à un autre revendeur.', 403);
  }
  const licenses = (await env.DB.prepare('SELECT * FROM licenses WHERE device_id IN (?, ?)')
    .bind(oldDev.id, newDev.id).all()).results || [];
  const oldLicenses = licenses.filter((row) => row.device_id === oldDev.id);
  const newLicenses = licenses.filter((row) => row.device_id === newDev.id);
  if (oldLicenses.length !== 1 || oldLicenses[0].app_id !== APP || virgin(oldLicenses[0])) {
    return failure(headers, 'novatube4k_source_license', 'La source doit posséder une seule licence NOVATUBE à transférer.');
  }
  if (newLicenses.length !== 1 || !virgin(newLicenses[0])) {
    return failure(headers, 'novatube4k_destination_paid', 'La destination possède déjà une licence ou une autre application.');
  }
  const oldLicense = oldLicenses[0];
  const newLicense = newLicenses[0];
  await schema(env, deps);
  const stored = (await env.DB.prepare('SELECT * FROM device_sources WHERE mac IN (?, ?)')
    .bind(oldMac, newMac).all()).results || [];
  const oldSource = stored.find((row) => row.mac === oldMac);
  const newSource = stored.find((row) => row.mac === newMac);
  const items = panelItems(oldSource); // valeurs déjà chiffrées, jamais ouvertes.
  const now = Date.now();
  const trace = /^[A-Za-z0-9_.:-]{8,64}$/.test(request.headers.get('X-Request-Id') || '')
    ? request.headers.get('X-Request-Id') : crypto.randomUUID();
  headers.set('X-Request-Id', trace);
  const actor = { type: user.role === 'reseller' ? 'reseller' : 'admin', id: user.sub };
  const guardId = crypto.randomUUID();
  const conditions = [];
  const values = [];
  for (const dev of [oldDev, newDev]) {
    conditions.push('EXISTS (SELECT 1 FROM devices WHERE id = ? AND mac = ? AND customer_id = ? AND reseller_id IS ? AND block_status IS ?)');
    values.push(dev.id, dev.mac, dev.customer_id, dev.reseller_id, dev.block_status);
  }
  for (const license of [oldLicense, newLicense]) {
    conditions.push('(SELECT COUNT(*) FROM licenses WHERE device_id = ?) = 1');
    values.push(license.device_id);
    conditions.push(`EXISTS (SELECT 1 FROM licenses WHERE id = ? AND device_id = ? AND app_id = ?
      AND status = ? AND plan = ? AND expires_at IS ? AND updated_at = ?)`);
    values.push(license.id, license.device_id, license.app_id, license.status,
      license.plan, license.expires_at, license.updated_at);
  }
  for (const [mac, source] of [[oldMac, oldSource], [newMac, newSource]]) {
    conditions.push(source ? 'EXISTS (SELECT 1 FROM device_sources WHERE mac = ? AND version = ?)' : 'NOT EXISTS (SELECT 1 FROM device_sources WHERE mac = ?)');
    values.push(mac);
    if (source) values.push(Number(source.version) || 0);
  }
  const statements = [
    // Le CHECK provoque un ROLLBACK de TOUT le lot si une activation,
    // attribution, liste ou propriété a changé depuis les lectures.
    env.DB.prepare('INSERT INTO novatube4k_transfer_guard (id, valid) SELECT ?, CASE WHEN '
      + conditions.join(' AND ') + ' THEN 1 ELSE 0 END').bind(guardId, ...values),
    env.DB.prepare('DELETE FROM licenses WHERE id = ?').bind(newLicense.id),
    env.DB.prepare('UPDATE devices SET customer_id = ?, reseller_id = COALESCE(reseller_id, ?), block_status = ? WHERE id = ?')
      .bind(oldDev.customer_id, oldDev.reseller_id, oldDev.block_status, newDev.id),
    env.DB.prepare('UPDATE licenses SET device_id = ?, customer_id = ?, updated_at = ? WHERE id = ?')
      .bind(newDev.id, oldDev.customer_id, now, oldLicense.id),
    env.DB.prepare('DELETE FROM device_sources WHERE mac = ?').bind(newMac),
    env.DB.prepare('UPDATE device_sources SET mac = ?, updated_at = ?, version = version + 1 WHERE mac = ?')
      .bind(newMac, now, oldMac),
    // Un tombstone interdit le repli sur une vieille liste KV, même quand
    // la source transférée n'avait aucune liste. Une ligne D1 prime sinon.
    env.DB.prepare(`INSERT INTO device_source_clears (mac, cleared_at) VALUES (?, ?), (?, ?)
      ON CONFLICT(mac) DO UPDATE SET cleared_at = excluded.cleared_at`).bind(oldMac, now, newMac, now),
    // Une ancienne réponse de liste ne peut être confirmée après transfert.
    env.DB.prepare('UPDATE novatube4k_devices SET last_served_rev = NULL WHERE mac IN (?, ?)').bind(oldMac, newMac),
  ];
  const revisionIndexes = [];
  for (const [mac, panel] of [[oldMac, []], [newMac, items]]) {
    revisionIndexes.push(statements.length);
    statements.push(env.DB.prepare(`INSERT INTO source_revisions
      (mac, rev, state, panel_json, item_count, hosts, trace_id, actor_type, actor_id,
       validated_at, published_at, created_at)
      SELECT ?, COALESCE((SELECT MAX(rev) FROM source_revisions WHERE mac = ?), 0) + 1,
        'published', ?, ?, '[]', ?, ?, ?, ?, ?, ? RETURNING rev`)
      .bind(mac, mac, JSON.stringify(panel), panel.length, trace, actor.type, actor.id, now, now, now));
  }
  statements.push(env.DB.prepare(`INSERT INTO audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, before_json, after_json,
     ip, user_agent, created_at, correlation_id) VALUES (?, ?, ?, 'device.transfer', 'device', ?, ?, ?, ?, ?, ?, ?)`)
    .bind('aud_' + crypto.randomUUID(), actor.type, actor.id, oldDev.id,
      JSON.stringify({ old_mac: oldMac }), JSON.stringify({ new_mac: newMac, moved_licenses: 1, app_id: APP }),
      request.headers.get('CF-Connecting-IP'), request.headers.get('User-Agent'), now, trace));
  statements.push(env.DB.prepare('DELETE FROM novatube4k_transfer_guard WHERE id = ?').bind(guardId));
  let results;
  try { results = await env.DB.batch(statements); }
  catch (error) {
    if (/CHECK constraint failed/i.test(String(error?.message || ''))) {
      return failure(headers, 'transfer_conflict', 'Les données ont changé. Relis les fiches avant de réessayer.');
    }
    // Toute erreur de licence, liste, révision ou audit est avant COMMIT.
    return failure(headers, 'transfer_unavailable', 'Le transfert n’a pas été enregistré. Réessaie.', 503);
  }
  const revisions = revisionIndexes.map((index) => results[index]?.results?.[0]?.rev || null);
  const notices = await Promise.allSettled([oldMac, newMac].map((mac, index) =>
    deps.notifyBox(env, mac, 'transfer', { traceId: trace, configRev: revisions[index], t1: now, t2: now })));
  return reply(headers, { ok: true, old_mac: oldMac, new_mac: newMac, moved_licenses: 1,
    notifications_ok: notices.every((notice) => notice.status === 'fulfilled' && !!notice.value) });
}
