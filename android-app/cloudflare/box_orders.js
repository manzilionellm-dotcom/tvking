// =========================================================
//  box_orders.js — Ordres panel → box suivis de bout en bout
// =========================================================
//  Avant (6 octobre 2026) : `POST /api/box/ack` répondait `ok` sans rien
//  écrire. Le serveur ne savait pas distinguer « envoyé », « reçu » et
//  « appliqué ».
//
//  Ici, chaque ordre a un `order_id` unique et une ligne `box_orders` :
//
//    CREATED   écrit juste après la transaction métier (T2) ;
//    SENT      publié au Durable Object de la box (T3) ;
//    RECEIVED  la box l'a reçu (T4, heure box + heure serveur de l'accusé) ;
//    APPLIED   la box l'a appliqué (T5) avec son résultat ;
//    FAILED    la box l'a reçu mais l'application a échoué (code + message) ;
//    EXPIRED   aucune réponse terminale après ORDER_TTL_MS (calculé à la
//              lecture et écrit au passage : jamais d'état « à moitié »).
//
//  Le même `trace_id` (X-Request-Id du panel) suit : action admin → audit
//  → ordre → trame temps réel → accusé de la box → résultat.
//
//  Révisions de listes (`source_revisions`) : chaque envoi de listes crée
//  une révision numérotée (1, 2, 3… par MAC). États : VALIDATED (contrôle
//  serveur passé) → PUBLISHED (servie à la box) → ACKNOWLEDGED (la box l'a
//  chargée) ou REJECTED_BY_BOX (la box l'a refusée et garde la précédente).
//  La dernière ACKNOWLEDGED est la « dernière bonne » : retour arrière
//  possible vers elle. Aucune révision n'est jamais effacée.
//
//  Rien ici ne contient de mot de passe : les révisions gardent les listes
//  scellées telles que `device_sources` les stocke, et les messages
//  d'erreur de la box sont expurgés avant écriture.
// =========================================================

export const ORDER_STATES = Object.freeze({
  CREATED: 'created',
  SENT: 'sent',
  RECEIVED: 'received',
  APPLIED: 'applied',
  FAILED: 'failed',
  EXPIRED: 'expired',
});

/// Au-delà, un ordre sans réponse terminale est EXPIRED.
export const ORDER_TTL_MS = 10 * 60 * 1000;

const RANK = { created: 0, sent: 1, received: 2, applied: 3, failed: 3, expired: 3 };
const ORDER_ID_RX = /^ord_[A-Za-z0-9-]{8,64}$/;
const ACK_STATES = new Set(['received', 'applied', 'failed']);

/// Table EXPLICITE des transitions permises (06/10/2026). Tout le reste est
/// refusé (l'état ne bouge pas). Règles :
///   • on n'avance que vers l'avant ; APPLIED et FAILED sont définitifs ;
///   • un accusé de la box PROUVE l'envoi : CREATED → RECEIVED/APPLIED/FAILED
///     est permis (la box peut accuser avant que le serveur ait noté SENT :
///     la publication et l'accusé se croisent) ;
///   • EXPIRED est un verdict PROVISOIRE (délai sans réponse) : un accusé
///     terminal qui arrive après le délai (box hors ligne puis revenue) le
///     remplace, marqué `late_ack = 1`. Un simple RECEIVED tardif, non.
export const ORDER_TRANSITIONS = Object.freeze({
  created: ['sent', 'received', 'applied', 'failed', 'expired'],
  sent: ['received', 'applied', 'failed', 'expired'],
  received: ['applied', 'failed', 'expired'],
  expired: ['applied', 'failed'],
  applied: [],
  failed: [],
});

export function canTransition(from, to) {
  const allowed = ORDER_TRANSITIONS[from];
  return !!(allowed && allowed.includes(to));
}

/// Transition (pure, testée) : l'état suivant, ou l'état courant si la
/// transition n'est pas permise.
export function nextOrderState(current, incoming) {
  return canTransition(current, incoming) ? incoming : current;
}

/// Ordre → famille d'opération mesurée.
export function opForKind(kind) {
  switch (kind) {
    case 'activate': return 'activation';
    case 'renew': return 'renewal';
    case 'source':
    case 'source_clear': return 'source';
    case 'reset': return 'reset';
    default: return String(kind || '');
  }
}

/// Un ordre non terminal plus vieux que le délai est EXPIRED.
export function effectiveState(row, now = Date.now()) {
  const state = String(row && row.state || '');
  if (RANK[state] === undefined) return state;
  if (RANK[state] >= 3) return state;
  const created = Number(row.created_at) || 0;
  return created > 0 && now - created > ORDER_TTL_MS ? ORDER_STATES.EXPIRED : state;
}

/// Les messages d'erreur viennent de la box : ils peuvent contenir une
/// adresse de liste. On retire identifiants et requêtes d'URL.
export function redactError(text) {
  if (text == null) return null;
  let s = String(text).slice(0, 600);
  s = s.replace(/([?&](?:username|password|user|pass|token|key)=)[^&\s"']*/gi, '$1***');
  s = s.replace(/(https?:\/\/)[^/\s:@]+:[^/\s@]+@/gi, '$1***@');
  s = s.replace(/(https?:\/\/[^\s?#"']+)\?[^\s"']*/gi, '$1?***');
  return s.slice(0, 300);
}

/// Validation d'un accusé (pure, testée). Rend { ack } ou { error }.
export function validateAck(raw) {
  if (!raw || typeof raw !== 'object') return { error: 'ack object required' };
  const orderId = String(raw.order_id || '');
  if (!ORDER_ID_RX.test(orderId)) return { error: 'bad order_id' };
  const state = String(raw.state || '').toLowerCase();
  if (!ACK_STATES.has(state)) return { error: 'state must be received, applied or failed' };
  const num = (v) => (Number.isFinite(Number(v)) && Number(v) > 0 ? Math.floor(Number(v)) : null);
  const short = (v, n) => (v == null ? null : String(v).replace(/[\u0000-\u001f]/g, ' ').slice(0, n));
  return {
    ack: {
      order_id: orderId,
      state,
      received_at: num(raw.received_at),
      applied_at: num(raw.applied_at),
      config_rev: num(raw.config_rev),
      result: short(raw.result, 60),
      error_code: short(raw.error_code, 60),
      error_message: redactError(raw.error_message),
      trace_id: short(raw.trace_id, 64),
      app_version: short(raw.app_version, 40),
    },
  };
}

/// Centile au rang le plus proche (pure). `null` si aucune valeur.
export function percentile(values, p) {
  const v = values.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  if (!v.length) return null;
  const idx = Math.min(v.length - 1, Math.max(0, Math.ceil((p / 100) * v.length) - 1));
  return v[idx];
}

/// Résumé de latence par opération et par segment (pure, testée).
/// Segments mesurés avec l'HORLOGE SERVEUR, sauf `client_to_api` (horloge
/// du navigateur → serveur : décalage d'horloge possible, signalé).
///   api        T2 - T1  réception API → transaction engagée
///   publish    T3 - T2  transaction → trame publiée (Durable Object)
///   received   T4 - T3  publiée → accusé « reçu » arrivé au serveur
///   applied    T5 - T3  publiée → accusé « appliqué » arrivé au serveur
///   end_to_end T5 - T1  réception API → box appliquée
///   client_to_api T1 - T0
export function latencySummary(rows) {
  const segs = {
    client_to_api: (r) => diff(r.t1_api, r.t0_client),
    api: (r) => diff(r.t2_commit, r.t1_api),
    publish: (r) => diff(r.t3_published, r.t2_commit),
    received: (r) => diff(r.received_srv, r.t3_published),
    applied: (r) => diff(r.applied_srv, r.t3_published),
    received_to_applied: (r) => diff(r.applied_srv, r.received_srv),
    // Durée de traitement SUR la box (les deux heures viennent de l'horloge
    // de la box : pas de décalage). Pour un ordre de listes : téléchargement
    // + analyse + écriture, non détaillés (la boîte noire de la box les donne).
    box_apply: (r) => diff(r.applied_at, r.received_at),
    failed: (r) => diff(r.failed_srv, r.t3_published),
    end_to_end: (r) => diff(r.applied_srv, r.t1_api),
  };
  const byOp = {};
  for (const row of rows || []) {
    const op = row.op || opForKind(row.kind);
    if (!byOp[op]) byOp[op] = { n: 0, states: {}, segments: {} };
    const o = byOp[op];
    o.n += 1;
    const st = effectiveState(row);
    o.states[st] = (o.states[st] || 0) + 1;
    for (const [name, fn] of Object.entries(segs)) {
      const d = fn(row);
      if (d == null) continue;
      (o.segments[name] = o.segments[name] || []).push(d);
    }
  }
  const out = {};
  for (const [op, o] of Object.entries(byOp)) {
    const segments = {};
    for (const name of Object.keys(segs)) {
      const vals = o.segments[name] || [];
      segments[name] = vals.length
        ? { n: vals.length, p50: percentile(vals, 50), p95: percentile(vals, 95), p99: percentile(vals, 99) }
        : { n: 0, p50: null, p95: null, p99: null };
    }
    out[op] = { orders: o.n, states: o.states, segments };
  }
  return out;
}

function diff(a, b) {
  const x = Number(a); const y = Number(b);
  if (!Number.isFinite(x) || !Number.isFinite(y) || x <= 0 || y <= 0) return null;
  const d = x - y;
  return d >= 0 ? d : null;
}

// ---------------------------------------------------------
//  Base
// ---------------------------------------------------------
// Prêt PAR base (WeakSet) : un drapeau global sautait la création des
// tables pour une seconde base du même isolate (vu en test le 06/10/2026).
const _ready = new WeakSet();
export async function ensureOrderTables(env) {
  if (!env || !env.DB || _ready.has(env.DB)) return;
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS box_orders ('
    + 'order_id TEXT PRIMARY KEY, mac TEXT NOT NULL, customer_id TEXT, device_id TEXT, '
    + 'kind TEXT NOT NULL, op TEXT, trace_id TEXT, seq INTEGER, config_rev INTEGER, state TEXT NOT NULL, '
    + 't0_client INTEGER, t1_api INTEGER, t2_commit INTEGER, t3_published INTEGER, '
    + 'received_at INTEGER, received_srv INTEGER, applied_at INTEGER, applied_srv INTEGER, '
    + 'failed_at INTEGER, failed_srv INTEGER, late_ack INTEGER NOT NULL DEFAULT 0, '
    + 'result TEXT, error_code TEXT, error_message TEXT, applied_rev INTEGER, app_version TEXT, '
    + 'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  ).run();
  for (const col of ['customer_id TEXT', 'device_id TEXT', 'failed_at INTEGER', 'failed_srv INTEGER',
    'late_ack INTEGER NOT NULL DEFAULT 0']) {
    try { await env.DB.prepare(`ALTER TABLE box_orders ADD COLUMN ${col}`).run(); } catch (_) { /* déjà là */ }
  }
  await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_box_orders_mac ON box_orders(mac, created_at)').run();
  await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_box_orders_trace ON box_orders(trace_id)').run();
  await env.DB.prepare('CREATE INDEX IF NOT EXISTS idx_box_orders_created ON box_orders(created_at)').run();
  await env.DB.prepare(
    'CREATE TABLE IF NOT EXISTS source_revisions ('
    + 'mac TEXT NOT NULL, rev INTEGER NOT NULL, state TEXT NOT NULL, '
    + 'panel_json TEXT NOT NULL, item_count INTEGER NOT NULL, hosts TEXT, '
    + 'trace_id TEXT, actor_type TEXT, actor_id TEXT, rollback_of INTEGER, '
    + 'validated_at INTEGER, published_at INTEGER, acked_at INTEGER, ack_result TEXT, ack_error TEXT, '
    + 'created_at INTEGER NOT NULL, PRIMARY KEY (mac, rev))',
  ).run();
  _ready.add(env.DB);
}

function newOrderId() {
  return `ord_${crypto.randomUUID()}`;
}

/// Crée l'ordre (CREATED). Ne jette jamais : l'action métier est déjà engagée.
export async function createOrder(env, { mac, kind, traceId, t0, t1, t2, configRev }) {
  if (!env || !env.DB) return null;
  try {
    await ensureOrderTables(env);
    const orderId = newOrderId();
    const now = Date.now();
    // device_id / customer_id lus DANS l'insertion (une seule requête).
    await env.DB.prepare(
      'INSERT INTO box_orders (order_id, mac, customer_id, device_id, kind, op, trace_id, config_rev, state, '
      + 't0_client, t1_api, t2_commit, created_at, updated_at) '
      + 'VALUES (?, ?, (SELECT customer_id FROM devices WHERE mac = ?), (SELECT id FROM devices WHERE mac = ?), '
      + '?, ?, ?, ?, \'created\', ?, ?, ?, ?, ?)',
    ).bind(orderId, mac, mac, mac, kind, opForKind(kind), traceId || null, configRev || null,
      t0 || null, t1 || null, t2 || now, now, now).run();
    return orderId;
  } catch (_) {
    return null;
  }
}

/// Publiée au Durable Object (SENT, T3).
export async function markOrderSent(env, orderId, seq, t3 = Date.now()) {
  if (!env || !env.DB || !orderId) return;
  try {
    // T3 est noté même si la box a déjà accusé (publication et accusé se
    // croisent) ; l'état ne passe à SENT que depuis CREATED.
    await env.DB.prepare(
      'UPDATE box_orders SET seq = COALESCE(seq, ?), t3_published = COALESCE(t3_published, ?), '
      + 'state = CASE WHEN state = \'created\' THEN \'sent\' ELSE state END, updated_at = ? '
      + 'WHERE order_id = ?',
    ).bind(seq || null, t3, t3, orderId).run();
  } catch (_) { /* l'ordre restera CREATED puis EXPIRED : visible */ }
}

/// Enregistre un accusé de la box. Rend { status, body }.
/// Idempotent : le même accusé rejoué ne change rien (`changed: false`).
export async function recordAck(env, mac, raw, now = Date.now()) {
  const v = validateAck(raw);
  if (v.error) {
    logAck('rejected', { mac, reason: v.error });
    return { status: 400, body: { error: 'bad_ack', message: v.error } };
  }
  const ack = v.ack;
  await ensureOrderTables(env);
  const row = await env.DB.prepare('SELECT * FROM box_orders WHERE order_id = ?')
    .bind(ack.order_id).first();
  // Ordre inconnu, ou d'une autre box : refusé ET journalisé (jamais lu ni modifié).
  if (!row || row.mac !== mac) {
    logAck('unknown_order', { mac, order_id: ack.order_id });
    return { status: 404, body: { error: 'unknown_order' } };
  }
  // Le numéro fourni doit être celui de CET ordre, même pour RECEIVED :
  // sinon l'accusé d'un ancien envoi pourrait confirmer ou refuser une
  // autre révision de la même box. Refus avant toute écriture. Les
  // anciens clients sans config_rev gardent leur contrat actuel ; ils
  // n'attestent alors aucune révision (voir markRevisionAck ci-dessous).
  if (ack.config_rev && row.config_rev
    && Number(ack.config_rev) !== Number(row.config_rev)) {
    logAck('revision_mismatch', { mac, order_id: ack.order_id });
    return { status: 409, body: { error: 'config_revision_mismatch' } };
  }
  const current = effectiveState(row, now);
  const next = nextOrderState(current, ack.state);
  if (next === current) {
    if (current !== ack.state) logAck('transition_refused', { order_id: ack.order_id, from: current, to: ack.state });
    return { status: 200, body: { ok: true, order_id: ack.order_id, state: current, changed: false } };
  }
  const late = current === 'expired' ? 1 : 0;
  const isApplied = next === 'applied';
  const isFailed = next === 'failed';
  // Condition sur l'état LU : deux accusés simultanés ne s'écrasent pas
  // (le perdant ne change rien et reçoit changed: false).
  const upd = await env.DB.prepare(
    'UPDATE box_orders SET state = ?, late_ack = MAX(late_ack, ?), '
    + 'received_at = COALESCE(received_at, ?), received_srv = COALESCE(received_srv, ?), '
    + 'applied_at = CASE WHEN ? THEN COALESCE(?, applied_at) ELSE applied_at END, '
    + 'applied_srv = CASE WHEN ? THEN ? ELSE applied_srv END, '
    + 'failed_at = CASE WHEN ? THEN COALESCE(?, failed_at) ELSE failed_at END, '
    + 'failed_srv = CASE WHEN ? THEN ? ELSE failed_srv END, '
    + 'result = COALESCE(?, result), error_code = COALESCE(?, error_code), '
    + 'error_message = COALESCE(?, error_message), applied_rev = COALESCE(?, applied_rev), '
    + 'app_version = COALESCE(?, app_version), updated_at = ? '
    + 'WHERE order_id = ? AND state = ?',
  ).bind(
    next, late,
    ack.received_at || ack.applied_at, now,
    isApplied ? 1 : 0, ack.applied_at,
    isApplied ? 1 : 0, now,
    isFailed ? 1 : 0, ack.applied_at || ack.received_at,
    isFailed ? 1 : 0, now,
    ack.result, ack.error_code, ack.error_message, ack.config_rev, ack.app_version, now,
    ack.order_id, row.state,
  ).run();
  if (!(upd && upd.meta && upd.meta.changes === 1)) {
    const fresh = await env.DB.prepare('SELECT state FROM box_orders WHERE order_id = ?').bind(ack.order_id).first();
    return { status: 200, body: { ok: true, order_id: ack.order_id, state: fresh ? fresh.state : current, changed: false } };
  }
  // Accusé d'une révision de listes : la révision passe ACKNOWLEDGED ou
  // REJECTED_BY_BOX (la box garde alors la précédente). Une révision déjà
  // tranchée ne change plus (WHERE state = 'published').
  if ((isApplied || isFailed) && ack.config_rev
    && (row.kind === 'source' || row.kind === 'source_clear' || row.kind === 'reset')) {
    await markRevisionAck(env, mac, ack.config_rev, isApplied && ack.result !== 'refused',
      ack.result, ack.error_message, now);
  }
  return { status: 200, body: { ok: true, order_id: ack.order_id, state: next, changed: true, late_ack: !!late } };
}

function logAck(event, detail) {
  try { console.log(JSON.stringify({ level: 'warn', source: 'box_ack', event, ...detail })); } catch (_) { /* journal best-effort */ }
}

/// Ordres d'une ou plusieurs MAC (ou d'un trace_id), états effectifs.
export async function listOrders(env, { macs = [], traceId = null, since = 0, limit = 200 }) {
  await ensureOrderTables(env);
  const now = Date.now();
  let rows = [];
  if (traceId) {
    rows = (await env.DB.prepare('SELECT * FROM box_orders WHERE trace_id = ? ORDER BY created_at ASC LIMIT ?')
      .bind(traceId, limit).all()).results || [];
  } else if (macs.length) {
    const marks = macs.map(() => '?').join(',');
    rows = (await env.DB.prepare(
      `SELECT * FROM box_orders WHERE mac IN (${marks}) AND created_at >= ? ORDER BY created_at DESC LIMIT ?`,
    ).bind(...macs, since, limit).all()).results || [];
  }
  // Écrit l'expiration au passage : la base ne garde pas d'état ambigu.
  const expired = rows.filter((r) => effectiveState(r, now) === 'expired' && r.state !== 'expired');
  for (const r of expired) {
    try {
      await env.DB.prepare('UPDATE box_orders SET state = \'expired\', updated_at = ? WHERE order_id = ? AND state = ?')
        .bind(now, r.order_id, r.state).run();
      r.state = 'expired';
    } catch (_) { /* relu au prochain passage */ }
  }
  return rows;
}

export async function latencyStats(env, sinceMs) {
  await ensureOrderTables(env);
  const rows = (await env.DB.prepare(
    'SELECT kind, op, state, created_at, t0_client, t1_api, t2_commit, t3_published, '
    + 'received_srv, applied_srv, failed_srv, received_at, applied_at FROM box_orders WHERE created_at >= ?',
  ).bind(sinceMs).all()).results || [];
  return latencySummary(rows);
}

// ---------------------------------------------------------
//  Révisions de listes
// ---------------------------------------------------------

// (recordRevision supprimée le 06/10/2026 : numérotation « MAX+1 lu puis
// inséré » perdue en concurrence. Les révisions sont écrites par
// device_sources_store.js, dans la même transaction que les listes.)


export async function markRevisionAck(env, mac, rev, ok, result, error, now = Date.now()) {
  try {
    await env.DB.prepare(
      'UPDATE source_revisions SET state = ?, acked_at = ?, ack_result = ?, ack_error = ? '
      + 'WHERE mac = ? AND rev = ? AND state = \'published\'',
    ).bind(ok ? 'acknowledged' : 'rejected_by_box', now, result || null, error || null, mac, rev).run();
  } catch (_) { /* best-effort */ }
}

/// Vue des révisions d'une MAC (sans identifiant ni mot de passe).
export async function revisionView(env, mac) {
  await ensureOrderTables(env);
  const rows = (await env.DB.prepare(
    'SELECT rev, state, item_count, hosts, trace_id, actor_type, rollback_of, validated_at, '
    + 'published_at, acked_at, ack_result, ack_error, created_at FROM source_revisions '
    + 'WHERE mac = ? ORDER BY rev DESC LIMIT 50',
  ).bind(mac).all()).results || [];
  return summarizeRevisions(rows);
}

/// Pure (testée) : révision courante, dernière bonne, retour arrière possible.
export function summarizeRevisions(rows) {
  const list = (rows || []).map((r) => ({
    ...r,
    hosts: (() => { try { return JSON.parse(r.hosts || '[]'); } catch (_) { return []; } })(),
  }));
  const current = list.length ? list[0] : null;
  const lastGood = list.find((r) => r.state === 'acknowledged') || null;
  return {
    current_revision: current ? current.rev : null,
    current_state: current ? current.state : null,
    last_good_revision: lastGood ? lastGood.rev : null,
    rollback_available: !!(lastGood && current && lastGood.rev !== current.rev),
    revisions: list,
  };
}

export async function revisionPanelJson(env, mac, rev) {
  await ensureOrderTables(env);
  const row = await env.DB.prepare('SELECT panel_json, state FROM source_revisions WHERE mac = ? AND rev = ?')
    .bind(mac, rev).first();
  return row || null;
}

export async function currentRevision(env, mac) {
  try {
    await ensureOrderTables(env);
    const row = await env.DB.prepare('SELECT MAX(rev) AS r FROM source_revisions WHERE mac = ?').bind(mac).first();
    return row && row.r ? Number(row.r) : null;
  } catch (_) {
    return null;
  }
}
