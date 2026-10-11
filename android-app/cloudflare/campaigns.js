// Campagnes du propriétaire : préparation privée puis diffusion datée.
// L'identifiant d'annonce est attribué AU DÉBUT de la diffusion : réserver
// cet identifiant à la création ferait sauter le message aux apps à curseur.
const schemas = new WeakMap();

export async function ensureCampaigns(env) {
  if (!schemas.has(env.DB)) {
    const pending = migrate(env.DB);
    schemas.set(env.DB, pending);
    try { await pending; } catch (error) { schemas.delete(env.DB); throw error; }
  }
  await schemas.get(env.DB);
}

async function migrate(db) {
  await db.prepare(`CREATE TABLE IF NOT EXISTS app_broadcasts (
    id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT,
    url TEXT, created_at INTEGER)`).run();
  const definitions = ['kind TEXT', 'cta TEXT', 'country TEXT',
    'expires_at INTEGER', 'active INTEGER DEFAULT 1', 'campaign_id TEXT'];
  const columns = new Set((await db.prepare('PRAGMA table_info(app_broadcasts)').all()).results.map(c => c.name));
  for (const definition of definitions) {
    const name = definition.split(' ')[0];
    if (columns.has(name)) continue;
    try {
      await db.prepare(`ALTER TABLE app_broadcasts ADD COLUMN ${definition}`).run();
    } catch (error) {
      // Deux isolates peuvent migrer ensemble. Seul le doublon de colonne
      // confirmé en base est acceptable ; une panne D1 reste une erreur.
      if (!/duplicate column name/i.test(String(error))) throw error;
      const found = (await db.prepare('PRAGMA table_info(app_broadcasts)').all()).results;
      if (!found.some(c => c.name === name)) throw error;
    }
  }
  await db.prepare('CREATE UNIQUE INDEX IF NOT EXISTS broadcast_campaign ON app_broadcasts(campaign_id)').run();
  await db.prepare(`CREATE TABLE IF NOT EXISTS panel_campaigns (
    id TEXT PRIMARY KEY, type TEXT NOT NULL, title TEXT NOT NULL,
    body TEXT NOT NULL, url TEXT NOT NULL, cta TEXT NOT NULL, country TEXT NOT NULL,
    starts_at INTEGER NOT NULL, ends_at INTEGER NOT NULL, timezone TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft', version INTEGER NOT NULL DEFAULT 1,
    broadcast_id INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)`).run();
  await db.prepare('CREATE INDEX IF NOT EXISTS campaign_due ON panel_campaigns(status, starts_at, ends_at)').run();
}

class InvalidCampaign extends Error {}
const invalid = message => { throw new InvalidCampaign(message); };
const fields = ['type', 'title', 'body', 'url', 'cta', 'country', 'starts_at', 'ends_at', 'timezone'];

function validate(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) invalid('Formulaire invalide.');
  const clean = {};
  for (const [name, max] of [['title', 108], ['body', 500], ['url', 300], ['cta', 40], ['country', 2], ['timezone', 80]]) {
    if (typeof body[name] !== 'string' || body[name].trim().length > max) invalid(`Champ ${name} invalide.`);
    clean[name] = body[name].trim();
  }
  if (!clean.title || !clean.body) invalid('Le titre et le message sont obligatoires.');
  if (!['advertisement', 'event'].includes(body.type)) invalid('Choisis Publicité ou Événement.');
  clean.type = body.type;
  if (clean.country && !/^[A-Z]{2}$/.test(clean.country)) invalid('Pays invalide.');
  try { new Intl.DateTimeFormat('fr', { timeZone: clean.timezone }).format(); }
  catch { invalid('Fuseau horaire invalide.'); }
  if (!clean.timezone) invalid('Fuseau horaire obligatoire.');
  for (const key of ['starts_at', 'ends_at']) {
    if (!Number.isSafeInteger(body[key]) || body[key] <= 0 || body[key] > 8640000000000000) invalid('Dates invalides.');
    clean[key] = body[key];
  }
  if (clean.ends_at <= clean.starts_at) invalid('La fin doit être après le début.');
  if (clean.url) {
    let url;
    try { url = new URL(clean.url); } catch { invalid('Lien HTTPS invalide.'); }
    if (url.protocol !== 'https:' || url.username || url.password || url.hash ||
        [...url.searchParams.keys()].some(k => /password|passwd|username|token|secret|api.?key|authorization/i.test(k))) {
      invalid('Utilise un lien HTTPS public sans identifiants.');
    }
  }
  if (Boolean(clean.url) !== Boolean(clean.cta)) invalid('Le lien et le texte du bouton vont ensemble.');
  return clean;
}

function json(data, status = 200) {
  return Response.json(data, { status, headers: { 'Cache-Control': 'no-store' } });
}

// Audit atomique avec l'écriture ; aucun texte, lien ou secret dans le journal.
function audit(db, actor, id, action, now) {
  return db.prepare(`INSERT INTO audit_logs
    (id, actor_type, actor_id, action, target_type, target_id, after_json, created_at)
    SELECT ?, ?, ?, ?, 'campaign', id, json_object('status', status, 'version', version), ?
    FROM panel_campaigns WHERE id = ? AND changes() = 1`)
    .bind(crypto.randomUUID(), actor.type, actor.id, `campaign.${action}`, now, id);
}

export async function handleCampaigns(request, env, actor, parts) {
  await ensureCampaigns(env);
  if (request.method === 'GET' && parts.length === 1) {
    const rs = await env.DB.prepare(`SELECT c.*, b.active AS delivery_active
      FROM panel_campaigns c LEFT JOIN app_broadcasts b ON b.id = c.broadcast_id
      ORDER BY c.created_at DESC, c.id DESC LIMIT 100`).all();
    return json({ items: rs.results, now: Date.now() });
  }
  if (!['POST', 'PATCH'].includes(request.method) ||
      (request.method === 'POST' ? parts.length !== 1 : parts.length !== 2)) {
    return json({ error: 'not_found', message: 'Opération inconnue.' }, 404);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: 'bad_json', message: 'Formulaire invalide.' }, 400); }
  try {
    const id = request.method === 'POST' ? body?.id : parts[1];
    if (typeof id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) invalid('Identifiant de campagne invalide.');
    const now = Date.now();
    const read = env.DB.prepare('SELECT * FROM panel_campaigns WHERE id = ?').bind(id);
    if (request.method === 'POST') {
      const clean = validate(body);
      const result = await env.DB.batch([
        env.DB.prepare(`INSERT INTO panel_campaigns (id, ${fields.join(', ')}, created_at, updated_at)
          VALUES (${Array(12).fill('?').join(',')}) ON CONFLICT(id) DO NOTHING`)
          .bind(id, ...fields.map(k => clean[k]), now, now),
        audit(env.DB, actor, id, 'create', now), read,
      ]);
      const item = result[2].results[0];
      if (!fields.every(k => item[k] === clean[k])) return json({ error: 'conflict', message: 'Ce brouillon existe déjà avec un autre contenu. Recharge la liste.' }, 409);
      return json({ item }, result[0].meta.changes ? 201 : 200);
    }
    if (!body || !Number.isSafeInteger(body.version) || body.version < 1) invalid('Version de campagne obligatoire.');
    const before = await read.first();
    if (!before) return json({ error: 'not_found', message: 'Campagne introuvable.' }, 404);
    if (before.version !== body.version) return json({ error: 'conflict', message: 'Cette campagne a changé. Recharge la liste.' }, 409);
    let set, values;
    if (body.action === 'save') {
      if (before.broadcast_id || !['draft', 'paused'].includes(before.status)) {
        return json({ error: 'conflict', message: 'Mets le brouillon en pause ou duplique une campagne déjà diffusée.' }, 409);
      }
      const clean = validate(body);
      set = fields.map(k => `${k} = ?`).join(', ');
      values = fields.map(k => clean[k]);
    } else {
      const statuses = { schedule: 'scheduled', pause: 'paused', archive: 'archived' };
      const status = Object.hasOwn(statuses, body.action) ? statuses[body.action] : null;
      if (!status) invalid('Action inconnue.');
      if (before.status === 'archived') return json({ error: 'conflict', message: 'Une campagne archivée doit être dupliquée.' }, 409);
      if (status === 'scheduled' && before.ends_at <= now) invalid('Cette période est terminée. Crée un nouveau brouillon.');
      if (status === 'scheduled' && before.broadcast_id) {
        const exists = await env.DB.prepare('SELECT 1 FROM app_broadcasts WHERE id = ?').bind(before.broadcast_id).first();
        if (!exists) return json({ error: 'conflict', message: 'Cette annonce a été retirée. Il faut la dupliquer pour diffuser à nouveau.' }, 409);
      }
      set = 'status = ?';
      values = [status];
    }
    const result = await env.DB.batch([
      env.DB.prepare(`UPDATE panel_campaigns SET ${set}, version = version + 1, updated_at = ?
        WHERE id = ? AND version = ? AND
        (? != 'save' OR (broadcast_id IS NULL AND status IN ('draft', 'paused')))
        AND (? != 'schedule' OR broadcast_id IS NULL OR EXISTS
          (SELECT 1 FROM app_broadcasts WHERE id = panel_campaigns.broadcast_id))`)
        .bind(...values, now, id, body.version, body.action, body.action),
      audit(env.DB, actor, id, body.action, now),
      // Pause et reprise s'appliquent dans la même transaction. On ne
      // recrée jamais une annonce retirée par l'ancien écran Annonces.
      env.DB.prepare(`UPDATE app_broadcasts SET active =
        (SELECT CASE WHEN status = 'scheduled' THEN 1 ELSE 0 END FROM panel_campaigns WHERE id = ?)
        WHERE campaign_id = ?`).bind(id, id), read,
    ]);
    if (!result[0].meta.changes) return json({ error: 'conflict', message: 'Cette campagne a changé. Recharge la liste.' }, 409);
    return json({ item: result[3].results[0] });
  } catch (error) {
    if (!(error instanceof InvalidCampaign)) throw error;
    return json({ error: 'invalid_campaign', message: error.message }, 400);
  }
}

export async function dispatchDueCampaigns(env, now) {
  await ensureCampaigns(env);
  const due = await env.DB.prepare(`SELECT 1 FROM panel_campaigns
    WHERE status = 'scheduled' AND starts_at <= ? AND ends_at > ?
      AND broadcast_id IS NULL LIMIT 1`).bind(now, now).first();
  if (!due) return;
  // Lot D1 atomique : une panne ne laisse jamais une annonce sans son
  // marqueur. L'index unique protège aussi contre plusieurs lecteurs.
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO app_broadcasts
      (title, body, url, kind, cta, country, expires_at, created_at, active, campaign_id)
      SELECT CASE WHEN type = 'advertisement' THEN 'Publicité · ' ELSE 'Événement · ' END || title,
        body, url, CASE WHEN type = 'advertisement' THEN 'promo' ELSE 'info' END,
        cta, country, ends_at, ?, 1, id
      FROM panel_campaigns WHERE status = 'scheduled' AND starts_at <= ?
        AND ends_at > ? AND broadcast_id IS NULL
      ORDER BY starts_at, created_at, id ON CONFLICT(campaign_id) DO NOTHING`).bind(now, now, now),
    env.DB.prepare(`UPDATE panel_campaigns SET broadcast_id =
      (SELECT id FROM app_broadcasts WHERE campaign_id = panel_campaigns.id)
      WHERE broadcast_id IS NULL AND EXISTS
        (SELECT 1 FROM app_broadcasts WHERE campaign_id = panel_campaigns.id)`),
  ]);
}

export async function clearCampaignAnnouncements(env) {
  await ensureCampaigns(env);
  await env.DB.batch([
    env.DB.prepare(`UPDATE panel_campaigns SET status = 'paused', version = version + 1,
      updated_at = ? WHERE status = 'scheduled'`).bind(Date.now()),
    env.DB.prepare('DELETE FROM app_broadcasts'),
  ]);
}
