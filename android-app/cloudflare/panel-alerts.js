// Boîte de réception privée du propriétaire. Ce module ne dépend ni du
// routeur historique ni du transport Web Push ; le dispatcher peut le lire.
// Les tables d'annonces destinées aux clients restent indépendantes.
const NOW_SQL = "CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER)";
const MAC = /^(?:MK(?::[0-9A-F]{2}){5}|(?:[0-9A-F]{2}:){5}[0-9A-F]{2})$/;
const TYPES = new Set(['new_device', 'activation', 'problem']);
const ready = new WeakMap();

export function panelAlertSchemaStatements() {
  return [
    `CREATE TABLE IF NOT EXISTS panel_alert_events (
      seq INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT NOT NULL UNIQUE,
      dedupe_key TEXT NOT NULL UNIQUE, type TEXT NOT NULL, mac TEXT NOT NULL,
      app_id TEXT, created_at INTEGER NOT NULL, title TEXT NOT NULL,
      message TEXT NOT NULL, url TEXT NOT NULL, source_kind TEXT NOT NULL,
      source_id TEXT NOT NULL
    )`,
    `CREATE TABLE IF NOT EXISTS panel_alert_preferences (
      actor_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0,
      new_device INTEGER NOT NULL DEFAULT 1, activation INTEGER NOT NULL DEFAULT 1,
      problem INTEGER NOT NULL DEFAULT 1, enabled_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0
    )`,
    `CREATE TABLE IF NOT EXISTS panel_alert_reads (
      actor_id TEXT NOT NULL, event_id TEXT NOT NULL, read_at INTEGER NOT NULL,
      PRIMARY KEY(actor_id, event_id),
      FOREIGN KEY(event_id) REFERENCES panel_alert_events(event_id) ON DELETE CASCADE
    )`,
    `CREATE TABLE IF NOT EXISTS panel_push_subscriptions (
      id TEXT PRIMARY KEY, actor_id TEXT NOT NULL, session_id TEXT NOT NULL,
      endpoint_hash TEXT NOT NULL UNIQUE, endpoint TEXT NOT NULL,
      p256dh TEXT NOT NULL, auth TEXT NOT NULL, label TEXT NOT NULL DEFAULT '',
      enabled INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL,
      consented_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, expires_at INTEGER,
      last_success_at INTEGER, revoked_at INTEGER, revoked_reason TEXT
    )`,
    `CREATE TABLE IF NOT EXISTS panel_push_deliveries (
      event_id TEXT NOT NULL, subscription_id TEXT NOT NULL,
      state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at INTEGER NOT NULL DEFAULT 0, lease_token TEXT, lease_until INTEGER,
      last_status INTEGER, last_error TEXT, sent_at INTEGER,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      PRIMARY KEY(event_id, subscription_id),
      FOREIGN KEY(event_id) REFERENCES panel_alert_events(event_id) ON DELETE CASCADE,
      FOREIGN KEY(subscription_id) REFERENCES panel_push_subscriptions(id) ON DELETE CASCADE
    )`,
    `CREATE TABLE IF NOT EXISTS panel_alert_meta (
      id INTEGER PRIMARY KEY CHECK(id = 1), installed_at INTEGER NOT NULL
    )`,
    `INSERT OR IGNORE INTO panel_alert_meta(id, installed_at) VALUES(1, ${NOW_SQL})`,
    'CREATE INDEX IF NOT EXISTS idx_panel_alert_events_time ON panel_alert_events(created_at, seq)',
    'CREATE INDEX IF NOT EXISTS idx_panel_push_actor ON panel_push_subscriptions(actor_id, enabled)',
    'CREATE INDEX IF NOT EXISTS idx_panel_push_due ON panel_push_deliveries(state, next_attempt_at, lease_until)',
  ];
}

function validMacSql(value) {
  // D1 borne la complexité de GLOB : ne pas construire le motif complet
  // d'une MAC. Longueur/séparateurs sont exacts, le motif hex reste court.
  return `(length(${value})=17 AND ${[3,6,9,12,15].map((at) => `substr(${value},${at},1)=':'`).join(' AND ')}
    AND CASE WHEN substr(upper(${value}),1,2)='MK'
      THEN length(replace(substr(upper(${value}),4),':',''))=10
        AND replace(substr(upper(${value}),4),':','') NOT GLOB '*[^0-9A-F]*'
      ELSE length(replace(upper(${value}),':',''))=12
        AND replace(upper(${value}),':','') NOT GLOB '*[^0-9A-F]*' END)`;
}
const COLUMNS = '(event_id,dedupe_key,type,mac,app_id,created_at,title,message,url,source_kind,source_id)';
const ID_SQL = "'pae_' || lower(hex(randomblob(16)))";
const insert = (select) => `INSERT INTO panel_alert_events ${COLUMNS} ${select} ON CONFLICT(dedupe_key) DO NOTHING;`;

/** Déclencheurs AFTER : l'outbox partage le commit/rollback de la donnée.
 * Aucun trigger sur box_orders : D1 meta.changes peut compter les écritures
 * indirectes, alors que recordAck historique exige exactement une ligne.
 */
export function panelAlertTriggerStatements(existingTables) {
  const tables = new Set(existingTables);
  const statements = [];
  if (tables.has('devices')) {
    statements.push(`CREATE TRIGGER IF NOT EXISTS panel_alert_device_v1 AFTER INSERT ON devices
      WHEN ${validMacSql('NEW.mac')} BEGIN
      ${insert(`SELECT ${ID_SQL}, 'device:' || NEW.id, 'new_device', upper(NEW.mac), NULL, ${NOW_SQL},
        'Nouvelle box enregistrée', 'La box ' || upper(NEW.mac) || ' a été enregistrée dans Atlas.',
        '/devices?mac=' || upper(NEW.mac), 'devices', NEW.id WHERE 1`)} END`);
  }
  if (tables.has('licenses') && tables.has('devices')) {
    const emit = (kind, title, message) => insert(`SELECT ${ID_SQL},
      'license:' || NEW.id || ':' || NEW.updated_at || ':' || coalesce(NEW.expires_at, 'life') || ':${kind}',
      'activation', upper(d.mac), NEW.app_id, ${NOW_SQL}, '${title}',
      '${message}' || upper(d.mac) || '.', '/devices?mac=' || upper(d.mac), 'licenses', NEW.id
      FROM devices d WHERE d.id = NEW.device_id AND ${validMacSql('d.mac')}`);
    statements.push(`CREATE TRIGGER IF NOT EXISTS panel_alert_license_insert_v1 AFTER INSERT ON licenses
      WHEN NEW.status = 'active' BEGIN
      ${emit('create', 'Licence activée', 'Une licence a été activée pour la box ')} END`);
    statements.push(`CREATE TRIGGER IF NOT EXISTS panel_alert_license_active_v1 AFTER UPDATE ON licenses
      WHEN NEW.status = 'active' AND OLD.status <> 'active' BEGIN
      ${emit('active', 'Licence activée', 'La licence a été activée pour la box ')} END`);
    statements.push(`CREATE TRIGGER IF NOT EXISTS panel_alert_license_extend_v1 AFTER UPDATE ON licenses
      WHEN NEW.status = 'active' AND OLD.status = 'active' AND (
        (OLD.expires_at IS NOT NULL AND NEW.expires_at IS NULL)
        OR (NEW.expires_at IS NOT NULL AND OLD.expires_at IS NOT NULL AND NEW.expires_at > OLD.expires_at)
      ) BEGIN ${emit('extended', 'Licence prolongée', 'La durée de licence a été prolongée pour la box ')} END`);
  }
  if (tables.has('novatube4k_recovery_requests')) {
    const emit = insert(`SELECT ${ID_SQL},
      'recovery:' || upper(NEW.mac) || ':' || CAST(NEW.created_at / 600000 AS INTEGER),
      'problem', upper(NEW.mac), 'app_novatube4k', NEW.created_at,
      'Vérification d’identité demandée', 'Une nouvelle installation demande une vérification pour la box ' || upper(NEW.mac) || '.',
      '/devices?mac=' || upper(NEW.mac), 'recovery', NEW.request_id WHERE 1`);
    statements.push(`CREATE TRIGGER IF NOT EXISTS panel_alert_recovery_insert_v1 AFTER INSERT ON novatube4k_recovery_requests
      WHEN NEW.state = 'pending' AND NEW.expires_at > ${NOW_SQL} AND ${validMacSql('NEW.mac')}
      BEGIN ${emit} END`);
    statements.push(`CREATE TRIGGER IF NOT EXISTS panel_alert_recovery_update_v1 AFTER UPDATE ON novatube4k_recovery_requests
      WHEN NEW.request_id <> OLD.request_id AND NEW.state = 'pending'
        AND NEW.expires_at > ${NOW_SQL} AND ${validMacSql('NEW.mac')}
      BEGIN ${emit} END`);
  }
  if (tables.has('box_orders')) {
    statements.push("CREATE INDEX IF NOT EXISTS idx_panel_alert_failed_orders ON box_orders(failed_srv,order_id) WHERE state='failed'");
  }
  return statements;
}

export async function ensurePanelAlertsSchema(env) {
  if (!env?.DB) throw new Error('panel_alerts_storage_unavailable');
  const cached = ready.get(env.DB), now = Date.now();
  if (cached && (cached.complete || now - cached.at < 30_000)) return;
  await env.DB.batch(panelAlertSchemaStatements().map((sql) => env.DB.prepare(sql)));
  const found = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type='table'").all();
  const tables = new Set((found.results || []).map((row) => row.name));
  const statements = panelAlertTriggerStatements(tables);
  if (statements.length) await env.DB.batch(statements.map((sql) => env.DB.prepare(sql)));
  // Une table recovery peut apparaître après l'activation de cette fonction.
  // Les demandes encore valides récentes sont alors reprises, sans code/hash.
  if (tables.has('novatube4k_recovery_requests')) {
    await env.DB.prepare(`INSERT INTO panel_alert_events ${COLUMNS}
      SELECT ${ID_SQL}, 'recovery:' || upper(r.mac) || ':' || CAST(r.created_at / 600000 AS INTEGER),
        'problem', upper(r.mac), 'app_novatube4k', r.created_at, 'Vérification d’identité demandée',
        'Une nouvelle installation demande une vérification pour la box ' || upper(r.mac) || '.',
        '/devices?mac=' || upper(r.mac), 'recovery', r.request_id
      FROM novatube4k_recovery_requests r WHERE r.state = 'pending' AND r.expires_at > ?
        AND r.created_at >= MAX(?, (SELECT installed_at FROM panel_alert_meta WHERE id=1))
        AND ${validMacSql('r.mac')} ORDER BY r.created_at LIMIT 100
      ON CONFLICT(dedupe_key) DO NOTHING`).bind(now, now - 600_000).run();
  }
  ready.set(env.DB, { at: now, complete: ['devices','licenses','box_orders','novatube4k_recovery_requests'].every((name) => tables.has(name)) });
}

export function panelAlertPayload(row) {
  if (!row || !/^[A-Za-z0-9_.:-]{8,128}$/.test(row.event_id || '') || !TYPES.has(row.type)
    || typeof row.title !== 'string' || !row.title.length || row.title.length > 96
    || typeof row.message !== 'string' || row.message.length > 240
    || /[\u0000-\u001f\u007f]/.test(row.title + row.message)
    || /https?:\/\/|\b[a-f0-9]{64}\b/i.test(row.title + row.message)
    || typeof row.url !== 'string' || row.url.length > 160) return null;
  try {
    const url = new URL(row.url, 'https://panel.invalid');
    const mac = url.searchParams.get('mac');
    if (url.origin !== 'https://panel.invalid' || !['/devices', '/blackbox'].includes(url.pathname)
      || url.hash || !MAC.test(mac || '') || Array.from(url.searchParams.keys()).length !== 1
      || !row.url.startsWith('/') || row.url.startsWith('//')) return null;
  } catch { return null; }
  return { v: 1, event_id: row.event_id, type: row.type, title: row.title, message: row.message, url: row.url };
}

/** Scan borné des échecs réellement persistés. L'anti-jointure + clé unique
 * remplace un curseur temporel fragile : un commit retardé au même timestamp
 * ne sera pas perdu. Aucun incident antérieur au bootstrap, ni absence de poll.
 */
export async function collectConfirmedOrderFailures(env, now = Date.now()) {
  await ensurePanelAlertsSchema(env);
  const table = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='box_orders'").first();
  if (!table) return { scanned: 0, inserted: 0, more: false };
  const rows = await env.DB.prepare(`SELECT o.order_id, o.mac, o.failed_srv
    FROM box_orders o WHERE o.state = 'failed' AND o.failed_srv IS NOT NULL
      AND o.failed_srv >= MAX(?, (SELECT installed_at FROM panel_alert_meta WHERE id=1))
      AND o.failed_srv <= ? AND ${validMacSql('o.mac')}
      AND NOT EXISTS (SELECT 1 FROM panel_alert_events e WHERE e.dedupe_key = 'order-failed:' || o.order_id)
    ORDER BY o.failed_srv, o.order_id LIMIT 200`).bind(now - 86_400_000, now).all();
  const list = rows.results || [];
  if (!list.length) return { scanned: 0, inserted: 0, more: false };
  const results = await env.DB.batch(list.map((row) => env.DB.prepare(`INSERT INTO panel_alert_events ${COLUMNS}
    VALUES (?, ?, 'problem', ?, NULL, ?, 'Commande en échec', ?, ?, 'box_orders', ?)
    ON CONFLICT(dedupe_key) DO NOTHING`).bind('pae_' + crypto.randomUUID().replaceAll('-', ''),
    'order-failed:' + row.order_id, row.mac.toUpperCase(), row.failed_srv,
    'Une commande de la box ' + row.mac.toUpperCase() + ' est marquée en échec.',
    '/blackbox?mac=' + row.mac.toUpperCase(), row.order_id)));
  return { scanned: list.length, inserted: results.reduce((n, r) => n + Number(r.meta?.changes || 0), 0), more: list.length === 200 };
}

export function panelAlertMac(value) {
  return typeof value === 'string' && MAC.test(value.toUpperCase()) ? value.toUpperCase() : null;
}
