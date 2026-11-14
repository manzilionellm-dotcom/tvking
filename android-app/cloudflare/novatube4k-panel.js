// Pont du panel Atlas pour les installations NOVATUBE déjà authentifiées.
// Ce module ne crée ni appareil, ni licence, ni essai, ni source payante.
// La clé est vérifiée par novatube4k.js AVANT tout appel à ces fonctions.
// Les handlers historiques restent la référence des formats et du stockage.

export const PANEL_BODY_LIMITS = Object.freeze({
  panel: 16 * 1024,
  blackbox: 256 * 1024,
  'orders-ack': 24 * 1024,
  wait: 4096,
  'rt-ticket': 4096,
  history: 4096,
  backup: 512 * 1024,
  feedback: 12 * 1024,
});

const DOWNLOAD_URL = 'https://novatube4k-apk.vercel.app/';
const encoder = new TextEncoder();
const ready = new WeakSet();
const qualityReady = new WeakSet();
// Seules des valeurs JSON terminées sont mémorisées, jamais un Request,
// une Promise ou un binding appartenant à une autre requête Workers.
const configCache = new WeakMap();
const ORDER_ID = /^ord_[A-Za-z0-9-]{8,64}$/;
const SOURCE_KINDS = new Set(['source', 'source_clear']);
const GLOBAL_KINDS = Object.freeze({
  announcements: 'message', theme: 'theme', 'home-layout': 'home',
  featured: 'featured', ad: 'ad', pricing: 'pricing',
  'feedback-prompt': 'feedback', servers: 'servers',
  'force-update': 'force_update', 'app-version': 'force_update',
  'grant-trial-all': 'license',
});

function json(body, status = 200) {
  return Response.json(body, { status, headers: {
    'Cache-Control': 'no-store, private', 'X-Content-Type-Options': 'nosniff',
  } });
}
function fail(error, status = 400) { return json({ ok: false, error }, status); }
function plain(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
function integer(value, min, max, fallback = 0) {
  return Number.isSafeInteger(value) && value >= min && value <= max ? value : fallback;
}
function text(value, max = 120) {
  return typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, ' ').slice(0, max) : '';
}

// Le filtre historique masque déjà URLs et identifiants. Ce filet propre à
// NOVATUBE masque en plus les noms de clé d'installation et ses 64 caractères.
// L'app applique aussi son filtre avant l'envoi ; aucun journal brut n'est lu.
export function sanitizeNovatubeDiagnostic(value, rawMac = '') {
  let out = typeof value === 'string' ? value : '';
  out = out.replace(/\b(?:https?|rtsps?|rtmps?|udp|rtp|mms|mmsh):\/\/[^\s<>"'()]+/gi, '[lien]');
  out = out.replace(/\b(?:X-Device-Key|device[_-]?key|authorization|raw[_-]?mac)\b\s*["']?\s*[:=]\s*["']?[^\s,;"'}]+/gi, '[secret masqué]');
  out = out.replace(/\b[a-f0-9]{64}\b/gi, '[empreinte masquée]');
  out = out.replace(/\b(?:password|passwd|pwd|username|user|login|token|auth|pass)\b\s*[:=]\s*[^\s&,;]+/gi, '[identifiant masqué]');
  if (/^[A-F0-9]{12}$/.test(rawMac)) {
    out = out.replaceAll(rawMac, '[identité appareil]').replaceAll(rawMac.toLowerCase(), '[identité appareil]');
    const colon = rawMac.match(/../g).join(':');
    out = out.replaceAll(colon, '[identité appareil]').replaceAll(colon.toLowerCase(), '[identité appareil]');
  }
  return out;
}

function safeText(value, max, binding) {
  return text(sanitizeNovatubeDiagnostic(value, binding.raw_mac), max);
}

function safeOrigin(value) {
  try {
    const url = new URL(String(value || ''));
    return ['http:', 'https:'].includes(url.protocol) ? url.origin.slice(0, 200) : '';
  } catch { return ''; }
}

async function ensurePanelTables(env) {
  if (ready.has(env.DB)) return;
  await env.DB.batch([
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_order_delivery (
      mac TEXT NOT NULL, order_id TEXT NOT NULL, served_at INTEGER NOT NULL,
      PRIMARY KEY (mac, order_id)
    )`),
    env.DB.prepare(`CREATE TABLE IF NOT EXISTS novatube4k_panel_version (
      id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL
    )`),
    env.DB.prepare('INSERT OR IGNORE INTO novatube4k_panel_version (id, version) VALUES (1, 0)'),
  ]);
  ready.add(env.DB);
}

export async function readNovatubePanelSignals(env, binding, deps) {
  const body = {};
  const reads = [
    ['reset_at', deps.resetAtFor],
    ['blackbox_pull', deps.blackboxRequestedAt],
  ];
  const results = await Promise.allSettled(reads.map(async ([key, helper]) => {
    if (typeof helper !== 'function') throw new Error('missing_signal_helper');
    return [key, integer(await helper(env, binding.mac), 0, Number.MAX_SAFE_INTEGER)];
  }));
  body.signal_errors = [];
  results.forEach((result, index) => {
    if (result.status === 'fulfilled') body[result.value[0]] = result.value[1];
    else body.signal_errors.push(reads[index][0]);
  });
  return body;
}

async function telemetry(env, binding, input, request, deps, now) {
  if (![deps.recordPresence, deps.ensureScaleSchema, deps.updateDeviceInfo].every((fn) => typeof fn === 'function')) {
    return false;
  }
  // Jamais le heartbeat public : il pourrait créer un essai, toucher une
  // ancre trial ou prendre la licence d'une autre application.
  await deps.ensureScaleSchema(env);
  const info = {};
  for (const [key, max] of [['model', 80], ['build', 120], ['android', 20], ['appVersion', 24]]) {
    info[key] = safeText(input[key], max, binding);
  }
  info.platform = input.platform === 'mobile' ? 'mobile' : 'tv';
  info.appBuild = integer(input.appBuild, 1_577_836_800, Math.floor(now / 1000) + 86_400);
  if (Array.isArray(input.sources)) {
    info.sources = input.sources.slice(0, 5).filter(plain).map((source) => ({
      type: source.type === 'm3u' ? 'm3u' : 'xtream',
      name: safeText(source.name, 60, binding),
      server: safeOrigin(source.server),
      // L'inventaire n'a besoin ni du compte fournisseur, ni de sa query.
      username: '',
      channels: integer(source.channels, 0, 10_000_000, null),
      active: source.active === true,
    }));
  }
  if (Array.isArray(input.recent)) {
    info.recent = input.recent.slice(0, 50).filter((id) => typeof id === 'string' && /^[\w.:-]{1,80}$/.test(id));
  }
  await deps.updateDeviceInfo(env, binding.mac, info);
  // Le handler historique remplace un nombre inconnu par zéro. NOVATUBE
  // garde « inconnu » (null ; le panel affiche —), et un historique vidé
  // peut réellement être vidé au lieu de conserver le précédent.
  const detailWrites = [];
  if (info.sources) detailWrites.push(env.DB.prepare('UPDATE devices SET local_sources_json = ? WHERE id = ?')
    .bind(JSON.stringify(info.sources), binding.device_id));
  if (info.recent) detailWrites.push(env.DB.prepare('UPDATE devices SET recent_json = ? WHERE id = ?')
    .bind(JSON.stringify(info.recent), binding.device_id));
  if (detailWrites.length) {
    const written = await env.DB.batch(detailWrites);
    if (written.some((row) => row?.meta?.changes !== 1)) return false;
  }
  const channel = safeText(input.channel, 120, binding);
  const quality = typeof input.quality === 'number' && Number.isFinite(input.quality)
    && input.quality >= 0 && input.quality <= 100 ? Math.round(input.quality) : null;
  await deps.recordPresence(env, binding.mac, text(request.headers.get('CF-Connecting-IP'), 64),
    text(request.headers.get('CF-IPCountry'), 8), now, channel, quality);
  // La baseline 317 ignore le dernier argument quality. Ajout de colonne
  // local et écriture de CET appareil seulement, sans remplacer son handler.
  if (!qualityReady.has(env.DB)) {
    try { await env.DB.prepare('ALTER TABLE presence ADD COLUMN quality INTEGER').run(); }
    catch (error) {
      if (!/duplicate column name:\s*quality\b/i.test(String(error?.message || ''))) throw error;
    }
    qualityReady.add(env.DB);
  }
  const written = await env.DB.prepare('UPDATE presence SET quality = ? WHERE mac = ? AND last_seen = ?')
    .bind(quality, binding.mac, now).run();
  if (written?.meta?.changes !== 1) return false;
  await env.DB.batch([
    env.DB.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?').bind(now, binding.device_id),
    // Le poll de licence ne doit pas effacer la chaîne fraîchement remontée.
    env.DB.prepare('UPDATE novatube4k_devices SET updated_at = ? WHERE raw_mac = ?').bind(now, binding.raw_mac),
  ]);
  return true;
}

async function readJson(response, limit = 256 * 1024) {
  if (!response?.ok || !response.body) throw new Error('upstream_unavailable');
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) { await reader.cancel(); throw new Error('upstream_too_large'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const value = JSON.parse(new TextDecoder().decode(bytes));
  if (!plain(value)) throw new Error('upstream_invalid');
  return value;
}

async function configuration(env, input, request, deps, now) {
  if (typeof deps.relay !== 'function') throw new Error('missing_relay');
  const platform = input.platform === 'mobile' ? 'mobile' : 'tv';
  const after = integer(input.announcements_after, 0, Number.MAX_SAFE_INTEGER);
  const version = Number((await env.DB.prepare('SELECT version FROM novatube4k_panel_version WHERE id = 1').first())?.version) || 0;
  const country = text(request.headers.get('CF-IPCountry'), 8);
  const key = JSON.stringify([platform, country, after, version]);
  let cache = configCache.get(env.DB);
  if (!cache) { cache = new Map(); configCache.set(env.DB, cache); }
  let entry = cache.get(key);
  // Les règles de date, expirations d'annonces et écritures externes restent
  // visibles même sans événement. Un hook panel invalide immédiatement.
  if (!entry || now - entry.at >= 2000) {
    const paths = {
      announcements: '/api/announcement?after=' + after,
      home: '/api/home-layout', theme: '/api/theme?platform=' + platform,
      featured: '/api/featured', ad: '/api/ad', pricing: '/api/pricing',
      feedback: '/api/feedback-prompt', servers: '/api/servers',
      // Aucun ?build= : le build NOVATUBE ne relève pas du build Flutter.
      app_version: '/api/app-version?platform=' + platform,
    };
    const entries = Object.entries(paths);
    const results = await Promise.allSettled(entries.map(async ([name, path]) => {
      const value = await readJson(await deps.relay('GET', path));
      if (name === 'app_version') value.download_url = DOWNLOAD_URL;
      return [name, value];
    }));
    const config = {};
    const errors = [];
    results.forEach((result, index) => {
      if (result.status === 'fulfilled') config[result.value[0]] = result.value[1];
      else errors.push(entries[index][0]);
    });
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(JSON.stringify(config))));
    const etag = Array.from(digest, (n) => n.toString(16).padStart(2, '0')).join('');
    entry = { at: now, config, errors, etag };
    if (cache.size >= 64) cache.delete(cache.keys().next().value);
    cache.set(key, entry);
  }
  return {
    config_etag: entry.etag,
    config_scope: 'platform',
    config_errors: entry.errors,
    config_unchanged: input.config_etag === entry.etag,
    ...(input.config_etag === entry.etag ? {} : { config: entry.config }),
  };
}

async function commands(env, binding, deps, now) {
  if (typeof deps.ensureOrderTables !== 'function' || typeof deps.markOrderSent !== 'function') {
    throw new Error('missing_orders');
  }
  await deps.ensureOrderTables(env);
  const rows = await env.DB.prepare(`SELECT order_id, kind, trace_id, config_rev, created_at, state
    FROM box_orders WHERE mac = ? AND state NOT IN ('applied', 'failed')
    ORDER BY created_at DESC, order_id DESC LIMIT 50`).bind(binding.mac).all();
  // Les anciens ordres source ne peuvent pas confirmer une révision plus
  // récente. Ils restent auditables, sans affamer une révocation ou un reset.
  const result = [];
  for (const row of rows.results || []) {
    if (!ORDER_ID.test(row.order_id || '')) continue;
    await env.DB.prepare(`INSERT INTO novatube4k_order_delivery (mac, order_id, served_at)
      VALUES (?, ?, ?) ON CONFLICT(mac, order_id) DO UPDATE SET served_at = excluded.served_at`)
      .bind(binding.mac, row.order_id, now).run();
    await deps.markOrderSent(env, row.order_id, null, now);
    result.push({ ...row, state: row.state === 'created' ? 'sent' : row.state });
  }
  return result;
}

async function ordersAck(env, binding, input, deps) {
  if (!Array.isArray(input.orders) || input.orders.length === 0 || input.orders.length > 20) return fail('invalid_orders');
  if (typeof deps.recordAck !== 'function') return fail('orders_unavailable', 503);
  if (typeof deps.ensureOrderTables === 'function') await deps.ensureOrderTables(env);
  const results = [];
  for (const item of input.orders) {
    const id = plain(item) && typeof item.order_id === 'string' ? item.order_id : '';
    if (!ORDER_ID.test(id) || !['received', 'applied', 'failed'].includes(item?.state)) {
      results.push({ order_id: id, status: 400, error: 'invalid_ack' });
      continue;
    }
    const row = await env.DB.prepare(`SELECT o.kind, o.config_rev, o.trace_id FROM box_orders o
      JOIN novatube4k_order_delivery d ON d.order_id = o.order_id AND d.mac = o.mac
      WHERE o.order_id = ? AND o.mac = ?`).bind(id, binding.mac).first();
    if (!row) { results.push({ order_id: id, status: 404, error: 'order_not_served' }); continue; }
    if (SOURCE_KINDS.has(row.kind) && item.state === 'applied') {
      // Seul /ack vérifie la révision effectivement servie et enregistrée.
      results.push({ order_id: id, status: 409, error: 'source_ack_required' });
      continue;
    }
    const ack = {
      order_id: id, state: item.state,
      received_at: integer(item.received_at, 1, Number.MAX_SAFE_INTEGER, null),
      applied_at: integer(item.applied_at, 1, Number.MAX_SAFE_INTEGER, null),
      config_rev: row.config_rev, trace_id: row.trace_id,
      result: safeText(item.result, 60, binding) || null,
      error_code: safeText(item.error_code, 60, binding) || null,
      error_message: safeText(item.error_message, 300, binding) || null,
      app_version: safeText(item.app_version || input.app_version, 40, binding) || null,
    };
    const recorded = await deps.recordAck(env, binding.mac, ack, Date.now());
    results.push({ order_id: id, status: recorded.status, ...recorded.body });
  }
  return json({ ok: true, results });
}

function containsInstallationSecret(value, depth = 0) {
  if (depth > 20) return true;
  if (!value || typeof value !== 'object') return false;
  return Object.entries(value).some(([key, child]) => /^(?:device[_-]?key|device_key_hash|activation_key)$/i.test(key)
    || containsInstallationSecret(child, depth + 1));
}

export async function handleNovatube4kPanel(action, request, env, binding, input, deps, access) {
  await ensurePanelTables(env);
  if (action === 'panel') {
    const now = Date.now();
    let telemetryOk = false;
    try { telemetryOk = await telemetry(env, binding, input, request, deps, now); } catch (_) { /* diagnostic partiel */ }
    const signals = await readNovatubePanelSignals(env, binding, deps);
    let orders = [];
    let commandsOk = true;
    try { orders = await commands(env, binding, deps, now); } catch (_) { commandsOk = false; }
    const config = await configuration(env, input, request, deps, now);
    return json({ ok: true, app_id: 'app_novatube4k', mac: binding.mac, server_now: now,
      telemetry_ok: telemetryOk, commands: orders, commands_ok: commandsOk, ...signals, ...config });
  }
  if (action === 'orders-ack') return ordersAck(env, binding, input, deps);
  if (action === 'blackbox') {
    if (typeof input.text !== 'string') return fail('text_required');
    return deps.relay('POST', '/api/blackbox', {
      mac: binding.mac, text: sanitizeNovatubeDiagnostic(input.text, binding.raw_mac),
    });
  }
  if (action === 'wait') {
    if (!env.RT_HUB || String(env.REALTIME_PUSH_OFF) === '1') return fail('realtime_unavailable', 503);
    const after = integer(input.after, 0, Number.MAX_SAFE_INTEGER);
    const timeout = integer(input.timeout, 200, 20000, 20000);
    // Même boîte aux lettres et même format que handleBoxRoute, après notre
    // contrôle de clé. Aucun second quota public partagé par toutes les MAC.
    const hub = env.RT_HUB.get(env.RT_HUB.idFromName(binding.mac));
    return hub.fetch('https://hub/wait?after=' + after + '&timeout=' + timeout, { method: 'GET' });
  }
  if (action === 'rt-ticket') {
    if (!env.RT_HUB || String(env.REALTIME_PUSH_OFF) === '1') return fail('realtime_unavailable', 503);
    const hub = env.RT_HUB.get(env.RT_HUB.idFromName('devices-v1'));
    return hub.fetch('https://hub/device-ticket', { method: 'POST',
      body: JSON.stringify({ mac: binding.mac, exp: Date.now() + 60_000 }) });
  }
  if (action === 'feedback') {
    if (typeof input.message !== 'string' || !input.message.trim()) return fail('message_required');
    if (!Number.isSafeInteger(input.rating) || input.rating < 0 || input.rating > 5) return fail('invalid_rating');
    return deps.relay('POST', '/api/feedback', { mac: binding.mac,
      rating: integer(input.rating, 0, 5), message: safeText(input.message, 2000, binding) });
  }
  // Historique et sauvegarde peuvent contenir des données personnelles ou
  // des listes locales. La clé seule ne remplace pas la licence d'accès.
  if (!access || access.status !== 'active') return fail('license_inactive', 403);
  if (action === 'history') return deps.relay('GET', '/api/history/' + binding.mac);
  if (action === 'backup') {
    if (input.op === 'get') return deps.relay('GET', '/api/backup/' + binding.mac);
    if (input.op !== 'put' || !plain(input.data) || containsInstallationSecret(input.data)) return fail('invalid_backup');
    if (encoder.encode(JSON.stringify(input.data)).byteLength > 256 * 1024) return fail('body_too_large', 413);
    return deps.relay('PUT', '/api/backup/' + binding.mac, { data: input.data });
  }
  return fail('not_found', 404);
}

// Les réglages globaux ne publient historiquement qu'au WebSocket de flotte.
// NOVATUBE peut rester sur son attente longue : après une écriture panel
// réussie, on réveille ses seules MAC en ligne avec un signal sans payload.
export async function notifyNovatubePanelMutation(request, response, env) {
  if (!response?.ok || !['POST', 'PUT', 'PATCH', 'DELETE'].includes(request.method) || !env?.DB) return;
  const parts = new URL(request.url).pathname.split('/').filter(Boolean);
  let blackboxMac = null;
  if (parts.length === 5 && parts[0] === 'api' && parts[1] === 'v1'
    && parts[2] === 'blackbox' && parts[4] === 'ask') {
    try { blackboxMac = decodeURIComponent(parts[3]).trim().toUpperCase(); } catch (_) { return; }
    if (!/^MK(?::[0-9A-F]{2}){5}$/.test(blackboxMac)) return;
  }
  // Le signal license demande seulement une relecture du statut : celui-ci
  // porte blackbox_pull. Aucune commande ou confirmation factice n'est créée.
  const kind = blackboxMac ? 'license' : parts[0] === 'api' && parts[1] === 'v1' ? GLOBAL_KINDS[parts[2]]
    : (parts.join('/') === 'api/announcement' ? 'message' : null);
  if (!kind) return;
  // Aucune mutation annexe avant le premier appareil NOVATUBE.
  let devices;
  try {
    devices = await env.DB.prepare(`SELECT n.mac FROM novatube4k_devices n
      JOIN devices d ON d.id = n.device_id WHERE d.last_seen_at >= ?
      ${blackboxMac ? 'AND n.mac = ?' : ''} LIMIT 1000`)
      .bind(...(blackboxMac ? [Date.now() - 120_000, blackboxMac] : [Date.now() - 120_000])).all();
  } catch (error) {
    if (/no such table:\s*novatube4k_devices\b/i.test(String(error?.message || ''))) return;
    throw error;
  }
  if (!blackboxMac) {
    await ensurePanelTables(env);
    await env.DB.prepare('UPDATE novatube4k_panel_version SET version = version + 1 WHERE id = 1').run();
    configCache.delete(env.DB);
  }
  if (!env.RT_HUB || String(env.REALTIME_PUSH_OFF) === '1') return;
  const list = devices.results || [];
  for (let index = 0; index < list.length; index += 20) {
    await Promise.allSettled(list.slice(index, index + 20).map(({ mac }) => {
      const hub = env.RT_HUB.get(env.RT_HUB.idFromName(mac));
      return hub.fetch('https://hub/notify', { method: 'POST', body: JSON.stringify({ mac, kind }) });
    }));
  }
}
