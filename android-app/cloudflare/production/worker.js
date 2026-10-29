var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// trial_access.js
var DAY_MS = 24 * 60 * 60 * 1e3;
var TRIAL_DAYS = 7;
var MAX_EXTEND_DAYS = 365;
function trialEnforcementOn(env) {
  const v = String(env && env.TRIAL_ENFORCEMENT || "").trim().toLowerCase();
  return v === "1" || v === "true" || v === "on" || v === "yes";
}
__name(trialEnforcementOn, "trialEnforcementOn");
function trialWindow(startedAt, now, days = TRIAL_DAYS) {
  const start = Number(startedAt) > 0 ? Number(startedAt) : now;
  const trialUntil = start + days * DAY_MS;
  const expired = now >= trialUntil;
  const daysLeft = expired ? 0 : Math.max(0, Math.ceil((trialUntil - now) / DAY_MS));
  return { start, trialUntil, expired, daysLeft };
}
__name(trialWindow, "trialWindow");
var _anchorReady = /* @__PURE__ */ new WeakSet();
async function ensureTrialAnchorTable(env) {
  if (!env || !env.DB || _anchorReady.has(env.DB))
    return;
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS trial_anchors (mac TEXT PRIMARY KEY, android_id TEXT, started_at INTEGER NOT NULL, extended_until INTEGER)"
  ).run();
  try {
    await env.DB.prepare(
      "ALTER TABLE trial_anchors ADD COLUMN extended_until INTEGER"
    ).run();
  } catch (_) {
  }
  try {
    await env.DB.prepare(
      "CREATE INDEX IF NOT EXISTS idx_trial_anchors_android ON trial_anchors(android_id)"
    ).run();
  } catch (_) {
  }
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS trial_extensions (id TEXT PRIMARY KEY, mac TEXT NOT NULL, days INTEGER NOT NULL, previous_until INTEGER, new_until INTEGER NOT NULL, actor_type TEXT, actor_id TEXT, created_at INTEGER NOT NULL)"
  ).run();
  _anchorReady.add(env.DB);
}
__name(ensureTrialAnchorTable, "ensureTrialAnchorTable");
function combineTrialUntil(computedUntil, extendedUntil) {
  const base = Number(computedUntil);
  const ext = Number(extendedUntil);
  const hasBase = Number.isFinite(base) && base > 0;
  const hasExt = Number.isFinite(ext) && ext > 0;
  if (hasBase && hasExt)
    return Math.max(base, ext);
  if (hasExt)
    return ext;
  return hasBase ? base : 0;
}
__name(combineTrialUntil, "combineTrialUntil");
function parseExtendDays(value) {
  let n;
  if (typeof value === "number") {
    if (!Number.isFinite(value) || !Number.isInteger(value)) {
      return { error: "Le nombre de jours doit \xEAtre un entier." };
    }
    n = value;
  } else if (typeof value === "string") {
    const s = value.trim();
    if (!/^[0-9]+$/.test(s)) {
      return { error: "Le nombre de jours doit \xEAtre un entier." };
    }
    n = Number(s);
  } else {
    return { error: "Le nombre de jours doit \xEAtre un entier." };
  }
  if (n < 1)
    return { error: "Indique au moins 1 jour." };
  if (n > MAX_EXTEND_DAYS) {
    return { error: `Maximum ${MAX_EXTEND_DAYS} jours \xE0 la fois.` };
  }
  return { days: n };
}
__name(parseExtendDays, "parseExtendDays");
function nextTrialEnd(currentUntil, now, days) {
  const cur = Number(currentUntil);
  const base = Number.isFinite(cur) && cur > now ? cur : now;
  return base + days * DAY_MS;
}
__name(nextTrialEnd, "nextTrialEnd");
async function readExtendedUntil(env, mac) {
  if (!env || !env.DB || !mac)
    return 0;
  try {
    await ensureTrialAnchorTable(env);
    const row = await env.DB.prepare("SELECT extended_until FROM trial_anchors WHERE mac = ?").bind(mac).first();
    const n = row && Number(row.extended_until);
    return Number.isFinite(n) && n > 0 ? n : 0;
  } catch (_) {
    return 0;
  }
}
__name(readExtendedUntil, "readExtendedUntil");
async function rememberTrialStart(env, mac, androidId, candidateStart) {
  const candidate = Number(candidateStart) > 0 ? Number(candidateStart) : Date.now();
  if (!env || !env.DB || !mac)
    return candidate;
  try {
    await ensureTrialAnchorTable(env);
    const aid = String(androidId || "").trim().slice(0, 64);
    const macRow = await env.DB.prepare("SELECT started_at, android_id FROM trial_anchors WHERE mac = ?").bind(mac).first();
    let started = candidate;
    if (macRow && Number(macRow.started_at) > 0 && Number(macRow.started_at) < started) {
      started = Number(macRow.started_at);
    }
    if (aid) {
      const idRow = await env.DB.prepare("SELECT MIN(started_at) AS started_at FROM trial_anchors WHERE android_id = ?").bind(aid).first();
      if (idRow && Number(idRow.started_at) > 0 && Number(idRow.started_at) < started) {
        started = Number(idRow.started_at);
      }
    }
    const storedAid = macRow && macRow.android_id ? String(macRow.android_id) : "";
    const unchanged = macRow && Number(macRow.started_at) === started && (aid === "" || storedAid === aid);
    if (unchanged)
      return started;
    if (macRow) {
      await env.DB.prepare(
        "UPDATE trial_anchors SET started_at = ?, android_id = CASE WHEN ? != '' THEN ? ELSE android_id END WHERE mac = ?"
      ).bind(started, aid, aid, mac).run();
    } else {
      try {
        await env.DB.prepare(
          "INSERT INTO trial_anchors (mac, android_id, started_at) VALUES (?, ?, ?)"
        ).bind(mac, aid || null, started).run();
      } catch (_) {
        const again = await env.DB.prepare("SELECT started_at FROM trial_anchors WHERE mac = ?").bind(mac).first();
        if (again && Number(again.started_at) > 0) {
          return Math.min(started, Number(again.started_at));
        }
      }
    }
    return started;
  } catch (_) {
    return candidate;
  }
}
__name(rememberTrialStart, "rememberTrialStart");
async function configuredTrialDays(env) {
  if (!env || !env.DB)
    return TRIAL_DAYS;
  try {
    const r = await env.DB.prepare("SELECT value FROM app_config WHERE key = 'trial_days'").first();
    const td = parseInt(r && r.value, 10);
    return Number.isFinite(td) && td >= 0 ? td : TRIAL_DAYS;
  } catch (_) {
    return TRIAL_DAYS;
  }
}
__name(configuredTrialDays, "configuredTrialDays");
function cfg(value) {
  return value == null ? "" : String(value);
}
__name(cfg, "cfg");
async function loadBlockCopy(env) {
  const empty = {
    title_fr: "",
    body_fr: "",
    title_en: "",
    body_en: "",
    pay_url: ""
  };
  if (!env || !env.DB)
    return empty;
  try {
    const rs = await env.DB.prepare(
      "SELECT key, value FROM app_config WHERE key IN ('trial_block_title_fr','trial_block_body_fr','trial_block_title_en','trial_block_body_en','trial_pay_url')"
    ).all();
    const map = {};
    for (const row of rs && rs.results || [])
      map[row.key] = cfg(row.value);
    return {
      title_fr: map.trial_block_title_fr || "",
      body_fr: map.trial_block_body_fr || "",
      title_en: map.trial_block_title_en || "",
      body_en: map.trial_block_body_en || "",
      pay_url: map.trial_pay_url || ""
    };
  } catch (_) {
    return empty;
  }
}
__name(loadBlockCopy, "loadBlockCopy");
function shapeEnforcedStatus(base, now, copy) {
  const block = !!(base && base.expired && !base.paid && !base.frozen && !base.banned);
  const c = copy || {};
  return {
    ...base,
    status: block ? "expired" : base.status,
    trial_until: block ? 0 : base.trial_until,
    trial_enforced: true,
    server_now: now,
    block_title_fr: c.title_fr || "",
    block_body_fr: c.body_fr || "",
    block_title_en: c.title_en || "",
    block_body_en: c.body_en || "",
    pay_url: c.pay_url || ""
  };
}
__name(shapeEnforcedStatus, "shapeEnforcedStatus");
function dateLabel(ms) {
  try {
    return new Date(ms).toISOString().slice(0, 10);
  } catch (_) {
    return "";
  }
}
__name(dateLabel, "dateLabel");
function trialLabelFromUntil(until, now) {
  const left = Math.max(0, Math.ceil((until - now) / DAY_MS));
  const j = left > 1 ? "jours restants" : "jour restant";
  return {
    access: "trial",
    label: `Essai en cours \xB7 ${left} ${j}`,
    days_left: left,
    ends_at: until
  };
}
__name(trialLabelFromUntil, "trialLabelFromUntil");
function describeAccess({ now, startedAt, trialDays, license, blockStatus, extendedUntil }) {
  if (blockStatus === "banned") {
    return { access: "banned", label: "Banni", days_left: 0, ends_at: null };
  }
  if (blockStatus === "frozen") {
    return { access: "frozen", label: "Gel\xE9", days_left: 0, ends_at: null };
  }
  const st = license && license.status;
  const ignored = !st || st === "inactive" || st === "pending";
  if (!ignored) {
    const lifetime = license.expires_at === null || license.expires_at === void 0;
    if (lifetime && st === "active") {
      return { access: "lifetime", label: "Activ\xE9 \xE0 vie", days_left: null, ends_at: null };
    }
    if (st === "active" && !lifetime && Number(license.expires_at) > now) {
      const ends = Number(license.expires_at);
      const left = Math.max(0, Math.ceil((ends - now) / DAY_MS));
      return {
        access: "activated",
        label: `Activ\xE9 \xB7 fin le ${dateLabel(ends)}`,
        days_left: left,
        ends_at: ends
      };
    }
    if (!lifetime && license.expires_at != null && Number(license.expires_at) <= now) {
      const ext = Number(extendedUntil);
      if (Number.isFinite(ext) && ext > now)
        return trialLabelFromUntil(ext, now);
      const ends = Number(license.expires_at);
      return {
        access: "expired",
        label: `Expir\xE9 \xB7 le ${dateLabel(ends)}`,
        days_left: 0,
        ends_at: ends
      };
    }
  }
  const days = Number.isFinite(Number(trialDays)) ? Number(trialDays) : TRIAL_DAYS;
  const win = trialWindow(startedAt, now, days);
  const until = combineTrialUntil(win.trialUntil, extendedUntil);
  if (now >= until) {
    return { access: "expired", label: "Essai expir\xE9", days_left: 0, ends_at: until };
  }
  return trialLabelFromUntil(until, now);
}
__name(describeAccess, "describeAccess");

// linkage.js
var ANNOUNCEMENT_PAGE = 30;
function announcementInactive(row) {
  const a = row && row.active;
  return a === 0 || a === "0" || a === false;
}
__name(announcementInactive, "announcementInactive");
function announcementFresh(row, now) {
  const exp = row ? row.expires_at : 0;
  if (exp === null || exp === void 0 || exp === "" || exp === false)
    return true;
  const n = Number(exp);
  if (!Number.isFinite(n) || n === 0)
    return true;
  return n > now;
}
__name(announcementFresh, "announcementFresh");
function announcementForCountry(row, country) {
  const c = String(row && row.country || "").trim().toUpperCase();
  if (!c)
    return true;
  const want = String(country || "").trim().toUpperCase();
  return c === want;
}
__name(announcementForCountry, "announcementForCountry");
function isAnnouncementVisible(row, { now, country }) {
  if (!row || row.id == null)
    return false;
  if (announcementInactive(row))
    return false;
  if (!announcementFresh(row, now))
    return false;
  if (!announcementForCountry(row, country))
    return false;
  const title = String(row.title || "");
  const body = String(row.body || "");
  return title.length > 0 || body.length > 0;
}
__name(isAnnouncementVisible, "isAnnouncementVisible");
function selectAnnouncements(rows, { after = 0, now = Date.now(), country = "" } = {}) {
  const cursor = Number(after) || 0;
  const byId = /* @__PURE__ */ new Map();
  for (const row of rows || []) {
    if (!isAnnouncementVisible(row, { now, country }))
      continue;
    const id = Number(row.id);
    if (!Number.isFinite(id))
      continue;
    if (!byId.has(id))
      byId.set(id, row);
  }
  const unique = [...byId.values()].sort((a, b) => Number(a.id) - Number(b.id));
  const latest = unique.length ? unique[unique.length - 1] : null;
  const pending = unique.filter((r) => Number(r.id) > cursor).slice(0, ANNOUNCEMENT_PAGE);
  return { latest, pending };
}
__name(selectAnnouncements, "selectAnnouncements");
function coerceSourceList(sources) {
  if (Array.isArray(sources))
    return sources.filter(Boolean);
  if (sources && typeof sources === "object")
    return [sources];
  return [];
}
__name(coerceSourceList, "coerceSourceList");
function resolvePublicSource({ d1Sources, kvSource, clearedAt }) {
  const d1 = Array.isArray(d1Sources) ? d1Sources.filter(Boolean) : [];
  if (d1.length > 0) {
    return { source: d1[0], sources: d1, cleared: false, from: "d1" };
  }
  if (clearedAt) {
    return { source: null, sources: [], cleared: true, from: "tombstone" };
  }
  if (kvSource && typeof kvSource === "object") {
    return { source: kvSource, sources: [kvSource], cleared: false, from: "kv" };
  }
  return { source: null, sources: [], cleared: false, from: "none" };
}
__name(resolvePublicSource, "resolvePublicSource");
async function markSourcesCleared(env, mac, now = Date.now()) {
  if (!env || !env.DB)
    return;
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS device_source_clears (mac TEXT PRIMARY KEY, cleared_at INTEGER NOT NULL)"
  ).run();
  await env.DB.prepare(
    "INSERT INTO device_source_clears (mac, cleared_at) VALUES (?, ?) ON CONFLICT(mac) DO UPDATE SET cleared_at = excluded.cleared_at"
  ).bind(mac, now).run();
  await scrubKvPlaylists(env, mac);
}
__name(markSourcesCleared, "markSourcesCleared");
async function clearSourceTombstone(env, mac) {
  if (!env || !env.DB)
    return;
  try {
    await env.DB.prepare("DELETE FROM device_source_clears WHERE mac = ?").bind(mac).run();
  } catch (_) {
  }
}
__name(clearSourceTombstone, "clearSourceTombstone");
async function readSourceTombstone(env, mac) {
  if (!env || !env.DB)
    return 0;
  try {
    const row = await env.DB.prepare(
      "SELECT cleared_at FROM device_source_clears WHERE mac = ?"
    ).bind(mac).first();
    return row && row.cleared_at ? Number(row.cleared_at) : 0;
  } catch (_) {
    return 0;
  }
}
__name(readSourceTombstone, "readSourceTombstone");
async function scrubKvPlaylists(env, mac) {
  const kv = env && env.KV_7MOTION;
  if (!kv || typeof kv.get !== "function" || typeof kv.put !== "function")
    return;
  try {
    const raw = await kv.get("client:" + mac);
    if (!raw)
      return;
    const data = JSON.parse(raw);
    if (!data || !Array.isArray(data.playlists) || data.playlists.length === 0)
      return;
    data.playlists = [];
    data.updated_at = Date.now();
    await kv.put("client:" + mac, JSON.stringify(data));
  } catch (_) {
  }
}
__name(scrubKvPlaylists, "scrubKvPlaylists");

// box_orders.js
var ORDER_STATES = Object.freeze({
  CREATED: "created",
  SENT: "sent",
  RECEIVED: "received",
  APPLIED: "applied",
  FAILED: "failed",
  EXPIRED: "expired"
});
var ORDER_TTL_MS = 10 * 60 * 1e3;
var RANK = { created: 0, sent: 1, received: 2, applied: 3, failed: 3, expired: 3 };
var ORDER_ID_RX = /^ord_[A-Za-z0-9-]{8,64}$/;
var ACK_STATES = /* @__PURE__ */ new Set(["received", "applied", "failed"]);
var ORDER_TRANSITIONS = Object.freeze({
  created: ["sent", "received", "applied", "failed", "expired"],
  sent: ["received", "applied", "failed", "expired"],
  received: ["applied", "failed", "expired"],
  expired: ["applied", "failed"],
  applied: [],
  failed: []
});
function canTransition(from, to) {
  const allowed = ORDER_TRANSITIONS[from];
  return !!(allowed && allowed.includes(to));
}
__name(canTransition, "canTransition");
function nextOrderState(current, incoming) {
  return canTransition(current, incoming) ? incoming : current;
}
__name(nextOrderState, "nextOrderState");
function opForKind(kind) {
  switch (kind) {
    case "activate":
      return "activation";
    case "renew":
      return "renewal";
    case "source":
    case "source_clear":
      return "source";
    case "reset":
      return "reset";
    default:
      return String(kind || "");
  }
}
__name(opForKind, "opForKind");
function effectiveState(row, now = Date.now()) {
  const state = String(row && row.state || "");
  if (RANK[state] === void 0)
    return state;
  if (RANK[state] >= 3)
    return state;
  const created = Number(row.created_at) || 0;
  return created > 0 && now - created > ORDER_TTL_MS ? ORDER_STATES.EXPIRED : state;
}
__name(effectiveState, "effectiveState");
function redactError(text) {
  if (text == null)
    return null;
  let s = String(text).slice(0, 600);
  s = s.replace(/([?&](?:username|password|user|pass|token|key)=)[^&\s"']*/gi, "$1***");
  s = s.replace(/(https?:\/\/)[^/\s:@]+:[^/\s@]+@/gi, "$1***@");
  s = s.replace(/(https?:\/\/[^\s?#"']+)\?[^\s"']*/gi, "$1?***");
  return s.slice(0, 300);
}
__name(redactError, "redactError");
function validateAck(raw) {
  if (!raw || typeof raw !== "object")
    return { error: "ack object required" };
  const orderId = String(raw.order_id || "");
  if (!ORDER_ID_RX.test(orderId))
    return { error: "bad order_id" };
  const state = String(raw.state || "").toLowerCase();
  if (!ACK_STATES.has(state))
    return { error: "state must be received, applied or failed" };
  const num2 = /* @__PURE__ */ __name((v) => Number.isFinite(Number(v)) && Number(v) > 0 ? Math.floor(Number(v)) : null, "num");
  const short = /* @__PURE__ */ __name((v, n) => v == null ? null : String(v).replace(/[\u0000-\u001f]/g, " ").slice(0, n), "short");
  return {
    ack: {
      order_id: orderId,
      state,
      received_at: num2(raw.received_at),
      applied_at: num2(raw.applied_at),
      config_rev: num2(raw.config_rev),
      result: short(raw.result, 60),
      error_code: short(raw.error_code, 60),
      error_message: redactError(raw.error_message),
      trace_id: short(raw.trace_id, 64),
      app_version: short(raw.app_version, 40)
    }
  };
}
__name(validateAck, "validateAck");
function percentile(values, p) {
  const v = values.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  if (!v.length)
    return null;
  const idx = Math.min(v.length - 1, Math.max(0, Math.ceil(p / 100 * v.length) - 1));
  return v[idx];
}
__name(percentile, "percentile");
function latencySummary(rows) {
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
    end_to_end: (r) => diff(r.applied_srv, r.t1_api)
  };
  const byOp = {};
  for (const row of rows || []) {
    const op = row.op || opForKind(row.kind);
    if (!byOp[op])
      byOp[op] = { n: 0, states: {}, segments: {} };
    const o = byOp[op];
    o.n += 1;
    const st = effectiveState(row);
    o.states[st] = (o.states[st] || 0) + 1;
    for (const [name, fn] of Object.entries(segs)) {
      const d = fn(row);
      if (d == null)
        continue;
      (o.segments[name] = o.segments[name] || []).push(d);
    }
  }
  const out = {};
  for (const [op, o] of Object.entries(byOp)) {
    const segments = {};
    for (const name of Object.keys(segs)) {
      const vals = o.segments[name] || [];
      segments[name] = vals.length ? { n: vals.length, p50: percentile(vals, 50), p95: percentile(vals, 95), p99: percentile(vals, 99) } : { n: 0, p50: null, p95: null, p99: null };
    }
    out[op] = { orders: o.n, states: o.states, segments };
  }
  return out;
}
__name(latencySummary, "latencySummary");
function diff(a, b) {
  const x = Number(a);
  const y = Number(b);
  if (!Number.isFinite(x) || !Number.isFinite(y) || x <= 0 || y <= 0)
    return null;
  const d = x - y;
  return d >= 0 ? d : null;
}
__name(diff, "diff");
var _ready = /* @__PURE__ */ new WeakSet();
async function ensureOrderTables(env) {
  if (!env || !env.DB || _ready.has(env.DB))
    return;
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS box_orders (order_id TEXT PRIMARY KEY, mac TEXT NOT NULL, customer_id TEXT, device_id TEXT, kind TEXT NOT NULL, op TEXT, trace_id TEXT, seq INTEGER, config_rev INTEGER, state TEXT NOT NULL, t0_client INTEGER, t1_api INTEGER, t2_commit INTEGER, t3_published INTEGER, received_at INTEGER, received_srv INTEGER, applied_at INTEGER, applied_srv INTEGER, failed_at INTEGER, failed_srv INTEGER, late_ack INTEGER NOT NULL DEFAULT 0, result TEXT, error_code TEXT, error_message TEXT, applied_rev INTEGER, app_version TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
  ).run();
  for (const col of [
    "customer_id TEXT",
    "device_id TEXT",
    "failed_at INTEGER",
    "failed_srv INTEGER",
    "late_ack INTEGER NOT NULL DEFAULT 0"
  ]) {
    try {
      await env.DB.prepare(`ALTER TABLE box_orders ADD COLUMN ${col}`).run();
    } catch (_) {
    }
  }
  await env.DB.prepare("CREATE INDEX IF NOT EXISTS idx_box_orders_mac ON box_orders(mac, created_at)").run();
  await env.DB.prepare("CREATE INDEX IF NOT EXISTS idx_box_orders_trace ON box_orders(trace_id)").run();
  await env.DB.prepare("CREATE INDEX IF NOT EXISTS idx_box_orders_created ON box_orders(created_at)").run();
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS source_revisions (mac TEXT NOT NULL, rev INTEGER NOT NULL, state TEXT NOT NULL, panel_json TEXT NOT NULL, item_count INTEGER NOT NULL, hosts TEXT, trace_id TEXT, actor_type TEXT, actor_id TEXT, rollback_of INTEGER, validated_at INTEGER, published_at INTEGER, acked_at INTEGER, ack_result TEXT, ack_error TEXT, created_at INTEGER NOT NULL, PRIMARY KEY (mac, rev))"
  ).run();
  _ready.add(env.DB);
}
__name(ensureOrderTables, "ensureOrderTables");
function newOrderId() {
  return `ord_${crypto.randomUUID()}`;
}
__name(newOrderId, "newOrderId");
async function createOrder(env, { mac, kind, traceId, t0, t1, t2, configRev }) {
  if (!env || !env.DB)
    return null;
  try {
    await ensureOrderTables(env);
    const orderId = newOrderId();
    const now = Date.now();
    await env.DB.prepare(
      "INSERT INTO box_orders (order_id, mac, customer_id, device_id, kind, op, trace_id, config_rev, state, t0_client, t1_api, t2_commit, created_at, updated_at) VALUES (?, ?, (SELECT customer_id FROM devices WHERE mac = ?), (SELECT id FROM devices WHERE mac = ?), ?, ?, ?, ?, 'created', ?, ?, ?, ?, ?)"
    ).bind(
      orderId,
      mac,
      mac,
      mac,
      kind,
      opForKind(kind),
      traceId || null,
      configRev || null,
      t0 || null,
      t1 || null,
      t2 || now,
      now,
      now
    ).run();
    return orderId;
  } catch (_) {
    return null;
  }
}
__name(createOrder, "createOrder");
async function markOrderSent(env, orderId, seq, t3 = Date.now()) {
  if (!env || !env.DB || !orderId)
    return;
  try {
    await env.DB.prepare(
      "UPDATE box_orders SET seq = COALESCE(seq, ?), t3_published = COALESCE(t3_published, ?), state = CASE WHEN state = 'created' THEN 'sent' ELSE state END, updated_at = ? WHERE order_id = ?"
    ).bind(seq || null, t3, t3, orderId).run();
  } catch (_) {
  }
}
__name(markOrderSent, "markOrderSent");
async function recordAck(env, mac, raw, now = Date.now()) {
  const v = validateAck(raw);
  if (v.error) {
    logAck("rejected", { mac, reason: v.error });
    return { status: 400, body: { error: "bad_ack", message: v.error } };
  }
  const ack = v.ack;
  await ensureOrderTables(env);
  const row = await env.DB.prepare("SELECT * FROM box_orders WHERE order_id = ?").bind(ack.order_id).first();
  if (!row || row.mac !== mac) {
    logAck("unknown_order", { mac, order_id: ack.order_id });
    return { status: 404, body: { error: "unknown_order" } };
  }
  const current = effectiveState(row, now);
  const next = nextOrderState(current, ack.state);
  if (next === current) {
    if (current !== ack.state)
      logAck("transition_refused", { order_id: ack.order_id, from: current, to: ack.state });
    return { status: 200, body: { ok: true, order_id: ack.order_id, state: current, changed: false } };
  }
  const late = current === "expired" ? 1 : 0;
  const isApplied = next === "applied";
  const isFailed = next === "failed";
  const upd = await env.DB.prepare(
    "UPDATE box_orders SET state = ?, late_ack = MAX(late_ack, ?), received_at = COALESCE(received_at, ?), received_srv = COALESCE(received_srv, ?), applied_at = CASE WHEN ? THEN COALESCE(?, applied_at) ELSE applied_at END, applied_srv = CASE WHEN ? THEN ? ELSE applied_srv END, failed_at = CASE WHEN ? THEN COALESCE(?, failed_at) ELSE failed_at END, failed_srv = CASE WHEN ? THEN ? ELSE failed_srv END, result = COALESCE(?, result), error_code = COALESCE(?, error_code), error_message = COALESCE(?, error_message), applied_rev = COALESCE(?, applied_rev), app_version = COALESCE(?, app_version), updated_at = ? WHERE order_id = ? AND state = ?"
  ).bind(
    next,
    late,
    ack.received_at || ack.applied_at,
    now,
    isApplied ? 1 : 0,
    ack.applied_at,
    isApplied ? 1 : 0,
    now,
    isFailed ? 1 : 0,
    ack.applied_at || ack.received_at,
    isFailed ? 1 : 0,
    now,
    ack.result,
    ack.error_code,
    ack.error_message,
    ack.config_rev,
    ack.app_version,
    now,
    ack.order_id,
    row.state
  ).run();
  if (!(upd && upd.meta && upd.meta.changes === 1)) {
    const fresh = await env.DB.prepare("SELECT state FROM box_orders WHERE order_id = ?").bind(ack.order_id).first();
    return { status: 200, body: { ok: true, order_id: ack.order_id, state: fresh ? fresh.state : current, changed: false } };
  }
  if ((isApplied || isFailed) && ack.config_rev && (row.kind === "source" || row.kind === "source_clear" || row.kind === "reset")) {
    await markRevisionAck(
      env,
      mac,
      ack.config_rev,
      isApplied && ack.result !== "refused",
      ack.result,
      ack.error_message,
      now
    );
  }
  return { status: 200, body: { ok: true, order_id: ack.order_id, state: next, changed: true, late_ack: !!late } };
}
__name(recordAck, "recordAck");
function logAck(event, detail) {
  try {
    console.log(JSON.stringify({ level: "warn", source: "box_ack", event, ...detail }));
  } catch (_) {
  }
}
__name(logAck, "logAck");
async function listOrders(env, { macs = [], traceId = null, since = 0, limit = 200 }) {
  await ensureOrderTables(env);
  const now = Date.now();
  let rows = [];
  if (traceId) {
    rows = (await env.DB.prepare("SELECT * FROM box_orders WHERE trace_id = ? ORDER BY created_at ASC LIMIT ?").bind(traceId, limit).all()).results || [];
  } else if (macs.length) {
    const marks = macs.map(() => "?").join(",");
    rows = (await env.DB.prepare(
      `SELECT * FROM box_orders WHERE mac IN (${marks}) AND created_at >= ? ORDER BY created_at DESC LIMIT ?`
    ).bind(...macs, since, limit).all()).results || [];
  }
  const expired = rows.filter((r) => effectiveState(r, now) === "expired" && r.state !== "expired");
  for (const r of expired) {
    try {
      await env.DB.prepare("UPDATE box_orders SET state = 'expired', updated_at = ? WHERE order_id = ? AND state = ?").bind(now, r.order_id, r.state).run();
      r.state = "expired";
    } catch (_) {
    }
  }
  return rows;
}
__name(listOrders, "listOrders");
async function latencyStats(env, sinceMs) {
  await ensureOrderTables(env);
  const rows = (await env.DB.prepare(
    "SELECT kind, op, state, created_at, t0_client, t1_api, t2_commit, t3_published, received_srv, applied_srv, failed_srv, received_at, applied_at FROM box_orders WHERE created_at >= ?"
  ).bind(sinceMs).all()).results || [];
  return latencySummary(rows);
}
__name(latencyStats, "latencyStats");
async function markRevisionAck(env, mac, rev, ok, result, error, now = Date.now()) {
  try {
    await env.DB.prepare(
      "UPDATE source_revisions SET state = ?, acked_at = ?, ack_result = ?, ack_error = ? WHERE mac = ? AND rev = ? AND state = 'published'"
    ).bind(ok ? "acknowledged" : "rejected_by_box", now, result || null, error || null, mac, rev).run();
  } catch (_) {
  }
}
__name(markRevisionAck, "markRevisionAck");
async function revisionView(env, mac) {
  await ensureOrderTables(env);
  const rows = (await env.DB.prepare(
    "SELECT rev, state, item_count, hosts, trace_id, actor_type, rollback_of, validated_at, published_at, acked_at, ack_result, ack_error, created_at FROM source_revisions WHERE mac = ? ORDER BY rev DESC LIMIT 50"
  ).bind(mac).all()).results || [];
  return summarizeRevisions(rows);
}
__name(revisionView, "revisionView");
function summarizeRevisions(rows) {
  const list = (rows || []).map((r) => ({
    ...r,
    hosts: (() => {
      try {
        return JSON.parse(r.hosts || "[]");
      } catch (_) {
        return [];
      }
    })()
  }));
  const current = list.length ? list[0] : null;
  const lastGood = list.find((r) => r.state === "acknowledged") || null;
  return {
    current_revision: current ? current.rev : null,
    current_state: current ? current.state : null,
    last_good_revision: lastGood ? lastGood.rev : null,
    rollback_available: !!(lastGood && current && lastGood.rev !== current.rev),
    revisions: list
  };
}
__name(summarizeRevisions, "summarizeRevisions");
async function revisionPanelJson(env, mac, rev) {
  await ensureOrderTables(env);
  const row = await env.DB.prepare("SELECT panel_json, state FROM source_revisions WHERE mac = ? AND rev = ?").bind(mac, rev).first();
  return row || null;
}
__name(revisionPanelJson, "revisionPanelJson");
async function currentRevision(env, mac) {
  try {
    await ensureOrderTables(env);
    const row = await env.DB.prepare("SELECT MAX(rev) AS r FROM source_revisions WHERE mac = ?").bind(mac).first();
    return row && row.r ? Number(row.r) : null;
  } catch (_) {
    return null;
  }
}
__name(currentRevision, "currentRevision");

// box_channel.js
var CHANNEL_KINDS = Object.freeze([
  "source",
  "source_clear",
  "activate",
  "renew",
  "expire",
  "suspend",
  "resume",
  "block",
  "license",
  "transfer",
  "device_delete",
  "message",
  "theme",
  "home",
  "force_update",
  "featured",
  "ad",
  "pricing",
  "feedback",
  "servers",
  "banner",
  // Remise à neuf de la box depuis le panel (06/10/2026) : la box relit
  // son statut, y lit `reset_at`, efface tout, puis relit ses listes.
  "reset"
]);
var KIND_SET = new Set(CHANNEL_KINDS);
var MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/;
var RING_MAX = 32;
var HOLD_DEFAULT_MS = 20 * 1e3;
var HOLD_MIN_MS = 200;
var HOLD_MAX_MS = 20 * 1e3;
var PANEL_NAME = "panel-v1";
function realtimePushOff(env) {
  return !!(env && String(env.REALTIME_PUSH_OFF) === "1");
}
__name(realtimePushOff, "realtimePushOff");
function normalizeMac(raw) {
  let text = "";
  try {
    text = decodeURIComponent(String(raw || ""));
  } catch (_) {
    text = String(raw || "");
  }
  const mac = text.trim().toUpperCase();
  return MAC_RX.test(mac) ? mac : "";
}
__name(normalizeMac, "normalizeMac");
function canonicalKind(raw) {
  const kind = String(raw || "").trim();
  return KIND_SET.has(kind) ? kind : "";
}
__name(canonicalKind, "canonicalKind");
function clampTimeout(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n))
    return HOLD_DEFAULT_MS;
  if (n < HOLD_MIN_MS)
    return HOLD_MIN_MS;
  if (n > HOLD_MAX_MS)
    return HOLD_MAX_MS;
  return Math.floor(n);
}
__name(clampTimeout, "clampTimeout");
function eventsAfter(ring, after) {
  const cursor = Number(after);
  const min = Number.isFinite(cursor) ? cursor : 0;
  const out = [];
  for (const item of ring || []) {
    if (!item || typeof item !== "object")
      continue;
    const seq = Number(item.seq);
    if (!Number.isFinite(seq) || seq <= min)
      continue;
    out.push(item);
  }
  return out;
}
__name(eventsAfter, "eventsAfter");
function publicEvent(event) {
  const out = {
    v: 1,
    seq: Number(event.seq) || 0,
    type: String(event.type || ""),
    mac: String(event.mac || ""),
    at: Number(event.at) || 0
  };
  if (safeId(event.order_id))
    out.order_id = event.order_id;
  if (safeId(event.trace_id))
    out.trace_id = event.trace_id;
  return out;
}
__name(publicEvent, "publicEvent");
function safeId(v) {
  return typeof v === "string" && /^[A-Za-z0-9_.:-]{8,80}$/.test(v);
}
__name(safeId, "safeId");
function waitBody(events, timeout) {
  const list = Array.isArray(events) ? events.map(publicEvent) : [];
  return {
    v: 1,
    timeout: timeout === true,
    box: list.map((event) => ({
      id: event.seq,
      kind: event.type,
      created_at: event.at,
      ...event.order_id ? { order_id: event.order_id } : {},
      ...event.trace_id ? { trace_id: event.trace_id } : {}
    })),
    fleet: [],
    events: list
  };
}
__name(waitBody, "waitBody");
var SECRET_KEYS = /* @__PURE__ */ new Set([
  "password",
  "username",
  "server_url",
  "m3u_url",
  "epg_url",
  "secret",
  "token"
]);
function containsSecretKey(value) {
  if (!value || typeof value !== "object")
    return false;
  for (const [key, child] of Object.entries(value)) {
    if (SECRET_KEYS.has(String(key).toLowerCase()))
      return true;
    if (containsSecretKey(child))
      return true;
  }
  return false;
}
__name(containsSecretKey, "containsSecretKey");
function panelMaySee(actor, deviceResellerId2) {
  if (!actor || !actor.role)
    return false;
  if (actor.role !== "reseller")
    return true;
  if (!actor.id || !deviceResellerId2)
    return false;
  return String(deviceResellerId2) === String(actor.id);
}
__name(panelMaySee, "panelMaySee");
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" }
  });
}
__name(json, "json");
function createMacMailbox(storage) {
  const waiters = [];
  let chain = Promise.resolve();
  function enqueue(fn) {
    const run = chain.then(fn, fn);
    chain = run.then(() => {
    }, () => {
    });
    return run;
  }
  __name(enqueue, "enqueue");
  async function readRing() {
    const ring = await storage.get("ring");
    return Array.isArray(ring) ? ring : [];
  }
  __name(readRing, "readRing");
  async function since(after) {
    return eventsAfter(await readRing(), after);
  }
  __name(since, "since");
  async function push(kind, mac, ids = {}) {
    const type = canonicalKind(kind);
    const clean = normalizeMac(mac);
    if (!type || !clean)
      return null;
    const event = await enqueue(async () => {
      const seq = (Number(await storage.get("seq")) || 0) + 1;
      const ring = eventsAfter(await storage.get("ring"), 0);
      const next = { v: 1, seq, type, mac: clean, at: Date.now() };
      if (safeId(ids.order_id))
        next.order_id = ids.order_id;
      if (safeId(ids.trace_id))
        next.trace_id = ids.trace_id;
      ring.push(next);
      while (ring.length > RING_MAX)
        ring.shift();
      await storage.put("seq", seq);
      await storage.put("ring", ring);
      return next;
    });
    const pending = waiters.splice(0, waiters.length);
    for (const waiter of pending) {
      waiter.done = true;
      clearTimeout(waiter.timer);
      const fresh = await since(waiter.after);
      waiter.resolve(waitBody(fresh.length ? fresh : [event], false));
    }
    return event;
  }
  __name(push, "push");
  function wait(after, timeoutMs) {
    const limit = clampTimeout(timeoutMs);
    return since(after).then((first) => {
      if (first.length)
        return waitBody(first, false);
      return new Promise((resolve) => {
        const waiter = { after: Number(after) || 0, resolve, done: false, timer: null };
        waiter.timer = setTimeout(() => {
          if (waiter.done)
            return;
          waiter.done = true;
          const idx = waiters.indexOf(waiter);
          if (idx >= 0)
            waiters.splice(idx, 1);
          resolve(waitBody([], true));
        }, limit);
        waiters.push(waiter);
        since(after).then((second) => {
          if (waiter.done || !second.length)
            return;
          waiter.done = true;
          clearTimeout(waiter.timer);
          const idx = waiters.indexOf(waiter);
          if (idx >= 0)
            waiters.splice(idx, 1);
          resolve(waitBody(second, false));
        });
      });
    });
  }
  __name(wait, "wait");
  return { push, since, wait };
}
__name(createMacMailbox, "createMacMailbox");
function stub(env, name) {
  if (!env || !env.RT_HUB || typeof env.RT_HUB.idFromName !== "function")
    return null;
  return env.RT_HUB.get(env.RT_HUB.idFromName(name));
}
__name(stub, "stub");
async function notifyBox(env, mac, kind, opts = {}) {
  let orderId = null;
  try {
    const clean = normalizeMac(mac);
    const type = canonicalKind(kind);
    if (!clean || !type)
      return null;
    orderId = await createOrder(env, {
      mac: clean,
      kind: type,
      traceId: opts.traceId,
      t0: opts.t0,
      t1: opts.t1,
      t2: opts.t2 || Date.now(),
      configRev: opts.configRev
    });
    if (realtimePushOff(env))
      return orderId;
    const ids = { order_id: orderId || void 0, trace_id: opts.traceId || void 0 };
    const body = JSON.stringify({ kind: type, mac: clean, ...ids });
    const macStub = stub(env, clean);
    const panelStub = stub(env, PANEL_NAME);
    if (macStub) {
      try {
        const res = await macStub.fetch("https://hub/notify", { method: "POST", body });
        let seq = null;
        try {
          seq = (await res.json()).seq || null;
        } catch (_) {
          seq = null;
        }
        if (res.ok && orderId)
          await markOrderSent(env, orderId, seq);
      } catch (_) {
      }
    }
    if (panelStub) {
      try {
        await panelStub.fetch("https://hub/fanout", { method: "POST", body });
      } catch (_) {
      }
    }
  } catch (_) {
  }
  return orderId;
}
__name(notifyBox, "notifyBox");
function notFound() {
  return json({ error: "not_found" }, 404);
}
__name(notFound, "notFound");
async function handleBoxRoute(request, env, segments) {
  if (!segments || segments[0] !== "api" || segments[1] !== "box")
    return null;
  const action = segments[2] || "";
  if (action !== "ws" && action !== "wait" && action !== "ack")
    return null;
  if (action === "ack") {
    if (request.method !== "POST")
      return json({ error: "method" }, 405);
    const ackMac = normalizeMac(segments[3] || new URL(request.url).searchParams.get("mac"));
    if (!ackMac)
      return json({ error: "bad_mac" }, 400);
    let payload = null;
    try {
      payload = await request.json();
    } catch (_) {
      payload = null;
    }
    const list = payload && Array.isArray(payload.orders) ? payload.orders.slice(0, 20) : null;
    if (!list || !env || !env.DB)
      return json({ ok: true });
    const results = [];
    for (const item of list) {
      try {
        const r = await recordAck(env, ackMac, item);
        results.push({ order_id: item && item.order_id, status: r.status, ...r.body });
      } catch (_) {
        results.push({ order_id: item && item.order_id, status: 500, error: "ack_failed" });
      }
    }
    return json({ ok: true, results });
  }
  if (realtimePushOff(env) || !env || !env.RT_HUB)
    return notFound();
  const url = new URL(request.url);
  if (action === "ws") {
    if (request.method !== "GET")
      return json({ error: "method" }, 405);
    if (request.headers.get("Upgrade") !== "websocket") {
      return json({ error: "upgrade_required" }, 426);
    }
    const mac2 = normalizeMac(url.searchParams.get("mac"));
    if (!mac2)
      return json({ error: "bad_mac" }, 400);
    const target2 = stub(env, mac2);
    if (!target2)
      return notFound();
    return target2.fetch(request);
  }
  const mac = normalizeMac(segments[3] || url.searchParams.get("mac"));
  if (!mac)
    return json({ error: "bad_mac" }, 400);
  const target = stub(env, mac);
  if (!target)
    return notFound();
  if (request.method !== "GET")
    return json({ error: "method" }, 405);
  const after = url.searchParams.get("after") || "0";
  const timeout = url.searchParams.get("timeout") || "";
  const inner = new URL("https://hub/wait");
  inner.searchParams.set("after", after);
  inner.searchParams.set("timeout", timeout);
  return target.fetch(new Request(inner.toString(), { method: "GET" }));
}
__name(handleBoxRoute, "handleBoxRoute");
function openPanelSocket(request, env, actor) {
  if (realtimePushOff(env) || !env || !env.RT_HUB)
    return notFound();
  if (!actor || !actor.id || !actor.role)
    return json({ error: "no_auth" }, 401);
  if (request.headers.get("Upgrade") !== "websocket") {
    return json({ error: "upgrade_required" }, 426);
  }
  const target = stub(env, PANEL_NAME);
  if (!target)
    return notFound();
  const headers = new Headers(request.headers);
  headers.set("X-Panel-Role", String(actor.role));
  headers.set("X-Panel-Id", String(actor.id));
  const forwarded = new Request(request.url, { method: request.method, headers });
  return target.fetch(forwarded);
}
__name(openPanelSocket, "openPanelSocket");
async function deviceResellerId(env, mac) {
  if (!env || !env.DB)
    return "";
  try {
    const row = await env.DB.prepare("SELECT reseller_id FROM devices WHERE mac = ?").bind(mac).first();
    return row && row.reseller_id ? String(row.reseller_id) : "";
  } catch (_) {
    return "";
  }
}
__name(deviceResellerId, "deviceResellerId");
var RealtimeHub = class {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.mailbox = createMacMailbox(ctx.storage);
  }
  async fetch(request) {
    const url = new URL(request.url);
    if (request.headers.get("Upgrade") === "websocket") {
      return this.#socket(request);
    }
    if (url.pathname === "/notify" && request.method === "POST") {
      return this.#notify(request, false);
    }
    if (url.pathname === "/fanout" && request.method === "POST") {
      return this.#notify(request, true);
    }
    if (url.pathname === "/wait" && request.method === "GET") {
      const body = await this.mailbox.wait(
        url.searchParams.get("after"),
        url.searchParams.get("timeout")
      );
      if (containsSecretKey(body))
        return json({ error: "blocked" }, 500);
      return json(body);
    }
    return notFound();
  }
  async #notify(request, fanout) {
    let payload = {};
    try {
      payload = await request.json();
    } catch (_) {
      return json({ error: "bad_json" }, 400);
    }
    const event = await this.mailbox.push(payload.kind, payload.mac, {
      order_id: payload.order_id,
      trace_id: payload.trace_id
    });
    if (!event)
      return json({ error: "ignored" }, 400);
    const text = JSON.stringify(publicEvent(event));
    if (containsSecretKey(JSON.parse(text)))
      return json({ error: "blocked" }, 500);
    if (fanout)
      await this.#sendPanel(text, event.mac);
    else
      this.#sendAll(text);
    return json({ ok: true, seq: event.seq });
  }
  #sendAll(text) {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(text);
      } catch (_) {
      }
    }
  }
  async #sendPanel(text, mac) {
    const resellerId = await deviceResellerId(this.env, mac);
    for (const ws of this.ctx.getWebSockets()) {
      let att = {};
      try {
        att = ws.deserializeAttachment() || {};
      } catch (_) {
        att = {};
      }
      const allowed = panelMaySee(
        { id: att.id, role: att.role },
        resellerId
      );
      if (!allowed)
        continue;
      try {
        ws.send(text);
      } catch (_) {
      }
    }
  }
  #socket(request) {
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.ctx.acceptWebSocket(server);
    const role = request.headers.get("X-Panel-Role") || "";
    const id = request.headers.get("X-Panel-Id") || "";
    if (role && id) {
      server.serializeAttachment({ role, id });
    } else {
      server.serializeAttachment({ role: "box" });
    }
    this.mailbox.since(0).then((events) => {
      const last = events.length ? events[events.length - 1] : null;
      if (!last)
        return;
      try {
        server.send(JSON.stringify(publicEvent(last)));
      } catch (_) {
      }
    });
    return new Response(null, { status: 101, webSocket: client });
  }
  async webSocketMessage(ws, message) {
    let hello = false;
    try {
      const text = typeof message === "string" ? message : "";
      const parsed = JSON.parse(text);
      hello = !!(parsed && parsed.type === "hello" && !containsSecretKey(parsed));
    } catch (_) {
      hello = false;
    }
    if (!hello)
      return;
    try {
      ws.send(JSON.stringify({ v: 1, type: "hello" }));
    } catch (_) {
    }
  }
  async webSocketClose() {
  }
  async webSocketError(ws) {
    try {
      ws.close(1011, "error");
    } catch (_) {
    }
  }
};
__name(RealtimeHub, "RealtimeHub");

// blackbox_journal.js
var BLACKBOX_MAX_BYTES = 32 * 1024;
var MAC_RX2 = /^MK(?::[0-9A-F]{2}){5}$/i;
function isBlackboxMac(mac) {
  return typeof mac === "string" && MAC_RX2.test(mac.trim());
}
__name(isBlackboxMac, "isBlackboxMac");
function prepareBlackBoxText(raw, opts = {}) {
  const enabled = opts.enabled !== false;
  if (!enabled)
    return null;
  if (typeof raw !== "string")
    return null;
  const capped = raw.length > 256 * 1024 ? raw.slice(-256 * 1024) : raw;
  const max = opts.maxBytes || BLACKBOX_MAX_BYTES;
  const clean = truncateBlackBoxTail(redactBlackBox(capped), max);
  if (!clean.trim())
    return null;
  return clean;
}
__name(prepareBlackBoxText, "prepareBlackBoxText");
function redactBlackBox(input) {
  let text = String(input ?? "");
  const urlRe = /\b(?:https?|rtsps?|rtmps?|udp|rtp|mms|mmsh):\/\/[^\s<>"'()]+/gi;
  const userInfoRe = /\b[^:\s/@]{1,80}:[^:\s/@]{1,80}@[\w.-]+(?::\d+)?/g;
  const pathRe = /\/(live|movie|series)\/[^/\s]+\/[^/\s]+\//gi;
  const fieldRe = /\b(password|passwd|pwd|username|user|login|token|auth|pass)\b\s*[:=]\s*[^\s&,;]+/gi;
  const labelRe = /\b(utilisateur|identifiant)\b\s*[:=]?\s+\S+/gi;
  const emailRe = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi;
  text = text.replace(urlRe, "[lien]");
  text = text.replace(userInfoRe, "[identifiants]");
  text = text.replace(pathRe, (_, kind) => `/${kind}/[masqu\xE9]/[masqu\xE9]/`);
  text = text.replace(fieldRe, (_, key) => `${key}=[masqu\xE9]`);
  text = text.replace(labelRe, (_, word) => `${word} [masqu\xE9]`);
  text = text.replace(emailRe, "[identifiant]");
  return text;
}
__name(redactBlackBox, "redactBlackBox");
function truncateBlackBoxTail(text, maxBytes) {
  if (maxBytes <= 0)
    return "";
  const enc = new TextEncoder();
  const dec = new TextDecoder("utf-8", { fatal: false });
  const bytes = enc.encode(text);
  if (bytes.length <= maxBytes)
    return text;
  let slice = bytes.subarray(bytes.length - maxBytes);
  let i = 0;
  while (i < slice.length && (slice[i] & 192) === 128)
    i += 1;
  if (i > 0)
    slice = slice.subarray(i);
  let s = dec.decode(slice);
  const nl = s.indexOf("\n");
  if (nl >= 0 && nl < s.length - 1)
    s = s.slice(nl + 1);
  return s;
}
__name(truncateBlackBoxTail, "truncateBlackBoxTail");
var tableReady = /* @__PURE__ */ new WeakSet();
async function ensureBlackboxTable(env) {
  if (!env || !env.DB || tableReady.has(env.DB))
    return;
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS device_blackbox (mac TEXT PRIMARY KEY, body TEXT NOT NULL, updated_at INTEGER NOT NULL, requested_at INTEGER NOT NULL DEFAULT 0)"
  ).run();
  tableReady.add(env.DB);
}
__name(ensureBlackboxTable, "ensureBlackboxTable");
async function saveBlackBox(env, mac, text, now = Date.now()) {
  if (!env || !env.DB)
    return { error: "no_db" };
  const clean = prepareBlackBoxText(text, { enabled: true });
  if (clean == null)
    return { error: "empty" };
  await ensureBlackboxTable(env);
  await env.DB.prepare(
    "INSERT INTO device_blackbox (mac, body, updated_at, requested_at) VALUES (?, ?, ?, 0) ON CONFLICT(mac) DO UPDATE SET body = excluded.body, updated_at = excluded.updated_at"
  ).bind(mac, clean, now).run();
  return { updated_at: now };
}
__name(saveBlackBox, "saveBlackBox");
async function readBlackBox(env, mac) {
  if (!env || !env.DB)
    return { body: "", updated_at: 0 };
  try {
    await ensureBlackboxTable(env);
    const row = await env.DB.prepare(
      "SELECT body, updated_at FROM device_blackbox WHERE mac = ?"
    ).bind(mac).first();
    if (!row)
      return { body: "", updated_at: 0 };
    return {
      body: typeof row.body === "string" ? row.body : "",
      updated_at: Number(row.updated_at) || 0
    };
  } catch (_) {
    return { body: "", updated_at: 0 };
  }
}
__name(readBlackBox, "readBlackBox");
async function blackboxRequestedAt(env, mac) {
  if (!env || !env.DB || !mac)
    return 0;
  try {
    await ensureBlackboxTable(env);
    const row = await env.DB.prepare(
      "SELECT requested_at FROM device_blackbox WHERE mac = ?"
    ).bind(mac).first();
    return row && row.requested_at ? Number(row.requested_at) : 0;
  } catch (_) {
    return 0;
  }
}
__name(blackboxRequestedAt, "blackboxRequestedAt");
async function markBlackBoxAsked(env, mac, now = Date.now()) {
  if (!env || !env.DB)
    return 0;
  await ensureBlackboxTable(env);
  await env.DB.prepare(
    "INSERT INTO device_blackbox (mac, body, updated_at, requested_at) VALUES (?, '', 0, ?) ON CONFLICT(mac) DO UPDATE SET requested_at = excluded.requested_at"
  ).bind(mac, now).run();
  return now;
}
__name(markBlackBoxAsked, "markBlackBoxAsked");

// source_url.js
var MAX_SOURCE_URL = 2048;
function httpUrlError(value, label) {
  const s = String(value || "").trim();
  if (!s)
    return `${label} requis`;
  if (s.length > MAX_SOURCE_URL)
    return `${label} trop long`;
  let u;
  try {
    u = new URL(s);
  } catch (_) {
    return `${label} invalide`;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") {
    return `${label} doit commencer par http:// ou https://`;
  }
  if (!u.hostname)
    return `${label} invalide`;
  return null;
}
__name(httpUrlError, "httpUrlError");
var TYPOGRAPHIC_RX = /[‘’‚‛“”«»̀-ͯ –—]/;
var TYPOGRAPHIC_ENC_RX = /%E2%80%9[89ABCD]|%CC%8[0-9A-F]|%CD%[8-9A-F][0-9A-F]|%C2%A0|%E2%80%9[34]/i;
function sourceTextProblem(value, label) {
  const s = String(value || "");
  if (/[\s\u0000-\u001f]/.test(s.trim()))
    return `${label} contient un espace ou un caract\xE8re invisible`;
  if (TYPOGRAPHIC_RX.test(s) || TYPOGRAPHIC_ENC_RX.test(s)) {
    return `${label} contient un caract\xE8re de clavier de t\xE9l\xE9phone (\u2019 ou accent) : retape-le \xE0 la main`;
  }
  return null;
}
__name(sourceTextProblem, "sourceTextProblem");
function sourceUrlProblem(value, label) {
  const s = String(value || "").trim();
  const base = httpUrlError(s, label);
  if (base)
    return base;
  if ((s.match(/https?:\/\//gi) || []).length > 1)
    return `${label} : lien coll\xE9 deux fois`;
  return sourceTextProblem(s, label);
}
__name(sourceUrlProblem, "sourceUrlProblem");

// secret_box.js
var PREFIX = "enc1.";
var SECRET_FIELDS = ["password", "m3u_url"];
function b64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}
__name(b64url, "b64url");
function b64urlDecode(s) {
  s = String(s).replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4)
    s += "=";
  const raw = atob(s);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++)
    arr[i] = raw.charCodeAt(i);
  return arr;
}
__name(b64urlDecode, "b64urlDecode");
function encryptionKeyMaterial(env) {
  const raw = String(
    env && (env.SOURCE_ENCRYPTION_KEY || env.SECRETS_KEY) || ""
  ).trim();
  if (raw.length < 16)
    return "";
  return raw;
}
__name(encryptionKeyMaterial, "encryptionKeyMaterial");
async function aesKey(env) {
  const raw = encryptionKeyMaterial(env);
  if (!raw)
    return null;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(raw)
  );
  return crypto.subtle.importKey(
    "raw",
    digest,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"]
  );
}
__name(aesKey, "aesKey");
async function sealField(env, value) {
  if (typeof value !== "string" || !value)
    return value;
  if (value.startsWith(PREFIX))
    return value;
  const key = await aesKey(env);
  if (!key)
    return value;
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(value)
  ));
  return `${PREFIX}${b64url(iv)}.${b64url(ct)}`;
}
__name(sealField, "sealField");
function b64stdDecode(s) {
  const raw = atob(s);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++)
    arr[i] = raw.charCodeAt(i);
  return arr;
}
__name(b64stdDecode, "b64stdDecode");
async function openLegacyColon(env, value) {
  const key = await aesKey(env);
  if (!key)
    return null;
  try {
    const rest = value.slice("enc1:".length);
    const dot = rest.indexOf(".");
    if (dot < 1)
      return null;
    const iv = b64stdDecode(rest.slice(0, dot));
    const ct = b64stdDecode(rest.slice(dot + 1));
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      key,
      ct
    );
    return new TextDecoder().decode(plain);
  } catch (_) {
    return null;
  }
}
__name(openLegacyColon, "openLegacyColon");
async function openField(env, value) {
  if (typeof value !== "string" || !value)
    return value;
  if (value.startsWith("enc1:"))
    return openLegacyColon(env, value);
  if (!value.startsWith(PREFIX))
    return value;
  const key = await aesKey(env);
  if (!key)
    return null;
  try {
    const rest = value.slice(PREFIX.length);
    const dot = rest.indexOf(".");
    if (dot < 1)
      return null;
    const iv = b64urlDecode(rest.slice(0, dot));
    const ct = b64urlDecode(rest.slice(dot + 1));
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      key,
      ct
    );
    return new TextDecoder().decode(plain);
  } catch (_) {
    return null;
  }
}
__name(openField, "openField");
async function sealSource(env, source) {
  if (!source || typeof source !== "object")
    return source;
  const out = { ...source };
  for (const field of SECRET_FIELDS) {
    if (typeof out[field] === "string" && out[field]) {
      out[field] = await sealField(env, out[field]);
    }
  }
  return out;
}
__name(sealSource, "sealSource");
async function openSource(env, source) {
  if (!source || typeof source !== "object")
    return source;
  const out = { ...source };
  for (const field of SECRET_FIELDS) {
    if (typeof out[field] === "string" && out[field]) {
      out[field] = await openField(env, out[field]);
    }
  }
  return out;
}
__name(openSource, "openSource");
async function openSourceList(env, list) {
  if (!Array.isArray(list))
    return [];
  const out = [];
  for (const item of list)
    out.push(await openSource(env, item));
  return out;
}
__name(openSourceList, "openSourceList");

// device_sources_store.js
var _versionReady = /* @__PURE__ */ new WeakSet();
var STORE_COLUMNS = [
  "sources_json TEXT",
  "origin TEXT",
  "reseller_id TEXT",
  "version INTEGER NOT NULL DEFAULT 0"
];
async function ensureSourcesVersion(env) {
  if (!env || !env.DB || _versionReady.has(env.DB))
    return;
  for (const col of STORE_COLUMNS) {
    try {
      await env.DB.prepare(`ALTER TABLE device_sources ADD COLUMN ${col}`).run();
    } catch (_) {
    }
  }
  try {
    await env.DB.prepare("SELECT sources_json, origin, reseller_id, version FROM device_sources LIMIT 0").all();
    _versionReady.add(env.DB);
  } catch (_) {
  }
}
__name(ensureSourcesVersion, "ensureSourcesVersion");
function storedItems(row) {
  if (!row)
    return [];
  let items = [];
  if (row.sources_json) {
    try {
      items = JSON.parse(row.sources_json) || [];
    } catch (_) {
      items = [];
    }
  }
  if (!Array.isArray(items) || !items.length) {
    if (!row.type && !row.m3u_url && !row.server_url)
      return [];
    items = [{
      type: row.type,
      label: row.label,
      server_url: row.server_url,
      username: row.username,
      password: row.password,
      m3u_url: row.m3u_url,
      epg_url: row.epg_url
    }];
  }
  return items;
}
__name(storedItems, "storedItems");
function hostsOf(items) {
  const out = [];
  for (const s of items || []) {
    const raw = s && (s.server_url || s.m3u_url);
    if (!raw || typeof raw !== "string" || raw.startsWith("enc1"))
      continue;
    try {
      out.push(new URL(raw).host);
    } catch (_) {
    }
  }
  return out;
}
__name(hostsOf, "hostsOf");
async function casWriteSources(env, mac, mutate, opts = {}) {
  await ensureSourcesVersion(env);
  if (opts.revision)
    await ensureOrderTables(env);
  const maxAttempts = opts.maxAttempts || 50;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const row = await env.DB.prepare(
      "SELECT mac, type, label, server_url, username, password, m3u_url, epg_url, sources_json, origin, reseller_id, version FROM device_sources WHERE mac = ?"
    ).bind(mac).first();
    const out = await mutate(row, storedItems(row));
    if (out && out.abort !== void 0)
      return { abort: out.abort };
    const sealed = [];
    for (const item of out && out.items || [])
      sealed.push(await sealSource(env, item));
    const now = Date.now();
    const stmts = [];
    let writes = true;
    if (row && sealed.length) {
      const first = sealed[0];
      const rowOrigin = sealed.every((s) => s.origin === "self") ? "self" : "panel";
      stmts.push(env.DB.prepare(
        `UPDATE device_sources SET
           type = ?, label = ?, server_url = ?, username = ?, password = ?, m3u_url = ?, epg_url = ?,
           sources_json = ?, origin = ?, reseller_id = COALESCE(?, reseller_id),
           updated_at = ?, version = version + 1
         WHERE mac = ? AND version = ?`
      ).bind(
        first.type || null,
        first.label || null,
        first.server_url || null,
        first.username || null,
        first.password || null,
        first.m3u_url || null,
        first.epg_url || null,
        JSON.stringify(sealed),
        rowOrigin,
        opts.resellerId || null,
        now,
        mac,
        Number(row.version) || 0
      ));
    } else if (row && !sealed.length) {
      stmts.push(env.DB.prepare("DELETE FROM device_sources WHERE mac = ? AND version = ?").bind(mac, Number(row.version) || 0));
    } else if (!row && sealed.length) {
      const first = sealed[0];
      const rowOrigin = sealed.every((s) => s.origin === "self") ? "self" : "panel";
      stmts.push(env.DB.prepare(
        `INSERT INTO device_sources
           (mac, type, label, server_url, username, password, m3u_url, epg_url, sources_json, origin,
            reseller_id, updated_at, version)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
         ON CONFLICT(mac) DO NOTHING`
      ).bind(
        mac,
        first.type || null,
        first.label || null,
        first.server_url || null,
        first.username || null,
        first.password || null,
        first.m3u_url || null,
        first.epg_url || null,
        JSON.stringify(sealed),
        rowOrigin,
        opts.resellerId || null,
        now
      ));
    } else {
      writes = false;
    }
    const revIdx = stmts.length;
    if (opts.revision) {
      const panelSealed = sealed.filter((s) => s.origin !== "self");
      const panelClear = (out && out.items || []).filter((s) => s && s.origin !== "self");
      const r = opts.revision;
      stmts.push(env.DB.prepare(
        `INSERT INTO source_revisions
           (mac, rev, state, panel_json, item_count, hosts, trace_id, actor_type, actor_id,
            rollback_of, validated_at, published_at, created_at)
         SELECT ?, COALESCE((SELECT MAX(rev) FROM source_revisions WHERE mac = ?), 0) + 1,
                'published', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
         WHERE ${writes ? "changes() = 1" : "1"}
         RETURNING rev`
      ).bind(
        mac,
        mac,
        JSON.stringify(panelSealed),
        panelSealed.length,
        JSON.stringify(hostsOf(panelClear)),
        r.traceId || null,
        r.actor ? r.actor.type : null,
        r.actor ? r.actor.id : null,
        r.rollbackOf || null,
        now,
        now,
        now
      ));
    }
    if (!stmts.length)
      return { ok: true, items: sealed, rev: null, version: null, attempts: attempt };
    const res = await env.DB.batch(stmts);
    const wrote = !writes || res[0] && res[0].meta && res[0].meta.changes === 1;
    if (wrote) {
      const revRow = opts.revision && res[revIdx] && res[revIdx].results ? res[revIdx].results[0] : null;
      return {
        ok: true,
        items: sealed,
        rev: revRow ? revRow.rev : null,
        version: row ? (Number(row.version) || 0) + 1 : sealed.length ? 1 : null,
        attempts: attempt
      };
    }
  }
  return { conflict: true, attempts: maxAttempts };
}
__name(casWriteSources, "casWriteSources");

// page_query.js
function parsePageQuery(url, opts = {}) {
  const defaultLimit = opts.defaultLimit ?? 200;
  const maxLimit = opts.maxLimit ?? 200;
  const params = url && url.searchParams ? url.searchParams : url;
  const rawLimit = Number(params && params.get ? params.get("limit") : NaN);
  const rawOffset = Number(params && params.get ? params.get("offset") : NaN);
  let limit = defaultLimit;
  if (Number.isFinite(rawLimit) && rawLimit > 0) {
    limit = Math.min(Math.floor(rawLimit), maxLimit);
  }
  let offset = 0;
  if (Number.isFinite(rawOffset) && rawOffset > 0) {
    offset = Math.min(Math.floor(rawOffset), 1e6);
  }
  return { limit, offset };
}
__name(parsePageQuery, "parsePageQuery");
function pageEnvelope(items, total, limit, offset) {
  const list = Array.isArray(items) ? items : [];
  const t = Number(total);
  const totalN = Number.isFinite(t) ? t : list.length;
  const lim = Number(limit);
  const off = Number(offset);
  const limitN = Number.isFinite(lim) ? lim : list.length;
  const offsetN = Number.isFinite(off) && off > 0 ? off : 0;
  return {
    items: list,
    total: totalN,
    limit: limitN,
    offset: offsetN,
    truncated: offsetN + list.length < totalN
  };
}
__name(pageEnvelope, "pageEnvelope");
function epochMs(value) {
  if (value == null || value === "")
    return null;
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n) || n <= 0)
    return null;
  if (n < 1e11)
    return Math.round(n * 1e3);
  return n;
}
__name(epochMs, "epochMs");
function epochSql(column) {
  if (!/^[a-zA-Z_][a-zA-Z0-9_.]*$/.test(column)) {
    throw new Error("epochSql: nom de colonne refuse");
  }
  return `(CASE WHEN ${column} > 0 AND ${column} < 100000000000 THEN ${column} * 1000 ELSE ${column} END)`;
}
__name(epochSql, "epochSql");
function liveLicenseStatus(status, expiresAt, now) {
  if (status === "banned" || status === "frozen")
    return status;
  const exp = epochMs(expiresAt);
  if (exp == null) {
    if (!status || status === "active" || status === "expired")
      return "active";
    return status;
  }
  if (status && status !== "active" && status !== "expired")
    return status;
  return exp > now ? "active" : "expired";
}
__name(liveLicenseStatus, "liveLicenseStatus");
function num(row, key) {
  const v = Number(row && row[key]);
  return Number.isFinite(v) ? v : 0;
}
__name(num, "num");
function redact(value) {
  return String(value == null ? "" : value).replace(/Bearer\s+\S+/gi, "Bearer [redacted]").replace(
    /(password|passwd|token|secret|authorization|m3u_url|m3u)\s*[=:]\s*\S+/gi,
    "$1=[redacted]"
  ).slice(0, 500);
}
__name(redact, "redact");
function safeRoute(request) {
  try {
    return new URL(request.url).pathname.slice(0, 120);
  } catch (_) {
    return "unknown";
  }
}
__name(safeRoute, "safeRoute");

// api_v1.js
var JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Access-Control-Allow-Origin": "*",
  // X-Request-Id, X-Client-Sent-At, Idempotency-Key : envoyés par le panel
  // à chaque écriture depuis le 06/10/2026 (suivi et anti double débit).
  // Absents ici, le navigateur bloquait la requête : « Connexion
  // impossible » sur toute modification (cors_panel.test.mjs).
  "Access-Control-Allow-Headers": "Authorization, X-Admin-Secret, Content-Type, X-Request-Id, X-Client-Sent-At, Idempotency-Key",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff"
};
var PANEL_ORIGINS = /* @__PURE__ */ new Set([
  "https://tvking-admin.pages.dev",
  "https://admin.7themotion.com",
  "http://localhost:5173",
  "http://127.0.0.1:5173"
]);
function originAllowed(origin, env) {
  if (!origin)
    return false;
  if (PANEL_ORIGINS.has(origin))
    return true;
  const extra = String(env && env.PANEL_ORIGINS || "");
  return extra.split(",").map((s) => s.trim()).filter(Boolean).includes(origin);
}
__name(originAllowed, "originAllowed");
function applyCors(request, env, res) {
  const headers = new Headers(res.headers);
  headers.delete("access-control-allow-origin");
  const origin = request.headers.get("Origin");
  if (originAllowed(origin, env)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
  }
  return new Response(res.body, {
    status: res.status,
    statusText: res.statusText,
    headers
  });
}
__name(applyCors, "applyCors");
function jsonResp(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS
  });
}
__name(jsonResp, "jsonResp");
function errResp(code, message, status = 400) {
  return jsonResp({ error: code, message }, status);
}
__name(errResp, "errResp");
async function ensureRateLimitTable(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS rate_limits (k TEXT PRIMARY KEY, count INTEGER NOT NULL, window_start INTEGER NOT NULL)"
  ).run();
}
__name(ensureRateLimitTable, "ensureRateLimitTable");
function clientIp(request) {
  return request.headers.get("CF-Connecting-IP") || request.headers.get("X-Forwarded-For") || "unknown";
}
__name(clientIp, "clientIp");
async function rateLimitHit(env, request, bucket, maxAttempts, windowMs) {
  try {
    await ensureRateLimitTable(env);
    const k = `${bucket}:${clientIp(request)}`;
    const now = Date.now();
    const row = await env.DB.prepare("SELECT count, window_start FROM rate_limits WHERE k = ?").bind(k).first();
    if (!row || now - row.window_start > windowMs) {
      await env.DB.prepare(
        "INSERT INTO rate_limits (k, count, window_start) VALUES (?, 1, ?) ON CONFLICT(k) DO UPDATE SET count = 1, window_start = ?"
      ).bind(k, now, now).run();
      return true;
    }
    if (row.count >= maxAttempts)
      return false;
    await env.DB.prepare("UPDATE rate_limits SET count = count + 1 WHERE k = ?").bind(k).run();
    return true;
  } catch (_) {
    return true;
  }
}
__name(rateLimitHit, "rateLimitHit");
async function rateLimitReset(env, request, bucket) {
  try {
    await env.DB.prepare("DELETE FROM rate_limits WHERE k = ?").bind(`${bucket}:${clientIp(request)}`).run();
  } catch (_) {
  }
}
__name(rateLimitReset, "rateLimitReset");
function b64url2(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}
__name(b64url2, "b64url");
function b64urlDecode2(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4)
    s += "=";
  const raw = atob(s);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++)
    arr[i] = raw.charCodeAt(i);
  return arr;
}
__name(b64urlDecode2, "b64urlDecode");
async function hmacSha256(secret, msg) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(msg)
  );
  return new Uint8Array(sig);
}
__name(hmacSha256, "hmacSha256");
async function signJwt(payload, secret, expMinutes = 60 * 24 * 7) {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1e3);
  const claims = {
    ...payload,
    iat: now,
    exp: now + expMinutes * 60
  };
  const h = b64url2(new TextEncoder().encode(JSON.stringify(header)));
  const p = b64url2(new TextEncoder().encode(JSON.stringify(claims)));
  const sig = b64url2(await hmacSha256(secret, `${h}.${p}`));
  return `${h}.${p}.${sig}`;
}
__name(signJwt, "signJwt");
function safeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string")
    return false;
  const len = Math.max(a.length, b.length);
  let diff2 = a.length === b.length ? 0 : 1;
  for (let i = 0; i < len; i++) {
    const ca = i < a.length ? a.charCodeAt(i) : 0;
    const cb = i < b.length ? b.charCodeAt(i) : 0;
    diff2 |= ca ^ cb;
  }
  return diff2 === 0;
}
__name(safeEqual, "safeEqual");
function authSecret(env) {
  const s = String(env && env.ADMIN_SECRET || "").trim();
  if (!s || s === "dev-secret" || s === "change-me")
    return null;
  return s;
}
__name(authSecret, "authSecret");
async function ensurePasswordChangedColumn(env, table) {
  if (table !== "admin_users" && table !== "resellers")
    return;
  try {
    await env.DB.prepare(
      `ALTER TABLE ${table} ADD COLUMN password_changed_at INTEGER`
    ).run();
  } catch (_) {
  }
}
__name(ensurePasswordChangedColumn, "ensurePasswordChangedColumn");
async function verifyJwt(token, secret) {
  try {
    const [h, p, s] = token.split(".");
    if (!h || !p || !s)
      return null;
    const header = JSON.parse(new TextDecoder().decode(b64urlDecode2(h)));
    if (!header || header.alg !== "HS256")
      return null;
    const expectedSig = b64url2(await hmacSha256(secret, `${h}.${p}`));
    if (!safeEqual(s, expectedSig))
      return null;
    const claims = JSON.parse(
      new TextDecoder().decode(b64urlDecode2(p))
    );
    const now = Math.floor(Date.now() / 1e3);
    if (claims.exp && claims.exp < now)
      return null;
    return claims;
  } catch (_) {
    return null;
  }
}
__name(verifyJwt, "verifyJwt");
async function hashPassword(plain) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const keyMat = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(plain),
    { name: "PBKDF2" },
    false,
    ["deriveBits"]
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: 1e5, hash: "SHA-256" },
    keyMat,
    256
  );
  return `pbkdf2$100000$${b64url2(salt)}$${b64url2(bits)}`;
}
__name(hashPassword, "hashPassword");
async function verifyPassword(plain, stored) {
  try {
    const [algo, iter, saltB64, hashB64] = stored.split("$");
    if (algo !== "pbkdf2")
      return false;
    const salt = b64urlDecode2(saltB64);
    const keyMat = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(plain),
      { name: "PBKDF2" },
      false,
      ["deriveBits"]
    );
    const bits = await crypto.subtle.deriveBits(
      {
        name: "PBKDF2",
        salt,
        iterations: Number(iter),
        hash: "SHA-256"
      },
      keyMat,
      256
    );
    return b64url2(bits) === hashB64;
  } catch (_) {
    return false;
  }
}
__name(verifyPassword, "verifyPassword");
function genId(prefix) {
  const ts = Date.now().toString(36).padStart(8, "0");
  const rand = Array.from(crypto.getRandomValues(new Uint8Array(8))).map((b) => (b % 36).toString(36)).join("");
  return `${prefix}_${ts}${rand}`;
}
__name(genId, "genId");
var DUMMY_PASSWORD_HASH = "pbkdf2$100000$kFBE63yLabFQ6rL-K2epjA$UPY1WDxzSdMhJRQS8N2InJq65Q00rcYjO2bGkl9xRzM";
function tokenStale(row, claims) {
  const changed = Number(row && row.password_changed_at) || 0;
  if (!changed || !claims || !claims.iat)
    return false;
  if (changed > 1e12)
    return changed > claims.iat * 1e3;
  return claims.iat < changed;
}
__name(tokenStale, "tokenStale");
async function readAdminActor(env, id) {
  try {
    return await env.DB.prepare(
      "SELECT id, email, name, role, is_active, password_changed_at FROM admin_users WHERE id = ?"
    ).bind(id).first();
  } catch (_) {
    return await env.DB.prepare(
      "SELECT id, email, name, role, is_active FROM admin_users WHERE id = ?"
    ).bind(id).first();
  }
}
__name(readAdminActor, "readAdminActor");
async function readResellerActor(env, id) {
  try {
    return await env.DB.prepare(
      "SELECT id, email, name, status, level, permissions, password_changed_at FROM resellers WHERE id = ?"
    ).bind(id).first();
  } catch (_) {
    return await env.DB.prepare(
      "SELECT id, email, name, status, level, permissions FROM resellers WHERE id = ?"
    ).bind(id).first();
  }
}
__name(readResellerActor, "readResellerActor");
async function hydrateActor(env, claims) {
  if (!claims || !claims.sub)
    return null;
  if (claims.role === "reseller") {
    const row2 = await readResellerActor(env, claims.sub);
    if (!row2 || row2.status !== "active")
      return null;
    if (tokenStale(row2, claims))
      return null;
    const level = row2.level || "basique";
    return {
      sub: row2.id,
      email: row2.email,
      role: "reseller",
      name: row2.name,
      level,
      permissions: resellerPerms(row2.permissions, level)
    };
  }
  const row = await readAdminActor(env, claims.sub);
  if (!row || !row.is_active)
    return null;
  if (tokenStale(row, claims))
    return null;
  return {
    sub: row.id,
    email: row.email,
    role: row.role,
    name: row.name
  };
}
__name(hydrateActor, "hydrateActor");
async function panelActorFromToken(env, token) {
  const secret = authSecret(env);
  if (!secret || !token)
    return null;
  const claims = await verifyJwt(String(token), secret);
  if (!claims)
    return null;
  return hydrateActor(env, claims);
}
__name(panelActorFromToken, "panelActorFromToken");
async function requireAuth(request, env) {
  const secret = authSecret(env);
  if (!secret) {
    return { error: errResp("auth_unconfigured", "Authentification indisponible.", 503) };
  }
  const auth = request.headers.get("Authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m)
    return { error: errResp("no_auth", "Missing Authorization header", 401) };
  const claims = await verifyJwt(m[1], secret);
  if (!claims)
    return { error: errResp("bad_token", "Invalid or expired token", 401) };
  const user = await hydrateActor(env, claims);
  if (!user)
    return { error: errResp("bad_token", "Invalid or expired token", 401) };
  return { user };
}
__name(requireAuth, "requireAuth");
function adminSecretMatches(request, env) {
  const provided = request.headers.get("X-Admin-Secret") || "";
  const expected = env.ADMIN_SECRET || "";
  if (!expected || typeof provided !== "string")
    return false;
  if (provided.length !== expected.length)
    return false;
  let diff2 = 0;
  for (let i = 0; i < expected.length; i++) {
    diff2 |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff2 === 0;
}
__name(adminSecretMatches, "adminSecretMatches");
async function handleReferencesList(request, env, user) {
  const reseller = user && user.role === "reseller";
  const { limit, offset } = parsePageQuery(new URL(request.url), {
    defaultLimit: 100,
    maxLimit: 200
  });
  try {
    const where = reseller ? "WHERE d.reseller_id = ?" : "";
    const binds = reseller ? [user.sub] : [];
    const now = Date.now();
    const page = await pagedQuery(
      env,
      `SELECT COUNT(*) as n FROM device_sources ds
         LEFT JOIN devices d ON d.mac = ds.mac
         ${where}`,
      binds,
      `SELECT ds.mac AS mac, ds.username AS username, ds.server_url AS server_url,
              ds.sources_json AS sources_json, ds.label AS label,
              ds.updated_at AS updated_at, c.name AS customer_name,
              (SELECT l.status    FROM licenses l JOIN devices dl ON dl.id = l.device_id
                 WHERE dl.mac = ds.mac
                 ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_status,
              (SELECT l.expires_at FROM licenses l JOIN devices dl ON dl.id = l.device_id
                 WHERE dl.mac = ds.mac
                 ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_expires
       FROM device_sources ds
       LEFT JOIN devices d   ON d.mac = ds.mac
       LEFT JOIN customers c ON c.id = d.customer_id
       ${where}
       ORDER BY ds.updated_at DESC LIMIT ? OFFSET ?`,
      binds,
      limit,
      offset
    );
    const rs = { results: page.items };
    const items = (rs.results || []).map((r) => {
      let usernames = [];
      let servers = [];
      if (r.sources_json) {
        try {
          const arr = JSON.parse(r.sources_json) || [];
          usernames = arr.map((s) => s && s.username).filter(Boolean);
          servers = arr.map((s) => s && (s.server_url || s.server)).filter(Boolean);
        } catch (_) {
        }
      }
      if (usernames.length === 0 && r.username)
        usernames = [r.username];
      if (servers.length === 0 && r.server_url)
        servers = [r.server_url];
      let status = "none";
      if (r.lic_status === "banned")
        status = "banned";
      else if (r.lic_status === "frozen")
        status = "frozen";
      else if (r.lic_status && r.lic_status !== "active")
        status = "inactive";
      else if (r.lic_status) {
        status = liveLicenseStatus(r.lic_status, r.lic_expires, now);
      }
      return {
        mac: r.mac,
        customer_name: r.customer_name || null,
        usernames,
        servers,
        status,
        label: r.label || null,
        updated_at: epochMs(r.updated_at)
      };
    });
    return jsonResp({ ...page, items });
  } catch (e) {
    const msg = String(e && e.message || e);
    if (/no such table/i.test(msg))
      return jsonResp(pageEnvelope([], 0, 0, 0));
    throw e;
  }
}
__name(handleReferencesList, "handleReferencesList");
async function handleAuditLogsList(request, env) {
  const { limit, offset } = parsePageQuery(new URL(request.url));
  try {
    const page = await pagedQuery(
      env,
      "SELECT COUNT(*) as n FROM audit_logs",
      [],
      `SELECT id, actor_type, actor_id, action, target_type, target_id,
              before_json, after_json, created_at
       FROM audit_logs ORDER BY created_at DESC LIMIT ? OFFSET ?`,
      [],
      limit,
      offset
    );
    page.items = page.items.map((row) => ({
      ...row,
      created_at: epochMs(row.created_at)
    }));
    return jsonResp(page);
  } catch (e) {
    const msg = String(e && e.message || e);
    if (/no such table/i.test(msg))
      return jsonResp(pageEnvelope([], 0, 0, 0));
    throw e;
  }
}
__name(handleAuditLogsList, "handleAuditLogsList");
async function bootstrapSuperAdminIfNeeded(env) {
  const secret = authSecret(env);
  if (!secret)
    return false;
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS admin_users (
       id TEXT PRIMARY KEY,
       email TEXT NOT NULL UNIQUE,
       password_hash TEXT NOT NULL,
       name TEXT,
       role TEXT NOT NULL DEFAULT 'admin',
       is_active INTEGER NOT NULL DEFAULT 1,
       last_login_at INTEGER,
       created_at INTEGER NOT NULL
     )`
  ).run();
  const count = await env.DB.prepare(
    "SELECT COUNT(*) as n FROM admin_users"
  ).first();
  if (count && count.n > 0)
    return false;
  const id = genId("adm");
  const now = Date.now();
  const pwd = await hashPassword(secret);
  const res = await env.DB.prepare(
    `INSERT INTO admin_users
        (id, email, password_hash, name, role, is_active, created_at)
       SELECT ?, ?, ?, ?, ?, 1, ?
       WHERE NOT EXISTS (SELECT 1 FROM admin_users)
       ON CONFLICT DO NOTHING`
  ).bind(id, "admin", pwd, "Super Admin", "super_admin", now).run();
  return !!(res && res.meta && res.meta.changes === 1);
}
__name(bootstrapSuperAdminIfNeeded, "bootstrapSuperAdminIfNeeded");
var IDEMPOTENCY_TTL_MS = 24 * 3600 * 1e3;
var _idempotencyReady = /* @__PURE__ */ new WeakSet();
async function ensureIdempotencyTable(env) {
  if (_idempotencyReady.has(env.DB))
    return;
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS idempotency_keys (k TEXT PRIMARY KEY, actor_id TEXT, request_hash TEXT NOT NULL, status INTEGER, body_json TEXT, created_at INTEGER NOT NULL, committed_at INTEGER, commit_ref TEXT)"
  ).run();
  for (const col of ["committed_at INTEGER", "commit_ref TEXT"]) {
    try {
      await env.DB.prepare(`ALTER TABLE idempotency_keys ADD COLUMN ${col}`).run();
    } catch (_) {
    }
  }
  _idempotencyReady.add(env.DB);
}
__name(ensureIdempotencyTable, "ensureIdempotencyTable");
async function sha256Hex(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
__name(sha256Hex, "sha256Hex");
var IDEMPOTENCY_STALE_MS = 60 * 1e3;
async function withIdempotency(request, env, actor, route, run, recover = null) {
  const key = (request.headers.get("Idempotency-Key") || "").trim();
  if (!key)
    return run(request, null);
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(key)) {
    return errResp("bad_idempotency_key", "Idempotency-Key : 8 \xE0 128 caract\xE8res [A-Za-z0-9_-].", 400);
  }
  await ensureIdempotencyTable(env);
  const bodyText = await request.text();
  const k = `${actor.type}:${actor.id}:${key}`;
  const hash = await sha256Hex(`${route}
${bodyText}`);
  const now = Date.now();
  const prev = await env.DB.prepare("SELECT request_hash, status, body_json, created_at, committed_at, commit_ref FROM idempotency_keys WHERE k = ?").bind(k).first();
  if (prev) {
    if (prev.request_hash !== hash) {
      return errResp(
        "idempotency_mismatch",
        "Cette cl\xE9 a d\xE9j\xE0 servi pour une autre requ\xEAte. G\xE9n\xE8re une nouvelle cl\xE9.",
        409
      );
    }
    if (prev.status != null) {
      const res2 = jsonResp(JSON.parse(prev.body_json || "null"), prev.status);
      return withResponseHeader(res2, "Idempotent-Replayed", "true");
    }
    if (prev.committed_at != null && recover) {
      let ref = null;
      try {
        ref = JSON.parse(prev.commit_ref || "null");
      } catch (_) {
        ref = null;
      }
      const rebuilt = await recover(ref);
      const text2 = await rebuilt.clone().text();
      await env.DB.prepare("UPDATE idempotency_keys SET status = ?, body_json = ? WHERE k = ? AND status IS NULL").bind(rebuilt.status, text2, k).run();
      return withResponseHeader(rebuilt, "Idempotent-Replayed", "recovered");
    }
    if (prev.committed_at == null && now - Number(prev.created_at || 0) > IDEMPOTENCY_STALE_MS) {
      const took = await env.DB.prepare(
        "UPDATE idempotency_keys SET created_at = ? WHERE k = ? AND status IS NULL AND committed_at IS NULL AND created_at = ?"
      ).bind(now, k, prev.created_at).run();
      if (!(took && took.meta && took.meta.changes === 1)) {
        return errResp(
          "idempotency_in_progress",
          "La m\xEAme activation est d\xE9j\xE0 en cours. R\xE9essaie dans quelques secondes.",
          409
        );
      }
    } else {
      return errResp(
        "idempotency_in_progress",
        "La m\xEAme activation est d\xE9j\xE0 en cours. R\xE9essaie dans quelques secondes.",
        409
      );
    }
  } else {
    try {
      await env.DB.prepare(
        "INSERT INTO idempotency_keys (k, actor_id, request_hash, status, body_json, created_at) VALUES (?, ?, ?, NULL, NULL, ?)"
      ).bind(k, actor.id, hash, now).run();
    } catch (_) {
      return errResp(
        "idempotency_in_progress",
        "La m\xEAme activation est d\xE9j\xE0 en cours. R\xE9essaie dans quelques secondes.",
        409
      );
    }
  }
  let res;
  try {
    res = await run(new Request(request, { body: bodyText }), { key: k });
  } catch (e) {
    try {
      await env.DB.prepare("DELETE FROM idempotency_keys WHERE k = ? AND committed_at IS NULL").bind(k).run();
    } catch (_) {
    }
    throw e;
  }
  const text = await res.clone().text();
  await env.DB.prepare("UPDATE idempotency_keys SET status = ?, body_json = ? WHERE k = ?").bind(res.status, text, k).run();
  if (Math.random() < 0.05) {
    try {
      await env.DB.prepare("DELETE FROM idempotency_keys WHERE created_at < ?").bind(now - IDEMPOTENCY_TTL_MS).run();
    } catch (_) {
    }
  }
  return res;
}
__name(withIdempotency, "withIdempotency");
function recoverActivationResponse(ref) {
  if (!ref || !ref.license_id) {
    return errResp("idempotency_unrecoverable", "Activation engag\xE9e mais illisible. Relis la fiche.", 409);
  }
  return jsonResp({
    ok: true,
    license_id: ref.license_id,
    device_id: ref.device_id,
    customer_id: ref.customer_id,
    mac: ref.mac,
    plan: ref.plan,
    expires_at: ref.expires_at === void 0 ? null : ref.expires_at,
    credits_charged: ref.credits_charged || 0,
    credit_balance: ref.credit_balance === void 0 ? null : ref.credit_balance,
    renewed: !!ref.renewed,
    order_id: null,
    trace_id: ref.trace_id || null,
    recovered: true
  }, 201);
}
__name(recoverActivationResponse, "recoverActivationResponse");
var _auditCorrelationReady = /* @__PURE__ */ new WeakSet();
async function ensureAuditCorrelationColumn(env) {
  if (!env.DB || _auditCorrelationReady.has(env.DB))
    return;
  try {
    await env.DB.prepare("ALTER TABLE audit_logs ADD COLUMN correlation_id TEXT").run();
  } catch (_) {
  }
  _auditCorrelationReady.add(env.DB);
}
__name(ensureAuditCorrelationColumn, "ensureAuditCorrelationColumn");
async function logAudit(env, request, actor, action, target, before, after) {
  try {
    await ensureAuditCorrelationColumn(env);
    await env.DB.prepare(
      `INSERT INTO audit_logs
          (id, actor_type, actor_id, action, target_type, target_id,
           before_json, after_json, ip, user_agent, created_at, correlation_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      genId("aud"),
      actor.type,
      actor.id,
      action,
      target.type || null,
      target.id || null,
      before ? JSON.stringify(before) : null,
      after ? JSON.stringify(after) : null,
      request && request.headers ? request.headers.get("CF-Connecting-IP") : null,
      request && request.headers ? request.headers.get("User-Agent") : null,
      Date.now(),
      request && request.headers ? request.headers.get("X-Request-Id") || null : null
    ).run();
  } catch (e) {
    console.error(JSON.stringify({
      level: "error",
      source: "api_v1",
      route: "audit_log",
      message: redact(e && e.message ? e.message : e)
    }));
  }
}
__name(logAudit, "logAudit");
function requestIdFrom(request) {
  const given = (request.headers.get("X-Request-Id") || "").trim();
  return /^[A-Za-z0-9_.:-]{8,64}$/.test(given) ? given : crypto.randomUUID();
}
__name(requestIdFrom, "requestIdFrom");
function withRequestId(request, requestId, receivedAt = Date.now()) {
  const headers = new Headers(request.headers);
  headers.set("X-Request-Id", requestId);
  headers.set("X-Api-Received-At", String(receivedAt));
  return new Request(request, { headers });
}
__name(withRequestId, "withRequestId");
function orderOpts(request, extra = {}) {
  const t1 = Number(request.headers.get("X-Api-Received-At")) || null;
  const t0raw = Number(request.headers.get("X-Client-Sent-At"));
  const t0 = Number.isFinite(t0raw) && t0raw > 0 && t1 && Math.abs(t1 - t0raw) < 24 * 3600 * 1e3 ? t0raw : null;
  return { traceId: request.headers.get("X-Request-Id") || null, t0, t1, t2: Date.now(), ...extra };
}
__name(orderOpts, "orderOpts");
function withResponseHeader(res, name, value) {
  const headers = new Headers(res.headers);
  headers.set(name, value);
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}
__name(withResponseHeader, "withResponseHeader");
async function apiV1(request, env) {
  let res;
  const requestId = requestIdFrom(request);
  const receivedAt = Date.now();
  try {
    if (request.method === "OPTIONS") {
      res = new Response(null, { status: 204, headers: JSON_HEADERS });
    } else {
      res = await apiV1Inner(withRequestId(request, requestId, receivedAt), env);
    }
    res = withResponseHeader(res, "X-Request-Id", requestId);
  } catch (e) {
    const raw = e && e.message ? String(e.message) : String(e);
    console.error(JSON.stringify({
      level: "error",
      source: "api_v1",
      request_id: requestId,
      route: safeRoute(request),
      message: redact(raw)
    }));
    const safe = /no such table|no such column/i.test(raw) ? raw.replace(/\s+/g, " ").slice(0, 180) : "Erreur interne.";
    res = jsonResp({
      error: "internal_error",
      message: safe,
      request_id: requestId
    }, 500);
  }
  return applyCors(request, env, res);
}
__name(apiV1, "apiV1");
async function pagedQuery(env, countSql, countBinds, listSql, listBinds, limit, offset) {
  const countRow = await env.DB.prepare(countSql).bind(...countBinds).first();
  const total = num(countRow, "n");
  const rs = await env.DB.prepare(listSql).bind(...listBinds, limit, offset).all();
  return pageEnvelope(rs.results || [], total, limit, offset);
}
__name(pagedQuery, "pagedQuery");
async function apiV1Inner(request, env) {
  if (!env.DB) {
    return errResp(
      "db_unbound",
      'D1 database binding "DB" is missing. Did you run `wrangler d1 create`?',
      500
    );
  }
  const url = new URL(request.url);
  const sub = url.pathname.replace(/^\/api\/v1\/?/, "");
  const parts = sub.split("/").filter(Boolean);
  if (parts[0] === "auth") {
    if (parts[1] === "login" && request.method === "POST") {
      return handleLogin(request, env);
    }
    if (parts[1] === "reseller" && parts[2] === "login" && request.method === "POST") {
      return handleResellerLogin(request, env);
    }
    if (parts[1] === "reseller" && parts[2] === "signup" && request.method === "POST") {
      return handleResellerSignup(request, env);
    }
    if (parts[1] === "me" && request.method === "GET") {
      const a2 = await requireAuth(request, env);
      if (a2.error)
        return a2.error;
      return jsonResp({ user: a2.user });
    }
  }
  if (parts[0] === "trial-extend" && parts.length === 1 && request.method === "POST") {
    if (adminSecretMatches(request, env)) {
      return handleTrialExtend(request, env, { type: "admin", id: "admin_secret" });
    }
  }
  const a = await requireAuth(request, env);
  if (a.error)
    return a.error;
  const isReseller = a.user.role === "reseller";
  const actor = { type: isReseller ? "reseller" : "admin", id: a.user.sub };
  if (parts[0] === "stats" && parts[1] === "overview") {
    return handleStatsOverview(env, a.user);
  }
  if (parts[0] === "backup" && parts.length === 1) {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (request.method === "GET")
      return handleBackup(env);
  }
  if (parts[0] === "audit-logs" && parts.length === 1 && request.method === "GET") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    return handleAuditLogsList(request, env);
  }
  if (parts[0] === "references" && parts.length === 1 && request.method === "GET") {
    return handleReferencesList(request, env, a.user);
  }
  if (parts[0] === "me" && parts.length === 1 && request.method === "GET") {
    return handleMe(env, a.user);
  }
  if (parts[0] === "me" && parts[1] === "password" && request.method === "POST") {
    return handleChangeOwnPassword(request, env, a.user, actor);
  }
  if (parts[0] === "plan-costs" && parts.length === 1) {
    if (request.method === "GET")
      return handlePlanCostsList(env);
    if (request.method === "PUT") {
      if (!isOwner(a.user))
        return errResp("forbidden", "Owner only", 403);
      return handlePlanCostsUpdate(request, env, actor);
    }
  }
  if (parts[0] === "resellers") {
    if (isReseller && !resellerCan(a.user, "resellers")) {
      return errResp("forbidden", "Ton niveau ne permet pas de g\xE9rer des revendeurs.", 403);
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleResellersList(env, a.user);
      if (request.method === "POST")
        return handleResellersCreate(request, env, actor, a.user);
    }
    if (parts.length === 2) {
      const rid = parts[1];
      if (request.method === "GET")
        return handleResellersGet(env, rid, a.user);
      if (request.method === "PATCH")
        return handleResellersUpdate(request, env, rid, actor, a.user);
    }
    if (parts.length === 3 && parts[2] === "credits") {
      const rid = parts[1];
      if (request.method === "POST")
        return handleResellerCreditsIssue(request, env, rid, actor, a.user);
      if (request.method === "GET")
        return handleResellerCreditsList(env, rid, a.user);
    }
  }
  if (parts[0] === "activate" && parts.length === 1 && request.method === "POST") {
    if (!resellerCan(a.user, "activate")) {
      return errResp("forbidden", "Ton compte n'a pas le droit d'activer des appareils.", 403);
    }
    return withIdempotency(
      request,
      env,
      actor,
      "activate",
      (req, slot) => handleActivate(req, env, a.user, actor, slot),
      async (ref) => recoverActivationResponse(ref)
    );
  }
  if (parts[0] === "transfer" && parts.length === 1 && request.method === "POST") {
    if (!resellerCan(a.user, "activate")) {
      return errResp("forbidden", "Ton compte n'a pas le droit de transf\xE9rer.", 403);
    }
    return handleDeviceTransfer(request, env, a.user, actor);
  }
  if (parts[0] === "trial-extend" && parts.length === 1 && request.method === "POST") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Seul l\u2019administrateur peut ajouter des jours d\u2019essai.", 403);
    }
    return handleTrialExtend(request, env, actor);
  }
  if (parts[0] === "families") {
    if (!resellerCan(a.user, "activate")) {
      return errResp("forbidden", "Ton compte n'a pas le droit de g\xE9rer des familles.", 403);
    }
    await ensureFamiliesTables(env);
    if (request.method === "POST") {
      return errResp(
        "family_clone_disabled",
        "Le clonage familial n\u2019est plus propos\xE9. Les appareils d\xE9j\xE0 activ\xE9s en famille continuent de fonctionner.",
        403
      );
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleFamiliesList(env, a.user);
      if (request.method === "POST")
        return handleFamiliesCreate(request, env, actor, a.user);
    }
    if (parts.length === 2) {
      const fid = parts[1];
      if (request.method === "GET")
        return handleFamiliesGet(env, fid, a.user);
      if (request.method === "DELETE")
        return handleFamiliesDelete(env, fid, actor, a.user);
    }
    if (parts.length === 3 && parts[2] === "members" && request.method === "POST") {
      return handleFamilyAddMember(request, env, a.user, actor, parts[1]);
    }
    if (parts.length === 4 && parts[2] === "members" && request.method === "DELETE") {
      return handleFamilyRemoveMember(env, parts[1], decodeMac(parts[3]), actor, a.user);
    }
    if (parts.length === 3 && parts[2] === "links" && request.method === "POST") {
      return handleFamilyCreateLink(request, env, a.user, actor, parts[1]);
    }
    if (parts.length === 4 && parts[2] === "links" && request.method === "DELETE") {
      return handleFamilyDeleteLink(env, parts[1], parts[3], actor, a.user);
    }
  }
  if (parts[0] === "apps") {
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleAppsList(env, a.user);
      if (request.method === "POST") {
        if (a.user.role !== "super_admin") {
          return errResp("forbidden", "Only super_admin can create apps", 403);
        }
        return handleAppsCreate(request, env, actor);
      }
    }
    if (parts.length === 2) {
      const id = parts[1];
      if (request.method === "GET")
        return handleAppsGet(env, id);
      if (request.method === "PATCH") {
        if (a.user.role !== "super_admin") {
          return errResp("forbidden", "Only super_admin can edit apps", 403);
        }
        return handleAppsUpdate(request, env, id, actor);
      }
    }
  }
  if (parts[0] === "servers") {
    if (isReseller)
      return errResp("forbidden", "Admin only", 403);
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleServersList(env);
      if (request.method === "POST")
        return handleServersCreate(request, env, actor);
    }
    if (parts.length === 2) {
      const sid = parts[1];
      if (request.method === "PATCH")
        return handleServersUpdate(request, env, sid, actor);
      if (request.method === "DELETE")
        return handleServersDelete(request, env, sid, actor);
    }
  }
  if (parts[0] === "announcements") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleAnnouncementsList(env);
      if (request.method === "POST") {
        return handleAnnouncementsCreate(request, env, actor);
      }
      if (request.method === "DELETE") {
        return handleAnnouncementsClear(env, actor, request);
      }
    }
    if (parts.length === 2) {
      if (parts[1] === "settings") {
        if (request.method === "GET")
          return handleAnnouncementsSettingsGet(env);
        if (request.method === "PUT") {
          return handleAnnouncementsSettingsPut(request, env, actor);
        }
      } else {
        if (request.method === "DELETE") {
          return handleAnnouncementsDelete(env, parts[1], actor, request);
        }
        if (request.method === "PATCH") {
          return handleAnnouncementsUpdate(request, env, parts[1], actor);
        }
      }
    }
  }
  if (parts[0] === "home-layout") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleHomeLayoutGet(env);
      if (request.method === "PUT")
        return handleHomeLayoutSave(request, env, actor);
    }
    if (parts.length === 2 && parts[1] === "history" && request.method === "GET") {
      return handleHomeLayoutHistory(env);
    }
    if (parts.length === 2 && parts[1] === "restore" && request.method === "POST") {
      return handleHomeLayoutRestore(request, env, actor);
    }
  }
  if (parts[0] === "online" && parts.length === 1 && request.method === "GET") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    return handleOnlineGet(request, env);
  }
  if (parts[0] === "force-update") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    const fuPlatform = url.searchParams.get("platform");
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleForceUpdateGet(env, fuPlatform);
      if (request.method === "POST")
        return handleForceUpdatePost(request, env, actor, fuPlatform);
    }
  }
  if (parts[0] === "featured") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleFeaturedGet(env);
      if (request.method === "POST")
        return handleFeaturedPost(request, env, actor);
    }
  }
  if (parts[0] === "theme") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    const themePlatform = url.searchParams.get("platform");
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleThemeGet(env, themePlatform);
      if (request.method === "PUT")
        return handleThemePut(request, env, actor, themePlatform);
    }
    if (parts.length === 2 && parts[1] === "automations") {
      if (request.method === "GET")
        return handleThemeAutomationsGet(env, themePlatform);
      if (request.method === "PUT")
        return handleThemeAutomationsPut(request, env, actor, themePlatform);
    }
  }
  if (parts[0] === "ad") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleAdGet(env);
      if (request.method === "PUT")
        return handleAdPut(request, env, actor);
    }
  }
  if (parts[0] === "pricing") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handlePricingGet(env);
      if (request.method === "PUT")
        return handlePricingPut(request, env, actor);
    }
  }
  if (parts[0] === "feedback-prompt") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleFeedbackPromptGet(env);
      if (request.method === "PUT")
        return handleFeedbackPromptPut(request, env, actor);
    }
  }
  if (parts[0] === "grant-trial-all") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1 && request.method === "POST") {
      return handleGrantTrialAll(request, env, actor);
    }
  }
  if (parts[0] === "feedback") {
    if (a.user.role !== "super_admin") {
      return errResp("forbidden", "Owner only", 403);
    }
    if (parts.length === 1 && request.method === "GET") {
      return handleFeedbackList(env);
    }
  }
  if (parts[0] === "blackbox" && parts.length >= 2 && parts.length <= 3) {
    const gate = await sourceMacForActor(env, parts[1], a.user);
    if (gate.error)
      return gate.error;
    const mac = gate.mac;
    if (!isBlackboxMac(mac)) {
      return errResp("bad_mac", "mac must be MK:XX:XX:XX:XX:XX", 400);
    }
    if (parts.length === 2 && request.method === "GET") {
      const row = await readBlackBox(env, mac);
      return jsonResp({ mac, text: row.body, updated_at: row.updated_at });
    }
    if (parts.length === 3 && parts[2] === "ask" && request.method === "POST") {
      const requestedAt = await markBlackBoxAsked(env, mac, Date.now());
      return jsonResp({ ok: true, requested_at: requestedAt });
    }
  }
  if (parts[0] === "sources" && parts.length === 3 && parts[2] === "revisions" && request.method === "GET") {
    return handleSourceRevisions(env, parts[1], a.user);
  }
  if (parts[0] === "sources" && parts.length === 3 && parts[2] === "rollback" && request.method === "POST") {
    if (!resellerCan(a.user, "sources")) {
      return errResp("forbidden", "Ton niveau ne permet pas de pousser une source.", 403);
    }
    return handleSourceRollback(request, env, parts[1], actor, a.user);
  }
  if (parts[0] === "orders" && parts.length === 1 && request.method === "GET") {
    return handleOrdersList(request, env, a.user);
  }
  if (parts[0] === "metrics" && parts[1] === "latency" && request.method === "GET") {
    if (!isOwner(a.user))
      return errResp("forbidden", "R\xE9serv\xE9 \xE0 l\u2019administrateur.", 403);
    return handleLatencyMetrics(request, env);
  }
  if (parts[0] === "timeline" && parts.length === 1 && request.method === "GET") {
    return handleTimeline(request, env, actor, a.user);
  }
  if (parts[0] === "sources" && parts.length === 2) {
    const mac = parts[1];
    if (request.method === "GET")
      return handleSourceGet(env, mac, a.user);
    if ((request.method === "PUT" || request.method === "DELETE") && !resellerCan(a.user, "sources")) {
      return errResp("forbidden", "Ton niveau ne permet pas de pousser une source.", 403);
    }
    if (request.method === "PUT")
      return handleSourcePut(request, env, mac, actor, a.user);
    if (request.method === "DELETE")
      return handleSourceDelete(request, env, mac, actor, a.user);
  }
  if (parts[0] === "customers") {
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleCustomersList(request, env, a.user);
      if (request.method === "POST")
        return handleCustomersCreate(request, env, actor, a.user);
    }
    if (parts.length === 2) {
      const id = parts[1];
      if (request.method === "GET")
        return handleCustomersGet(env, id, a.user);
      if (request.method === "PATCH")
        return handleCustomersUpdate(request, env, id, actor, a.user);
    }
    if (parts.length === 3 && parts[2] === "devices") {
      return handleCustomerDevices(env, parts[1], a.user);
    }
  }
  if (parts[0] === "devices") {
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleDevicesList(request, env, a.user);
      if (request.method === "POST") {
        if (isReseller)
          return errResp("forbidden", "Passe par l'activation.", 403);
        return handleDevicesCreate(request, env, actor);
      }
    }
    if (parts.length === 2) {
      const did = parts[1];
      if (request.method === "PATCH")
        return handleDeviceUpdate(request, env, did, actor, a.user);
      if (request.method === "DELETE")
        return handleDeviceDelete(env, did, actor, a.user);
    }
    if (parts.length === 3 && parts[2] === "overview") {
      if (request.method === "GET")
        return handleDeviceOverview(env, parts[1], a.user);
    }
  }
  if (parts[0] === "licenses") {
    if (parts.length === 1) {
      if (request.method === "GET")
        return handleLicensesList(request, env, a.user);
      if (request.method === "POST") {
        if (isReseller)
          return errResp("forbidden", "Passe par l'activation.", 403);
        return handleLicensesCreate(request, env, actor);
      }
    }
    if (parts.length === 2) {
      const id = parts[1];
      if (request.method === "PATCH") {
        if (isReseller)
          return errResp("forbidden", "Owner only", 403);
        return handleLicensesUpdate(request, env, id, actor);
      }
    }
    if (parts.length === 3 && parts[2] === "renew") {
      if (isReseller)
        return errResp("forbidden", "Owner only", 403);
      return handleLicensesRenew(request, env, parts[1], actor);
    }
  }
  return errResp("not_found", `Unknown route: ${url.pathname}`, 404);
}
__name(apiV1Inner, "apiV1Inner");
async function handleLogin(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const email = (body.email || "").trim().toLowerCase();
  const password = body.password || "";
  if (!email || !password) {
    return errResp("missing_fields", "email and password required", 400);
  }
  if (!await rateLimitHit(env, request, "login", 10, 10 * 60 * 1e3)) {
    return errResp(
      "rate_limited",
      "Trop de tentatives de connexion. R\xE9essaie dans ~10 minutes.",
      429
    );
  }
  const secret = authSecret(env);
  if (!secret) {
    return errResp("auth_unconfigured", "Authentification indisponible.", 503);
  }
  await bootstrapSuperAdminIfNeeded(env);
  const row = await env.DB.prepare(
    "SELECT id, email, password_hash, name, role, is_active FROM admin_users WHERE email = ?"
  ).bind(email).first();
  if (!row || !row.is_active) {
    await verifyPassword(password, DUMMY_PASSWORD_HASH);
    return errResp("bad_credentials", "Invalid credentials", 401);
  }
  let ok = await verifyPassword(password, row.password_hash);
  if (!ok && row.role === "super_admin" && safeEqual(password, secret)) {
    const synced = await hashPassword(secret);
    const changed = Math.floor(Date.now() / 1e3);
    await ensurePasswordChangedColumn(env, "admin_users");
    await env.DB.prepare("UPDATE admin_users SET password_hash = ?, password_changed_at = ? WHERE id = ?").bind(synced, changed, row.id).run();
    ok = true;
  }
  if (!ok) {
    return errResp("bad_credentials", "Invalid credentials", 401);
  }
  await rateLimitReset(env, request, "login");
  await env.DB.prepare("UPDATE admin_users SET last_login_at = ? WHERE id = ?").bind(Date.now(), row.id).run();
  const token = await signJwt(
    { sub: row.id, email: row.email, role: row.role, name: row.name },
    secret
  );
  return jsonResp({
    token,
    user: { id: row.id, email: row.email, name: row.name, role: row.role }
  });
}
__name(handleLogin, "handleLogin");
function redactSecrets(row) {
  if (!row || typeof row !== "object")
    return row;
  const out = {};
  for (const [key, value] of Object.entries(row)) {
    if (/password|secret|token|m3u_url/i.test(key))
      continue;
    out[key] = value;
  }
  return out;
}
__name(redactSecrets, "redactSecrets");
async function handleBackup(env) {
  const tables = [
    "apps",
    "resellers",
    "customers",
    "devices",
    "licenses",
    "playlists",
    "payments",
    "credit_ledger",
    "plan_costs",
    "app_config",
    "app_broadcasts",
    "default_servers",
    "feedback",
    "home_layout",
    "home_layout_history",
    "presence"
  ];
  const dump = {};
  for (const tbl of tables) {
    if (!/^[a-z_]+$/.test(tbl))
      continue;
    try {
      const rs = await env.DB.prepare("SELECT * FROM " + tbl).all();
      dump[tbl] = (rs && rs.results || []).map(redactSecrets);
    } catch (_) {
      dump[tbl] = [];
    }
  }
  try {
    const rs = await env.DB.prepare("SELECT id, email, name, role, status, created_at FROM admin_users").all();
    dump.admin_users = (rs && rs.results || []).map(redactSecrets);
  } catch (_) {
    dump.admin_users = [];
  }
  return jsonResp({ generatedAt: Date.now(), version: 1, tables: dump });
}
__name(handleBackup, "handleBackup");
async function handleStatsOverview(env, user) {
  const now = Date.now();
  const month = 30 * 24 * 60 * 60 * 1e3;
  const isReseller = user && user.role === "reseller";
  const rid = isReseller ? user.sub : null;
  const exp = epochSql("expires_at");
  const activeSql = `status='active' AND (expires_at IS NULL OR expires_at = 0 OR ${exp} > ?)`;
  const expiredSql = `expires_at IS NOT NULL AND expires_at > 0 AND ${exp} <= ?`;
  const [customers, devices, licenses, activeLicenses, expiredLicenses, apps] = await Promise.all([
    isReseller ? env.DB.prepare("SELECT COUNT(*) as n FROM customers WHERE reseller_id = ?").bind(rid).first() : env.DB.prepare("SELECT COUNT(*) as n FROM customers").first(),
    isReseller ? env.DB.prepare("SELECT COUNT(*) as n FROM devices WHERE reseller_id = ?").bind(rid).first() : env.DB.prepare("SELECT COUNT(*) as n FROM devices").first(),
    isReseller ? env.DB.prepare("SELECT COUNT(*) as n FROM licenses WHERE reseller_id = ?").bind(rid).first() : env.DB.prepare("SELECT COUNT(*) as n FROM licenses").first(),
    isReseller ? env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE ${activeSql} AND reseller_id = ?`).bind(now, rid).first() : env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE ${activeSql}`).bind(now).first(),
    isReseller ? env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE ${expiredSql} AND reseller_id = ?`).bind(now, rid).first() : env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE ${expiredSql}`).bind(now).first(),
    env.DB.prepare("SELECT COUNT(*) as n FROM apps WHERE is_active = 1").first()
  ]);
  const out = {
    customers: num(customers, "n"),
    devices: num(devices, "n"),
    licenses: num(licenses, "n"),
    active_licenses: num(activeLicenses, "n"),
    expired_licenses: num(expiredLicenses, "n"),
    apps: num(apps, "n")
  };
  const week = 7 * 24 * 60 * 60 * 1e3;
  const soonSql = `status='active' AND expires_at IS NOT NULL AND expires_at > 0 AND ${exp} > ? AND ${exp} <= ?`;
  const expSoon = isReseller ? await env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE ${soonSql} AND reseller_id = ?`).bind(now, now + week, rid).first() : await env.DB.prepare(`SELECT COUNT(*) as n FROM licenses WHERE ${soonSql}`).bind(now, now + week).first();
  out.expiring_7d = num(expSoon, "n");
  if (isReseller) {
    const r = await env.DB.prepare("SELECT credit_balance FROM resellers WHERE id = ?").bind(rid).first();
    out.credit_balance = r ? r.credit_balance : 0;
  } else {
    const [resellers, paidLastMonth] = await Promise.all([
      env.DB.prepare("SELECT COUNT(*) as n FROM resellers").first(),
      env.DB.prepare(
        `SELECT COALESCE(SUM(amount_cents), 0) as cents
           FROM payments WHERE status = 'succeeded' AND paid_at > ?`
      ).bind(now - month).first()
    ]);
    out.resellers = num(resellers, "n");
    out.revenue_30d_cents = num(paidLastMonth, "cents");
  }
  return jsonResp(out);
}
__name(handleStatsOverview, "handleStatsOverview");
async function ensureDefewTvApp(env) {
  try {
    const exists = await env.DB.prepare("SELECT id FROM apps WHERE id = 'app_thefew_tv'").first();
    if (exists)
      return;
    const now = Date.now();
    await env.DB.prepare(
      `INSERT INTO apps
        (id, name, package_name, primary_color, default_playlist_type,
         download_url, is_active, created_at, updated_at)
       VALUES ('app_thefew_tv', 'DeFew TV', 'com.manzilionellm.tvking.tv',
               '#D63A30', 'xtream', 'https://app.7themotion.com/tv',
               1, ?, ?)`
    ).bind(now, now).run();
  } catch (_) {
  }
}
__name(ensureDefewTvApp, "ensureDefewTvApp");
async function handleAppsList(env, user) {
  await ensureDefewTvApp(env);
  const rs = await env.DB.prepare(
    `SELECT id, name, package_name, primary_color, tagline,
              default_iptv_server, default_playlist_type, pricing_json,
              download_url, is_active, created_at, updated_at
       FROM apps ORDER BY name ASC`
  ).all();
  const items = (rs.results || []).map((row) => {
    if (user && user.role === "reseller") {
      const { default_iptv_server, ...rest } = row;
      return rest;
    }
    return row;
  });
  return jsonResp({ items });
}
__name(handleAppsList, "handleAppsList");
async function handleAppsGet(env, id) {
  const row = await env.DB.prepare("SELECT * FROM apps WHERE id = ?").bind(id).first();
  if (!row)
    return errResp("not_found", "App not found", 404);
  return jsonResp(row);
}
__name(handleAppsGet, "handleAppsGet");
async function handleAppsCreate(request, env, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  if (!body.name || !body.package_name) {
    return errResp("missing_fields", "name and package_name required", 400);
  }
  const id = body.id || genId("app");
  const now = Date.now();
  try {
    await env.DB.prepare(
      `INSERT INTO apps
          (id, name, package_name, logo_url, primary_color, tagline,
           default_iptv_server, default_playlist_type, pricing_json,
           download_url, is_active, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      id,
      body.name,
      body.package_name,
      body.logo_url || null,
      body.primary_color || null,
      body.tagline || null,
      body.default_iptv_server || null,
      body.default_playlist_type || "xtream",
      body.pricing_json ? JSON.stringify(body.pricing_json) : null,
      body.download_url || null,
      body.is_active === false ? 0 : 1,
      now,
      now
    ).run();
  } catch (e) {
    return errResp("duplicate_package", `package_name already exists`, 409);
  }
  await logAudit(env, request, actor, "app.create", { type: "app", id }, null, body);
  return jsonResp({ id }, 201);
}
__name(handleAppsCreate, "handleAppsCreate");
async function handleAppsUpdate(request, env, id, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const before = await env.DB.prepare("SELECT * FROM apps WHERE id = ?").bind(id).first();
  if (!before)
    return errResp("not_found", "App not found", 404);
  const fields = [
    "name",
    "logo_url",
    "primary_color",
    "tagline",
    "default_iptv_server",
    "default_playlist_type",
    "pricing_json",
    "is_active"
  ];
  const sets = [];
  const vals = [];
  for (const f of fields) {
    if (body[f] !== void 0) {
      sets.push(`${f} = ?`);
      vals.push(f === "is_active" ? body[f] ? 1 : 0 : f === "pricing_json" && typeof body[f] === "object" ? JSON.stringify(body[f]) : body[f]);
    }
  }
  if (sets.length === 0)
    return jsonResp({ updated: 0 });
  sets.push("updated_at = ?");
  vals.push(Date.now());
  vals.push(id);
  await env.DB.prepare(`UPDATE apps SET ${sets.join(", ")} WHERE id = ?`).bind(...vals).run();
  await logAudit(env, request, actor, "app.update", { type: "app", id }, before, body);
  return jsonResp({ updated: 1 });
}
__name(handleAppsUpdate, "handleAppsUpdate");
async function ensureServersTable(env) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS default_servers (
         id TEXT PRIMARY KEY,
         label TEXT NOT NULL,
         url TEXT NOT NULL,
         position INTEGER NOT NULL DEFAULT 0,
         enabled INTEGER NOT NULL DEFAULT 1,
         created_at INTEGER NOT NULL,
         updated_at INTEGER NOT NULL
       )`
  ).run();
}
__name(ensureServersTable, "ensureServersTable");
async function ensureAnnouncementsTable(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS app_broadcasts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT, url TEXT, created_at INTEGER)"
  ).run();
  for (const col of [
    "kind TEXT",
    "cta TEXT",
    "country TEXT",
    "expires_at INTEGER",
    "active INTEGER DEFAULT 1"
  ]) {
    try {
      await env.DB.prepare(
        "ALTER TABLE app_broadcasts ADD COLUMN " + col
      ).run();
    } catch (_) {
    }
  }
}
__name(ensureAnnouncementsTable, "ensureAnnouncementsTable");
var ANNOUNCEMENT_KINDS = ["nouveaute", "promo", "info", "maintenance"];
async function handleAnnouncementsList(env) {
  await ensureAnnouncementsTable(env);
  const rs = await env.DB.prepare(
    "SELECT id, title, body, url, kind, cta, country, expires_at, active, created_at FROM app_broadcasts ORDER BY id DESC LIMIT 20"
  ).all();
  return jsonResp({ items: rs.results || [] });
}
__name(handleAnnouncementsList, "handleAnnouncementsList");
async function handleAnnouncementsUpdate(request, env, id, actor) {
  await ensureAnnouncementsTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const active = body.active ? 1 : 0;
  const r = await env.DB.prepare("UPDATE app_broadcasts SET active = ? WHERE id = ?").bind(active, id).run();
  await logAudit(
    env,
    request,
    actor,
    "announcement.toggle",
    { type: "app_broadcasts", id },
    null,
    { active }
  );
  return jsonResp({
    ok: true,
    updated: r.meta && r.meta.changes || 0,
    active: active === 1
  });
}
__name(handleAnnouncementsUpdate, "handleAnnouncementsUpdate");
async function handleAnnouncementsSettingsGet(env) {
  await ensureAppConfigTable(env);
  const v = await _cfgGetStr(env, "announcements_enabled");
  return jsonResp({ enabled: v !== "0" });
}
__name(handleAnnouncementsSettingsGet, "handleAnnouncementsSettingsGet");
async function handleAnnouncementsSettingsPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const enabled = body.enabled === false ? "0" : "1";
  await _cfgSet(env, "announcements_enabled", enabled);
  await logAudit(
    env,
    request,
    actor,
    "announcements.settings",
    { type: "app_config", id: null },
    null,
    { enabled }
  );
  return jsonResp({ ok: true, enabled: enabled === "1" });
}
__name(handleAnnouncementsSettingsPut, "handleAnnouncementsSettingsPut");
async function handleAnnouncementsCreate(request, env, actor) {
  await ensureAnnouncementsTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const title = (body.title || "").toString().trim().slice(0, 120);
  const msg = (body.body || "").toString().trim().slice(0, 500);
  const urlVal = (body.url || "").toString().trim().slice(0, 300);
  const kindRaw = (body.kind || "").toString().trim().toLowerCase();
  const kind = ANNOUNCEMENT_KINDS.includes(kindRaw) ? kindRaw : "";
  const cta = (body.cta || "").toString().trim().slice(0, 40);
  const countryRaw = (body.country || "").toString().trim().toUpperCase();
  const country = /^[A-Z]{2}$/.test(countryRaw) ? countryRaw : "";
  if (!title && !msg) {
    return errResp("missing_fields", "title or body required", 400);
  }
  const now = Date.now();
  let durationMin = parseInt(body.durationMin, 10);
  if (!Number.isFinite(durationMin) || durationMin < 0)
    durationMin = 0;
  if (durationMin > 1440)
    durationMin = 1440;
  const expiresAt = durationMin > 0 ? now + durationMin * 6e4 : 0;
  const res = await env.DB.prepare(
    "INSERT INTO app_broadcasts (title, body, url, kind, cta, country, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  ).bind(title, msg, urlVal, kind, cta, country, expiresAt, now).run();
  const id = res.meta && res.meta.last_row_id || null;
  await logAudit(
    env,
    request,
    actor,
    "announcement.create",
    { type: "announcement", id },
    null,
    { title, body: msg, kind, country, durationMin }
  );
  return jsonResp({ ok: true, id }, 201);
}
__name(handleAnnouncementsCreate, "handleAnnouncementsCreate");
async function handleAnnouncementsClear(env, actor, request) {
  await ensureAnnouncementsTable(env);
  await env.DB.prepare("DELETE FROM app_broadcasts").run();
  await logAudit(
    env,
    request,
    actor,
    "announcement.clear",
    { type: "announcement", id: null },
    null,
    null
  );
  return jsonResp({ ok: true });
}
__name(handleAnnouncementsClear, "handleAnnouncementsClear");
async function handleAnnouncementsDelete(env, id, actor, request) {
  await ensureAnnouncementsTable(env);
  await env.DB.prepare("DELETE FROM app_broadcasts WHERE id = ?").bind(id).run();
  await logAudit(
    env,
    request,
    actor,
    "announcement.delete",
    { type: "announcement", id },
    null,
    null
  );
  return jsonResp({ ok: true });
}
__name(handleAnnouncementsDelete, "handleAnnouncementsDelete");
var HOME_SECTION_KEYS = [
  "recent",
  "favorites",
  "sport",
  "entertainment",
  "info",
  "kids",
  "general",
  "cinema"
];
var HOME_RIBBONS = [
  "",
  "NOUVEAU",
  "POPULAIRE",
  "EXCLUSIF",
  "EN DIRECT",
  "VIP",
  "COUPE DU MONDE",
  "EURO 2028",
  "UFC",
  "CHAMPIONS LEAGUE"
];
async function ensureHomeLayoutTable(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS home_layout (key TEXT PRIMARY KEY, position INTEGER, enabled INTEGER DEFAULT 1, ribbon TEXT DEFAULT '', featured INTEGER DEFAULT 0, updated_at INTEGER)"
  ).run();
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS home_layout_history (id INTEGER PRIMARY KEY AUTOINCREMENT, payload_json TEXT, label TEXT, created_at INTEGER)"
  ).run();
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM home_layout").first();
  if (!row || !row.n) {
    const now = Date.now();
    for (let i = 0; i < HOME_SECTION_KEYS.length; i++) {
      await env.DB.prepare(
        "INSERT INTO home_layout (key, position, enabled, ribbon, featured, updated_at) VALUES (?, ?, 1, '', 0, ?)"
      ).bind(HOME_SECTION_KEYS[i], i, now).run();
    }
  }
}
__name(ensureHomeLayoutTable, "ensureHomeLayoutTable");
async function readHomeLayout(env) {
  await ensureHomeLayoutTable(env);
  const rs = await env.DB.prepare(
    "SELECT key, position, enabled, ribbon, featured, updated_at FROM home_layout ORDER BY position ASC, key ASC"
  ).all();
  const items = rs.results || [];
  let version = 0;
  for (const it of items) {
    if ((it.updated_at || 0) > version)
      version = it.updated_at;
  }
  return { items, version };
}
__name(readHomeLayout, "readHomeLayout");
async function handleHomeLayoutGet(env) {
  const data = await readHomeLayout(env);
  return jsonResp(data);
}
__name(handleHomeLayoutGet, "handleHomeLayoutGet");
async function handleHomeLayoutSave(request, env, actor) {
  await ensureHomeLayoutTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const items = Array.isArray(body.items) ? body.items : null;
  if (!items)
    return errResp("missing_fields", "items[] required", 400);
  const current = await readHomeLayout(env);
  await env.DB.prepare(
    "INSERT INTO home_layout_history (payload_json, label, created_at) VALUES (?, ?, ?)"
  ).bind(
    JSON.stringify(current.items),
    (body.label || "Modification accueil").toString().slice(0, 80),
    Date.now()
  ).run();
  const now = Date.now();
  let pos = 0;
  for (const it of items) {
    const key = (it.key || "").toString();
    if (!HOME_SECTION_KEYS.includes(key))
      continue;
    const ribbonRaw = (it.ribbon || "").toString();
    const ribbon = HOME_RIBBONS.includes(ribbonRaw) ? ribbonRaw : "";
    const enabled = it.enabled ? 1 : 0;
    const featured = it.featured ? 1 : 0;
    await env.DB.prepare(
      "INSERT INTO home_layout (key, position, enabled, ribbon, featured, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(key) DO UPDATE SET position=excluded.position, enabled=excluded.enabled, ribbon=excluded.ribbon, featured=excluded.featured, updated_at=excluded.updated_at"
    ).bind(key, pos, enabled, ribbon, featured, now).run();
    pos++;
  }
  await logAudit(
    env,
    request,
    actor,
    "home_layout.save",
    { type: "home_layout", id: null },
    current.items,
    items
  );
  const data = await readHomeLayout(env);
  return jsonResp({ ok: true, ...data });
}
__name(handleHomeLayoutSave, "handleHomeLayoutSave");
async function handleHomeLayoutHistory(env) {
  await ensureHomeLayoutTable(env);
  const rs = await env.DB.prepare(
    "SELECT id, label, created_at FROM home_layout_history ORDER BY id DESC LIMIT 20"
  ).all();
  return jsonResp({ items: rs.results || [] });
}
__name(handleHomeLayoutHistory, "handleHomeLayoutHistory");
async function handleHomeLayoutRestore(request, env, actor) {
  await ensureHomeLayoutTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const snapId = body.id;
  if (!snapId)
    return errResp("missing_fields", "id required", 400);
  const snap = await env.DB.prepare("SELECT payload_json FROM home_layout_history WHERE id = ?").bind(snapId).first();
  if (!snap)
    return errResp("not_found", "Snapshot introuvable", 404);
  let items;
  try {
    items = JSON.parse(snap.payload_json);
  } catch (_) {
    items = [];
  }
  const fakeReq = new Request("https://x/", {
    method: "PUT",
    body: JSON.stringify({ items, label: "Restauration #" + snapId })
  });
  return handleHomeLayoutSave(fakeReq, env, actor);
}
__name(handleHomeLayoutRestore, "handleHomeLayoutRestore");
async function ensureAppConfigTable(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT)"
  ).run();
}
__name(ensureAppConfigTable, "ensureAppConfigTable");
async function _cfgGet(env, key) {
  const row = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(key).first();
  return row ? parseInt(row.value, 10) || 0 : 0;
}
__name(_cfgGet, "_cfgGet");
async function _cfgSet(env, key, value) {
  await env.DB.prepare(
    "INSERT INTO app_config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
  ).bind(key, String(value)).run();
}
__name(_cfgSet, "_cfgSet");
function _fuSfx(platform) {
  return platform === "tv" ? "_tv" : "";
}
__name(_fuSfx, "_fuSfx");
async function handleForceUpdateGet(env, platform) {
  await ensureAppConfigTable(env);
  const s = _fuSfx(platform);
  return jsonResp({
    minBuildTs: await _cfgGet(env, "min_build_ts" + s),
    latestBuildTs: await _cfgGet(env, "latest_build_ts" + s)
  });
}
__name(handleForceUpdateGet, "handleForceUpdateGet");
async function handleForceUpdatePost(request, env, actor, platform) {
  await ensureAppConfigTable(env);
  const s = _fuSfx(platform);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const action = (body.action || "").toString();
  if (action === "force") {
    const latest = await _cfgGet(env, "latest_build_ts" + s);
    if (!latest) {
      return errResp(
        "no_build",
        "Aucun build r\xE9cent d\xE9tect\xE9. Ouvre la derni\xE8re app une fois pour qu'elle se signale, puis r\xE9essaie.",
        400
      );
    }
    await _cfgSet(env, "min_build_ts" + s, latest);
    await logAudit(
      env,
      request,
      actor,
      "force_update.on",
      { type: "app_config", id: null },
      null,
      { platform: platform || "mobile", min_build_ts: latest }
    );
    return jsonResp({ ok: true, minBuildTs: latest });
  }
  if (action === "disable") {
    await _cfgSet(env, "min_build_ts" + s, 0);
    await logAudit(
      env,
      request,
      actor,
      "force_update.off",
      { type: "app_config", id: null },
      null,
      { platform: platform || "mobile" }
    );
    return jsonResp({ ok: true, minBuildTs: 0 });
  }
  return errResp("bad_action", "action doit \xEAtre 'force' ou 'disable'", 400);
}
__name(handleForceUpdatePost, "handleForceUpdatePost");
function _themeSfx(platform) {
  return platform === "tv" ? "_tv" : "";
}
__name(_themeSfx, "_themeSfx");
async function handleThemeGet(env, platform) {
  await ensureAppConfigTable(env);
  const s = _themeSfx(platform);
  return jsonResp({
    appName: await _cfgGetStr(env, "theme_name" + s),
    accent: await _cfgGetStr(env, "theme_accent" + s),
    bg: await _cfgGetStr(env, "theme_bg" + s)
  });
}
__name(handleThemeGet, "handleThemeGet");
async function handleThemeAutomationsGet(env, platform) {
  await ensureAppConfigTable(env);
  const raw = await _cfgGetStr(env, "theme_automations" + _themeSfx(platform));
  let rules = [];
  try {
    rules = raw ? JSON.parse(raw) : [];
  } catch (_) {
    rules = [];
  }
  return jsonResp({ rules: Array.isArray(rules) ? rules : [] });
}
__name(handleThemeAutomationsGet, "handleThemeAutomationsGet");
async function handleThemeAutomationsPut(request, env, actor, platform) {
  await ensureAppConfigTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const inRules = Array.isArray(body.rules) ? body.rules : [];
  const clean = inRules.slice(0, 50).map((r) => {
    let accent = (r && r.accent ? String(r.accent) : "").trim();
    if (accent && /^#?[0-9a-fA-F]{6}$/.test(accent)) {
      accent = (accent[0] === "#" ? accent : "#" + accent).toUpperCase();
    } else {
      accent = "";
    }
    const month = Number(r && r.month);
    return {
      enabled: !!(r && r.enabled),
      label: (r && r.label ? String(r.label) : "").slice(0, 40),
      month: month >= 1 && month <= 12 ? month : null,
      from: r && /^\d{4}$/.test(String(r.from)) ? String(r.from) : null,
      to: r && /^\d{4}$/.test(String(r.to)) ? String(r.to) : null,
      accent,
      bg: r && (r.bg === "light" || r.bg === "dark") ? r.bg : "",
      appName: (r && r.appName ? String(r.appName) : "").slice(0, 40)
    };
  });
  await _cfgSet(env, "theme_automations" + _themeSfx(platform), JSON.stringify(clean));
  await logAudit(
    env,
    request,
    actor,
    "theme.automations.save",
    { type: "app_config", id: null },
    null,
    { count: clean.length }
  );
  return jsonResp({ ok: true, rules: clean });
}
__name(handleThemeAutomationsPut, "handleThemeAutomationsPut");
async function handleThemePut(request, env, actor, platform) {
  await ensureAppConfigTable(env);
  const s = _themeSfx(platform);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const appName = (body.appName == null ? "" : String(body.appName)).trim().slice(0, 40);
  let accent = (body.accent == null ? "" : String(body.accent)).trim();
  const bg = body.bg === "light" ? "light" : body.bg === "dark" ? "dark" : "";
  if (accent && !/^#?[0-9a-fA-F]{6}$/.test(accent)) {
    return errResp("bad_color", "Couleur invalide (format #RRGGBB)", 400);
  }
  if (accent && accent[0] !== "#")
    accent = "#" + accent;
  accent = accent.toUpperCase();
  await _cfgSet(env, "theme_name" + s, appName);
  await _cfgSet(env, "theme_accent" + s, accent);
  await _cfgSet(env, "theme_bg" + s, bg);
  await logAudit(
    env,
    request,
    actor,
    "theme.save",
    { type: "app_config", id: null },
    null,
    { platform: platform || "mobile", appName, accent, bg }
  );
  return jsonResp({ ok: true, appName, accent, bg });
}
__name(handleThemePut, "handleThemePut");
async function handleAdGet(env) {
  await ensureAppConfigTable(env);
  const skip = parseInt(await _cfgGetStr(env, "ad_skip"), 10);
  return jsonResp({
    enabled: await _cfgGetStr(env, "ad_enabled") === "1",
    url: await _cfgGetStr(env, "ad_url"),
    skip: Number.isFinite(skip) ? skip : 5,
    freq: await _cfgGetStr(env, "ad_freq") || "always"
  });
}
__name(handleAdGet, "handleAdGet");
async function handleAdPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const url = (body.url == null ? "" : String(body.url)).trim().slice(0, 500);
  const enabled = body.enabled ? "1" : "0";
  let skip = parseInt(body.skip, 10);
  if (!Number.isFinite(skip) || skip < 0)
    skip = 5;
  if (skip > 60)
    skip = 60;
  const freq = body.freq === "daily" ? "daily" : "always";
  await _cfgSet(env, "ad_url", url);
  await _cfgSet(env, "ad_enabled", enabled);
  await _cfgSet(env, "ad_skip", String(skip));
  await _cfgSet(env, "ad_freq", freq);
  await logAudit(
    env,
    request,
    actor,
    "ad.save",
    { type: "app_config", id: null },
    null,
    { url, enabled, skip, freq }
  );
  return jsonResp({ ok: true, enabled: enabled === "1", url, skip, freq });
}
__name(handleAdPut, "handleAdPut");
function cleanHttpsUrl(v) {
  const s = (v == null ? "" : String(v)).trim().slice(0, 500);
  if (!s)
    return "";
  if (!/^https:\/\//i.test(s))
    return "";
  return s;
}
__name(cleanHttpsUrl, "cleanHttpsUrl");
function cleanBlockText(v, max) {
  return (v == null ? "" : String(v)).replace(/[\u0000-\u001F]/g, "").trim().slice(0, max);
}
__name(cleanBlockText, "cleanBlockText");
async function handlePricingGet(env) {
  await ensureAppConfigTable(env);
  const td = parseInt(await _cfgGetStr(env, "trial_days"), 10);
  return jsonResp({
    currency: await _cfgGetStr(env, "price_currency") || "\u20AC",
    lifetime: await _cfgGetStr(env, "price_lifetime") || "9,9",
    yearly: await _cfgGetStr(env, "price_yearly") || "4,9",
    trialDays: Number.isFinite(td) && td >= 0 ? td : 7,
    promoEnabled: await _cfgGetStr(env, "promo_enabled") === "1",
    promoMessage: await _cfgGetStr(env, "promo_msg"),
    // Textes de l'écran « essai terminé ». Vides = l'app utilise son
    // texte intégré. Le lien de paiement vide = on ne invente rien,
    // l'app garde WhatsApp / le site déjà dans le projet.
    blockTitleFr: await _cfgGetStr(env, "trial_block_title_fr"),
    blockBodyFr: await _cfgGetStr(env, "trial_block_body_fr"),
    blockTitleEn: await _cfgGetStr(env, "trial_block_title_en"),
    blockBodyEn: await _cfgGetStr(env, "trial_block_body_en"),
    payUrl: await _cfgGetStr(env, "trial_pay_url"),
    // Lecture seule : l'interrupteur est une variable d'environnement,
    // pas un bouton du panel (pour ne pas bloquer les clients par erreur).
    trialEnforced: trialEnforcementOn(env)
  });
}
__name(handlePricingGet, "handlePricingGet");
async function handlePricingPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const cleanPrice = /* @__PURE__ */ __name((v) => (v == null ? "" : String(v)).trim().slice(0, 12), "cleanPrice");
  const lifetime = cleanPrice(body.lifetime) || "9,9";
  const yearly = cleanPrice(body.yearly) || "4,9";
  const currency = (body.currency == null ? "\u20AC" : String(body.currency)).trim().slice(0, 4) || "\u20AC";
  let trialDays = parseInt(body.trialDays, 10);
  if (!Number.isFinite(trialDays) || trialDays < 0)
    trialDays = 7;
  if (trialDays > 365)
    trialDays = 365;
  const promoMessage = (body.promoMessage == null ? "" : String(body.promoMessage)).trim().slice(0, 240);
  const promoEnabled = body.promoEnabled ? "1" : "0";
  await _cfgSet(env, "price_lifetime", lifetime);
  await _cfgSet(env, "price_yearly", yearly);
  await _cfgSet(env, "price_currency", currency);
  await _cfgSet(env, "trial_days", String(trialDays));
  await _cfgSet(env, "promo_msg", promoMessage);
  await _cfgSet(env, "promo_enabled", promoEnabled);
  let blockTitleFr = await _cfgGetStr(env, "trial_block_title_fr");
  let blockBodyFr = await _cfgGetStr(env, "trial_block_body_fr");
  let blockTitleEn = await _cfgGetStr(env, "trial_block_title_en");
  let blockBodyEn = await _cfgGetStr(env, "trial_block_body_en");
  let payUrl = await _cfgGetStr(env, "trial_pay_url");
  if (body.blockTitleFr !== void 0) {
    blockTitleFr = cleanBlockText(body.blockTitleFr, 120);
    await _cfgSet(env, "trial_block_title_fr", blockTitleFr);
  }
  if (body.blockBodyFr !== void 0) {
    blockBodyFr = cleanBlockText(body.blockBodyFr, 500);
    await _cfgSet(env, "trial_block_body_fr", blockBodyFr);
  }
  if (body.blockTitleEn !== void 0) {
    blockTitleEn = cleanBlockText(body.blockTitleEn, 120);
    await _cfgSet(env, "trial_block_title_en", blockTitleEn);
  }
  if (body.blockBodyEn !== void 0) {
    blockBodyEn = cleanBlockText(body.blockBodyEn, 500);
    await _cfgSet(env, "trial_block_body_en", blockBodyEn);
  }
  if (body.payUrl !== void 0) {
    payUrl = cleanHttpsUrl(body.payUrl);
    await _cfgSet(env, "trial_pay_url", payUrl);
  }
  await logAudit(
    env,
    request,
    actor,
    "pricing.save",
    { type: "app_config", id: null },
    null,
    { lifetime, yearly, currency, trialDays, promoEnabled }
  );
  return jsonResp({
    ok: true,
    currency,
    lifetime,
    yearly,
    trialDays,
    promoEnabled: promoEnabled === "1",
    promoMessage,
    blockTitleFr,
    blockBodyFr,
    blockTitleEn,
    blockBodyEn,
    payUrl,
    trialEnforced: trialEnforcementOn(env)
  });
}
__name(handlePricingPut, "handlePricingPut");
async function handleGrantTrialAll(request, env, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }
  let days = parseInt(body && body.days, 10);
  if (!Number.isFinite(days) || days <= 0)
    days = 7;
  if (days > 365)
    days = 365;
  const now = Date.now();
  const newExpiry = now + days * 24 * 60 * 60 * 1e3;
  const res = await env.DB.prepare(
    "UPDATE licenses SET expires_at = ?, updated_at = ? WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at < ?"
  ).bind(newExpiry, now, newExpiry).run();
  const updated = res && res.meta && res.meta.changes || 0;
  await logAudit(
    env,
    request,
    actor,
    "licenses.grant_trial_all",
    { type: "license", id: null },
    null,
    { days, updated, expires_at: newExpiry }
  );
  return jsonResp({ ok: true, days, updated, expires_at: newExpiry });
}
__name(handleGrantTrialAll, "handleGrantTrialAll");
async function handleFeedbackPromptGet(env) {
  await ensureAppConfigTable(env);
  return jsonResp({
    enabled: await _cfgGetStr(env, "feedback_enabled") === "1",
    message: await _cfgGetStr(env, "feedback_msg")
  });
}
__name(handleFeedbackPromptGet, "handleFeedbackPromptGet");
async function handleFeedbackPromptPut(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const message = (body.message == null ? "" : String(body.message)).trim().slice(0, 500);
  const enabled = body.enabled ? "1" : "0";
  await _cfgSet(env, "feedback_enabled", enabled);
  await _cfgSet(env, "feedback_msg", message);
  await logAudit(
    env,
    request,
    actor,
    "feedback_prompt.save",
    { type: "app_config", id: null },
    null,
    { enabled, message }
  );
  return jsonResp({ ok: true, enabled: enabled === "1", message });
}
__name(handleFeedbackPromptPut, "handleFeedbackPromptPut");
async function handleFeedbackList(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS feedback (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, country TEXT, rating INTEGER, message TEXT, created_at INTEGER)"
  ).run();
  const rows = await env.DB.prepare(
    "SELECT id, mac, country, rating, message, created_at FROM feedback ORDER BY created_at DESC LIMIT 500"
  ).all();
  return jsonResp({ items: rows && rows.results || [] });
}
__name(handleFeedbackList, "handleFeedbackList");
async function _cfgGetStr(env, key) {
  const row = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(key).first();
  return row ? row.value || "" : "";
}
__name(_cfgGetStr, "_cfgGetStr");
async function handleFeaturedGet(env) {
  await ensureAppConfigTable(env);
  return jsonResp({
    name: await _cfgGetStr(env, "featured_name"),
    note: await _cfgGetStr(env, "featured_note")
  });
}
__name(handleFeaturedGet, "handleFeaturedGet");
async function handleFeaturedPost(request, env, actor) {
  await ensureAppConfigTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const name = (body.name || "").toString().trim().slice(0, 80);
  const note = (body.note || "").toString().trim().slice(0, 120);
  await _cfgSet(env, "featured_name", name);
  await _cfgSet(env, "featured_note", note);
  await logAudit(
    env,
    request,
    actor,
    "featured.set",
    { type: "app_config", id: null },
    null,
    { name, note }
  );
  return jsonResp({ ok: true, name, note });
}
__name(handleFeaturedPost, "handleFeaturedPost");
async function handleOnlineGet(request, env) {
  try {
    await env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS presence (mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER)"
    ).run();
  } catch (_) {
  }
  const now = Date.now();
  const ONLINE_MS = 15 * 60 * 1e3;
  const DAY_MS3 = 24 * 60 * 60 * 1e3;
  try {
    await env.DB.prepare("ALTER TABLE presence ADD COLUMN channel TEXT").run();
  } catch (_) {
  }
  const { limit, offset } = parsePageQuery(new URL(request.url), {
    defaultLimit: 100,
    maxLimit: 200
  });
  const seen = epochSql("last_seen");
  const onlineSince = now - ONLINE_MS;
  const daySince = now - DAY_MS3;
  const onlineCountRow = await env.DB.prepare(`SELECT COUNT(*) as n FROM presence WHERE ${seen} > ?`).bind(onlineSince).first();
  const todayCountRow = await env.DB.prepare(`SELECT COUNT(*) as n FROM presence WHERE ${seen} > ?`).bind(daySince).first();
  const countries = await env.DB.prepare(
    `SELECT UPPER(country) as c, COUNT(*) as n FROM presence
        WHERE ${seen} > ? AND country IS NOT NULL AND LENGTH(TRIM(country)) = 2
        GROUP BY UPPER(country)`
  ).bind(onlineSince).all();
  const rs = await env.DB.prepare(
    `SELECT mac, ip, country, last_seen, channel FROM presence
        WHERE ${seen} > ?
        ORDER BY ${seen} DESC LIMIT ? OFFSET ?`
  ).bind(onlineSince, limit, offset).all();
  const byCountry = {};
  for (const r of countries.results || []) {
    const c = String(r.c || "").toUpperCase();
    if (!/^[A-Z]{2}$/.test(c))
      continue;
    byCountry[c] = num(r, "n");
  }
  const onlineCount = num(onlineCountRow, "n");
  const items = (rs.results || []).map((r) => ({
    mac: r.mac,
    ip: r.ip || "",
    country: /^[A-Za-z]{2}$/.test(r.country || "") ? String(r.country).toUpperCase() : "",
    lastSeen: epochMs(r.last_seen) || 0,
    channel: r.channel || ""
  }));
  return jsonResp({
    onlineCount,
    todayCount: num(todayCountRow, "n"),
    byCountry,
    ...pageEnvelope(items, onlineCount, limit, offset)
  });
}
__name(handleOnlineGet, "handleOnlineGet");
async function handleServersList(env) {
  await ensureServersTable(env);
  const rs = await env.DB.prepare(
    `SELECT id, label, url, position, enabled, created_at, updated_at
         FROM default_servers
        ORDER BY position ASC, created_at ASC`
  ).all();
  return jsonResp({ items: rs.results || [] });
}
__name(handleServersList, "handleServersList");
async function handleServersCreate(request, env, actor) {
  await ensureServersTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const label = (body.label || "").trim();
  const urlVal = (body.url || "").trim();
  if (!label || !urlVal) {
    return errResp("missing_fields", "label and url required", 400);
  }
  const position = Number.isFinite(body.position) ? body.position : null;
  const id = body.id || genId("srv");
  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO default_servers
        (id, label, url, position, enabled, created_at, updated_at)
       SELECT ?, ?, ?, COALESCE(?, (SELECT COALESCE(MAX(position), 0) + 1 FROM default_servers)), ?, ?, ?`
  ).bind(id, label, urlVal, position, body.enabled === false ? 0 : 1, now, now).run();
  await logAudit(
    env,
    request,
    actor,
    "server.create",
    { type: "server", id },
    null,
    { label, url: urlVal }
  );
  return jsonResp({ id }, 201);
}
__name(handleServersCreate, "handleServersCreate");
async function handleServersUpdate(request, env, id, actor) {
  await ensureServersTable(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const before = await env.DB.prepare("SELECT * FROM default_servers WHERE id = ?").bind(id).first();
  if (!before)
    return errResp("not_found", "Server not found", 404);
  const fields = ["label", "url", "position", "enabled"];
  const sets = [];
  const vals = [];
  for (const f of fields) {
    if (body[f] !== void 0) {
      sets.push(`${f} = ?`);
      vals.push(f === "enabled" ? body[f] ? 1 : 0 : body[f]);
    }
  }
  if (sets.length === 0)
    return jsonResp({ updated: 0 });
  sets.push("updated_at = ?");
  vals.push(Date.now());
  vals.push(id);
  await env.DB.prepare(`UPDATE default_servers SET ${sets.join(", ")} WHERE id = ?`).bind(...vals).run();
  await logAudit(
    env,
    request,
    actor,
    "server.update",
    { type: "server", id },
    before,
    body
  );
  return jsonResp({ updated: 1 });
}
__name(handleServersUpdate, "handleServersUpdate");
async function handleServersDelete(request, env, id, actor) {
  await ensureServersTable(env);
  const before = await env.DB.prepare("SELECT * FROM default_servers WHERE id = ?").bind(id).first();
  if (!before)
    return errResp("not_found", "Server not found", 404);
  await env.DB.prepare("DELETE FROM default_servers WHERE id = ?").bind(id).run();
  await logAudit(
    env,
    request,
    actor,
    "server.delete",
    { type: "server", id },
    before,
    null
  );
  return jsonResp({ deleted: 1 });
}
__name(handleServersDelete, "handleServersDelete");
async function handleCustomersList(request, env, user) {
  const url = new URL(request.url);
  const search = (url.searchParams.get("q") || "").trim();
  const { limit, offset } = parsePageQuery(url);
  const where = [];
  const binds = [];
  if (search) {
    where.push("(email LIKE ? OR name LIKE ? OR phone LIKE ?)");
    binds.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
  if (user && user.role === "reseller") {
    where.push("reseller_id = ?");
    binds.push(user.sub);
  }
  const whereSql = where.length ? " WHERE " + where.join(" AND ") : "";
  const page = await pagedQuery(
    env,
    `SELECT COUNT(*) as n FROM customers${whereSql}`,
    binds,
    `SELECT id, email, name, phone, reseller_id, created_at
       FROM customers${whereSql}
      ORDER BY created_at DESC LIMIT ? OFFSET ?`,
    binds,
    limit,
    offset
  );
  page.items = page.items.map((row) => ({ ...row, created_at: epochMs(row.created_at) }));
  return jsonResp(page);
}
__name(handleCustomersList, "handleCustomersList");
async function handleCustomersGet(env, id, user) {
  const row = await env.DB.prepare("SELECT * FROM customers WHERE id = ?").bind(id).first();
  const gate = customerForActor(row, user);
  if (gate.error)
    return gate.error;
  return jsonResp(customerView(gate.row));
}
__name(handleCustomersGet, "handleCustomersGet");
function customerView(row) {
  if (!row)
    return row;
  const { password_hash, ...rest } = row;
  return rest;
}
__name(customerView, "customerView");
function customerForActor(row, user) {
  if (!row)
    return { error: errResp("not_found", "Customer not found", 404) };
  if (user && user.role === "reseller" && row.reseller_id !== user.sub) {
    return { error: errResp("forbidden", "Ce client ne vous appartient pas", 403) };
  }
  return { row };
}
__name(customerForActor, "customerForActor");
async function handleCustomersCreate(request, env, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const id = genId("cus");
  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO customers (id, email, name, phone, reseller_id, notes,
                              created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    id,
    body.email || null,
    body.name || null,
    body.phone || null,
    user && user.role === "reseller" ? user.sub : body.reseller_id || null,
    body.notes || null,
    now,
    now
  ).run();
  await logAudit(env, request, actor, "customer.create", { type: "customer", id }, null, {
    email: body.email || null,
    name: body.name || null
  });
  return jsonResp({ id }, 201);
}
__name(handleCustomersCreate, "handleCustomersCreate");
async function handleCustomersUpdate(request, env, id, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const before = await env.DB.prepare("SELECT * FROM customers WHERE id = ?").bind(id).first();
  const gate = customerForActor(before, user);
  if (gate.error)
    return gate.error;
  const fields = ["email", "name", "phone", "notes"];
  if (user && user.role !== "reseller")
    fields.push("reseller_id");
  const sets = [];
  const vals = [];
  for (const f of fields) {
    if (body[f] !== void 0) {
      sets.push(`${f} = ?`);
      vals.push(body[f]);
    }
  }
  if (sets.length === 0)
    return jsonResp({ updated: 0 });
  sets.push("updated_at = ?");
  vals.push(Date.now());
  vals.push(id);
  await env.DB.prepare(`UPDATE customers SET ${sets.join(", ")} WHERE id = ?`).bind(...vals).run();
  await logAudit(
    env,
    request,
    actor,
    "customer.update",
    { type: "customer", id },
    customerView(before),
    redactSecrets(body)
  );
  return jsonResp({ updated: 1 });
}
__name(handleCustomersUpdate, "handleCustomersUpdate");
async function handleCustomerDevices(env, customerId, user) {
  if (user && user.role === "reseller") {
    const parent = await env.DB.prepare("SELECT reseller_id FROM customers WHERE id = ?").bind(customerId).first();
    const gate = customerForActor(parent, user);
    if (gate.error)
      return gate.error;
  }
  const rs = await env.DB.prepare(
    `SELECT id, mac, label, first_seen_at, last_seen_at
       FROM devices WHERE customer_id = ? ORDER BY last_seen_at DESC`
  ).bind(customerId).all();
  return jsonResp({ items: rs.results || [] });
}
__name(handleCustomerDevices, "handleCustomerDevices");
async function ensureSourcesTable(env) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS device_sources (
         mac        TEXT PRIMARY KEY,
         type       TEXT NOT NULL,
         label      TEXT,
         server_url TEXT,
         username   TEXT,
         password   TEXT,
         m3u_url    TEXT,
         epg_url    TEXT,
         updated_at INTEGER NOT NULL
       )`
  ).run();
  try {
    await env.DB.prepare("ALTER TABLE device_sources ADD COLUMN sources_json TEXT").run();
  } catch (_) {
  }
  try {
    await env.DB.prepare("ALTER TABLE device_sources ADD COLUMN origin TEXT").run();
  } catch (_) {
  }
  try {
    await env.DB.prepare("ALTER TABLE device_sources ADD COLUMN reseller_id TEXT").run();
  } catch (_) {
  }
}
__name(ensureSourcesTable, "ensureSourcesTable");
function normalizeSource(raw) {
  if (!raw || typeof raw !== "object") {
    return { error: "source object required" };
  }
  const off = raw.enabled === false ? { enabled: false } : {};
  const type = (raw.type || "").trim().toLowerCase();
  const label = (raw.label || "").trim() || null;
  const epgRaw = (raw.epg_url || "").trim();
  let epg = null;
  if (epgRaw) {
    const epgErr = httpUrlError(epgRaw, "epg_url");
    if (epgErr)
      return { error: epgErr };
    epg = epgRaw;
  }
  if (type === "xtream") {
    const server = (raw.server_url || "").trim();
    const user = (raw.username || "").trim();
    const pass = (raw.password || "").trim();
    if (!server || !user || !pass) {
      return { error: "xtream requires server_url, username, password" };
    }
    const serverErr = sourceUrlProblem(server, "server_url");
    if (serverErr)
      return { error: serverErr };
    const credErr = sourceTextProblem(user, "username") || sourceTextProblem(pass, "password");
    if (credErr)
      return { error: credErr };
    return { source: { type, label, server_url: server, username: user, password: pass, m3u_url: null, epg_url: epg, ...off } };
  }
  if (type === "m3u") {
    const m3u = (raw.m3u_url || "").trim();
    if (!m3u)
      return { error: "m3u requires m3u_url" };
    const m3uErr = sourceUrlProblem(m3u, "m3u_url");
    if (m3uErr)
      return { error: m3uErr };
    return { source: { type, label, server_url: null, username: null, password: null, m3u_url: m3u, epg_url: epg, ...off } };
  }
  return { error: "type must be 'xtream' or 'm3u'" };
}
__name(normalizeSource, "normalizeSource");
async function upsertDeviceSource(env, mac, sources, resellerId = null, revision = null) {
  await ensureSourcesTable(env);
  const panelItems = coerceSourceList(sources).map((s) => ({ ...s, origin: "panel" }));
  const out = await casWriteSources(env, mac, (row, items) => ({
    items: [...panelItems, ...items.filter((s) => s && s.origin === "self")]
  }), { resellerId, revision });
  if (out.conflict)
    return { conflict: true };
  await clearSourceTombstone(env, mac);
  return { ok: true, rev: out.rev };
}
__name(upsertDeviceSource, "upsertDeviceSource");
async function assertSourceAccess(env, user, mac) {
  if (!user || user.role !== "reseller")
    return null;
  await ensureSourcesTable(env);
  const dev = await env.DB.prepare("SELECT reseller_id FROM devices WHERE mac = ?").bind(mac).first();
  if (dev && dev.reseller_id === user.sub)
    return null;
  if (dev && dev.reseller_id && dev.reseller_id !== user.sub) {
    return errResp("forbidden", "Cet appareil ne vous appartient pas", 403);
  }
  const src = await env.DB.prepare("SELECT reseller_id FROM device_sources WHERE mac = ?").bind(mac).first();
  if (!src || src.reseller_id === user.sub)
    return null;
  return errResp("forbidden", "Cette source ne vous appartient pas", 403);
}
__name(assertSourceAccess, "assertSourceAccess");
async function clearPanelSources(env, mac, revision = null) {
  await ensureSourcesTable(env);
  const out = await casWriteSources(env, mac, (row, items) => ({
    items: items.filter((s) => s && s.origin === "self")
  }), { revision });
  if (out.conflict)
    return { conflict: true };
  return { ok: true, rev: out.rev };
}
__name(clearPanelSources, "clearPanelSources");
function decodeMac(mac) {
  try {
    return decodeURIComponent(mac);
  } catch (_) {
    return mac;
  }
}
__name(decodeMac, "decodeMac");
async function sourceMacForActor(env, mac, user) {
  const m = decodeMac(mac).trim().toUpperCase();
  if (user && user.role === "reseller") {
    const dev = await env.DB.prepare("SELECT reseller_id FROM devices WHERE mac = ?").bind(m).first();
    if (!dev || dev.reseller_id !== user.sub) {
      return { error: errResp("forbidden", "Cet appareil ne vous appartient pas", 403) };
    }
  }
  return { mac: m };
}
__name(sourceMacForActor, "sourceMacForActor");
async function handleSourceGet(env, mac, user) {
  const gate = await sourceMacForActor(env, mac, user);
  if (gate.error)
    return gate.error;
  const m = gate.mac;
  await ensureSourcesTable(env);
  const access = await assertSourceAccess(env, user, m);
  if (access)
    return access;
  const row = await env.DB.prepare("SELECT * FROM device_sources WHERE mac = ?").bind(m).first();
  let sources = [];
  if (row && row.sources_json) {
    try {
      sources = JSON.parse(row.sources_json) || [];
    } catch (_) {
      sources = [];
    }
  }
  if (!sources.length && row) {
    const { sources_json, mac: _mac, updated_at, ...single } = row;
    sources = [single];
  }
  sources = await openSourceList(env, sources);
  return jsonResp({ mac: m, source: sources[0] || null, sources });
}
__name(handleSourceGet, "handleSourceGet");
async function handleSourcePut(request, env, mac, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const gate = await sourceMacForActor(env, mac, user);
  if (gate.error)
    return gate.error;
  const m = gate.mac;
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
    return errResp("bad_mac", "mac must be MK:XX:XX:XX:XX:XX", 400);
  }
  const access = await assertSourceAccess(env, user, m);
  if (access)
    return access;
  let rawList = Array.isArray(body.sources) ? body.sources : [body.source || body];
  rawList = rawList.slice(0, 3);
  const sources = [];
  for (const raw of rawList) {
    const norm = normalizeSource(raw);
    if (norm.error)
      return errResp("bad_source", norm.error, 400);
    sources.push(norm.source);
  }
  if (sources.length === 0) {
    return errResp("bad_source", "at least one source required", 400);
  }
  const resellerId = user && user.role === "reseller" ? user.sub : null;
  const opts = orderOpts(request);
  const written = await upsertDeviceSource(env, m, sources, resellerId, { traceId: opts.traceId, actor });
  if (written.conflict) {
    return errResp("sources_conflict", "Les listes de cette box changent en ce moment. R\xE9essaie.", 409);
  }
  const rev = written.rev;
  await logAudit(
    env,
    request,
    actor,
    "source.set",
    { type: "device_source", id: m },
    null,
    { count: sources.length, types: sources.map((s) => s.type), rev }
  );
  const orderId = await notifyBox(env, m, "source", { ...orderOpts(request), configRev: rev });
  return jsonResp({ ok: true, mac: m, count: sources.length, rev, order_id: orderId, trace_id: opts.traceId });
}
__name(handleSourcePut, "handleSourcePut");
async function handleSourceDelete(request, env, mac, actor, user) {
  const gate = await sourceMacForActor(env, mac, user);
  if (gate.error)
    return gate.error;
  const m = gate.mac;
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
    return errResp("bad_mac", "mac must be MK:XX:XX:XX:XX:XX", 400);
  }
  await ensureSourcesTable(env);
  const access = await assertSourceAccess(env, user, m);
  if (access)
    return access;
  const cleared = await clearPanelSources(env, m, { traceId: request.headers.get("X-Request-Id"), actor });
  if (cleared.conflict) {
    return errResp("sources_conflict", "Les listes de cette box changent en ce moment. R\xE9essaie.", 409);
  }
  await markSourcesCleared(env, m, Date.now());
  const rev = cleared.rev;
  await logAudit(
    env,
    request,
    actor,
    "source.clear",
    { type: "device_source", id: m },
    null,
    { rev }
  );
  const orderId = await notifyBox(env, m, "source_clear", { ...orderOpts(request), configRev: rev });
  return jsonResp({ ok: true, mac: m, rev, order_id: orderId });
}
__name(handleSourceDelete, "handleSourceDelete");
async function handleSourceRevisions(env, mac, user) {
  const gate = await sourceMacForActor(env, mac, user);
  if (gate.error)
    return gate.error;
  return jsonResp({ mac: gate.mac, ...await revisionView(env, gate.mac) });
}
__name(handleSourceRevisions, "handleSourceRevisions");
async function handleSourceRollback(request, env, mac, actor, user) {
  let body = {};
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }
  const gate = await sourceMacForActor(env, mac, user);
  if (gate.error)
    return gate.error;
  const m = gate.mac;
  const access = await assertSourceAccess(env, user, m);
  if (access)
    return access;
  const view = await revisionView(env, m);
  const target = Number(body.rev) || view.last_good_revision;
  if (!target)
    return errResp("no_good_revision", "Aucune r\xE9vision confirm\xE9e par la box : rien vers quoi revenir.", 409);
  const row = await revisionPanelJson(env, m, target);
  if (!row)
    return errResp("not_found", "R\xE9vision inconnue.", 404);
  if (row.state !== "acknowledged") {
    return errResp("revision_not_good", "Seule une r\xE9vision confirm\xE9e par la box peut \xEAtre republi\xE9e.", 409);
  }
  let sealed = [];
  try {
    sealed = JSON.parse(row.panel_json) || [];
  } catch (_) {
    sealed = [];
  }
  const opened = await openSourceList(env, sealed);
  const sources = [];
  for (const raw of opened) {
    const norm = normalizeSource(raw);
    if (norm.error)
      return errResp("bad_revision", norm.error, 409);
    sources.push(norm.source);
  }
  const resellerId = user && user.role === "reseller" ? user.sub : null;
  const opts = orderOpts(request);
  const revision = { traceId: opts.traceId, actor, rollbackOf: target };
  const written = sources.length ? await upsertDeviceSource(env, m, sources, resellerId, revision) : await clearPanelSources(env, m, revision);
  if (written.conflict) {
    return errResp("sources_conflict", "Les listes de cette box changent en ce moment. R\xE9essaie.", 409);
  }
  const rev = written.rev;
  await logAudit(
    env,
    request,
    actor,
    "source.rollback",
    { type: "device_source", id: m },
    { rev: view.current_revision },
    { rev, rollback_of: target }
  );
  const orderId = await notifyBox(env, m, "source", { ...orderOpts(request), configRev: rev });
  return jsonResp({ ok: true, mac: m, rev, rollback_of: target, order_id: orderId, trace_id: opts.traceId });
}
__name(handleSourceRollback, "handleSourceRollback");
async function visibleMacs(env, user, macs) {
  if (!user || user.role !== "reseller" || !macs.length)
    return macs;
  const marks = macs.map(() => "?").join(",");
  const rows = (await env.DB.prepare(
    `SELECT mac FROM devices WHERE mac IN (${marks}) AND reseller_id = ?`
  ).bind(...macs, user.sub).all()).results || [];
  const ok = new Set(rows.map((r) => r.mac));
  return macs.filter((x) => ok.has(x));
}
__name(visibleMacs, "visibleMacs");
function orderView(r) {
  return {
    order_id: r.order_id,
    mac: r.mac,
    customer_id: r.customer_id,
    device_id: r.device_id,
    kind: r.kind,
    op: r.op,
    trace_id: r.trace_id,
    state: effectiveState(r),
    late_ack: !!r.late_ack,
    config_rev: r.config_rev,
    applied_rev: r.applied_rev,
    t0_client: r.t0_client,
    t1_api: r.t1_api,
    t2_commit: r.t2_commit,
    t3_published: r.t3_published,
    received_at: r.received_at,
    received_srv: r.received_srv,
    applied_at: r.applied_at,
    applied_srv: r.applied_srv,
    failed_at: r.failed_at,
    failed_srv: r.failed_srv,
    result: r.result,
    error_code: r.error_code,
    error_message: r.error_message,
    app_version: r.app_version,
    created_at: r.created_at
  };
}
__name(orderView, "orderView");
async function handleOrdersList(request, env, user) {
  const url = new URL(request.url);
  const trace = (url.searchParams.get("trace") || "").trim();
  const macRaw = (url.searchParams.get("mac") || "").trim();
  let rows = [];
  if (trace) {
    rows = await listOrders(env, { traceId: trace });
    const allowed = new Set(await visibleMacs(env, user, [...new Set(rows.map((r) => r.mac))]));
    rows = rows.filter((r) => allowed.has(r.mac));
  } else if (macRaw) {
    const gate = await sourceMacForActor(env, macRaw, user);
    if (gate.error)
      return gate.error;
    rows = await listOrders(env, { macs: [gate.mac], limit: 100 });
  } else {
    return errResp("bad_query", "mac ou trace requis", 400);
  }
  return jsonResp({ items: rows.map(orderView) });
}
__name(handleOrdersList, "handleOrdersList");
async function handleLatencyMetrics(request, env) {
  const url = new URL(request.url);
  const hours = Math.min(24 * 30, Math.max(1, Number(url.searchParams.get("hours")) || 24));
  const since = Date.now() - hours * 3600 * 1e3;
  const ops = await latencyStats(env, since);
  return jsonResp({
    window_hours: hours,
    since,
    // Aucun chiffre inventé : un segment sans mesure vaut { n: 0, p50: null }.
    ops,
    clock_note: "client_to_api compare l\u2019horloge du navigateur \xE0 celle du serveur ; les autres segments n\u2019utilisent que l\u2019horloge serveur."
  });
}
__name(handleLatencyMetrics, "handleLatencyMetrics");
var TIMELINE_DROP_KEYS = /* @__PURE__ */ new Set(["password", "username", "m3u_url", "server_url", "url", "email", "phone"]);
function timelineScrub(value) {
  if (Array.isArray(value))
    return value.map(timelineScrub);
  if (!value || typeof value !== "object")
    return value;
  const out = {};
  for (const [k, v] of Object.entries(value)) {
    if (TIMELINE_DROP_KEYS.has(String(k).toLowerCase()))
      continue;
    out[k] = timelineScrub(v);
  }
  return out;
}
__name(timelineScrub, "timelineScrub");
function normalizeQueryMac(q) {
  const s = String(q || "").trim().toUpperCase();
  if (/^MK(?::[0-9A-F]{2}){5}$/.test(s))
    return s;
  if (/^(?:[0-9A-F]{2}:){4}[0-9A-F]{2}$/.test(s))
    return `MK:${s}`;
  return null;
}
__name(normalizeQueryMac, "normalizeQueryMac");
async function handleTimeline(request, env, actor, user) {
  const url = new URL(request.url);
  const q = (url.searchParams.get("q") || "").trim();
  const days = Math.min(30, Math.max(1, Number(url.searchParams.get("days")) || 7));
  const since = Date.now() - days * 24 * 3600 * 1e3;
  if (!q || q.length > 200)
    return errResp("bad_query", "q requis (MAC, e-mail, id client, id appareil ou trace)", 400);
  let devices = [];
  let kind = "trace";
  const mac = normalizeQueryMac(q);
  const sel = "SELECT id, mac, customer_id, reseller_id FROM devices";
  if (mac) {
    kind = "mac";
    devices = (await env.DB.prepare(`${sel} WHERE mac = ?`).bind(mac).all()).results || [];
  } else if (q.includes("@")) {
    kind = "email";
    devices = (await env.DB.prepare(
      `${sel} WHERE customer_id IN (SELECT id FROM customers WHERE lower(email) = lower(?)) LIMIT 10`
    ).bind(q).all()).results || [];
  } else if (q.startsWith("cus_")) {
    kind = "customer";
    devices = (await env.DB.prepare(`${sel} WHERE customer_id = ? LIMIT 10`).bind(q).all()).results || [];
  } else if (q.startsWith("dev_")) {
    kind = "device";
    devices = (await env.DB.prepare(`${sel} WHERE id = ?`).bind(q).all()).results || [];
  }
  let traceOrders = [];
  if (kind === "trace") {
    traceOrders = await listOrders(env, { traceId: q });
    const macs2 = [...new Set(traceOrders.map((r) => r.mac))];
    if (macs2.length) {
      const marks = macs2.map(() => "?").join(",");
      devices = (await env.DB.prepare(`${sel} WHERE mac IN (${marks})`).bind(...macs2).all()).results || [];
    }
  }
  if (user && user.role === "reseller") {
    devices = devices.filter((d) => d.reseller_id === user.sub);
  }
  const macs = devices.map((d) => d.mac);
  const deviceIds = devices.map((d) => d.id);
  const orders = kind === "trace" ? traceOrders.filter((r) => macs.includes(r.mac)) : macs.length ? await listOrders(env, { macs, since, limit: 300 }) : [];
  const traces = [...new Set(orders.map((r) => r.trace_id).filter(Boolean))];
  if (kind === "trace" && !traces.includes(q))
    traces.push(q);
  let licenseIds = [];
  if (deviceIds.length) {
    const marks = deviceIds.map(() => "?").join(",");
    licenseIds = ((await env.DB.prepare(`SELECT id FROM licenses WHERE device_id IN (${marks})`).bind(...deviceIds).all()).results || []).map((r) => r.id);
  }
  const targets = [...macs, ...deviceIds, ...licenseIds];
  let audits = [];
  if (targets.length || traces.length) {
    const conds = [];
    const binds = [];
    if (targets.length) {
      conds.push(`target_id IN (${targets.map(() => "?").join(",")})`);
      binds.push(...targets);
    }
    if (traces.length) {
      conds.push(`correlation_id IN (${traces.map(() => "?").join(",")})`);
      binds.push(...traces);
    }
    try {
      audits = (await env.DB.prepare(
        `SELECT action, actor_type, actor_id, target_type, target_id, before_json, after_json, correlation_id, created_at
           FROM audit_logs WHERE (${conds.join(" OR ")}) AND created_at >= ? ORDER BY created_at ASC LIMIT 300`
      ).bind(...binds, since).all()).results || [];
    } catch (_) {
      audits = [];
    }
  }
  if (user && user.role === "reseller") {
    if (!devices.length)
      audits = [];
  }
  const events = [];
  const parse = /* @__PURE__ */ __name((j) => {
    try {
      return j ? timelineScrub(JSON.parse(j)) : null;
    } catch (_) {
      return null;
    }
  }, "parse");
  for (const a of audits) {
    events.push({
      at: a.created_at,
      source: "audit",
      type: a.action,
      trace_id: a.correlation_id || null,
      actor: `${a.actor_type}:${a.actor_id || ""}`,
      target: `${a.target_type || ""}:${a.target_id || ""}`,
      before: parse(a.before_json),
      after: parse(a.after_json)
    });
  }
  for (const r of orders) {
    const base = {
      source: "order",
      order_id: r.order_id,
      mac: r.mac,
      device_id: r.device_id,
      customer_id: r.customer_id,
      kind: r.kind,
      trace_id: r.trace_id,
      config_rev: r.config_rev
    };
    if (r.t2_commit || r.created_at)
      events.push({ ...base, at: r.t2_commit || r.created_at, type: "ORDER_CREATED" });
    if (r.t3_published)
      events.push({ ...base, at: r.t3_published, type: "ORDER_SENT" });
    if (r.received_srv)
      events.push({ ...base, at: r.received_srv, type: "BOX_RECEIVED", box_time: r.received_at });
    if (r.applied_srv) {
      events.push({
        ...base,
        at: r.applied_srv,
        type: "BOX_APPLIED",
        late_ack: !!r.late_ack,
        box_time: r.applied_at,
        result: r.result,
        applied_rev: r.applied_rev
      });
    }
    if (r.failed_srv) {
      events.push({
        ...base,
        at: r.failed_srv,
        type: "BOX_FAILED",
        late_ack: !!r.late_ack,
        box_time: r.failed_at,
        result: r.result,
        error_code: r.error_code,
        error_message: r.error_message,
        applied_rev: r.applied_rev
      });
    }
    if (effectiveState(r) === "expired") {
      events.push({ ...base, at: (r.created_at || 0) + 10 * 60 * 1e3, type: "ORDER_EXPIRED" });
    }
  }
  const revisions = [];
  for (const m of macs) {
    const view = await revisionView(env, m);
    revisions.push({ mac: m, ...view, revisions: view.revisions.slice(0, 10) });
    for (const r of view.revisions) {
      if ((r.published_at || 0) < since)
        continue;
      events.push({ at: r.published_at, source: "revision", type: "CONFIG_REVISION_PUBLISHED", mac: m, rev: r.rev, trace_id: r.trace_id, rollback_of: r.rollback_of });
      if (r.acked_at) {
        events.push({ at: r.acked_at, source: "revision", type: r.state === "acknowledged" ? "CONFIG_REVISION_ACKNOWLEDGED" : "CONFIG_REVISION_REJECTED_BY_BOX", mac: m, rev: r.rev, result: r.ack_result, error_message: r.ack_error });
      }
    }
  }
  events.sort((x, y) => (x.at || 0) - (y.at || 0));
  const journals = [];
  for (const m of macs.slice(0, 3)) {
    const bb = await readBlackBox(env, m);
    const lines = (bb.body || "").split("\n").filter(Boolean).slice(-300);
    journals.push({
      mac: m,
      uploaded_at: bb.updated_at,
      clock: "heure locale de la box (sans fuseau)",
      lines: lines.map((line) => ({ line, trace_id: traces.find((t) => line.includes(t)) || null }))
    });
  }
  await logAudit(
    env,
    request,
    actor,
    "blackbox.search",
    { type: "timeline", id: kind },
    null,
    { kind, devices: deviceIds.length, events: events.length }
  );
  return jsonResp({
    query_kind: kind,
    days,
    devices: devices.map((d) => ({ id: d.id, mac: d.mac, customer_id: d.customer_id })),
    traces,
    events,
    revisions,
    box_journals: journals
  });
}
__name(handleTimeline, "handleTimeline");
var _MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;
async function ensureFamiliesTables(env) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS families (
       id TEXT PRIMARY KEY,
       name TEXT NOT NULL,
       source_json TEXT,
       reseller_id TEXT,
       created_at INTEGER,
       updated_at INTEGER
     )`
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS family_members (
       id TEXT PRIMARY KEY,
       family_id TEXT NOT NULL,
       mac TEXT NOT NULL,
       label TEXT,
       created_at INTEGER,
       UNIQUE(family_id, mac)
     )`
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS family_links (
       id TEXT PRIMARY KEY,
       family_id TEXT NOT NULL,
       token TEXT NOT NULL UNIQUE,
       label TEXT,
       created_at INTEGER
     )`
  ).run();
}
__name(ensureFamiliesTables, "ensureFamiliesTables");
async function _familyRowToJson(env, row, { hidePassword = true } = {}) {
  let source = null;
  try {
    source = row.source_json ? JSON.parse(row.source_json) : null;
  } catch (_) {
    source = null;
  }
  if (source)
    source = await openSource(env, source);
  if (source && hidePassword && source.password) {
    source = { ...source, password: "\u2022\u2022\u2022\u2022\u2022\u2022" };
  }
  return {
    id: row.id,
    name: row.name,
    source,
    reseller_id: row.reseller_id || null,
    created_at: row.created_at || 0,
    updated_at: row.updated_at || 0
  };
}
__name(_familyRowToJson, "_familyRowToJson");
async function handleFamiliesList(env, user) {
  const owner = isOwner(user);
  const rows = owner ? await env.DB.prepare("SELECT * FROM families ORDER BY created_at DESC").all() : await env.DB.prepare("SELECT * FROM families WHERE reseller_id = ? ORDER BY created_at DESC").bind(user.sub).all();
  const list = rows.results || [];
  const counts = {};
  try {
    const c = await env.DB.prepare(
      "SELECT family_id, COUNT(*) AS n FROM family_members GROUP BY family_id"
    ).all();
    for (const r of c.results || [])
      counts[r.family_id] = r.n;
  } catch (_) {
  }
  return jsonResp({
    items: await Promise.all(list.map(async (row) => ({
      ...await _familyRowToJson(env, row),
      member_count: counts[row.id] || 0
    })))
  });
}
__name(handleFamiliesList, "handleFamiliesList");
async function handleFamiliesCreate(request, env, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const name = (body.name || "").trim();
  if (!name)
    return errResp("bad_name", "name required", 400);
  const norm = normalizeSource(body.source || {});
  if (norm.error)
    return errResp("bad_source", norm.error, 400);
  const now = Date.now();
  const id = genId("fam");
  const resellerId = user.role === "reseller" ? user.sub : body.reseller_id || null;
  await ensureFamiliesTables(env);
  const sealed = await sealSource(env, norm.source);
  const sourceJson = JSON.stringify(sealed);
  await env.DB.prepare(
    `INSERT INTO families (id, name, source_json, reseller_id, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).bind(id, name, sourceJson, resellerId, now, now).run();
  await logAudit(
    env,
    request,
    actor,
    "family.create",
    { type: "family", id },
    null,
    { name }
  );
  return jsonResp({ ok: true, family: await _familyRowToJson(
    env,
    { id, name, source_json: sourceJson, reseller_id: resellerId, created_at: now, updated_at: now },
    { hidePassword: false }
  ), member_count: 0 }, 201);
}
__name(handleFamiliesCreate, "handleFamiliesCreate");
async function handleFamiliesGet(env, id, user) {
  const row = await env.DB.prepare("SELECT * FROM families WHERE id = ?").bind(id).first();
  if (!row)
    return errResp("not_found", "Family not found", 404);
  if (user.role === "reseller" && row.reseller_id !== user.sub) {
    return errResp("forbidden", "Not your family", 403);
  }
  const m = await env.DB.prepare(
    "SELECT mac, label, created_at FROM family_members WHERE family_id = ? ORDER BY created_at ASC"
  ).bind(id).all();
  const l = await env.DB.prepare(
    "SELECT id, token, label, created_at FROM family_links WHERE family_id = ? ORDER BY created_at ASC"
  ).bind(id).all();
  return jsonResp({
    family: await _familyRowToJson(env, row, { hidePassword: false }),
    members: m.results || [],
    links: l.results || []
  });
}
__name(handleFamiliesGet, "handleFamiliesGet");
async function handleFamilyCreateLink(request, env, user, actor, familyId) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }
  const fam = await env.DB.prepare("SELECT id, reseller_id FROM families WHERE id = ?").bind(familyId).first();
  if (!fam)
    return errResp("not_found", "Family not found", 404);
  if (user.role === "reseller" && fam.reseller_id !== user.sub) {
    return errResp("forbidden", "Not your family", 403);
  }
  const token = crypto.randomUUID().replace(/-/g, "");
  const id = genId("lnk");
  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO family_links (id, family_id, token, label, created_at)
     VALUES (?, ?, ?, ?, ?)`
  ).bind(id, familyId, token, (body.label || "").trim() || null, now).run();
  await logAudit(
    env,
    request,
    actor,
    "family.link.create",
    { type: "family", id: familyId },
    null,
    { label: body.label || null }
  );
  return jsonResp({ ok: true, id, token, label: (body.label || "").trim() || null, created_at: now }, 201);
}
__name(handleFamilyCreateLink, "handleFamilyCreateLink");
async function assertFamilyAccess(env, id, user) {
  const row = await env.DB.prepare("SELECT * FROM families WHERE id = ?").bind(id).first();
  if (!row)
    return { error: errResp("not_found", "Family not found", 404) };
  if (user && user.role === "reseller" && row.reseller_id !== user.sub) {
    return { error: errResp("forbidden", "Not your family", 403) };
  }
  return { row };
}
__name(assertFamilyAccess, "assertFamilyAccess");
async function handleFamilyDeleteLink(env, familyId, linkId, actor, user) {
  const gate = await assertFamilyAccess(env, familyId, user);
  if (gate.error)
    return gate.error;
  await env.DB.prepare("DELETE FROM family_links WHERE id = ? AND family_id = ?").bind(linkId, familyId).run();
  await logAudit(
    env,
    { headers: new Headers() },
    actor,
    "family.link.delete",
    { type: "family", id: familyId },
    null,
    { link: linkId }
  );
  return jsonResp({ ok: true, id: linkId });
}
__name(handleFamilyDeleteLink, "handleFamilyDeleteLink");
async function handleFamiliesDelete(env, id, actor, user) {
  const gate = await assertFamilyAccess(env, id, user);
  if (gate.error)
    return gate.error;
  const m = await env.DB.prepare("SELECT mac FROM family_members WHERE family_id = ?").bind(id).all();
  for (const r of m.results || []) {
    try {
      const c = await clearPanelSources(env, r.mac, { actor });
      if (c.conflict)
        console.error(JSON.stringify({ level: "warn", source: "family.delete", event: "sources_conflict" }));
      await markSourcesCleared(env, r.mac, Date.now());
    } catch (e) {
      console.error(JSON.stringify({ level: "warn", source: "family.delete", message: redact(String(e && e.message || e)) }));
    }
  }
  await env.DB.prepare("DELETE FROM family_members WHERE family_id = ?").bind(id).run();
  await env.DB.prepare("DELETE FROM families WHERE id = ?").bind(id).run();
  await logAudit(
    env,
    { headers: new Headers() },
    actor,
    "family.delete",
    { type: "family", id },
    null,
    null
  );
  return jsonResp({ ok: true, id });
}
__name(handleFamiliesDelete, "handleFamiliesDelete");
async function handleFamilyAddMember(request, env, user, actor, familyId) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    body = {};
  }
  const mac = (body.mac || "").trim().toUpperCase();
  if (!_MAC_RX.test(mac)) {
    return errResp("bad_mac", "mac must be MK:XX:XX:XX:XX:XX", 400);
  }
  const fam = await env.DB.prepare("SELECT * FROM families WHERE id = ?").bind(familyId).first();
  if (!fam)
    return errResp("not_found", "Family not found", 404);
  if (user.role === "reseller" && fam.reseller_id !== user.sub) {
    return errResp("forbidden", "Not your family", 403);
  }
  let source;
  try {
    source = JSON.parse(fam.source_json);
  } catch (_) {
    source = null;
  }
  if (source)
    source = await openSource(env, source);
  if (!source)
    return errResp("bad_source", "Family has no valid source", 400);
  const plan = body.plan || "lifetime";
  const actReq = new Request("https://internal/activate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      mac,
      plan,
      app_id: body.app_id || "app_7motion",
      customer_name: body.label ? `${fam.name} \u2014 ${body.label}` : fam.name,
      label: body.label || null
    })
  });
  const actResp = await handleActivate(actReq, env, user, actor);
  if (actResp && actResp.status >= 400)
    return actResp;
  const pushed = await upsertDeviceSource(env, mac, [source], null, { actor });
  if (pushed.conflict) {
    return errResp("sources_conflict", "Les listes de cette box changent en ce moment. R\xE9essaie.", 409);
  }
  await env.DB.prepare(
    `INSERT INTO family_members (id, family_id, mac, label, created_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(family_id, mac) DO UPDATE SET label = excluded.label`
  ).bind(genId("fm"), familyId, mac, body.label || null, Date.now()).run();
  await logAudit(
    env,
    request,
    actor,
    "family.member.add",
    { type: "family", id: familyId },
    null,
    { mac, label: body.label || null }
  );
  return jsonResp({ ok: true, family_id: familyId, mac, label: body.label || null }, 201);
}
__name(handleFamilyAddMember, "handleFamilyAddMember");
async function handleFamilyRemoveMember(env, familyId, mac, actor, user) {
  const gate = await assertFamilyAccess(env, familyId, user);
  if (gate.error)
    return gate.error;
  const m = (mac || "").trim().toUpperCase();
  await env.DB.prepare("DELETE FROM family_members WHERE family_id = ? AND mac = ?").bind(familyId, m).run();
  try {
    const c = await clearPanelSources(env, m, { actor });
    if (c.conflict)
      console.error(JSON.stringify({ level: "warn", source: "family.member.remove", event: "sources_conflict" }));
    await markSourcesCleared(env, m, Date.now());
  } catch (e) {
    console.error(JSON.stringify({ level: "warn", source: "family.member.remove", message: redact(String(e && e.message || e)) }));
  }
  await logAudit(
    env,
    { headers: new Headers() },
    actor,
    "family.member.remove",
    { type: "family", id: familyId },
    null,
    { mac: m }
  );
  return jsonResp({ ok: true, family_id: familyId, mac: m });
}
__name(handleFamilyRemoveMember, "handleFamilyRemoveMember");
async function handleDevicesList(request, env, user) {
  const url = new URL(request.url);
  const q = (url.searchParams.get("q") || "").trim();
  const { limit, offset } = parsePageQuery(url);
  const from = `FROM devices d LEFT JOIN customers c ON d.customer_id = c.id`;
  const where = [];
  const binds = [];
  if (q) {
    where.push("(d.mac LIKE ? OR d.label LIKE ? OR c.name LIKE ?)");
    binds.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }
  if (user && user.role === "reseller") {
    where.push("d.reseller_id = ?");
    binds.push(user.sub);
  }
  const whereSql = where.length ? " WHERE " + where.join(" AND ") : "";
  const page = await pagedQuery(
    env,
    `SELECT COUNT(*) as n ${from}${whereSql}`,
    binds,
    `SELECT d.*,
            (SELECT l.status FROM licenses l WHERE l.device_id = d.id
               ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_status,
            (SELECT l.plan FROM licenses l WHERE l.device_id = d.id
               ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_plan,
            (SELECT l.expires_at FROM licenses l WHERE l.device_id = d.id
               ORDER BY (l.expires_at IS NULL) DESC, l.expires_at DESC LIMIT 1) AS lic_expires,
            c.name as customer_name, c.email as customer_email
       ${from}${whereSql}
      ORDER BY d.last_seen_at DESC LIMIT ? OFFSET ?`,
    binds,
    limit,
    offset
  );
  const rows = page.items.map((row) => ({
    ...row,
    first_seen_at: epochMs(row.first_seen_at),
    last_seen_at: epochMs(row.last_seen_at)
  }));
  page.items = await annotateDeviceAccess(env, rows);
  page.trial_enforced = trialEnforcementOn(env);
  return jsonResp(page);
}
__name(handleDevicesList, "handleDevicesList");
async function annotateDeviceAccess(env, rows) {
  const enforced = trialEnforcementOn(env);
  const trialDays = enforced ? TRIAL_DAYS : await configuredTrialDays(env);
  const anchors = {};
  const extensions = {};
  try {
    await ensureTrialAnchorTable(env);
    const macs = rows.map((r) => r.mac).filter(Boolean);
    if (macs.length) {
      const marks = macs.map(() => "?").join(",");
      const a = await env.DB.prepare(
        `SELECT mac, started_at, extended_until FROM trial_anchors WHERE mac IN (${marks})`
      ).bind(...macs).all();
      for (const row of a && a.results || []) {
        anchors[row.mac] = row.started_at;
        if (Number(row.extended_until) > 0)
          extensions[row.mac] = Number(row.extended_until);
      }
    }
  } catch (_) {
  }
  const now = Date.now();
  return rows.map((r) => {
    const license = r.lic_status ? { status: r.lic_status, plan: r.lic_plan, expires_at: r.lic_expires } : null;
    const seen = r.first_seen_at || now;
    const anchored = anchors[r.mac];
    const started = enforced ? Math.min(seen, Number(anchored) > 0 ? Number(anchored) : seen) : seen;
    const access = describeAccess({
      now,
      startedAt: started,
      trialDays,
      license,
      blockStatus: r.block_status,
      extendedUntil: extensions[r.mac] || 0
    });
    return {
      ...r,
      access: access.access,
      access_label: access.label,
      access_days_left: access.days_left,
      access_ends_at: access.ends_at
    };
  });
}
__name(annotateDeviceAccess, "annotateDeviceAccess");
async function handleDeviceOverview(env, id, user) {
  const r = await deviceForActor(env, id, user);
  if (r.error)
    return r.error;
  const dev = r.dev;
  const now = Date.now();
  let license = null;
  try {
    const lic = await env.DB.prepare(
      `SELECT status, plan, started_at, expires_at, auto_renew
           FROM licenses WHERE device_id = ?
          ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`
    ).bind(dev.id).first();
    if (lic) {
      license = {
        status: liveLicenseStatus(lic.status, lic.expires_at, now),
        plan: lic.plan || null,
        started_at: epochMs(lic.started_at),
        expires_at: epochMs(lic.expires_at),
        auto_renew: lic.auto_renew ? 1 : 0
      };
    }
  } catch (_) {
  }
  let presence = null;
  try {
    const p = await env.DB.prepare("SELECT ip, country, last_seen, channel FROM presence WHERE mac = ?").bind(dev.mac).first();
    if (p) {
      const ONLINE_MS = 15 * 60 * 1e3;
      const seenMs = epochMs(p.last_seen) || 0;
      presence = {
        online: seenMs > now - ONLINE_MS,
        ip: p.ip || "",
        country: /^[A-Za-z]{2}$/.test(p.country || "") ? String(p.country).toUpperCase() : "",
        channel: p.channel || "",
        last_seen: seenMs
      };
    }
  } catch (_) {
  }
  let sources = [];
  try {
    await ensureSourcesTable(env);
    const row = await env.DB.prepare("SELECT * FROM device_sources WHERE mac = ?").bind(dev.mac).first();
    if (row && row.sources_json) {
      try {
        sources = JSON.parse(row.sources_json) || [];
      } catch (_) {
        sources = [];
      }
    }
    if (!sources.length && row) {
      const { sources_json, mac: _m, updated_at, ...single } = row;
      sources = [single];
    }
    sources = await openSourceList(env, sources);
  } catch (_) {
  }
  let localSources = [];
  try {
    const drow = await env.DB.prepare("SELECT local_sources_json FROM devices WHERE id = ?").bind(dev.id).first();
    if (drow && drow.local_sources_json) {
      try {
        localSources = JSON.parse(drow.local_sources_json) || [];
      } catch (_) {
        localSources = [];
      }
    }
  } catch (_) {
  }
  return jsonResp({ mac: dev.mac, license, presence, sources, localSources });
}
__name(handleDeviceOverview, "handleDeviceOverview");
async function handleDevicesCreate(request, env, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  if (!body.customer_id || !body.mac) {
    return errResp("missing_fields", "customer_id and mac required", 400);
  }
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(body.mac)) {
    return errResp("bad_mac", "mac must be MK:XX:XX:XX:XX:XX", 400);
  }
  const id = genId("dev");
  const now = Date.now();
  try {
    await env.DB.prepare(
      `INSERT INTO devices (id, customer_id, mac, label,
                              first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?)`
    ).bind(id, body.customer_id, body.mac, body.label || null, now, now).run();
  } catch (e) {
    return errResp("duplicate_mac", "This MAC already exists", 409);
  }
  await logAudit(env, request, actor, "device.create", { type: "device", id }, null, body);
  return jsonResp({ id }, 201);
}
__name(handleDevicesCreate, "handleDevicesCreate");
async function deviceForActor(env, id, user) {
  const dev = await env.DB.prepare("SELECT id, mac, reseller_id, block_status FROM devices WHERE id = ?").bind(id).first();
  if (!dev)
    return { error: errResp("not_found", "Device not found", 404) };
  if (user && user.role === "reseller" && dev.reseller_id !== user.sub) {
    return { error: errResp("forbidden", "Cet appareil ne vous appartient pas", 403) };
  }
  return { dev };
}
__name(deviceForActor, "deviceForActor");
async function handleDeviceUpdate(request, env, id, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const r = await deviceForActor(env, id, user);
  if (r.error)
    return r.error;
  const allowed = ["active", "frozen", "banned"];
  const next = body.block_status === "active" ? null : body.block_status;
  if (body.block_status !== void 0 && !allowed.includes(body.block_status)) {
    return errResp("bad_status", "block_status doit etre 'active', 'frozen' ou 'banned'", 400);
  }
  await env.DB.prepare("UPDATE devices SET block_status = ? WHERE id = ?").bind(next ?? null, id).run();
  await logAudit(
    env,
    request,
    actor,
    "device.block",
    { type: "device", id },
    { block_status: r.dev.block_status },
    { block_status: next }
  );
  const blockKind = body.block_status === "frozen" ? "suspend" : body.block_status === "banned" ? "block" : "resume";
  await notifyBox(env, r.dev.mac, blockKind);
  return jsonResp({ updated: 1, block_status: next });
}
__name(handleDeviceUpdate, "handleDeviceUpdate");
async function handleDeviceDelete(env, id, actor, user) {
  const r = await deviceForActor(env, id, user);
  if (r.error)
    return r.error;
  await env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(id).run();
  await logAudit(
    env,
    null,
    actor,
    "device.delete",
    { type: "device", id },
    { mac: r.dev.mac },
    null
  );
  await notifyBox(env, r.dev.mac, "device_delete");
  return jsonResp({ deleted: 1 });
}
__name(handleDeviceDelete, "handleDeviceDelete");
function planToDays(plan, customDays) {
  const hm = /^trial_(\d+)h$/.exec(plan || "");
  if (hm)
    return Number(hm[1]) / 24;
  const dm = /^trial_(\d+)d$/.exec(plan || "");
  if (dm)
    return Number(dm[1]);
  switch (plan) {
    case "1m":
    case "monthly":
      return 30;
    case "3m":
    case "quarterly":
      return 90;
    case "6m":
    case "biannual":
      return 180;
    case "1y":
    case "yearly":
      return 365;
    case "lifetime":
      return null;
    case "custom": {
      const d = Number(customDays);
      if (!(d > 0))
        return 30;
      return Math.min(Math.round(d), 3650);
    }
    case "trial":
      return 7;
    default:
      return 30;
  }
}
__name(planToDays, "planToDays");
function unknownPlanMessage(plan) {
  if (typeof plan !== "string" || !plan)
    return "plan requis";
  if (plan === "trial")
    return null;
  const hm = /^trial_(\d+)h$/.exec(plan);
  if (hm)
    return Number(hm[1]) > 24 * 30 ? "dur\xE9e d essai trop longue" : null;
  const dm = /^trial_(\d+)d$/.exec(plan);
  if (dm)
    return Number(dm[1]) > 90 ? "dur\xE9e d essai trop longue" : null;
  if (plan.startsWith("trial"))
    return "plan d essai inconnu";
  const known = ["1m", "monthly", "3m", "quarterly", "6m", "biannual", "1y", "yearly", "lifetime", "custom"];
  if (!known.includes(plan))
    return "plan inconnu";
  return null;
}
__name(unknownPlanMessage, "unknownPlanMessage");
async function handleLicensesList(request, env, user) {
  const url = new URL(request.url);
  const status = url.searchParams.get("status");
  const appId = url.searchParams.get("app_id");
  const where = [];
  const binds = [];
  if (status) {
    where.push("l.status = ?");
    binds.push(status);
  }
  if (appId) {
    where.push("l.app_id = ?");
    binds.push(appId);
  }
  if (user && user.role === "reseller") {
    where.push("l.reseller_id = ?");
    binds.push(user.sub);
  }
  const whereSql = where.length ? " WHERE " + where.join(" AND ") : "";
  const { limit, offset } = parsePageQuery(url);
  const from = `FROM licenses l
             JOIN customers c ON l.customer_id = c.id
             JOIN devices   d ON l.device_id   = d.id
             JOIN apps      a ON l.app_id      = a.id`;
  const page = await pagedQuery(
    env,
    `SELECT COUNT(*) as n ${from}${whereSql}`,
    binds,
    `SELECT l.id, l.customer_id, l.device_id, l.app_id, l.status,
            l.plan, l.started_at, l.expires_at, l.auto_renew, l.reseller_id,
            c.name as customer_name, c.email as customer_email,
            d.mac as device_mac, d.label as device_label,
            a.name as app_name
       ${from}${whereSql}
      ORDER BY l.created_at DESC LIMIT ? OFFSET ?`,
    binds,
    limit,
    offset
  );
  const now = Date.now();
  page.items = page.items.map((row) => ({
    ...row,
    status: liveLicenseStatus(row.status, row.expires_at, now),
    started_at: epochMs(row.started_at),
    expires_at: epochMs(row.expires_at)
  }));
  return jsonResp(page);
}
__name(handleLicensesList, "handleLicensesList");
async function handleLicensesCreate(request, env, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  if (!body.customer_id || !body.device_id || !body.app_id) {
    return errResp(
      "missing_fields",
      "customer_id, device_id and app_id required",
      400
    );
  }
  const id = genId("lic");
  const now = Date.now();
  const days = planToDays(body.plan, body.custom_days);
  const expiresAt = days === null ? null : now + days * 24 * 60 * 60 * 1e3;
  try {
    await env.DB.prepare(
      `INSERT INTO licenses
          (id, customer_id, device_id, app_id, status, plan,
           started_at, expires_at, auto_renew, reseller_id, notes,
           created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      id,
      body.customer_id,
      body.device_id,
      body.app_id,
      "active",
      body.plan || "1m",
      now,
      expiresAt,
      body.auto_renew ? 1 : 0,
      body.reseller_id || null,
      body.notes || null,
      now,
      now
    ).run();
  } catch (e) {
    return errResp(
      "duplicate_license",
      "This device already has a license for this app",
      409
    );
  }
  await logAudit(
    env,
    request,
    actor,
    "license.create",
    { type: "license", id },
    null,
    { ...body, expires_at: expiresAt }
  );
  return jsonResp({ id, expires_at: expiresAt }, 201);
}
__name(handleLicensesCreate, "handleLicensesCreate");
async function handleLicensesUpdate(request, env, id, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const before = await env.DB.prepare("SELECT * FROM licenses WHERE id = ?").bind(id).first();
  if (!before)
    return errResp("not_found", "License not found", 404);
  const fields = ["status", "plan", "expires_at", "auto_renew", "notes"];
  const sets = [];
  const vals = [];
  for (const f of fields) {
    if (body[f] !== void 0) {
      sets.push(`${f} = ?`);
      vals.push(f === "auto_renew" ? body[f] ? 1 : 0 : body[f]);
    }
  }
  if (sets.length === 0)
    return jsonResp({ updated: 0 });
  sets.push("updated_at = ?");
  vals.push(Date.now());
  vals.push(id);
  await env.DB.prepare(`UPDATE licenses SET ${sets.join(", ")} WHERE id = ?`).bind(...vals).run();
  await logAudit(env, request, actor, "license.update", { type: "license", id }, before, body);
  return jsonResp({ updated: 1 });
}
__name(handleLicensesUpdate, "handleLicensesUpdate");
async function handleLicensesRenew(request, env, id, actor) {
  let body = {};
  try {
    body = await request.json();
  } catch (_) {
  }
  const before = await env.DB.prepare("SELECT * FROM licenses WHERE id = ?").bind(id).first();
  if (!before)
    return errResp("not_found", "License not found", 404);
  if (body.plan) {
    const planError = unknownPlanMessage(body.plan);
    if (planError)
      return errResp("bad_plan", planError, 400);
  }
  const days = planToDays(body.plan || before.plan || "1y", body.custom_days);
  if (before.expires_at == null) {
    if (days !== null) {
      return errResp("already_lifetime", "Licence \xE0 vie : un renouvellement dat\xE9 est refus\xE9.", 409);
    }
    return jsonResp({ updated: 0, expires_at: null, already_lifetime: true });
  }
  const now = Date.now();
  const base = before.expires_at && before.expires_at > now ? before.expires_at : now;
  const newExpiry = days === null ? null : base + days * 24 * 60 * 60 * 1e3;
  await env.DB.prepare(
    `UPDATE licenses
       SET status = 'active', plan = ?, expires_at = ?, updated_at = ?
       WHERE id = ?`
  ).bind(body.plan || before.plan, newExpiry, now, id).run();
  await logAudit(
    env,
    request,
    actor,
    "license.renew",
    { type: "license", id },
    before,
    { plan: body.plan, expires_at: newExpiry }
  );
  return jsonResp({ updated: 1, expires_at: newExpiry });
}
__name(handleLicensesRenew, "handleLicensesRenew");
function isOwner(user) {
  return user && (user.role === "super_admin" || user.role === "admin");
}
__name(isOwner, "isOwner");
var RESELLER_CAPS_ALL = [
  "activate",
  // activer un appareil
  "sources",
  // pousser une source (playlist) aux clients
  "resellers",
  // gérer ses propres sous-revendeurs
  "devices",
  // voir ses appareils
  "activations"
  // voir ses activations
];
var RESELLER_LEGACY_LEVEL = {
  basique: ["activate"],
  standard: ["activate", "sources"],
  confiance: ["activate", "sources", "resellers", "devices", "activations"]
};
function resellerPerms(permissionsVal, level) {
  if (Array.isArray(permissionsVal))
    return permissionsVal;
  if (typeof permissionsVal === "string" && permissionsVal) {
    try {
      const a = JSON.parse(permissionsVal);
      if (Array.isArray(a))
        return a;
    } catch (_) {
    }
  }
  return RESELLER_LEGACY_LEVEL[level] || ["activate"];
}
__name(resellerPerms, "resellerPerms");
function sanitizePerms(arr) {
  if (!Array.isArray(arr))
    return [];
  return RESELLER_CAPS_ALL.filter((c) => arr.includes(c));
}
__name(sanitizePerms, "sanitizePerms");
function resellerCan(user, cap) {
  if (!user || user.role !== "reseller")
    return true;
  return resellerPerms(user.permissions, user.level).includes(cap);
}
__name(resellerCan, "resellerCan");
async function ensureResellerLevel(env) {
  try {
    await env.DB.prepare("ALTER TABLE resellers ADD COLUMN level TEXT NOT NULL DEFAULT 'basique'").run();
  } catch (_) {
  }
  try {
    await env.DB.prepare("ALTER TABLE resellers ADD COLUMN permissions TEXT").run();
  } catch (_) {
  }
}
__name(ensureResellerLevel, "ensureResellerLevel");
async function handleResellerSignup(request, env) {
  if (!await rateLimitHit(env, request, "signup", 5, 60 * 60 * 1e3)) {
    return errResp("rate_limited", "Trop d'inscriptions. R\xE9essaie plus tard.", 429);
  }
  await ensureResellerLevel(env);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const email = (body.email || "").trim().toLowerCase();
  const password = body.password || "";
  const name = (body.name || "").trim() || null;
  if (!email || !password) {
    return errResp("missing_fields", "Identifiant et mot de passe requis", 400);
  }
  if (email.length < 3)
    return errResp("bad_email", "Identifiant trop court", 400);
  if (password.length < 4) {
    return errResp("weak_password", "Mot de passe trop court (min. 4)", 400);
  }
  const existing = await env.DB.prepare("SELECT id FROM resellers WHERE email = ?").bind(email).first();
  if (existing)
    return errResp("email_taken", "Cet identifiant est d\xE9j\xE0 pris", 409);
  const id = genId("rsl");
  const now = Date.now();
  const hash = await hashPassword(password);
  const res = await env.DB.prepare(
    `INSERT INTO resellers
        (id, email, password_hash, name, credit_balance_cents, credit_balance,
         commission_rate, status, level, permissions, created_at)
       VALUES (?, ?, ?, ?, 0, 0, 0.20, 'pending', 'basique', ?, ?)
       ON CONFLICT(email) DO NOTHING`
  ).bind(id, email, hash, name, JSON.stringify(["activate"]), now).run();
  if (!res || !res.meta || res.meta.changes !== 1) {
    return errResp("email_taken", "Cet identifiant est d\xE9j\xE0 pris", 409);
  }
  return jsonResp({ ok: true, pending: true }, 201);
}
__name(handleResellerSignup, "handleResellerSignup");
async function handleResellerLogin(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const email = (body.email || "").trim().toLowerCase();
  const password = body.password || "";
  if (!email || !password) {
    return errResp("missing_fields", "email and password required", 400);
  }
  if (!await rateLimitHit(env, request, "rlogin", 10, 10 * 60 * 1e3)) {
    return errResp(
      "rate_limited",
      "Trop de tentatives de connexion. R\xE9essaie dans ~10 minutes.",
      429
    );
  }
  const secret = authSecret(env);
  if (!secret) {
    return errResp("auth_unconfigured", "Authentification indisponible.", 503);
  }
  await ensureResellerLevel(env);
  const row = await env.DB.prepare("SELECT id, email, password_hash, name, status, level, permissions, credit_balance FROM resellers WHERE email = ?").bind(email).first();
  if (!row) {
    await verifyPassword(password, DUMMY_PASSWORD_HASH);
    return errResp("bad_credentials", "Invalid credentials", 401);
  }
  const ok = await verifyPassword(password, row.password_hash);
  if (!ok)
    return errResp("bad_credentials", "Invalid credentials", 401);
  if (row.status === "pending") {
    return errResp("pending", "Compte en attente de validation par l'administrateur.", 403);
  }
  if (row.status !== "active") {
    return errResp("suspended", "Compte suspendu. Contacte l'administrateur.", 403);
  }
  await rateLimitReset(env, request, "rlogin");
  const level = row.level || "basique";
  const permissions = resellerPerms(row.permissions, level);
  const token = await signJwt(
    { sub: row.id, email: row.email, role: "reseller", name: row.name, level, permissions },
    secret
  );
  return jsonResp({
    token,
    user: {
      id: row.id,
      email: row.email,
      name: row.name,
      role: "reseller",
      level,
      permissions,
      credit_balance: row.credit_balance
    }
  });
}
__name(handleResellerLogin, "handleResellerLogin");
async function handleMe(env, user) {
  if (user.role === "reseller") {
    await ensureResellerLevel(env);
    const r = await env.DB.prepare("SELECT id, email, name, status, level, permissions, credit_balance, commission_rate FROM resellers WHERE id = ?").bind(user.sub).first();
    if (!r)
      return errResp("not_found", "Reseller not found", 404);
    return jsonResp({ user: {
      ...r,
      level: r.level || "basique",
      permissions: resellerPerms(r.permissions, r.level),
      role: "reseller"
    } });
  }
  return jsonResp({ user });
}
__name(handleMe, "handleMe");
async function handleChangeOwnPassword(request, env, user, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const current = body.current_password || "";
  const next = body.new_password || "";
  if (!next || next.length < 8) {
    return errResp("weak_password", "Le nouveau mot de passe doit faire au moins 8 caracteres", 400);
  }
  const table = user.role === "reseller" ? "resellers" : "admin_users";
  const row = await env.DB.prepare(`SELECT password_hash FROM ${table} WHERE id = ?`).bind(user.sub).first();
  if (!row)
    return errResp("not_found", "Compte introuvable", 404);
  const ok = await verifyPassword(current, row.password_hash);
  if (!ok)
    return errResp("bad_current", "Mot de passe actuel incorrect", 401);
  const hash = await hashPassword(next);
  const changed = Math.floor(Date.now() / 1e3);
  await ensurePasswordChangedColumn(env, table);
  await env.DB.prepare(
    `UPDATE ${table} SET password_hash = ?, password_changed_at = ? WHERE id = ?`
  ).bind(hash, changed, user.sub).run();
  await logAudit(
    env,
    request,
    actor,
    "password.change_self",
    { type: user.role === "reseller" ? "reseller" : "admin", id: user.sub },
    null,
    null
  );
  return jsonResp({ ok: true });
}
__name(handleChangeOwnPassword, "handleChangeOwnPassword");
async function handlePlanCostsList(env) {
  const rs = await env.DB.prepare("SELECT plan, credits FROM plan_costs ORDER BY credits ASC").all();
  return jsonResp({ items: rs.results || [] });
}
__name(handlePlanCostsList, "handlePlanCostsList");
async function handlePlanCostsUpdate(request, env, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const costs = body.costs || body;
  const entries = Object.entries(costs).filter(([, v]) => Number.isFinite(Number(v)));
  if (entries.length === 0) {
    return errResp("missing_fields", "costs map required", 400);
  }
  const stmts = entries.map(
    ([plan, credits]) => env.DB.prepare(
      `INSERT INTO plan_costs (plan, credits) VALUES (?, ?)
       ON CONFLICT(plan) DO UPDATE SET credits = excluded.credits`
    ).bind(plan, Math.max(0, Math.round(Number(credits))))
  );
  await env.DB.batch(stmts);
  await logAudit(
    env,
    request,
    actor,
    "plan_costs.update",
    { type: "plan_costs", id: "all" },
    null,
    costs
  );
  return jsonResp({ updated: entries.length });
}
__name(handlePlanCostsUpdate, "handlePlanCostsUpdate");
async function planCreditCost(env, plan) {
  if (typeof plan === "string" && plan.startsWith("trial"))
    return 0;
  const row = await env.DB.prepare("SELECT credits FROM plan_costs WHERE plan = ?").bind(plan).first();
  if (row)
    return row.credits;
  const def = { trial: 0, monthly: 1, quarterly: 3, biannual: 5, yearly: 1, lifetime: 2, custom: 1 };
  return def[plan] != null ? def[plan] : 1;
}
__name(planCreditCost, "planCreditCost");
async function handleResellersList(env, user) {
  await ensureResellerLevel(env);
  const reseller = user && user.role === "reseller";
  const where = reseller ? "WHERE r.parent_reseller_id = ?" : "";
  const binds = reseller ? [user.sub] : [];
  const rs = await env.DB.prepare(
    `SELECT r.id, r.email, r.name, r.status, r.level, r.permissions, r.credit_balance,
              r.commission_rate, r.parent_reseller_id, r.created_at,
              (SELECT COUNT(*) FROM devices d   WHERE d.reseller_id = r.id) as devices,
              (SELECT COUNT(*) FROM licenses l  WHERE l.reseller_id = r.id) as licenses,
              (SELECT COUNT(*) FROM resellers s WHERE s.parent_reseller_id = r.id) as sub_resellers
       FROM resellers r ${where} ORDER BY r.created_at DESC LIMIT 500`
  ).bind(...binds).all();
  const items = (rs.results || []).map((r) => ({
    ...r,
    permissions: resellerPerms(r.permissions, r.level)
  }));
  return jsonResp({ items });
}
__name(handleResellersList, "handleResellersList");
async function handleResellersGet(env, id, user) {
  const row = await env.DB.prepare("SELECT id, email, name, status, credit_balance, commission_rate, parent_reseller_id, created_at FROM resellers WHERE id = ?").bind(id).first();
  if (!row)
    return errResp("not_found", "Reseller not found", 404);
  if (user && user.role === "reseller" && id !== user.sub && row.parent_reseller_id !== user.sub) {
    return errResp("forbidden", "Forbidden", 403);
  }
  return jsonResp(row);
}
__name(handleResellersGet, "handleResellersGet");
async function handleResellersCreate(request, env, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const email = (body.email || "").trim().toLowerCase();
  const password = body.password || "";
  if (!email || !password) {
    return errResp("missing_fields", "email and password required", 400);
  }
  const isReseller = user && user.role === "reseller";
  const parentId = isReseller ? user.sub : null;
  const initial = Math.max(0, parseInt(body.credit_balance || 0, 10) || 0);
  const commission = Number.isFinite(Number(body.commission_rate)) ? Number(body.commission_rate) : 0.2;
  let parentBalanceAfter = null;
  if (isReseller && initial > 0) {
    const parent = await env.DB.prepare("SELECT credit_balance FROM resellers WHERE id = ?").bind(user.sub).first();
    if (!parent)
      return errResp("not_found", "Parent reseller not found", 404);
    if (parent.credit_balance < initial) {
      return errResp(
        "insufficient_credits",
        `Credits insuffisants (besoin ${initial}, solde ${parent.credit_balance})`,
        402
      );
    }
    parentBalanceAfter = parent.credit_balance - initial;
  }
  const id = genId("rsl");
  const now = Date.now();
  const hash = await hashPassword(password);
  try {
    await env.DB.prepare(
      `INSERT INTO resellers
          (id, email, password_hash, name, credit_balance_cents,
           credit_balance, commission_rate, status, parent_reseller_id, created_at)
         VALUES (?, ?, ?, ?, 0, ?, ?, 'active', ?, ?)`
    ).bind(id, email, hash, body.name || null, initial, commission, parentId, now).run();
  } catch (e) {
    return errResp("duplicate_email", "A reseller with this email already exists", 409);
  }
  const stmts = [];
  if (initial > 0) {
    stmts.push(env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      genId("cl"),
      id,
      initial,
      parentId ? "transfer_in" : "issue",
      initial,
      actor.type,
      actor.id,
      "Credits initiaux",
      now
    ));
  }
  if (isReseller && initial > 0) {
    stmts.push(env.DB.prepare("UPDATE resellers SET credit_balance = ? WHERE id = ?").bind(parentBalanceAfter, user.sub));
    stmts.push(env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, 'transfer_out', ?, ?, ?, ?, ?)`
    ).bind(
      genId("cl"),
      user.sub,
      -initial,
      parentBalanceAfter,
      actor.type,
      actor.id,
      "Vers " + email,
      now
    ));
  }
  if (stmts.length)
    await env.DB.batch(stmts);
  await logAudit(
    env,
    request,
    actor,
    "reseller.create",
    { type: "reseller", id },
    null,
    { email, name: body.name, initial, parent: parentId }
  );
  return jsonResp({ id, credit_balance: initial }, 201);
}
__name(handleResellersCreate, "handleResellersCreate");
async function handleResellersUpdate(request, env, id, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const before = await env.DB.prepare("SELECT * FROM resellers WHERE id = ?").bind(id).first();
  if (!before)
    return errResp("not_found", "Reseller not found", 404);
  if (user && user.role === "reseller" && before.parent_reseller_id !== user.sub) {
    return errResp("forbidden", "Forbidden", 403);
  }
  await ensureResellerLevel(env);
  const sets = [];
  const vals = [];
  if (body.name !== void 0) {
    sets.push("name = ?");
    vals.push(body.name);
  }
  if (body.status !== void 0) {
    sets.push("status = ?");
    vals.push(body.status);
  }
  if (body.permissions !== void 0 && isOwner(user)) {
    sets.push("permissions = ?");
    vals.push(JSON.stringify(sanitizePerms(body.permissions)));
  }
  if (body.commission_rate !== void 0 && isOwner(user)) {
    sets.push("commission_rate = ?");
    vals.push(Number(body.commission_rate));
  }
  if (body.password) {
    sets.push("password_hash = ?");
    vals.push(await hashPassword(body.password));
  }
  if (sets.length === 0)
    return jsonResp({ updated: 0 });
  vals.push(id);
  await env.DB.prepare(`UPDATE resellers SET ${sets.join(", ")} WHERE id = ?`).bind(...vals).run();
  await logAudit(env, request, actor, "reseller.update", { type: "reseller", id }, before, body);
  return jsonResp({ updated: 1 });
}
__name(handleResellersUpdate, "handleResellersUpdate");
async function handleResellerCreditsIssue(request, env, id, actor, user) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const amount = parseInt(body.amount, 10);
  if (!Number.isFinite(amount) || amount === 0) {
    return errResp("bad_amount", "amount required (positif = ajouter, negatif = retirer)", 400);
  }
  const target = await env.DB.prepare("SELECT credit_balance, parent_reseller_id FROM resellers WHERE id = ?").bind(id).first();
  if (!target)
    return errResp("not_found", "Reseller not found", 404);
  const now = Date.now();
  if (isOwner(user)) {
    const newBalance = target.credit_balance + amount;
    if (newBalance < 0) {
      return errResp("insufficient_credits", "Le solde resultant serait negatif", 400);
    }
    await env.DB.batch([
      env.DB.prepare("UPDATE resellers SET credit_balance = ? WHERE id = ?").bind(newBalance, id),
      env.DB.prepare(
        `INSERT INTO credit_ledger
          (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(
        genId("cl"),
        id,
        amount,
        amount > 0 ? "issue" : "adjust",
        newBalance,
        actor.type,
        actor.id,
        body.note || null,
        now
      )
    ]);
    await logAudit(
      env,
      request,
      actor,
      "reseller.credits",
      { type: "reseller", id },
      { balance: target.credit_balance },
      { amount, balance: newBalance }
    );
    return jsonResp({ credit_balance: newBalance, delta: amount });
  }
  if (target.parent_reseller_id !== user.sub) {
    return errResp("forbidden", "Ce revendeur n'est pas votre sous-revendeur", 403);
  }
  const parent = await env.DB.prepare("SELECT credit_balance FROM resellers WHERE id = ?").bind(user.sub).first();
  let parentAfter;
  let childAfter;
  if (amount > 0) {
    if (parent.credit_balance < amount) {
      return errResp(
        "insufficient_credits",
        `Credits insuffisants (besoin ${amount}, solde ${parent.credit_balance})`,
        402
      );
    }
    parentAfter = parent.credit_balance - amount;
    childAfter = target.credit_balance + amount;
  } else {
    const take = -amount;
    if (target.credit_balance < take) {
      return errResp(
        "insufficient_credits",
        "Le sous-revendeur n'a pas assez de credits a reprendre",
        400
      );
    }
    childAfter = target.credit_balance + amount;
    parentAfter = parent.credit_balance + take;
  }
  await env.DB.batch([
    env.DB.prepare("UPDATE resellers SET credit_balance = ? WHERE id = ?").bind(childAfter, id),
    env.DB.prepare("UPDATE resellers SET credit_balance = ? WHERE id = ?").bind(parentAfter, user.sub),
    env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      genId("cl"),
      id,
      amount,
      amount > 0 ? "transfer_in" : "transfer_out",
      childAfter,
      actor.type,
      actor.id,
      body.note || null,
      now
    ),
    env.DB.prepare(
      `INSERT INTO credit_ledger
        (id, reseller_id, delta, reason, balance_after, actor_type, actor_id, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      genId("cl"),
      user.sub,
      -amount,
      amount > 0 ? "transfer_out" : "transfer_in",
      parentAfter,
      actor.type,
      actor.id,
      body.note || null,
      now
    )
  ]);
  await logAudit(
    env,
    request,
    actor,
    "reseller.credits.transfer",
    { type: "reseller", id },
    { balance: target.credit_balance },
    { amount, balance: childAfter }
  );
  return jsonResp({ credit_balance: childAfter, delta: amount, your_balance: parentAfter });
}
__name(handleResellerCreditsIssue, "handleResellerCreditsIssue");
async function handleResellerCreditsList(env, id, user) {
  if (user && user.role === "reseller" && id !== user.sub) {
    const t = await env.DB.prepare("SELECT parent_reseller_id FROM resellers WHERE id = ?").bind(id).first();
    if (!t || t.parent_reseller_id !== user.sub) {
      return errResp("forbidden", "Forbidden", 403);
    }
  }
  const rs = await env.DB.prepare(
    `SELECT id, delta, reason, balance_after, ref_device_mac, ref_license_id, note, created_at
       FROM credit_ledger WHERE reseller_id = ? ORDER BY created_at DESC LIMIT 300`
  ).bind(id).all();
  return jsonResp({ items: rs.results || [] });
}
__name(handleResellerCreditsList, "handleResellerCreditsList");
async function handleDeviceTransfer(request, env, user, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const oldMac = (body.old_mac || "").trim().toUpperCase();
  const newMac = (body.new_mac || "").trim().toUpperCase();
  const macRx = /^MK(?::[0-9A-F]{2}){5}$/i;
  if (!macRx.test(oldMac))
    return errResp("bad_mac", "Ancienne MAC invalide.", 400);
  if (!macRx.test(newMac))
    return errResp("bad_mac", "Nouvelle MAC invalide.", 400);
  if (oldMac === newMac)
    return errResp("same_mac", "Les deux MAC sont identiques.", 400);
  const isReseller = user.role === "reseller";
  const now = Date.now();
  const oldDev = await env.DB.prepare("SELECT id, customer_id, reseller_id FROM devices WHERE mac = ?").bind(oldMac).first();
  if (!oldDev)
    return errResp("not_found", "Ancienne MAC introuvable.", 404);
  if (isReseller && oldDev.reseller_id && oldDev.reseller_id !== user.sub) {
    return errResp("forbidden", "Cet appareil ne t'appartient pas.", 403);
  }
  const lics = await env.DB.prepare("SELECT id, expires_at, status FROM licenses WHERE device_id = ?").bind(oldDev.id).all();
  const licRows = lics.results || [];
  let newDev = await env.DB.prepare("SELECT id, reseller_id FROM devices WHERE mac = ?").bind(newMac).first();
  let newDeviceId;
  if (newDev) {
    if (isReseller && newDev.reseller_id && newDev.reseller_id !== user.sub) {
      return errResp("forbidden", "La nouvelle MAC appartient \xE0 un autre revendeur.", 403);
    }
    newDeviceId = newDev.id;
    await env.DB.prepare(
      "UPDATE devices SET customer_id = ?, reseller_id = COALESCE(reseller_id, ?), block_status = NULL, last_seen_at = ? WHERE id = ?"
    ).bind(oldDev.customer_id, oldDev.reseller_id, now, newDeviceId).run();
  } else {
    newDeviceId = genId("dev");
    await env.DB.prepare(
      `INSERT INTO devices (id, customer_id, mac, label, reseller_id, first_seen_at, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      newDeviceId,
      oldDev.customer_id,
      newMac,
      body.label || "Transfert",
      oldDev.reseller_id,
      now,
      now
    ).run();
  }
  await env.DB.prepare(
    "UPDATE licenses SET device_id = ?, customer_id = ?, updated_at = ? WHERE device_id = ?"
  ).bind(newDeviceId, oldDev.customer_id, now, oldDev.id).run();
  try {
    await ensureSourcesTable(env);
    await ensureSourcesVersion(env);
    const [, moved] = await env.DB.batch([
      env.DB.prepare("DELETE FROM device_sources WHERE mac = ?").bind(newMac),
      env.DB.prepare(
        "UPDATE device_sources SET mac = ?, updated_at = ?, version = COALESCE(version, 0) + 1 WHERE mac = ?"
      ).bind(newMac, now, oldMac)
    ]);
    await markSourcesCleared(env, oldMac, now);
    if (moved && moved.meta && moved.meta.changes) {
      await clearSourceTombstone(env, newMac);
    } else {
      await markSourcesCleared(env, newMac, now);
    }
  } catch (_) {
  }
  await logAudit(
    env,
    request,
    actor,
    "device.transfer",
    { type: "device", id: oldDev.id },
    { old_mac: oldMac },
    { new_mac: newMac, moved_licenses: licRows.length }
  );
  return jsonResp({
    ok: true,
    old_mac: oldMac,
    new_mac: newMac,
    moved_licenses: licRows.length
  });
}
__name(handleDeviceTransfer, "handleDeviceTransfer");
async function trialDeadlineForDevice(env, dev, now) {
  let trialStart = dev.first_seen_at || now;
  let trialDays = await configuredTrialDays(env);
  if (trialEnforcementOn(env)) {
    trialStart = await rememberTrialStart(
      env,
      dev.mac,
      dev.android_id || "",
      trialStart
    );
    trialDays = TRIAL_DAYS;
  }
  const win = trialWindow(trialStart, now, trialDays);
  const ext = await readExtendedUntil(env, dev.mac);
  return ext > win.trialUntil ? ext : win.trialUntil;
}
__name(trialDeadlineForDevice, "trialDeadlineForDevice");
async function handleTrialExtend(request, env, actor) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const mac = String(body.mac || "").trim().toUpperCase();
  if (!/^MK(?::[0-9A-F]{2}){5}$/.test(mac)) {
    return errResp("bad_mac", "MAC invalide. Format attendu : MK:XX:XX:XX:XX:XX", 400);
  }
  const parsed = parseExtendDays(body.days);
  if (parsed.error)
    return errResp("bad_days", parsed.error, 400);
  let dev = null;
  try {
    dev = await env.DB.prepare(
      "SELECT id, mac, first_seen_at, android_id, block_status FROM devices WHERE mac = ?"
    ).bind(mac).first();
  } catch (_) {
    try {
      dev = await env.DB.prepare(
        "SELECT id, mac, first_seen_at, block_status FROM devices WHERE mac = ?"
      ).bind(mac).first();
    } catch (_2) {
      dev = null;
    }
  }
  if (!dev) {
    return errResp(
      "unknown_mac",
      "MAC inconnue. L\u2019appareil doit d\xE9j\xE0 s\u2019\xEAtre connect\xE9.",
      404
    );
  }
  dev.mac = mac;
  const now = Date.now();
  const previous = await trialDeadlineForDevice(env, dev, now);
  const trialUntil = nextTrialEnd(previous, now, parsed.days);
  await ensureTrialAnchorTable(env);
  const existing = await env.DB.prepare("SELECT mac FROM trial_anchors WHERE mac = ?").bind(mac).first();
  if (existing) {
    await env.DB.prepare(
      "UPDATE trial_anchors SET extended_until = ? WHERE mac = ?"
    ).bind(trialUntil, mac).run();
  } else {
    await env.DB.prepare(
      "INSERT INTO trial_anchors (mac, android_id, started_at, extended_until) VALUES (?, ?, ?, ?)"
    ).bind(mac, dev.android_id || null, dev.first_seen_at || now, trialUntil).run();
  }
  await env.DB.prepare(
    `INSERT INTO trial_extensions
      (id, mac, days, previous_until, new_until, actor_type, actor_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    genId("tx"),
    mac,
    parsed.days,
    previous || null,
    trialUntil,
    actor && actor.type,
    actor && actor.id,
    now
  ).run();
  await logAudit(
    env,
    request,
    actor,
    "trial.extend",
    { type: "device", id: dev.id },
    null,
    { mac, days: parsed.days, previous_until: previous, trial_until: trialUntil }
  );
  await notifyBox(env, mac, "license");
  return jsonResp({
    ok: true,
    mac,
    days: parsed.days,
    previous_until: previous,
    trial_until: trialUntil
  });
}
__name(handleTrialExtend, "handleTrialExtend");
async function handleActivate(request, env, user, actor, idemSlot = null) {
  const t0 = Date.now();
  const correlationId = request.headers.get("X-Request-Id") || null;
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return errResp("bad_json", "Invalid JSON body", 400);
  }
  const mac = (body.mac || "").trim().toUpperCase();
  const plan = body.plan || "monthly";
  const appId = body.app_id || "app_7motion";
  if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(mac)) {
    return errResp("bad_mac", "mac must be MK:XX:XX:XX:XX:XX", 400);
  }
  if (body.source || body.sources) {
    return errResp(
      "source_separate",
      "Activation et lien M3U sont deux op\xE9rations distinctes. Posez le lien avec PUT /api/v1/sources/:mac.",
      400
    );
  }
  const planError = unknownPlanMessage(plan);
  if (planError)
    return errResp("bad_plan", planError, 400);
  const isReseller = user.role === "reseller";
  const isTrialPlan = typeof plan === "string" && plan.startsWith("trial");
  const RESELLER_PLANS = ["yearly", "lifetime"];
  if (isReseller && !isTrialPlan && !RESELLER_PLANS.includes(plan)) {
    return errResp(
      "plan_forbidden",
      "Ce plan est r\xE9serv\xE9 \xE0 l\u2019administrateur. Les revendeurs activent 1 an (1 cr\xE9dit) ou \xE0 vie (2 cr\xE9dits).",
      403
    );
  }
  const chargeResellerId = isReseller ? user.sub : body.reseller_id || null;
  const cost = await planCreditCost(env, plan);
  const now = Date.now();
  const days = planToDays(plan, body.custom_days);
  const earlyDev = await env.DB.prepare("SELECT id, customer_id, reseller_id FROM devices WHERE mac = ?").bind(mac).first();
  if (earlyDev && isReseller && earlyDev.reseller_id && earlyDev.reseller_id !== user.sub) {
    return errResp("forbidden", "This device belongs to another reseller", 403);
  }
  if (earlyDev) {
    const earlyLic = await env.DB.prepare("SELECT id, expires_at FROM licenses WHERE device_id = ? AND app_id = ?").bind(earlyDev.id, appId).first();
    if (earlyLic && earlyLic.expires_at == null) {
      if (days !== null) {
        return errResp(
          "already_lifetime",
          "Cet appareil est d\xE9j\xE0 \xE0 vie. Un plan dat\xE9 ne peut pas le raccourcir.",
          409
        );
      }
      await env.DB.prepare(
        `UPDATE licenses SET status='active', plan='lifetime', updated_at=? WHERE id=?`
      ).bind(now, earlyLic.id).run();
      await env.DB.prepare("UPDATE devices SET block_status = NULL WHERE id = ?").bind(earlyDev.id).run();
      let balance = null;
      if (chargeResellerId) {
        const r = await env.DB.prepare("SELECT credit_balance FROM resellers WHERE id = ?").bind(chargeResellerId).first();
        balance = r ? r.credit_balance : null;
      }
      await logAudit(
        env,
        request,
        actor,
        "activate.keep_lifetime",
        { type: "license", id: earlyLic.id },
        null,
        { mac, plan: "lifetime", cost: 0 }
      );
      await notifyBox(env, mac, "activate", orderOpts(request));
      return jsonResp({
        ok: true,
        license_id: earlyLic.id,
        device_id: earlyDev.id,
        customer_id: earlyDev.customer_id,
        mac,
        plan: "lifetime",
        expires_at: null,
        credits_charged: 0,
        credit_balance: balance,
        renewed: false,
        already_lifetime: true
      }, 200);
    }
  }
  let resellerRow = null;
  if (chargeResellerId) {
    resellerRow = await env.DB.prepare("SELECT id, status, credit_balance FROM resellers WHERE id = ?").bind(chargeResellerId).first();
    if (!resellerRow)
      return errResp("not_found", "Reseller not found", 404);
    if (resellerRow.status !== "active") {
      return errResp("reseller_suspended", "Reseller is suspended", 403);
    }
    if (resellerRow.credit_balance < cost) {
      return errResp(
        "insufficient_credits",
        `Credits insuffisants (besoin ${cost}, solde ${resellerRow.credit_balance})`,
        402
      );
    }
  }
  let device = await env.DB.prepare("SELECT id, customer_id, reseller_id FROM devices WHERE mac = ?").bind(mac).first();
  if (!device) {
    const newCustomerId = genId("cus");
    const newDeviceId = genId("dev");
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO customers (id, email, name, phone, reseller_id, notes, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(
        newCustomerId,
        body.customer_email || null,
        body.customer_name || "Client " + mac.slice(-5),
        null,
        chargeResellerId,
        null,
        now,
        now
      ),
      env.DB.prepare(
        `INSERT INTO devices (id, customer_id, mac, label, reseller_id, first_seen_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(mac) DO NOTHING`
      ).bind(newDeviceId, newCustomerId, mac, body.label || null, chargeResellerId, now, now),
      env.DB.prepare(
        "DELETE FROM customers WHERE id = ? AND NOT EXISTS (SELECT 1 FROM devices WHERE customer_id = ?)"
      ).bind(newCustomerId, newCustomerId)
    ]);
    device = await env.DB.prepare("SELECT id, customer_id, reseller_id FROM devices WHERE mac = ?").bind(mac).first();
    if (!device) {
      return errResp("activation_conflict", "Appareil introuvable apr\xE8s cr\xE9ation. R\xE9essaie.", 409);
    }
  }
  if (isReseller && device.reseller_id && device.reseller_id !== user.sub) {
    return errResp("forbidden", "This device belongs to another reseller", 403);
  }
  const deviceId = device.id;
  const customerId = device.customer_id;
  if (chargeResellerId && !device.reseller_id) {
    await env.DB.prepare("UPDATE devices SET reseller_id = ?, last_seen_at = ? WHERE id = ? AND reseller_id IS NULL").bind(chargeResellerId, now, deviceId).run();
  }
  const enforceCredits = trialEnforcementOn(env);
  if (enforceCredits) {
    const early = await env.DB.prepare("SELECT id, expires_at, status FROM licenses WHERE device_id = ? AND app_id = ?").bind(deviceId, appId).first();
    const alreadyLife = early && early.status === "active" && (early.expires_at === null || early.expires_at === void 0);
    if (alreadyLife) {
      await notifyBox(env, mac, "activate", orderOpts(request));
      return jsonResp({
        ok: true,
        already_lifetime: true,
        license_id: early.id,
        device_id: deviceId,
        customer_id: customerId,
        mac,
        plan: "lifetime",
        expires_at: null,
        credits_charged: 0,
        credit_balance: resellerRow ? resellerRow.credit_balance : null,
        renewed: false
      }, 200);
    }
  }
  const before = await env.DB.prepare("SELECT id, expires_at, status, plan FROM licenses WHERE device_id = ? AND app_id = ?").bind(deviceId, appId).first();
  const addMs = days === null ? null : days * 24 * 60 * 60 * 1e3;
  const newLicenseId = genId("lic");
  const charge = !!(chargeResellerId && cost > 0);
  const conditional = charge;
  const guard = conditional ? "changes() = 1" : "1";
  const stmts = [];
  if (charge) {
    stmts.push(env.DB.prepare("UPDATE resellers SET credit_balance = credit_balance - ? WHERE id = ? AND credit_balance >= ?").bind(cost, chargeResellerId, cost));
  }
  const licenseIdx = stmts.length;
  stmts.push(env.DB.prepare(
    `INSERT INTO licenses
       (id, customer_id, device_id, app_id, status, plan, started_at,
        expires_at, auto_renew, reseller_id, created_at, updated_at)
     SELECT ?, ?, ?, ?, 'active', ?, ?, ?, 0, ?, ?, ? WHERE ${guard}
     ON CONFLICT(device_id, app_id) DO UPDATE SET
       status = 'active',
       -- Le libell\xE9 du plan suit la dur\xE9e achet\xE9e, sauf :
       --   \u2022 licence \xE0 vie : elle reste \xE0 vie ;
       --   \u2022 essai gratuit ajout\xE9 \xE0 un abonnement PAY\xC9 encore actif : les
       --     jours s'ajoutent, le plan pay\xE9 reste (mesur\xE9 le 06/10/2026 :
       --     box pay\xE9e jusqu'en 2027 affich\xE9e \xAB trial_7d \xBB).
       plan = CASE
         WHEN licenses.expires_at IS NULL AND ? IS NOT NULL THEN licenses.plan
         WHEN excluded.plan LIKE 'trial%' AND licenses.plan NOT LIKE 'trial%'
              AND licenses.status = 'active' AND licenses.expires_at > ? THEN licenses.plan
         ELSE excluded.plan
       END,
       expires_at = CASE
         WHEN ? IS NULL THEN NULL
         WHEN licenses.expires_at IS NULL THEN NULL
         ELSE MAX(licenses.expires_at, ?) + ?
       END,
       reseller_id = COALESCE(licenses.reseller_id, excluded.reseller_id),
       updated_at = excluded.updated_at
     RETURNING id, expires_at`
  ).bind(
    newLicenseId,
    customerId,
    deviceId,
    appId,
    plan,
    now,
    addMs === null ? null : now + addMs,
    chargeResellerId,
    now,
    now,
    addMs,
    now,
    addMs,
    now,
    addMs
  ));
  const ledgerId = genId("cl");
  if (charge) {
    stmts.push(env.DB.prepare(
      `INSERT INTO credit_ledger
         (id, reseller_id, delta, reason, balance_after, ref_license_id,
          ref_device_mac, actor_type, actor_id, note, created_at)
       SELECT ?, ?, ?,
              CASE WHEN (SELECT id FROM licenses WHERE device_id = ? AND app_id = ?) = ? THEN 'activation' ELSE 'renew' END,
              (SELECT credit_balance FROM resellers WHERE id = ?),
              (SELECT id FROM licenses WHERE device_id = ? AND app_id = ?),
              ?, ?, ?, ?, ?
       WHERE changes() = 1`
    ).bind(
      ledgerId,
      chargeResellerId,
      -cost,
      deviceId,
      appId,
      newLicenseId,
      chargeResellerId,
      deviceId,
      appId,
      mac,
      actor.type,
      actor.id,
      plan,
      now
    ));
  }
  stmts.push(env.DB.prepare("UPDATE devices SET block_status = NULL WHERE id = ?").bind(deviceId));
  if (idemSlot && idemSlot.key) {
    stmts.push(env.DB.prepare(
      `UPDATE idempotency_keys SET committed_at = ?, commit_ref = json_object(
         'license_id', (SELECT id FROM licenses WHERE device_id = ? AND app_id = ?),
         'expires_at', (SELECT expires_at FROM licenses WHERE device_id = ? AND app_id = ?),
         'renewed', CASE WHEN (SELECT id FROM licenses WHERE device_id = ? AND app_id = ?) = ? THEN 0 ELSE 1 END,
         'device_id', ?, 'customer_id', ?, 'mac', ?, 'plan', ?,
         'credits_charged', ?, 'credit_balance', (SELECT credit_balance FROM resellers WHERE id = ?),
         'trace_id', ?)
       WHERE k = ? AND ${charge ? "EXISTS (SELECT 1 FROM credit_ledger WHERE id = ?)" : "1 = ?"}`
    ).bind(
      Date.now(),
      deviceId,
      appId,
      deviceId,
      appId,
      deviceId,
      appId,
      newLicenseId,
      deviceId,
      customerId,
      mac,
      plan,
      chargeResellerId ? cost : 0,
      chargeResellerId || "",
      correlationId || null,
      idemSlot.key,
      charge ? ledgerId : 1
    ));
  }
  const balanceIdx = stmts.length;
  if (charge) {
    stmts.push(env.DB.prepare("SELECT credit_balance FROM resellers WHERE id = ?").bind(chargeResellerId));
  }
  const results = await env.DB.batch(stmts);
  if (conditional && !(results[0] && results[0].meta && results[0].meta.changes)) {
    const fresh = await env.DB.prepare("SELECT credit_balance FROM resellers WHERE id = ?").bind(chargeResellerId).first();
    return errResp(
      "insufficient_credits",
      `Credits insuffisants (besoin ${cost}, solde ${fresh ? fresh.credit_balance : 0})`,
      402
    );
  }
  const licRow = results[licenseIdx] && results[licenseIdx].results && results[licenseIdx].results[0];
  if (!licRow) {
    return errResp("activation_conflict", "Licence non \xE9crite. Relis la fiche puis r\xE9essaie.", 409);
  }
  const licenseId = licRow.id;
  const finalExpiry = licRow.expires_at === void 0 ? null : licRow.expires_at;
  const renewed = licenseId !== newLicenseId;
  const balRow = charge && results[balanceIdx] && results[balanceIdx].results ? results[balanceIdx].results[0] : null;
  const balanceAfter = charge ? balRow ? balRow.credit_balance : null : resellerRow ? resellerRow.credit_balance : null;
  await logAudit(
    env,
    request,
    actor,
    renewed ? "activate.renew" : "activate.create",
    { type: "license", id: licenseId },
    before ? { status: before.status, plan: before.plan, expires_at: before.expires_at } : null,
    {
      mac,
      plan,
      app_id: appId,
      cost,
      reseller_id: chargeResellerId,
      status: "active",
      expires_at: finalExpiry,
      device_id: deviceId,
      customer_id: customerId,
      took_ms: Date.now() - t0,
      request_id: correlationId
    }
  );
  const orderId = await notifyBox(env, mac, renewed ? "renew" : "activate", orderOpts(request));
  return jsonResp({
    ok: true,
    license_id: licenseId,
    device_id: deviceId,
    customer_id: customerId,
    mac,
    plan,
    expires_at: finalExpiry,
    credits_charged: chargeResellerId ? cost : 0,
    credit_balance: balanceAfter,
    renewed,
    order_id: orderId,
    trace_id: correlationId
  }, 201);
}
__name(handleActivate, "handleActivate");

// migrate_kv_to_d1.js
function genId2(prefix) {
  const ts = Date.now().toString(36).padStart(8, "0");
  const rand = Array.from(crypto.getRandomValues(new Uint8Array(8))).map((b) => (b % 36).toString(36)).join("");
  return `${prefix}_${ts}${rand}`;
}
__name(genId2, "genId");
function deriveLicenseStatus(kvClient, now) {
  if (kvClient.status === "banned")
    return "banned";
  if (kvClient.status === "frozen")
    return "frozen";
  if (kvClient.paid === true)
    return "active";
  const trial = kvClient.trial_until || 0;
  if (trial > now)
    return "active";
  return "expired";
}
__name(deriveLicenseStatus, "deriveLicenseStatus");
function derivePlan(kvClient) {
  return kvClient.paid === true ? "yearly" : "trial";
}
__name(derivePlan, "derivePlan");
function pickPrimaryPlaylist(kvClient) {
  const list = Array.isArray(kvClient.playlists) ? kvClient.playlists : [];
  return list.find((p) => p && p.type === "xtream") || list.find((p) => p && p.type === "m3u") || null;
}
__name(pickPrimaryPlaylist, "pickPrimaryPlaylist");
var DEFAULT_APP_ID = "app_7motion";
async function runMigration(env, { dryRun = false } = {}) {
  if (!env.DB) {
    return { error: 'D1 binding "DB" missing \u2014 wrangler.toml a jour ?' };
  }
  if (!env.KV_7MOTION) {
    return { error: 'KV binding "KV_7MOTION" missing' };
  }
  const indexRaw = await env.KV_7MOTION.get("_index");
  if (!indexRaw) {
    return { migrated: 0, skipped: 0, errors: [], note: "No _index in KV \u2014 nothing to migrate" };
  }
  let macs;
  try {
    macs = JSON.parse(indexRaw);
  } catch (_) {
    return { error: "_index is not valid JSON" };
  }
  if (!Array.isArray(macs)) {
    return { error: "_index is not an array" };
  }
  const now = Date.now();
  let migrated = 0;
  let skipped = 0;
  const errors = [];
  for (const mac of macs) {
    try {
      const raw = await env.KV_7MOTION.get(`client:${mac}`);
      if (!raw) {
        skipped++;
        continue;
      }
      const client = JSON.parse(raw);
      const existing = await env.DB.prepare("SELECT id, customer_id FROM devices WHERE mac = ?").bind(mac).first();
      let customerId;
      let deviceId;
      if (existing) {
        deviceId = existing.id;
        customerId = existing.customer_id;
        if (!dryRun) {
          await env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(client.last_seen_at || now, deviceId).run();
        }
      } else {
        customerId = genId2("cus");
        deviceId = genId2("dev");
        if (!dryRun) {
          const firstSeen = client.first_seen_at || client.added_at || now;
          const lastSeen = client.last_seen_at || firstSeen;
          await env.DB.batch([
            env.DB.prepare(
              `INSERT INTO customers (id, name, notes, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?)`
            ).bind(
              customerId,
              client.name || null,
              client.note || null,
              firstSeen,
              now
            ),
            env.DB.prepare(
              `INSERT INTO devices (id, customer_id, mac, label,
                                    first_seen_at, last_seen_at)
               VALUES (?, ?, ?, ?, ?, ?)`
            ).bind(
              deviceId,
              customerId,
              mac,
              null,
              firstSeen,
              lastSeen
            )
          ]);
        }
      }
      const existingLic = await env.DB.prepare("SELECT id FROM licenses WHERE device_id = ? AND app_id = ?").bind(deviceId, DEFAULT_APP_ID).first();
      if (existingLic) {
        skipped++;
        continue;
      }
      const status = deriveLicenseStatus(client, now);
      const plan = derivePlan(client);
      const startedAt = client.added_at || now;
      const expiresAt = client.trial_until ? client.trial_until : client.paid ? startedAt + 365 * 24 * 60 * 60 * 1e3 : null;
      const licenseId = genId2("lic");
      const playlist = pickPrimaryPlaylist(client);
      if (!dryRun) {
        const ops = [
          env.DB.prepare(
            `INSERT INTO licenses
              (id, customer_id, device_id, app_id, status, plan,
               started_at, expires_at, auto_renew, notes,
               created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)`
          ).bind(
            licenseId,
            customerId,
            deviceId,
            DEFAULT_APP_ID,
            status,
            plan,
            startedAt,
            expiresAt,
            client.note || null,
            now,
            now
          )
        ];
        if (playlist) {
          const playlistId = genId2("plt");
          ops.push(env.DB.prepare(
            `INSERT INTO playlists
              (id, license_id, type, server_url, username_enc,
               password_enc, m3u_url, epg_url, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
          ).bind(
            playlistId,
            licenseId,
            playlist.type || "xtream",
            playlist.server || playlist.url || null,
            playlist.username || null,
            playlist.password || null,
            playlist.type === "m3u" ? playlist.url || null : null,
            playlist.epg_url || null,
            now
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
__name(runMigration, "runMigration");

// cast_receiver.js
function castReceiverHtml(flavor) {
  const isRedRoom = flavor === "redroom";
  const appName = isRedRoom ? "Red Room" : "7 MOTION";
  const accent = "#D63A30";
  const bg = isRedRoom ? "#08060A" : "#0A0A0C";
  const logoUrl = isRedRoom ? "https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_redroom.png" : "https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_7motion.jpg";
  return `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${appName} \xB7 Cast</title>
  <!--
    CAF Receiver SDK v3 (Cast Application Framework) \u2014 transforme la
    page en receiver Cast officiel. mpegts.js = transmux MPEG-TS brut
    (IPTV Xtream) vers fMP4 cote TV. hls.js = repli HLS si le pipeline
    natif CAF refuse une variante. Les deux sont charges depuis un CDN
    par la TV elle-meme (pas par notre backend).
  -->
  <script src="//www.gstatic.com/cast/sdk/libs/caf_receiver/v3/cast_receiver_framework.js"><\/script>
  <script src="//cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.js"><\/script>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: ${bg};
      color: #F2F2F4;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      width: 100%;
      height: 100%;
      overflow: hidden;
    }

    /* ===== <cast-media-player> : pipeline CAF natif (HLS/DASH/MP4) ===== */
    cast-media-player {
      --theme-hue: 0;
      --background-color: ${bg};
      --logo-image: url('${logoUrl}');
      --logo-background-color: ${bg};
      --splash-image: url('${logoUrl}');
      --splash-background-color: ${bg};
      --progress-color: ${accent};
      --break-color: ${accent};
      --play-icon-color: #F2F2F4;
      --buffer-color: rgba(255, 90, 74, 0.45);
      width: 100%;
      height: 100%;
    }

    /* ===== <video> dedie au MPEG-TS brut pilote par mpegts.js =====
       Masque par defaut ; on l'affiche PAR-DESSUS le cast-media-player
       uniquement pendant une lecture TS. */
    #ts-video {
      position: fixed;
      inset: 0;
      width: 100%;
      height: 100%;
      background: ${bg};
      object-fit: contain;
      z-index: 1;
      display: none;
    }
    #ts-video.active { display: block; }

    /* ===== Watermark coin bas-droite pendant la lecture ===== */
    .brand-watermark {
      position: fixed;
      right: 24px;
      bottom: 24px;
      z-index: 3;
      opacity: 0.55;
      pointer-events: none;
      font-size: 11px;
      letter-spacing: 3px;
      font-weight: 700;
      color: rgba(255, 255, 255, 0.85);
      text-shadow: 0 2px 8px rgba(0, 0, 0, 0.8);
    }
    .brand-watermark::before {
      content: '';
      display: inline-block;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: ${accent};
      margin-right: 8px;
      vertical-align: middle;
    }
  </style>
</head>
<body>
  <!-- Pipeline CAF natif : splash + lecture HLS/DASH/MP4. -->
  <cast-media-player></cast-media-player>

  <!-- Element dedie au MPEG-TS brut (mpegts.js). Affiche par-dessus
       le cast-media-player seulement pendant une lecture TS. -->
  <video id="ts-video" playsinline></video>

  <div class="brand-watermark">${appName}</div>

  <script>
    // =====================================================
    //  Boot du receiver
    // =====================================================
    const APP = '${appName}';
    const context = cast.framework.CastReceiverContext.getInstance();
    const playerManager = context.getPlayerManager();

    const tsVideo = document.getElementById('ts-video');
    let mpegtsPlayer = null;     // instance mpegts.js courante
    let tsActive = false;        // true tant qu'une lecture TS est en cours

    // ---- Helpers -------------------------------------------------
    function log() {
      try { console.log.apply(console, ['[' + APP + ' cast]'].concat([].slice.call(arguments))); } catch (e) {}
    }

    // Heuristique : URL de flux MPEG-TS brut (IPTV Xtream live).
    //   - extension .ts (eventuellement suivie de query string)
    //   - contentType video/mp2t
    //   - chemin Xtream /live/USER/PASS/ID(.ts)
    // On EXCLUT explicitement le HLS (.m3u8) qui contient aussi des
    // segments .ts mais doit passer par le pipeline HLS, pas mpegts.js.
    function isRawMpegTs(url, contentType) {
      const u = (url || '').toLowerCase();
      const ct = (contentType || '').toLowerCase();
      if (u.indexOf('.m3u8') !== -1) return false;
      if (ct.indexOf('mpegurl') !== -1) return false;
      if (ct === 'video/mp2t' || ct === 'video/mpeg' || ct === 'video/vnd.dlna.mpeg-tts') return true;
      if (/\\.ts(\\?|$)/.test(u)) return true;
      if (u.indexOf('/live/') !== -1) return true;
      return false;
    }

    function teardownTs() {
      tsActive = false;
      tsVideo.classList.remove('active');
      try { tsVideo.pause(); } catch (e) {}
      if (mpegtsPlayer) {
        try { mpegtsPlayer.unload(); } catch (e) {}
        try { mpegtsPlayer.detachMediaElement(); } catch (e) {}
        try { mpegtsPlayer.destroy(); } catch (e) {}
        mpegtsPlayer = null;
      }
      try { tsVideo.removeAttribute('src'); tsVideo.load(); } catch (e) {}
    }

    // Lance un flux MPEG-TS brut via mpegts.js sur le <video> dedie.
    function playRawTs(url) {
      teardownTs();
      if (!window.mpegts || !mpegts.isSupported()) {
        log('mpegts.js indisponible \u2014 la TV ne supporte pas MSE pour le TS');
        return false;
      }
      mpegtsPlayer = mpegts.createPlayer({
        type: 'mpegts',
        isLive: true,
        url: url,
      }, {
        // Live : pas de buffer infini, on colle au direct.
        liveBufferLatencyChasing: true,
        lazyLoad: false,
        enableWorker: true,
      });
      mpegtsPlayer.attachMediaElement(tsVideo);
      mpegtsPlayer.on(mpegts.Events.ERROR, function (type, detail) {
        log('mpegts error', type, detail);
      });
      mpegtsPlayer.load();
      tsVideo.muted = false;
      const p = tsVideo.play();
      if (p && p.catch) p.catch(function (e) { log('ts autoplay blocked', e); });
      tsActive = true;
      tsVideo.classList.add('active');
      return true;
    }

    // =====================================================
    //  LOAD interceptor \u2014 route le flux selon son type
    // =====================================================
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.LOAD,
      function (request) {
        try {
          const media = request.media || {};
          const url = media.contentId || media.contentUrl || '';
          const ct = media.contentType || '';
          log('LOAD', url, ct);

          if (isRawMpegTs(url, ct)) {
            // MPEG-TS brut \u2192 mpegts.js sur le <video> dedie. On indique
            // a CAF que le contenu est gere en externe : on lance la
            // lecture nous-memes et on renvoie null pour suspendre le
            // pipeline CAF (qui ecran-noirerait sur du TS brut).
            const ok = playRawTs(url);
            if (ok) {
              // Met a jour le MediaInformation pour que le sender voie
              // un etat coherent (titre, live).
              return null; // suspend le load CAF natif (mpegts.js gere)
            }
            // mpegts.js KO \u2192 on laisse CAF tenter sa chance (repli).
          } else {
            // Tout flux NON-TS \u2192 pipeline CAF natif. On s'assure que le
            // <video> mpegts est bien rendu et qu'un eventuel flux TS
            // precedent est demonte.
            if (tsActive) teardownTs();
          }

          // HLS / DASH / MP4 : normalisations utiles.
          if (/\\.m3u8(\\?|$)/i.test(url) && !media.contentType) {
            media.contentType = 'application/x-mpegURL';
          }
          // Flux live (Xtream / pas de duree) \u2192 streamType LIVE, sinon
          // CAF attend une duree et peut rester en buffering.
          if (media.streamType == null &&
              (url.indexOf('/live/') !== -1 || /\\.m3u8(\\?|$)/i.test(url))) {
            media.streamType = cast.framework.messages.StreamType.LIVE;
          }
          request.media = media;
          return request;
        } catch (e) {
          log('LOAD interceptor error', e);
          return request;
        }
      }
    );

    // Quand le sender coupe (STOP) ou met en pause/play, on relaie au
    // lecteur mpegts.js s'il est actif.
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.STOP,
      function (request) { if (tsActive) teardownTs(); return request; }
    );
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.PAUSE,
      function (request) { if (tsActive) { try { tsVideo.pause(); } catch (e) {} return null; } return request; }
    );
    playerManager.setMessageInterceptor(
      cast.framework.messages.MessageType.PLAY,
      function (request) { if (tsActive) { try { tsVideo.play(); } catch (e) {} return null; } return request; }
    );

    playerManager.addEventListener(
      cast.framework.events.EventType.ERROR,
      function (event) { log('CAF error', event); }
    );

    // =====================================================
    //  Options de demarrage
    // =====================================================
    const options = new cast.framework.CastReceiverOptions();
    // Le receiver reste vivant tant qu'un flux joue (live IPTV =
    // sessions longues, le telephone peut etre eteint).
    options.disableIdleTimeout = true;
    options.statusText = APP;
    context.start(options);
  <\/script>
</body>
</html>`;
}
__name(castReceiverHtml, "castReceiverHtml");

// screen_receiver.js
function screenPairHtml() {
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>7 MOTION \u2014 \xC9cran</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:#0A0A0C;color:#fff;
    font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
  .wrap{position:fixed;inset:0;display:flex;flex-direction:column;
    align-items:center;justify-content:center;text-align:center;padding:6vh 5vw}
  .logo{font-size:clamp(28px,6vw,64px);font-weight:800;letter-spacing:.06em;margin-bottom:2vh}
  .logo b{color:#D63A30}
  .hint{font-size:clamp(15px,2.4vw,26px);color:#9aa;max-width:760px;line-height:1.5;margin-bottom:5vh}
  form{display:flex;flex-direction:column;align-items:center;gap:3.2vh}
  input{font-size:clamp(40px,10vw,110px);font-weight:800;letter-spacing:.22em;
    text-align:center;text-transform:uppercase;width:min(90vw,8em);
    background:#121216;color:#fff;border:3px solid #2a2a30;border-radius:18px;
    padding:.18em .1em;caret-color:#D63A30}
  input:focus{outline:none;border-color:#D63A30}
  button{font-size:clamp(18px,2.6vw,30px);font-weight:700;color:#fff;
    background:#D63A30;border:none;border-radius:14px;padding:.7em 2.4em;cursor:pointer}
  button:focus{outline:3px solid #fff;outline-offset:3px}
  .err{color:#D63A30;font-size:clamp(14px,2vw,20px);min-height:1.4em;margin-top:1vh}
</style>
</head>
<body>
  <div class="wrap">
    <div class="logo">7&nbsp;<b>MOTION</b></div>
    <div class="hint">Entre le code \xE0 4&nbsp;caract\xE8res affich\xE9 sur ton t\xE9l\xE9phone
      (rubrique \xAB Caster sur un \xE9cran \xBB).</div>
    <form id="f">
      <input id="c" autocomplete="off" autocapitalize="characters"
        autocorrect="off" spellcheck="false" maxlength="4"
        inputmode="text" placeholder="\u2013\u2013\u2013\u2013" autofocus>
      <button type="submit">Valider</button>
      <div class="err" id="e"></div>
    </form>
  </div>
<script>
(function(){
  var input=document.getElementById('c'), err=document.getElementById('e');
  document.getElementById('f').addEventListener('submit',function(ev){
    ev.preventDefault();
    var code=(input.value||'').toUpperCase().replace(/[^2-9A-Z]/g,'');
    if(code.length!==4){ err.textContent='Code \xE0 4 caract\xE8res (chiffres 2-9 et lettres).'; return; }
    window.location.href='/e/'+code;
  });
  input.addEventListener('input',function(){
    input.value=(input.value||'').toUpperCase().replace(/[^2-9A-Z]/g,'').slice(0,4);
    err.textContent='';
  });
})();
<\/script>
</body>
</html>`;
}
__name(screenPairHtml, "screenPairHtml");
function screenReceiverHtml(code) {
  const safeCode = String(code || "").replace(/[^0-9A-Za-z]/g, "").slice(0, 8);
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>7 MOTION \u2014 \xC9cran</title>
<script src="//cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.js"><\/script>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { width:100%; height:100%; background:#0A0A0C; color:#fff;
    font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
    overflow:hidden; }
  #video { position:fixed; inset:0; width:100%; height:100%;
    background:#000; object-fit:contain; display:none; }
  #video.active { display:block; }
  #panel { position:fixed; inset:0; display:flex; flex-direction:column;
    align-items:center; justify-content:center; text-align:center; padding:6vh 4vw; }
  #panel.hidden { display:none; }
  .logo { font-size:clamp(28px,6vw,64px); font-weight:800; letter-spacing:.06em;
    color:#fff; margin-bottom:3vh; }
  .logo b { color:#D63A30; }
  .hint { font-size:clamp(15px,2.2vw,24px); color:#9aa; max-width:680px;
    line-height:1.5; }
  .codebox { margin-top:4vh; padding:2.4vh 5vw; border:2px solid #2a2a30;
    border-radius:18px; background:#121216; }
  .codelbl { font-size:clamp(12px,1.6vw,16px); color:#778; text-transform:uppercase;
    letter-spacing:.18em; margin-bottom:1.2vh; }
  .code { font-size:clamp(40px,9vw,96px); font-weight:800; letter-spacing:.14em;
    color:#D63A30; font-variant-numeric:tabular-nums; }
  .dot { display:inline-block; width:.5em; height:.5em; border-radius:50%;
    background:#3a3; margin-right:.5em; vertical-align:middle;
    animation:pulse 1.6s ease-in-out infinite; }
  @keyframes pulse { 0%,100%{opacity:.35} 50%{opacity:1} }
  #err { position:fixed; left:0; right:0; bottom:0; padding:2.4vh 4vw;
    background:rgba(214,58,48,.92); color:#fff; font-size:clamp(15px,2.2vw,22px);
    text-align:center; display:none; }
  #err.show { display:block; }
</style>
</head>
<body>
  <video id="video" playsinline webkit-playsinline autoplay></video>

  <div id="panel">
    <div class="logo">7&nbsp;<b>MOTION</b></div>
    <div class="hint">Pr\xEAt \xE0 recevoir ta vid\xE9o. Depuis ton t\xE9l\xE9phone&nbsp;7&nbsp;MOTION,
      appuie sur \xAB Caster sur un \xE9cran \xBB et scanne le QR \u2014 ou v\xE9rifie que le code
      ci-dessous correspond.</div>
    <div class="codebox">
      <div class="codelbl"><span class="dot"></span>Connect\xE9 \xB7 code de l'\xE9cran</div>
      <div class="code" id="code">${safeCode}</div>
    </div>
  </div>

  <div id="err"></div>

<script>
(function(){
  var CODE = ${JSON.stringify(safeCode)};
  var POLL_MS = 1500;
  var video = document.getElementById('video');
  var panel = document.getElementById('panel');
  var errEl = document.getElementById('err');
  var player = null;        // instance mpegts.js courante
  var lastSeq = -1;         // derni\xE8re commande appliqu\xE9e
  var curUrl = null;        // URL en cours de lecture

  function showPanel(on){ panel.classList.toggle('hidden', !on); }
  function showErr(msg){ if(!msg){ errEl.classList.remove('show'); return; }
    errEl.textContent = msg; errEl.classList.add('show'); }

  function teardown(){
    try { if (player){ player.destroy(); player = null; } } catch(e){}
    try { video.removeAttribute('src'); video.load(); } catch(e){}
    video.classList.remove('active');
    curUrl = null;
  }

  var triedNative = false;

  function activate(){
    showPanel(false);
    video.classList.add('active');
    video.muted = false;
    var p = video.play();
    if (p && p.catch) p.catch(function(){
      // Autoplay bloqu\xE9 : on tente en muet (la TV d\xE9bloque au 1er geste).
      video.muted = true; video.play().catch(function(){});
    });
  }

  // Strat\xE9gie 2 : d\xE9codeur NATIF de la TV. Beaucoup de Smart TV ont le
  // HEVC/H265 en MAT\xC9RIEL (contrairement \xE0 Chrome desktop) \u2192 ce repli les
  // r\xE9cup\xE8re GRATUITEMENT, sans serveur de transcodage.
  function tryNative(url){
    triedNative = true;
    try { if (player){ player.destroy(); player = null; } } catch(e){}
    try {
      video.src = url;
      video.onerror = function(){
        showErr("Codec non lisible sur cet \xE9cran (souvent HEVC/H265). "
          + "Utilise Chromecast ou DLNA pour cette cha\xEEne.  [MediaError natif]");
      };
      activate();
      curUrl = url;
    } catch(e){
      showErr("Lecture impossible sur cet \xE9cran. Utilise Chromecast ou DLNA.");
    }
  }

  function playStream(url){
    teardown();
    showErr('');
    triedNative = false;
    // Strat\xE9gie 1 : mpegts.js (transmux TS H.264 \u2192 marche partout, m\xEAme
    // Chrome). Sur erreur codec, on bascule sur le d\xE9codeur natif (st. 2).
    if (window.mpegts && mpegts.isSupported()){
      try {
        player = mpegts.createPlayer(
          { type:'mpegts', isLive:true, url:url },
          { liveBufferLatencyChasing:true, lazyLoad:false, enableWorker:true }
        );
        player.attachMediaElement(video);
        player.on(mpegts.Events.ERROR, function(type, detail){
          if (type === 'NetworkError'){
            // On r\xE9cup\xE8re le VRAI code HTTP du serveur IPTV (expos\xE9 par le
            // proxy) pour diagnostiquer : 403 = IP bloqu\xE9e, 5xx/limite =
            // trop de connexions, 404 = URL.
            fetch(url).then(function(r){
              var us = r.headers.get('X-Upstream-Status') || String(r.status);
              try { if (r.body) r.body.cancel(); } catch(e){}
              showErr("Le serveur IPTV refuse la connexion du relais \u2014 code " + us
                + ". Souvent : limite de connexions atteinte (ton t\xE9l\xE9phone joue "
                + "d\xE9j\xE0 la cha\xEEne) OU l'IP du serveur bloque le cloud.  [HTTP " + us + "]");
            }).catch(function(){
              showErr("Serveur IPTV / r\xE9seau injoignable depuis le relais.  [NetworkError]");
            });
          } else if (!triedNative){
            // MediaError / autre (souvent HEVC) \u2192 d\xE9codeur natif de la TV.
            tryNative(url);
          }
        });
        player.load();
        activate();
        curUrl = url;
        return;
      } catch(e){ /* on tombe sur le natif ci-dessous */ }
    }
    tryNative(url);
  }

  function apply(state){
    if (!state) return;
    var a = state.action;
    if (a === 'expired'){ teardown(); showPanel(true); showErr("Session expir\xE9e \u2014 relance le cast depuis le t\xE9l\xE9phone."); return; }
    var seq = state.seq || 0;

    if (a === 'play'){
      if (seq !== lastSeq || state.playUrl !== curUrl){
        lastSeq = seq;
        if (state.playUrl) playStream(state.playUrl);
      }
      return;
    }
    if (a === 'control'){
      lastSeq = seq;
      try { if (state.paused) video.pause(); else video.play().catch(function(){}); } catch(e){}
      return;
    }
    if (a === 'idle' || a === 'stop'){
      if (seq !== lastSeq){ lastSeq = seq; teardown(); showPanel(true); showErr(''); }
      return;
    }
  }

  var failures = 0;
  function poll(){
    fetch('/api/screen/' + CODE, { cache:'no-store' })
      .then(function(r){ return r.json(); })
      .then(function(s){ failures = 0; apply(s); })
      .catch(function(){ failures++; if (failures === 5) showErr("Connexion au serveur perdue \u2014 on r\xE9essaie\u2026"); })
      .then(function(){ setTimeout(poll, POLL_MS); });
  }
  poll();

  // Garde l'\xE9cran r\xE9veill\xE9 tant que possible (best-effort).
  try {
    if (navigator.wakeLock && navigator.wakeLock.request){
      var reacquire = function(){ navigator.wakeLock.request('screen').catch(function(){}); };
      reacquire();
      document.addEventListener('visibilitychange', function(){
        if (document.visibilityState === 'visible') reacquire();
      });
    }
  } catch(e){}
})();
<\/script>
</body>
</html>`;
}
__name(screenReceiverHtml, "screenReceiverHtml");

// landing.js
function landingHtml() {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>7 MOTION \u2014 Lecteur TV premium, fluide et sans coupure | Mobile &amp; Smart TV</title>
<meta name="description" content="7 MOTION : un lecteur premium, fluide et sans coupure, pour t\xE9l\xE9phone et TV. Activation en minutes, accompagnement humain, s\xE9r\xE9nit\xE9 totale." />
<!-- PWA : le site s'installe comme une application -->
<link rel="manifest" href="/manifest.webmanifest" />
<meta name="theme-color" content="#0c0c0e" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<meta name="apple-mobile-web-app-title" content="7 MOTION" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<!-- ===== SEO ===== -->
<link rel="canonical" href="https://app.7themotion.com/" />
<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1" />
<meta name="author" content="7 MOTION" />
<meta name="application-name" content="7 MOTION" />
<meta name="keywords" content="7 MOTION, lecteur TV premium, application TV, lecteur multim\xE9dia, streaming TV, smart TV, Android TV, Fire Stick, NVIDIA SHIELD, lecteur IPTV, IPTV player, reproductor IPTV, IPTV app, lettore IPTV, IPTV Player, m3u player, xtream, t\xE9l\xE9vision en ligne, regarder la t\xE9l\xE9, multi-\xE9cran, EPG, premium, sans coupure" />
<meta name="geo.region" content="EU" />
<meta name="geo.placename" content="Europe, Am\xE9rique du Nord" />
<!-- hreflang : Europe + Am\xE9rique -->
<link rel="alternate" hreflang="fr" href="https://app.7themotion.com/" />
<link rel="alternate" hreflang="en" href="https://app.7themotion.com/" />
<link rel="alternate" hreflang="es" href="https://app.7themotion.com/" />
<link rel="alternate" hreflang="de" href="https://app.7themotion.com/" />
<link rel="alternate" hreflang="it" href="https://app.7themotion.com/" />
<link rel="alternate" hreflang="pt" href="https://app.7themotion.com/" />
<link rel="alternate" hreflang="nl" href="https://app.7themotion.com/" />
<link rel="alternate" hreflang="x-default" href="https://app.7themotion.com/" />
<!-- Open Graph (aper\xE7u Facebook, WhatsApp, etc.) -->
<meta property="og:type" content="website" />
<meta property="og:site_name" content="7 MOTION" />
<meta property="og:title" content="7 MOTION \u2014 L'exp\xE9rience t\xE9l\xE9, sereine et premium" />
<meta property="og:description" content="Un lecteur premium, fluide et sans coupure, pour t\xE9l\xE9phone et TV. Activation en minutes, accompagnement humain." />
<meta property="og:url" content="https://app.7themotion.com/" />
<meta property="og:image" content="https://app.7themotion.com/og-image.png" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:locale" content="fr_FR" />
<meta property="og:locale:alternate" content="en_US" />
<meta property="og:locale:alternate" content="es_ES" />
<meta property="og:locale:alternate" content="de_DE" />
<meta property="og:locale:alternate" content="it_IT" />
<meta property="og:locale:alternate" content="pt_PT" />
<!-- Twitter / X -->
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="7 MOTION \u2014 L'exp\xE9rience t\xE9l\xE9, sereine et premium" />
<meta name="twitter:description" content="Un lecteur premium, fluide et sans coupure, pour t\xE9l\xE9phone et TV." />
<meta name="twitter:image" content="https://app.7themotion.com/og-image.png" />
<style>
  /* ===========================================================
     7 MOTION \u2014 Th\xE8me PREMIUM. Noir profond + Or. Retenue & confiance.
     =========================================================== */
  :root{
    --bg:#0c0c0e;            /* noir profond MAIS doux (repos des yeux) */
    --bg-soft:#111115;
    --panel:rgba(255,255,255,.035);
    --panel-2:rgba(255,255,255,.06);
    --line:rgba(255,255,255,.09);
    --line-gold:rgba(214,176,94,.35);
    --gold:#d8b766;          /* or \u2014 couleur d'action VIP */
    --gold-bright:#ecd08a;
    --red:#e0202e;           /* accent marque, employ\xE9 avec parcimonie */
    --text:#d9d6ce;          /* blanc cass\xE9 doux \u2014 repose les yeux */
    --muted:#8f8c85;         /* gris chaud doux */
    --radius:20px; --maxw:1140px;
    --serif:"Hoefler Text","Iowan Old Style",Garamond,"Palatino Linotype","Times New Roman",serif;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  }
  *{box-sizing:border-box;margin:0;padding:0}
  html{scroll-behavior:smooth}
  body{
    background:var(--bg); color:var(--text); font-family:var(--sans);
    line-height:1.6; -webkit-font-smoothing:antialiased; overflow-x:hidden;
    /* Lumi\xE8re douce, ambiance feutr\xE9e (showroom de luxe) */
    background-image:
      radial-gradient(120% 80% at 50% -10%, rgba(216,183,102,.06), transparent 55%),
      radial-gradient(90% 60% at 85% 8%, rgba(224,32,46,.03), transparent 60%);
    background-attachment:fixed;
  }
  a{color:inherit;text-decoration:none}
  .wrap{max-width:var(--maxw);margin:0 auto;padding:0 22px}
  section{padding:86px 0;position:relative}
  .eyebrow{display:inline-block;color:var(--gold);font-size:12.5px;font-weight:700;
    letter-spacing:3.5px;text-transform:uppercase;margin-bottom:18px}
  h1,h2{font-family:var(--serif);font-weight:600;letter-spacing:-.4px;line-height:1.08}
  h2{font-size:clamp(28px,4.4vw,42px)}
  h2 .g{color:var(--gold)}
  .lead{color:var(--muted);font-size:clamp(16px,2.1vw,19px);max-width:600px}
  .center{text-align:center;margin-inline:auto}

  /* ---- Boutons ---- */
  .btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;
    padding:16px 30px;border-radius:999px;font-weight:700;font-size:16px;
    cursor:pointer;border:none;transition:.25s ease;white-space:nowrap;font-family:var(--sans)}
  .btn:active{transform:scale(.98)}
  /* Or = action principale (sur noir, l'or \xAB appelle le clic \xBB) */
  .btn-gold{background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606;
    font-weight:800;box-shadow:0 10px 34px rgba(216,183,102,.28)}
  .btn-gold:hover{transform:translateY(-2px);box-shadow:0 16px 50px rgba(216,183,102,.42)}
  .btn-ghost{background:transparent;color:var(--text);border:1px solid var(--line)}
  .btn-ghost:hover{border-color:var(--gold);color:var(--gold-bright)}

  /* ---- Nav ---- */
  header.nav{position:sticky;top:0;z-index:50;background:rgba(5,5,6,.72);
    backdrop-filter:blur(16px);border-bottom:1px solid var(--line)}
  .nav-in{display:flex;align-items:center;justify-content:space-between;height:70px}
  .logo{font-weight:800;font-size:22px;letter-spacing:2px}
  .logo b{color:var(--red)}
  .nav-links{display:flex;gap:30px;font-size:14.5px;color:var(--muted)}
  .nav-links a:hover{color:var(--text)}
  @media(max-width:820px){.nav-links{display:none}}
  .btn-nav{padding:12px 22px;font-size:14.5px}

  /* ---- Hero ---- */
  .hero{padding:96px 0 70px;text-align:center}
  .hero h1{font-size:clamp(40px,7.2vw,72px);margin:6px 0 0}
  .hero h1 .accent{color:var(--gold)}
  .hero .lead{margin:22px auto 32px}
  .hero-cta{display:flex;gap:14px;justify-content:center;flex-wrap:wrap}
  .reassure{margin-top:26px;color:var(--muted);font-size:14px;display:flex;gap:10px 22px;
    justify-content:center;flex-wrap:wrap}
  .reassure span{display:inline-flex;align-items:center;gap:7px}
  .dot{width:6px;height:6px;border-radius:50%;background:var(--gold);display:inline-block}

  /* ---- Bande confiance ---- */
  .trust{border-top:1px solid var(--line);border-bottom:1px solid var(--line);
    background:rgba(255,255,255,.015)}
  .trust .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:26px}
  .trust .item{text-align:center}
  .trust .tk{width:46px;height:46px;border-radius:14px;margin:0 auto 12px;
    display:flex;align-items:center;justify-content:center;font-size:20px;
    background:rgba(216,183,102,.10);border:1px solid var(--line-gold);color:var(--gold-bright)}
  .trust h3{font-size:16px;font-weight:700;margin-bottom:3px}
  .trust p{color:var(--muted);font-size:13.5px}
  @media(max-width:760px){.trust .grid{grid-template-columns:repeat(2,1fr);gap:30px 20px}}

  /* ---- Cartes / grilles ---- */
  .grid{display:grid;gap:18px}
  .g3{grid-template-columns:repeat(3,1fr)}
  @media(max-width:820px){.g3{grid-template-columns:1fr}}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);
    padding:30px;transition:.25s;backdrop-filter:blur(6px)}
  .card:hover{border-color:var(--line-gold);transform:translateY(-3px)}
  .card .ico{font-size:24px;margin-bottom:14px;color:var(--gold-bright)}
  .card h3{font-size:19px;font-weight:700;margin-bottom:8px}
  .card p{color:var(--muted);font-size:15px}
  .num{display:inline-flex;align-items:center;justify-content:center;width:40px;height:40px;
    border-radius:50%;border:1px solid var(--line-gold);color:var(--gold);
    font-family:var(--serif);font-size:18px;margin-bottom:16px}

  /* ---- QR ---- */
  .qr-row{display:flex;gap:26px;flex-wrap:wrap;justify-content:center}
  .qr-box{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);
    padding:24px;text-align:center;width:240px}
  .qr-tile{width:172px;height:172px;background:#fff;border-radius:14px;margin:0 auto 16px;
    padding:10px;box-shadow:0 12px 40px rgba(0,0,0,.45)}
  .qr-tile svg{width:100%;height:100%;display:block}
  .qr-box h3{font-size:16px;font-weight:700}
  .qr-box .lnk{color:var(--gold);font-size:12.5px;word-break:break-all;margin-top:6px;display:block}

  /* ---- T\xE9moignages ---- */
  .quote{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);padding:28px}
  .quote .stars{color:var(--gold);letter-spacing:2px;font-size:14px;margin-bottom:12px}
  .quote p{font-size:15.5px;line-height:1.65}
  .quote .who{margin-top:16px;display:flex;align-items:center;gap:12px}
  .quote .av{width:40px;height:40px;border-radius:50%;background:linear-gradient(135deg,var(--gold),#9c7d34);
    color:#1c1606;display:flex;align-items:center;justify-content:center;font-weight:800}
  .quote .who b{font-size:14.5px}.quote .who span{color:var(--muted);font-size:12.5px;display:block}

  /* ---- Tarifs ---- */
  .price-row{display:grid;grid-template-columns:repeat(2,1fr);gap:20px;max-width:760px;margin:0 auto}
  @media(max-width:640px){.price-row{grid-template-columns:1fr}}
  .price{background:var(--panel);border:1px solid var(--line);border-radius:24px;
    padding:38px 30px;text-align:center;position:relative}
  .price.feature{border-color:var(--gold);
    background:linear-gradient(180deg,rgba(216,183,102,.10),var(--panel));
    box-shadow:0 24px 70px rgba(216,183,102,.14)}
  .ribbon{position:absolute;top:-14px;left:50%;transform:translateX(-50%);
    background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606;
    font-weight:800;font-size:11.5px;letter-spacing:1.5px;padding:6px 16px;border-radius:999px}
  .price .plan{font-size:15px;color:var(--muted);font-weight:600;letter-spacing:1px;text-transform:uppercase}
  .price .amt{font-family:var(--serif);font-size:52px;margin:14px 0 2px}
  .price .amt .cur{font-size:24px;color:var(--muted)}
  .price .per{color:var(--muted);font-size:14px;margin-bottom:8px}
  .price .note{color:var(--gold);font-size:13.5px;font-weight:700;margin-bottom:18px}
  .price ul{list-style:none;text-align:left;margin:18px 0 24px;font-size:14.5px;color:var(--muted)}
  .price li{padding:7px 0 7px 26px;position:relative}
  .price li::before{content:"\u2713";position:absolute;left:0;color:var(--gold);font-weight:800}

  /* ---- Carte MAC ---- */
  .mac-card{background:linear-gradient(180deg,var(--panel-2),var(--panel));
    border:1px solid var(--line);border-radius:24px;padding:42px;text-align:center;max-width:660px;margin:0 auto}
  .mac-input{display:flex;gap:12px;flex-wrap:wrap;justify-content:center;margin-top:24px}
  .mac-input input{flex:1;min-width:240px;background:rgba(0,0,0,.4);border:1px solid var(--line);
    color:#fff;padding:16px 18px;border-radius:14px;font-size:17px;letter-spacing:1px;
    text-align:center;font-family:ui-monospace,monospace}
  .mac-input input:focus{outline:none;border-color:var(--gold)}
  .hint{color:var(--muted);font-size:13px;margin-top:14px}

  /* ---- FAQ ---- */
  details{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:20px 24px;margin-bottom:12px}
  details[open]{border-color:var(--line-gold)}
  summary{cursor:pointer;font-weight:600;font-size:16.5px;list-style:none}
  summary::-webkit-details-marker{display:none}
  summary::after{content:"+";float:right;color:var(--gold);font-weight:800}
  details[open] summary::after{content:"\u2013"}
  details p{color:var(--muted);margin-top:12px;font-size:14.5px}

  /* ---- Support VIP discret ---- */
  .support-vip{padding:38px 0;text-align:center}
  .vip-pill{display:inline-flex;align-items:center;gap:10px;padding:11px 20px;border-radius:999px;
    background:var(--panel);border:1px solid var(--line-gold);color:var(--text);font-size:14px}
  .live{width:9px;height:9px;border-radius:50%;background:#37d67a;animation:pulse 2.2s infinite}
  @keyframes pulse{0%{box-shadow:0 0 0 0 rgba(55,214,122,.55)}70%{box-shadow:0 0 0 11px rgba(55,214,122,0)}100%{box-shadow:0 0 0 0 rgba(55,214,122,0)}}
  .support-vip .slink{color:var(--gold);font-weight:700;font-size:14px;margin-top:14px;display:inline-block}
  .support-vip .slink:hover{color:var(--gold-bright)}
  /* ---- Footer ---- */
  footer{border-top:1px solid var(--line);padding:54px 0 40px;color:var(--muted);font-size:13.5px;
    background:var(--bg-soft)}
  footer a{color:var(--muted)}footer a:hover{color:var(--text)}
  .disclaimer{background:rgba(0,0,0,.35);border:1px solid var(--line);border-radius:14px;
    padding:18px 22px;font-size:12.5px;line-height:1.65;margin-bottom:28px}
  .foot-links{display:flex;gap:24px;flex-wrap:wrap;margin-top:14px}
  .hairline{height:1px;background:linear-gradient(90deg,transparent,var(--line-gold),transparent);
    max-width:var(--maxw);margin:0 auto}
</style>
</head>
<body>

<!-- \u2699\uFE0F \xC0 PERSONNALISER : ce bloc CONFIG uniquement -->
<script>
  const CONFIG = {
    whatsapp: "447307410512",                    // sans "+" ni espaces
    appUrl:  "https://app.7themotion.com/install",
    tvUrl:   "https://app.7themotion.com/tv",
    privacyUrl: "https://app.7themotion.com/privacy",
    prices: {
      year: { amount: "5,90", per: "/ an" },
      life: { amount: "9,90", per: "\xE0 vie, une seule fois" }
    },
    currency: "\u20AC"
  };
<\/script>

<!-- NAV -->
<header class="nav"><div class="wrap nav-in">
  <div class="logo">7&nbsp;<b>MOTION</b></div>
  <nav class="nav-links">
    <a href="#how">Comment \xE7a marche</a>
    <a href="#download">T\xE9l\xE9charger</a>
    <a href="#pricing">Tarifs</a>
    <a href="/mon-espace">Mes playlists</a>
    <a href="#trust">Confiance</a>
  </nav>
  <a class="btn btn-gold btn-nav" href="https://app.7themotion.com/install">T\xE9l\xE9charger</a>
</div></header>

<!-- HERO -->
<section class="hero"><div class="wrap">
  <span class="eyebrow">Exp\xE9rience premium</span>
  <h1>La t\xE9l\xE9vision,<br><span class="accent">enfin sereine.</span></h1>
  <p class="lead">Installez-vous. Une image nette, fluide, sans coupure \u2014 sur votre t\xE9l\xE9phone
    comme sur votre TV. On s'occupe de tout, vous n'avez plus qu'\xE0 regarder.</p>
  <div class="hero-cta">
    <a class="btn btn-gold" id="dlPhone" href="https://app.7themotion.com/install">T\xE9l\xE9charger l'application</a>
    <a class="btn btn-ghost" href="/mon-espace">G\xE9rer mes playlists</a>
  </div>
  <div class="reassure">
    <span><i class="dot"></i> Activation en quelques minutes</span>
    <span><i class="dot"></i> Accompagnement humain</span>
    <span><i class="dot"></i> Sans engagement</span>
  </div>
</div></section>

<!-- BANDE CONFIANCE -->
<section class="trust" style="padding:40px 0"><div class="wrap">
  <div class="grid">
    <div class="item"><div class="tk">\u26A1</div><h3>Activation rapide</h3><p>Pr\xEAt en quelques minutes, sans technique.</p></div>
    <div class="item"><div class="tk">\u{1F91D}</div><h3>Un humain vous r\xE9pond</h3><p>Accompagnement r\xE9el, \xE0 chaque \xE9tape.</p></div>
    <div class="item"><div class="tk">\u{1F512}</div><h3>Discret &amp; s\xE9curis\xE9</h3><p>Vos informations restent priv\xE9es.</p></div>
    <div class="item"><div class="tk">\u267E\uFE0F</div><h3>Sur tous vos \xE9crans</h3><p>T\xE9l\xE9phone, TV, box \u2014 partout, ensemble.</p></div>
  </div>
</div></section>

<!-- COMMENT \xC7A MARCHE -->
<section id="how"><div class="wrap">
  <div class="center" style="margin-bottom:48px">
    <span class="eyebrow">Simple, du d\xE9but \xE0 la fin</span>
    <h2>Trois \xE9tapes, <span class="g">tout en douceur</span></h2>
  </div>
  <div class="grid g3">
    <div class="card"><div class="num">1</div><h3>Installez l'application</h3><p>Sur votre t\xE9l\xE9phone ou votre TV. Aucun compte, aucune complication.</p></div>
    <div class="card"><div class="num">2</div><h3>Partagez votre adresse</h3><p>L'app affiche une adresse unique. Envoyez-la-nous, on s'occupe du reste.</p></div>
    <div class="card"><div class="num">3</div><h3>D\xE9tendez-vous</h3><p>Tout s'active automatiquement. Vous n'avez plus qu'\xE0 profiter, sereinement.</p></div>
  </div>
</div></section>

<!-- T\xC9L\xC9CHARGEMENT -->
<section id="download" style="background:var(--bg-soft)"><div class="wrap">
  <div class="center" style="margin-bottom:44px">
    <span class="eyebrow">\xC0 port\xE9e de scan</span>
    <h2>Installez en <span class="g">un instant</span></h2>
  </div>
  <div class="qr-row">
    <div class="qr-box"><div class="qr-tile"><svg width="165" height="165" class="segno"><g transform="scale(5)"><path fill="#fff" d="M0 0h33v33h-33z"/><path class="qrline" stroke="#000" d="M2 2.5h7m2 0h1m1 0h5m2 0h1m1 0h1m1 0h7m-29 1h1m5 0h1m1 0h2m1 0h1m3 0h1m1 0h1m4 0h1m5 0h1m-29 1h1m1 0h3m1 0h1m1 0h3m3 0h1m1 0h1m1 0h3m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m1 0h3m3 0h4m1 0h2m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m5 0h4m2 0h3m1 0h1m1 0h3m1 0h1m-29 1h1m5 0h1m2 0h2m2 0h2m2 0h2m1 0h1m1 0h1m5 0h1m-29 1h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7m-21 1h1m1 0h4m5 0h2m-21 1h1m5 0h1m1 0h1m1 0h2m2 0h2m1 0h1m1 0h1m1 0h2m2 0h3m-28 1h3m1 0h2m3 0h1m4 0h1m1 0h4m1 0h1m2 0h1m1 0h2m-28 1h2m1 0h1m1 0h4m2 0h1m3 0h1m1 0h1m2 0h1m-21 1h1m1 0h1m6 0h4m1 0h1m1 0h1m4 0h3m1 0h1m-26 1h2m3 0h4m4 0h2m1 0h1m3 0h1m1 0h2m4 0h1m-28 1h2m1 0h2m1 0h1m4 0h11m1 0h1m2 0h2m-29 1h1m2 0h2m1 0h5m1 0h4m8 0h3m-26 1h3m1 0h1m2 0h1m4 0h2m7 0h1m1 0h1m1 0h1m1 0h1m-29 1h2m3 0h2m1 0h1m2 0h2m1 0h1m2 0h2m1 0h1m2 0h1m1 0h2m-27 1h1m1 0h1m5 0h2m5 0h6m1 0h3m1 0h3m-29 1h2m2 0h3m2 0h1m2 0h4m3 0h1m1 0h1m1 0h3m2 0h1m-29 1h1m1 0h1m1 0h1m3 0h2m4 0h1m4 0h2m3 0h1m-25 1h1m1 0h2m2 0h2m2 0h3m2 0h1m1 0h1m1 0h6m1 0h3m-21 1h1m2 0h1m1 0h1m1 0h1m1 0h2m1 0h1m3 0h2m-26 1h7m2 0h2m1 0h4m2 0h3m1 0h1m1 0h3m-27 1h1m5 0h1m3 0h1m1 0h2m2 0h1m2 0h2m3 0h1m3 0h1m-29 1h1m1 0h3m1 0h1m3 0h1m2 0h1m1 0h1m3 0h7m1 0h2m-29 1h1m1 0h3m1 0h1m3 0h1m2 0h1m1 0h5m1 0h1m1 0h1m1 0h2m1 0h1m-29 1h1m1 0h3m1 0h1m3 0h4m1 0h3m1 0h9m-28 1h1m5 0h1m2 0h1m2 0h1m2 0h2m1 0h1m2 0h6m1 0h1m-29 1h7m1 0h2m1 0h2m2 0h3m1 0h1m4 0h1m1 0h1"/></g></svg></div><h3>T\xE9l\xE9phone</h3><a class="lnk" id="lnkPhone" href="https://app.7themotion.com/install">app.7themotion.com/install</a></div>
    <div class="qr-box"><div class="qr-tile"><svg width="165" height="165" class="segno"><g transform="scale(5)"><path fill="#fff" d="M0 0h33v33h-33z"/><path class="qrline" stroke="#000" d="M2 2.5h7m3 0h1m5 0h1m2 0h2m1 0h7m-29 1h1m5 0h1m1 0h5m1 0h1m2 0h1m4 0h1m5 0h1m-29 1h1m1 0h3m1 0h1m1 0h2m1 0h2m1 0h3m3 0h1m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m3 0h3m4 0h4m1 0h1m1 0h3m1 0h1m-29 1h1m1 0h3m1 0h1m3 0h2m2 0h1m2 0h1m1 0h1m2 0h1m1 0h3m1 0h1m-29 1h1m5 0h1m2 0h1m4 0h1m3 0h2m2 0h1m5 0h1m-29 1h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7m-18 1h1m2 0h2m1 0h1m2 0h1m-20 1h3m1 0h2m4 0h3m1 0h5m6 0h2m-28 1h1m4 0h1m2 0h1m3 0h1m1 0h2m1 0h1m1 0h1m1 0h2m1 0h3m1 0h1m-29 1h2m1 0h6m1 0h2m4 0h1m1 0h1m3 0h4m1 0h1m-26 1h1m2 0h1m3 0h1m2 0h3m4 0h2m2 0h2m3 0h1m-29 1h3m2 0h2m2 0h1m1 0h1m5 0h5m1 0h1m1 0h4m-28 1h2m2 0h1m4 0h1m1 0h1m2 0h1m1 0h3m2 0h2m1 0h2m1 0h1m-29 1h1m2 0h1m1 0h3m2 0h1m1 0h1m1 0h8m1 0h3m1 0h2m-24 1h1m1 0h1m3 0h2m1 0h1m3 0h1m2 0h2m1 0h2m-25 1h6m2 0h1m1 0h2m3 0h2m2 0h2m1 0h3m1 0h2m-25 1h1m2 0h1m2 0h1m1 0h2m2 0h1m3 0h1m2 0h1m-24 1h1m1 0h1m3 0h1m1 0h1m1 0h1m2 0h5m2 0h1m1 0h2m-22 1h4m1 0h1m1 0h1m1 0h4m2 0h3m1 0h2m1 0h4m-27 1h2m1 0h1m1 0h1m2 0h2m3 0h1m1 0h3m1 0h8m-20 1h1m3 0h1m3 0h1m3 0h1m3 0h2m1 0h2m-29 1h7m6 0h1m3 0h1m1 0h2m1 0h1m1 0h1m1 0h2m-28 1h1m5 0h1m1 0h3m1 0h1m3 0h1m3 0h1m3 0h1m2 0h2m-29 1h1m1 0h3m1 0h1m3 0h1m1 0h3m3 0h1m1 0h7m-27 1h1m1 0h3m1 0h1m1 0h1m1 0h2m1 0h1m2 0h2m1 0h1m4 0h1m2 0h1m-28 1h1m1 0h3m1 0h1m1 0h1m6 0h2m1 0h1m1 0h1m2 0h1m4 0h1m-29 1h1m5 0h1m1 0h2m3 0h2m1 0h1m1 0h1m1 0h2m2 0h2m1 0h1m-28 1h7m3 0h2m1 0h3m2 0h6m3 0h1"/></g></svg></div><h3>TV &amp; Box</h3><a class="lnk" id="lnkTv" href="https://app.7themotion.com/tv">app.7themotion.com/tv</a></div>
  </div>
  <p class="center lead" style="margin:26px auto 0;font-size:14px">Scannez, installez, regardez. Lien direct, sans publicit\xE9 ni inscription.</p>
</div></section>

<!-- POURQUOI CONFIANCE -->
<section id="trust"><div class="wrap">
  <div class="center" style="margin-bottom:48px">
    <span class="eyebrow">Une relation de confiance</span>
    <h2>Pourquoi des milliers de foyers <span class="g">nous restent fid\xE8les</span></h2>
    <p class="lead center" style="margin-top:14px">Pas de promesses tape-\xE0-l'\u0153il. Une exp\xE9rience qui tient,
      un accompagnement pr\xE9sent, et la tranquillit\xE9 d'esprit avant tout.</p>
  </div>
  <div class="grid g3">
    <div class="card"><div class="ico">\u2726</div><h3>Une image qui ne l\xE2che pas</h3><p>D\xE9marrage rapide, anti-coupure, reconnexion automatique. M\xEAme quand le r\xE9seau faiblit, l'image tient.</p></div>
    <div class="card"><div class="ico">\u2726</div><h3>Toujours quelqu'un au bout</h3><p>Un vrai conseiller vous r\xE9pond et reste avec vous jusqu'\xE0 ce que tout fonctionne. Pas de robot.</p></div>
    <div class="card"><div class="ico">\u2726</div><h3>Aucune mauvaise surprise</h3><p>Des tarifs clairs, rien de cach\xE9. Vous gardez le contr\xF4le, du premier jour au dernier.</p></div>
  </div>

  <div class="grid g3" style="margin-top:22px">
    <div class="quote"><div class="stars">\u2605\u2605\u2605\u2605\u2605</div><p>\xAB Install\xE9 en cinq minutes, et depuis \xE7a tourne sans accroc. On sent que c'est s\xE9rieux. \xBB</p>
      <div class="who"><div class="av">K</div><div><b>Karim</b><span>Lyon, France</span></div></div></div>
    <div class="quote"><div class="stars">\u2605\u2605\u2605\u2605\u2605</div><p>\xAB Ce que j'ai aim\xE9 : on m'a accompagn\xE9 jusqu'au bout. Aucune question laiss\xE9e sans r\xE9ponse. \xBB</p>
      <div class="who"><div class="av">S</div><div><b>Sofia</b><span>Bruxelles, Belgique</span></div></div></div>
    <div class="quote"><div class="stars">\u2605\u2605\u2605\u2605\u2605</div><p>\xAB Fluide sur la TV comme sur le t\xE9l\xE9phone. Discret, propre, premium. Exactement ce que je cherchais. \xBB</p>
      <div class="who"><div class="av">A</div><div><b>Adam</b><span>Montr\xE9al, Canada</span></div></div></div>
  </div>
</div></section>

<!-- TARIFS -->
<section id="pricing" style="background:var(--bg-soft)"><div class="wrap">
  <div class="center" style="margin-bottom:50px">
    <span class="eyebrow">Tarifs justes, sans pi\xE8ge</span>
    <h2>Deux choix, <span class="g">c'est tout</span></h2>
    <p class="lead center" style="margin-top:14px">Pas de catalogue interminable. Le juste prix, en toute transparence.</p>
  </div>
  <div class="price-row">
    <div class="price">
      <div class="plan">1 an</div>
      <div class="amt" id="pYear">\u2014</div>
      <div class="per">pour d\xE9couvrir en toute tranquillit\xE9</div>
      <ul><li>Activation compl\xE8te</li><li>Accompagnement humain</li><li>Mises \xE0 jour incluses</li><li>Sans engagement</li></ul>
      <a class="btn btn-ghost" data-plan="1 an" href="https://wa.me/447307410512" style="width:100%">Choisir</a>
    </div>
    <div class="price feature">
      <div class="ribbon">\u2605 LE PLUS SEREIN</div>
      <div class="plan">\xC0 vie</div>
      <div class="amt" id="pLife">\u2014</div>
      <div class="note">Une seule fois. Pour toujours.</div>
      <ul><li>Tout, sans limite de dur\xE9e</li><li>Accompagnement prioritaire</li><li>Mises \xE0 jour \xE0 vie</li><li>Le meilleur choix, l'esprit l\xE9ger</li></ul>
      <a class="btn btn-gold" data-plan="\xE0 vie" href="https://wa.me/447307410512" style="width:100%">Choisir \xE0 vie</a>
    </div>
  </div>
  <p class="center hint" style="margin-top:22px">Le r\xE8glement se fait avec un conseiller, simplement, sur WhatsApp. Humain, rapide, rassurant.</p>
</div></section>

<!-- MON ESPACE / G\xC9RER MA PLAYLIST -->
<section id="activate"><div class="wrap">
  <div class="mac-card">
    <span class="eyebrow">D\xE9j\xE0 l'application&nbsp;?</span>
    <h2 style="font-size:clamp(24px,3.6vw,32px)">G\xE9rez vos playlists, vous-m\xEAme</h2>
    <p class="lead center" style="margin:12px auto 0">Entrez l'adresse affich\xE9e dans l'app. Vous ouvrez votre espace et vous ajoutez autant de playlists que vous voulez \u2014 M3U ou Xtream \u2014 que vous pouvez changer ou retirer quand bon vous semble.</p>
    <div class="mac-input">
      <input id="macInput" type="text" placeholder="MK : XX : XX : XX : XX : XX" maxlength="23" autocomplete="off" autocapitalize="characters" spellcheck="false" />
      <a class="btn btn-gold" id="macSend" href="/mon-espace">Ouvrir mon espace</a>
    </div>
    <p class="hint">Vous trouvez cette adresse sur l'\xE9cran d'accueil de l'app, ou dans \xAB \xC0 propos \xBB. Un conseiller reste disponible si besoin.</p>
  </div>
</div></section>

<!-- FAQ -->
<section style="background:var(--bg-soft)"><div class="wrap" style="max-width:780px">
  <div class="center" style="margin-bottom:40px">
    <span class="eyebrow">On vous r\xE9pond franchement</span>
    <h2>Questions <span class="g">fr\xE9quentes</span></h2>
  </div>
  <details><summary>Est-ce compliqu\xE9 \xE0 installer&nbsp;?</summary><p>Non. Vous installez l'app, vous nous envoyez votre adresse, et tout s'active. La plupart de nos clients sont pr\xEAts en quelques minutes \u2014 et si besoin, un conseiller reste avec vous.</p></details>
  <details><summary>Sur quels appareils \xE7a fonctionne&nbsp;?</summary><p>T\xE9l\xE9phones et tablettes Android, Android TV, Google TV, Amazon Fire Stick, NVIDIA SHIELD et la plupart des box Android. La version iPhone arrive.</p></details>
  <details><summary>Et si j'ai un souci&nbsp;?</summary><p>Un vrai conseiller vous r\xE9pond sur WhatsApp et reste avec vous jusqu'\xE0 ce que tout fonctionne. Vous n'\xEAtes jamais seul.</p></details>
  <details><summary>Comment se passe le paiement&nbsp;?</summary><p>Simplement, avec un conseiller, sur WhatsApp. Vous choisissez votre formule, on active votre appareil, c'est r\xE9gl\xE9 en quelques minutes \u2014 sereinement.</p></details>
  <details><summary>L'image peut-elle couper&nbsp;?</summary><p>L'application est con\xE7ue pour la stabilit\xE9 : d\xE9marrage rapide, anti-coupure et reconnexion automatique. Une bonne connexion (ou Ethernet sur la TV) garantit le meilleur confort.</p></details>
</div></section>

<!-- CTA FINAL -->
<section class="center"><div class="wrap">
  <span class="eyebrow">Pr\xEAt quand vous l'\xEAtes</span>
  <h2>Offrez-vous la <span class="g">tranquillit\xE9</span></h2>
  <p class="lead center" style="margin:14px auto 30px">Installez l'application, dites-nous bonjour, et laissez-vous porter.</p>
  <div class="hero-cta">
    <a class="btn btn-gold" id="dlPhone2" href="https://app.7themotion.com/install">T\xE9l\xE9charger</a>
    <a class="btn btn-ghost" id="waBtn2" href="https://wa.me/447307410512">Parler \xE0 un conseiller</a>
  </div>
</div></section>

<!-- Support VIP : discret, tout en bas -->
<section class="support-vip"><div class="wrap">
  <div class="vip-pill"><span class="live"></span> Un conseiller VIP est en ligne</div>
  <div><a class="slink" href="https://wa.me/447307410512">Discuter en priv\xE9 \u2192</a></div>
</div></section>

<div class="hairline"></div>

<!-- FOOTER -->
<footer><div class="wrap">
  <div class="disclaimer"><b>Mention l\xE9gale \u2014</b> 7 MOTION est une application de lecture multim\xE9dia.
    Nous ne vendons, n'h\xE9bergeons et ne fournissons aucune cha\xEEne ni aucun contenu : l'utilisateur
    apporte sa propre source et reste responsable de sa conformit\xE9 dans son pays.</div>
  <div class="logo">7&nbsp;<b>MOTION</b></div>
  <p style="margin-top:8px">L'exp\xE9rience t\xE9l\xE9, sereine et premium.</p>
  <div class="foot-links">
    <a href="#how">Comment \xE7a marche</a>
    <a href="#pricing">Tarifs</a>
    <a href="#trust">Confiance</a>
    <a id="footPrivacy" href="#">Confidentialit\xE9</a>
    <a id="footWa" href="https://wa.me/447307410512">Conseiller VIP</a>
  </div>
  <p style="margin-top:18px;opacity:.6">\xA9 <span id="yr"></span> 7 MOTION. Tous droits r\xE9serv\xE9s.</p>
</div></footer>

<script>
(function(){
  var C = window.CONFIG;
  var wa = function(msg){ return "https://wa.me/" + C.whatsapp + (msg ? "?text=" + encodeURIComponent(msg) : ""); };
  function set(id, attr, val){ var e=document.getElementById(id); if(e) e[attr]=val; }

  ["dlPhone","dlPhone2"].forEach(function(id){ set(id,"href",C.appUrl); });
  set("lnkPhone","href",C.appUrl); set("lnkPhone","textContent",C.appUrl.replace("https://",""));
  set("lnkTv","href",C.tvUrl);     set("lnkTv","textContent",C.tvUrl.replace("https://",""));
  set("footPrivacy","href",C.privacyUrl);

  var waGeneral = wa("Bonjour \u{1F44B} Je souhaite des renseignements sur 7 MOTION.");
  ["waBtn2","footWa"].forEach(function(id){ set(id,"href",waGeneral); });

  function price(id,p){ var e=document.getElementById(id);
    if(e&&p) e.innerHTML = '<span class="cur"></span>' + p.amount + ' ' + C.currency + ' <span class="cur" style="font-size:18px;display:block;margin-top:2px;color:var(--muted)">' + p.per + '</span>'; }
  price("pYear",C.prices.year); price("pLife",C.prices.life);

  document.querySelectorAll("[data-plan]").forEach(function(b){
    b.href = wa("Bonjour \u{1F44B} Je souhaite la formule " + b.getAttribute("data-plan") + " pour 7 MOTION.");
  });

  // \xAB Ouvrir mon espace \xBB : vrai lien vers /mon-espace, cliquable m\xEAme sans JS.
  // Le JS ne fait qu'ENRICHIR le lien avec la MAC saisie (pr\xE9-remplissage).
  var send = document.getElementById("macSend");
  var macIn = document.getElementById("macInput");
  function updEspace(){
    if(!send) return;
    var mac = (macIn && macIn.value ? macIn.value : "").toUpperCase().replace(/\\s+/g,"").replace(/-/g,":");
    send.href = mac ? "/mon-espace#mac=" + encodeURIComponent(mac) : "/mon-espace";
  }
  if(macIn){ macIn.addEventListener("input", updEspace); updEspace(); }

  set("yr","textContent", String(new Date().getFullYear()));
})();
<\/script>

<!-- PWA : installer le site comme une application (discret, en bas) -->
<div id="pwaBar" style="display:none;position:fixed;left:50%;transform:translateX(-50%);bottom:18px;z-index:90">
  <button class="btn btn-gold" id="pwaBtn" style="box-shadow:0 14px 44px rgba(0,0,0,.55)">Installer l'application</button>
</div>
<script>
(function(){
  if ('serviceWorker' in navigator) { navigator.serviceWorker.register('/sw.js').catch(function(){}); }
  var bar = document.getElementById('pwaBar'), btn = document.getElementById('pwaBtn');
  var standalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  if (standalone) return; // d\xE9j\xE0 lanc\xE9 comme application
  var deferred = null;
  window.addEventListener('beforeinstallprompt', function(e){ e.preventDefault(); deferred = e; bar.style.display = 'block'; });
  window.addEventListener('appinstalled', function(){ bar.style.display = 'none'; });
  var isIOS = /iphone|ipad|ipod/i.test(window.navigator.userAgent);
  if (isIOS) {
    bar.style.display = 'block';
    btn.textContent = "Ajouter \xE0 l'\xE9cran d'accueil";
    btn.addEventListener('click', function(){
      alert("Pour installer 7 MOTION :\\n\\n1. Appuyez sur le bouton Partager.\\n2. Choisissez \xAB Sur l'\xE9cran d'accueil \xBB.");
    });
  } else {
    btn.addEventListener('click', function(){
      if (deferred) { deferred.prompt(); deferred.userChoice.then(function(){ deferred = null; bar.style.display = 'none'; }); }
    });
  }
})();
<\/script>
<script type="application/ld+json">{"@context": "https://schema.org", "@graph": [{"@type": "Organization", "@id": "https://app.7themotion.com/#org", "name": "7 MOTION", "url": "https://app.7themotion.com/", "logo": "https://app.7themotion.com/icon-512.png", "description": "Lecteur multim\xE9dia premium pour t\xE9l\xE9phone et TV.", "areaServed": ["Europe", "North America"]}, {"@type": "SoftwareApplication", "name": "7 MOTION", "operatingSystem": "Android, Android TV, Fire OS", "applicationCategory": "MultimediaApplication", "url": "https://app.7themotion.com/", "image": "https://app.7themotion.com/icon-512.png", "description": "Lecteur TV premium, fluide et sans coupure, pour t\xE9l\xE9phone et Smart TV.", "publisher": {"@id": "https://app.7themotion.com/#org"}, "offers": [{"@type": "Offer", "name": "1 an", "price": "5.90", "priceCurrency": "EUR"}, {"@type": "Offer", "name": "\xC0 vie", "price": "9.90", "priceCurrency": "EUR"}]}, {"@type": "FAQPage", "mainEntity": [{"@type": "Question", "name": "Est-ce compliqu\xE9 \xE0 installer ?", "acceptedAnswer": {"@type": "Answer", "text": "Non. Vous installez l'app, vous nous envoyez votre adresse, et tout s'active en quelques minutes."}}, {"@type": "Question", "name": "Sur quels appareils \xE7a fonctionne ?", "acceptedAnswer": {"@type": "Answer", "text": "T\xE9l\xE9phones et tablettes Android, Android TV, Google TV, Amazon Fire Stick, NVIDIA SHIELD et la plupart des box Android. La version iPhone arrive."}}, {"@type": "Question", "name": "Et si j'ai un souci ?", "acceptedAnswer": {"@type": "Answer", "text": "Un vrai conseiller vous r\xE9pond et reste avec vous jusqu'\xE0 ce que tout fonctionne."}}, {"@type": "Question", "name": "Comment se passe le paiement ?", "acceptedAnswer": {"@type": "Answer", "text": "Simplement, avec un conseiller, sur WhatsApp. Vous choisissez votre formule, on active votre appareil."}}, {"@type": "Question", "name": "L'image peut-elle couper ?", "acceptedAnswer": {"@type": "Answer", "text": "L'application est con\xE7ue pour la stabilit\xE9 : d\xE9marrage rapide, anti-coupure et reconnexion automatique."}}]}]}<\/script>
</body>
</html>
`;
}
__name(landingHtml, "landingHtml");

// portal.js
function portalHtml() {
  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Mon espace \u2014 G\xE9rer mes playlists | 7 MOTION</title>
<meta name="robots" content="noindex, nofollow" />
<meta name="theme-color" content="#0c0c0e" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<link rel="manifest" href="/manifest.webmanifest" />
<style>
  :root{
    --bg:#0c0c0e; --bg-soft:#111115;
    --panel:rgba(255,255,255,.035); --panel-2:rgba(255,255,255,.06);
    --line:rgba(255,255,255,.09); --line-gold:rgba(214,176,94,.35);
    --gold:#d8b766; --gold-bright:#ecd08a; --red:#e0202e;
    --green:#3ecf8e; --text:#d9d6ce; --muted:#8f8c85;
    --radius:20px;
    --serif:"Hoefler Text","Iowan Old Style",Garamond,"Palatino Linotype","Times New Roman",serif;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  }
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--bg);color:var(--text);font-family:var(--sans);line-height:1.6;
    -webkit-font-smoothing:antialiased;min-height:100vh;
    background-image:radial-gradient(120% 80% at 50% -10%,rgba(216,183,102,.06),transparent 55%),
      radial-gradient(90% 60% at 85% 8%,rgba(224,32,46,.03),transparent 60%);
    background-attachment:fixed}
  a{color:inherit;text-decoration:none}
  .wrap{max-width:720px;margin:0 auto;padding:0 20px}
  header.nav{position:sticky;top:0;z-index:50;background:rgba(5,5,6,.72);
    backdrop-filter:blur(16px);border-bottom:1px solid var(--line)}
  .nav-in{display:flex;align-items:center;justify-content:space-between;height:66px;
    max-width:720px;margin:0 auto;padding:0 20px}
  .logo{font-weight:800;font-size:20px;letter-spacing:2px}
  .logo b{color:var(--red)}
  .nav-back{color:var(--muted);font-size:14px}
  .nav-back:hover{color:var(--text)}
  main{padding:40px 0 90px}
  .eyebrow{display:inline-block;color:var(--gold);font-size:12px;font-weight:700;
    letter-spacing:3px;text-transform:uppercase;margin-bottom:14px}
  h1{font-family:var(--serif);font-weight:600;font-size:clamp(28px,6vw,40px);
    line-height:1.1;letter-spacing:-.4px}
  h2{font-family:var(--serif);font-weight:600;font-size:22px;letter-spacing:-.3px}
  .lead{color:var(--muted);font-size:16px;margin-top:12px}
  .card{background:linear-gradient(180deg,var(--panel-2),var(--panel));
    border:1px solid var(--line);border-radius:var(--radius);padding:24px;margin-top:20px}
  .card.gold{border-color:var(--line-gold)}
  .btn{display:inline-flex;align-items:center;justify-content:center;gap:9px;
    padding:15px 26px;border-radius:999px;font-weight:800;font-size:15.5px;
    cursor:pointer;border:none;transition:.22s ease;font-family:var(--sans);width:100%}
  .btn:active{transform:scale(.98)}
  .btn-gold{background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606;
    box-shadow:0 10px 30px rgba(216,183,102,.26)}
  .btn-gold:hover{transform:translateY(-1px)}
  .btn-ghost{background:transparent;color:var(--text);border:1px solid var(--line)}
  .btn-ghost:hover{border-color:var(--gold);color:var(--gold-bright)}
  .btn-danger{background:transparent;color:#e88;border:1px solid rgba(224,32,46,.4)}
  .btn-danger:hover{background:rgba(224,32,46,.1)}
  .btn-sm{width:auto;padding:9px 16px;font-size:13.5px}
  .btn-row{display:flex;gap:12px;flex-wrap:wrap;margin-top:8px}
  .btn-row .btn{width:auto;flex:1;min-width:130px;padding:13px 20px;font-size:14.5px}
  label{display:block;color:var(--muted);font-size:13px;margin:16px 0 7px;font-weight:600}
  input{width:100%;background:rgba(0,0,0,.4);border:1px solid var(--line);color:var(--text);
    border-radius:13px;padding:15px 17px;font-size:16px;font-family:var(--sans);letter-spacing:.3px}
  input:focus{outline:none;border-color:var(--gold)}
  .hint{color:var(--muted);font-size:13px;margin-top:12px}
  .row{display:flex;justify-content:space-between;align-items:center;gap:14px;
    padding:13px 0;border-bottom:1px solid var(--line)}
  .row:last-child{border-bottom:none}
  .row .k{color:var(--muted);font-size:13.5px}
  .row .v{font-weight:700;font-size:14.5px;text-align:right;word-break:break-word}
  .badge{display:inline-flex;align-items:center;gap:6px;font-size:11.5px;font-weight:800;
    letter-spacing:.5px;padding:5px 11px;border-radius:999px;text-transform:uppercase;white-space:nowrap}
  .badge.ok{background:rgba(62,207,142,.14);color:var(--green);border:1px solid rgba(62,207,142,.3)}
  .badge.lock{background:rgba(216,183,102,.14);color:var(--gold-bright);border:1px solid var(--line-gold)}
  .badge.wait{background:rgba(255,255,255,.06);color:var(--muted);border:1px solid var(--line)}
  /* Liste des playlists */
  .pl{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;
    background:rgba(0,0,0,.22);border:1px solid var(--line);border-radius:15px;
    padding:16px 17px;margin-top:12px}
  .pl.locked{border-color:var(--line-gold)}
  .pl-main{min-width:0;flex:1}
  .pl-name{font-weight:800;font-size:16px;display:flex;align-items:center;gap:9px;flex-wrap:wrap}
  .pl-url{color:var(--muted);font-size:13px;margin-top:5px;word-break:break-all}
  .pl-act{display:flex;flex-direction:column;gap:8px;flex-shrink:0}
  .seg{display:flex;gap:8px;background:rgba(0,0,0,.3);border:1px solid var(--line);
    border-radius:13px;padding:5px;margin-top:6px}
  .seg button{flex:1;background:transparent;border:none;color:var(--muted);font-weight:700;
    font-size:14px;padding:11px;border-radius:9px;cursor:pointer;font-family:var(--sans)}
  .seg button.on{background:linear-gradient(135deg,var(--gold-bright),var(--gold));color:#1c1606}
  .msg{margin-top:16px;padding:13px 16px;border-radius:13px;font-size:14px;display:none}
  .msg.show{display:block}
  .msg.ok{background:rgba(62,207,142,.1);border:1px solid rgba(62,207,142,.3);color:#bfe}
  .msg.err{background:rgba(224,32,46,.1);border:1px solid rgba(224,32,46,.35);color:#f9b9be}
  .hide{display:none !important}
  .center{text-align:center}
  .spin{display:inline-block;width:18px;height:18px;border:2px solid rgba(255,255,255,.25);
    border-top-color:#1c1606;border-radius:50%;animation:sp .7s linear infinite;vertical-align:-3px}
  @keyframes sp{to{transform:rotate(360deg)}}
  .foot{color:var(--muted);font-size:12.5px;text-align:center;margin-top:34px;line-height:1.7}
</style>
</head>
<body>
<header class="nav"><div class="nav-in">
  <div class="logo">7&nbsp;<b>MOTION</b></div>
  <a class="nav-back" href="/">&#8592; Accueil</a>
</div></header>

<main><div class="wrap">

  <!-- \xC9CRAN 1 : connexion par MAC -->
  <section id="login">
    <span class="eyebrow">Mon espace</span>
    <h1>G\xE9rez vos playlists</h1>
    <p class="lead">Entrez l'adresse de votre appareil (elle s'affiche sur l'\xE9cran d'accueil de l'app, ou dans \xAB \xC0&nbsp;propos&nbsp;\xBB). Ajoutez autant de playlists que vous voulez \u2014 M3U ou Xtream \u2014 et elles arrivent toutes seules sur l'appareil.</p>
    <div class="card">
      <label for="macIn">Adresse de l'appareil (MAC)</label>
      <input id="macIn" type="text" inputmode="text" autocomplete="off" autocapitalize="characters"
        spellcheck="false" placeholder="MK:XX:XX:XX:XX:XX" maxlength="23" />
      <div style="margin-top:18px"></div>
      <button class="btn btn-gold" id="loginBtn">Ouvrir mon espace</button>
      <div id="loginMsg" class="msg err"></div>
      <p class="hint">Aucun mot de passe. Votre adresse suffit \u2014 elle est unique \xE0 votre appareil.</p>
    </div>
  </section>

  <!-- \xC9CRAN 2 : tableau de bord -->
  <section id="dash" class="hide">
    <span class="eyebrow">Mon espace</span>
    <h1>Votre appareil</h1>

    <div class="card">
      <div class="row"><span class="k">Adresse (MAC)</span><span class="v" id="dMac">\u2014</span></div>
      <div class="row"><span class="k">Statut</span><span class="v" id="dStatus">\u2014</span></div>
    </div>

    <!-- Liste des playlists -->
    <div class="card">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:12px">
        <h2>Mes playlists</h2>
        <span id="plCount" class="badge wait">\u2014</span>
      </div>
      <div id="plList" style="margin-top:6px"></div>
      <div style="margin-top:18px"></div>
      <button class="btn btn-gold" id="addBtn">\uFF0B Ajouter une playlist</button>
      <p class="hint" id="addHint">Ajoutez-en autant que vous voulez. Elles apparaissent toutes dans l'app.</p>
    </div>

    <!-- Ajouter / modifier -->
    <div class="card gold hide" id="addCard">
      <h2 id="addTitle">Ajouter une playlist</h2>
      <div class="seg">
        <button type="button" id="tabM3u" class="on">Lien M3U</button>
        <button type="button" id="tabXc">Xtream (XC)</button>
      </div>

      <label for="fName">Nom (au choix)</label>
      <input id="fName" type="text" placeholder="Ma playlist" maxlength="60" />

      <!-- M3U -->
      <div id="formM3u">
        <label for="fM3u">Lien M3U</label>
        <input id="fM3u" type="url" inputmode="url" autocomplete="off" spellcheck="false"
          placeholder="http://\u2026/get.php?username=\u2026&password=\u2026&type=m3u_plus" />
      </div>

      <!-- Xtream -->
      <div id="formXc" class="hide">
        <label for="fHost">Serveur (host)</label>
        <input id="fHost" type="url" inputmode="url" autocomplete="off" spellcheck="false"
          placeholder="http://mon-serveur.com:8080" />
        <label for="fUser">Utilisateur</label>
        <input id="fUser" type="text" autocomplete="off" spellcheck="false" placeholder="username" />
        <label for="fPass">Mot de passe</label>
        <input id="fPass" type="text" autocomplete="off" spellcheck="false" placeholder="password" />
      </div>

      <label for="fEpg">Guide TV / EPG (optionnel)</label>
      <input id="fEpg" type="url" inputmode="url" autocomplete="off" spellcheck="false"
        placeholder="http://\u2026/xmltv.php?username=\u2026  (facultatif)" />

      <div style="margin-top:20px"></div>
      <button class="btn btn-gold" id="saveBtn">Enregistrer</button>
      <button class="btn btn-ghost" id="cancelBtn" style="margin-top:10px">Annuler</button>
      <div id="saveMsg" class="msg"></div>
      <p class="hint">Apr\xE8s enregistrement, ouvrez (ou red\xE9marrez) l'app : vos cha\xEEnes apparaissent automatiquement.</p>
    </div>

    <div class="btn-row" style="margin-top:24px">
      <button class="btn btn-ghost" id="refreshBtn">Rafra\xEEchir</button>
      <button class="btn btn-ghost" id="logoutBtn">Changer d'appareil</button>
    </div>

    <p class="foot">7&nbsp;MOTION est un lecteur multim\xE9dia. Vous fournissez vos propres playlists ;
      aucun contenu n'est fourni par le service. Besoin d'aide ? Un conseiller reste disponible.</p>
  </section>

</div></main>

<script>
(function(){
  "use strict";
  var MAC_RX = /^MK(:[0-9A-F]{2}){5}$/;
  // MAC en clair dans le path (les \xAB : \xBB sont valides en URL) ; le worker valide
  // la forme brute \u2014 l'encoder en %3A la ferait rejeter.
  var api = function(mac){ return "/api/self-source/" + mac; };
  var $ = function(id){ return document.getElementById(id); };
  var state = { mac:null, mode:"m3u", editId:null, canAdd:true };

  function normMac(v){ return String(v||"").toUpperCase().replace(/\\s+/g,"").replace(/-/g,":"); }
  function showMsg(el, kind, text){ el.className = "msg " + kind + " show"; el.textContent = text; }
  function hideMsg(el){ el.className = "msg"; el.textContent = ""; }
  function esc(s){ return String(s==null?"":s)
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"); }

  // ---- \xC9cran login -------------------------------------------------------
  function doLogin(){
    var mac = normMac($("macIn").value);
    $("macIn").value = mac;
    if(!MAC_RX.test(mac)){
      showMsg($("loginMsg"),"err","Adresse invalide. Format attendu : MK:XX:XX:XX:XX:XX (copiez-la depuis l'app).");
      return;
    }
    hideMsg($("loginMsg"));
    state.mac = mac;
    try{ localStorage.setItem("sm_mac", mac); }catch(e){}
    openDash();
  }

  function openDash(){
    $("login").classList.add("hide");
    $("dash").classList.remove("hide");
    $("dMac").textContent = state.mac;
    load();
  }

  // ---- Charger la liste des playlists ------------------------------------
  function load(){
    $("dStatus").textContent = "Chargement\u2026";
    $("plCount").className = "badge wait"; $("plCount").textContent = "\u2026";
    $("plList").innerHTML = "<p class='hint'>Chargement\u2026</p>";
    fetch(api(state.mac), { headers:{ "Accept":"application/json" } })
      .then(function(r){ return r.json().catch(function(){ return {}; }); })
      .then(render)
      .catch(function(){
        $("dStatus").innerHTML = "<span class='badge wait'>Hors ligne</span>";
        $("plList").innerHTML = "<p class='hint'>Connexion impossible. Touchez \xAB Rafra\xEEchir \xBB.</p>";
      });
  }

  function render(d){
    if(!d || d.ok !== true){
      $("dStatus").textContent = "\u2014";
      $("plCount").className = "badge wait"; $("plCount").textContent = "\u2014";
      $("plList").innerHTML = "<p class='hint'>Impossible de lire vos playlists pour le moment. Touchez \xAB Rafra\xEEchir \xBB.</p>";
      return;
    }
    var items = d.items || [];
    state.canAdd = d.canAdd !== false;
    $("dStatus").innerHTML = "<span class='badge ok'>Actif</span>";
    $("plCount").className = items.length ? "badge ok" : "badge wait";
    $("plCount").textContent = items.length ? (items.length + (items.length>1?" listes":" liste")) : "Aucune";

    if(!items.length){
      $("plList").innerHTML = "<p class='hint'>Aucune playlist pour l'instant. Touchez \xAB \uFF0B Ajouter une playlist \xBB ci-dessous.</p>";
    } else {
      $("plList").innerHTML = "";
      items.forEach(function(it){ $("plList").appendChild(itemRow(it)); });
    }

    // Bouton \xAB Ajouter \xBB : toujours visible ; d\xE9sactiv\xE9 seulement si plafond atteint.
    $("addBtn").disabled = !state.canAdd;
    $("addHint").textContent = state.canAdd
      ? "Ajoutez-en autant que vous voulez. Elles apparaissent toutes dans l'app."
      : "Limite atteinte (" + (d.maxItems||20) + "). Supprimez-en une pour en ajouter une autre.";
  }

  function itemRow(it){
    var wrap = document.createElement("div");
    wrap.className = "pl" + (it.locked ? " locked" : "");
    var kind = it.type === "xtream" ? "Xtream (XC)" : "Lien M3U";
    var url = it.type === "xtream" ? (it.server_url || "") : (it.m3u_url || "");
    var badge = it.locked
      ? "<span class='badge lock'>Conseiller</span>"
      : "<span class='badge ok'>Ma liste</span>";

    var main = document.createElement("div");
    main.className = "pl-main";
    main.innerHTML =
      "<div class='pl-name'>" + esc(it.label || "Ma playlist") + " " + badge + "</div>" +
      "<div class='pl-url'>" + esc(kind) + (url ? " \xB7 " + esc(url) : "") + "</div>";
    wrap.appendChild(main);

    var act = document.createElement("div");
    act.className = "pl-act";
    if(it.locked){
      var lk = document.createElement("span");
      lk.className = "hint"; lk.style.fontSize = "12px"; lk.style.margin = "0";
      lk.textContent = "Prot\xE9g\xE9e";
      act.appendChild(lk);
    } else {
      var edit = document.createElement("button");
      edit.className = "btn btn-ghost btn-sm"; edit.textContent = "Modifier";
      edit.addEventListener("click", function(){ openForm(it); });
      var del = document.createElement("button");
      del.className = "btn btn-danger btn-sm"; del.textContent = "Supprimer";
      del.addEventListener("click", function(){ doDelete(it); });
      act.appendChild(edit); act.appendChild(del);
    }
    wrap.appendChild(act);
    return wrap;
  }

  // ---- Formulaire ajout / modif -----------------------------------------
  function openForm(item){
    state.editId = item && item.id ? item.id : null;
    $("addCard").classList.remove("hide");
    $("addTitle").textContent = state.editId ? "Modifier la playlist" : "Ajouter une playlist";
    $("saveBtn").textContent = state.editId ? "Enregistrer les changements" : "Ajouter";
    hideMsg($("saveMsg"));
    $("fName").value = item && item.label ? item.label : "";
    $("fEpg").value  = item && item.epg_url ? item.epg_url : "";
    if(item && item.type === "xtream"){
      setMode("xc");
      $("fHost").value = item.server_url || "";
      $("fUser").value = item.username || "";
      $("fPass").value = ""; // le mot de passe n'est jamais relu \u2192 \xE0 re-saisir
    } else {
      setMode("m3u");
      $("fM3u").value = item && item.m3u_url ? item.m3u_url : "";
    }
    $("addCard").scrollIntoView({ behavior:"smooth", block:"center" });
  }
  function hideForm(){ $("addCard").classList.add("hide"); state.editId = null; }

  function setMode(m){
    state.mode = m;
    var xc = m === "xc";
    $("tabM3u").classList.toggle("on", !xc);
    $("tabXc").classList.toggle("on", xc);
    $("formM3u").classList.toggle("hide", xc);
    $("formXc").classList.toggle("hide", !xc);
  }

  function save(){
    hideMsg($("saveMsg"));
    var body = { label: ($("fName").value || "").trim() || "Ma playlist" };
    if(state.editId) body.id = state.editId;
    var epg = ($("fEpg").value || "").trim();
    if(epg) body.epg_url = epg;

    if(state.mode === "xc"){
      var host = ($("fHost").value || "").trim();
      var user = ($("fUser").value || "").trim();
      var pass = ($("fPass").value || "").trim();
      if(!/^https?:\\/\\//i.test(host)){ return showMsg($("saveMsg"),"err","Le serveur doit commencer par http:// ou https://"); }
      if(!user || !pass){ return showMsg($("saveMsg"),"err","Renseignez l'utilisateur et le mot de passe."); }
      body.type = "xtream"; body.server_url = host; body.username = user; body.password = pass;
    } else {
      var m3u = ($("fM3u").value || "").trim();
      if(!/^https?:\\/\\//i.test(m3u)){ return showMsg($("saveMsg"),"err","Le lien M3U doit commencer par http:// ou https://"); }
      body.type = "m3u"; body.m3u_url = m3u;
    }

    var btn = $("saveBtn"), old = btn.innerHTML;
    btn.disabled = true; btn.innerHTML = "<span class='spin'></span> Enregistrement\u2026";
    fetch(api(state.mac), {
      method:"POST", headers:{ "Content-Type":"application/json" }, body: JSON.stringify(body)
    })
    .then(function(r){ return r.json().then(function(j){ return { ok:r.ok, j:j }; }).catch(function(){ return { ok:false, j:{} }; }); })
    .then(function(res){
      btn.disabled = false; btn.innerHTML = old;
      if(res.ok && res.j && res.j.ok){
        showMsg($("saveMsg"),"ok", res.j.message || "Playlist enregistr\xE9e !");
        setTimeout(function(){ hideForm(); load(); }, 800);
      } else {
        showMsg($("saveMsg"),"err", (res.j && res.j.message) || "Enregistrement impossible. V\xE9rifiez vos informations.");
      }
    })
    .catch(function(){
      btn.disabled = false; btn.innerHTML = old;
      showMsg($("saveMsg"),"err","Connexion impossible. R\xE9essayez dans un instant.");
    });
  }

  function doDelete(item){
    if(!item || !item.id) return;
    if(!window.confirm("Supprimer \xAB " + (item.label || "cette playlist") + " \xBB ?")) return;
    fetch(api(state.mac) + "?id=" + encodeURIComponent(item.id), {
      method:"DELETE", headers:{ "Accept":"application/json" }
    })
    .then(function(r){ return r.json().catch(function(){ return {}; }); })
    .then(function(j){
      if(j && j.ok){ load(); }
      else { alert((j && j.message) || "Suppression impossible."); }
    })
    .catch(function(){ alert("Connexion impossible. R\xE9essayez."); });
  }

  function logout(){
    try{ localStorage.removeItem("sm_mac"); }catch(e){}
    state.mac = null;
    $("dash").classList.add("hide");
    $("login").classList.remove("hide");
    $("macIn").value = "";
  }

  // ---- C\xE2blage -----------------------------------------------------------
  $("loginBtn").addEventListener("click", doLogin);
  $("macIn").addEventListener("keydown", function(e){ if(e.key === "Enter") doLogin(); });
  $("tabM3u").addEventListener("click", function(){ setMode("m3u"); });
  $("tabXc").addEventListener("click", function(){ setMode("xc"); });
  $("addBtn").addEventListener("click", function(){ if(state.canAdd) openForm(null); });
  $("saveBtn").addEventListener("click", save);
  $("cancelBtn").addEventListener("click", function(){ hideForm(); });
  $("refreshBtn").addEventListener("click", load);
  $("logoutBtn").addEventListener("click", logout);

  // Pr\xE9-remplissage : #mac=... dans l'URL, sinon derni\xE8re MAC utilis\xE9e.
  (function boot(){
    var fromHash = "";
    if(location.hash){
      var m = location.hash.match(/mac=([^&]+)/i);
      if(m){ fromHash = normMac(decodeURIComponent(m[1])); }
    }
    var saved = "";
    try{ saved = localStorage.getItem("sm_mac") || ""; }catch(e){}
    var mac = fromHash || saved;
    if(mac && MAC_RX.test(mac)){ state.mac = mac; $("macIn").value = mac; openDash(); }
    else if(mac){ $("macIn").value = mac; }
  })();
})();
<\/script>
</body>
</html>`;
}
__name(portalHtml, "portalHtml");

// pwa_assets.js
var PWA_MANIFEST = `{"name": "7 MOTION", "short_name": "7 MOTION", "description": "L'exp\xE9rience t\xE9l\xE9, sereine et premium.", "start_url": "/?app=1", "scope": "/", "display": "standalone", "orientation": "portrait", "background_color": "#0c0c0e", "theme_color": "#0c0c0e", "icons": [{"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"}, {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"}]}`;
var PWA_SW = `const CACHE = 'sevenmotion-v1';
self.addEventListener('install', function(e){ self.skipWaiting(); });
self.addEventListener('activate', function(e){ e.waitUntil(self.clients.claim()); });
self.addEventListener('fetch', function(e){
  var req = e.request;
  if (req.method !== 'GET') return;
  // Network-first sur la navigation : toujours frais en ligne, repli cache hors-ligne.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req).then(function(r){ var c = r.clone(); caches.open(CACHE).then(function(x){ x.put(req, c); }); return r; })
      .catch(function(){ return caches.match(req).then(function(m){ return m || caches.match('/'); }); })
    );
  }
});
`;
var PWA_ICON_192 = "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";
var PWA_ICON_512 = "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";
var PWA_APPLE_ICON = "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";
var OG_IMAGE = "iVBORw0KGgoAAAANSUhEUgAABLAAAAJ2CAIAAADAIuwLAADhG0lEQVR4nOyddXgVx/rH33NCEhKSQHB3KO4EKVZoqSEtFKl7b11uf7e3vXVv7721W3cXWiq0pQ4Ud5fiTimWIAmByNnfH5ucbPbs2bMys/vO7Pt5+jwNye7MO7Kz8933nZlQ9erVASAEIXBHyGkCTm+0cZutLCxebLHGrGbNLlOr9luuFDsVbflCO03ioIM47o1g0zZfwGkg/nojCIKQEkVR/DbBAJRGVcJNvTm41dYdNmxjf6HV3C3aqFjJ2WJSDHO02Yg2W9xJ13LzyLh/3MJuEyAIgiAIgiAIgiDExH9BiP8bEsEcW5/lqIMIAc5P1ARBEHJDY68Q8HIPErLge5v7LwgJgiAIgiAIgiAIXyBBSEiI7x9aCIIgCIKQEppjEKhg0iGZCUJ6PAiCIAiCIAiCIMQChYeQxCRhDnUQIaBlDwRBEF5Co64QUCMR/GA1BqAQhARBEARBEARBEIT3kCAk5IQ+mxIEQRAEwRaaXRBSwlIQ0kNCSABF4LiBao8gCMIbaLx1A9UeQWghDyFBEARBEARBEERAIUFIEARBEARBEARjFNpSRxBIEAYUCpYgOEFdiyAIgjc00hIEwQoFlHD0J39NIVhB7wiCIAiCIAjCARa/NdBsUzLIQ+gQixLa6gNDzxUmkH95xW0dAPoKJAiCEBr8YyxyA/FXYLCw1hrUaFwhQUgQBEEQBEEQhPBQzKNd1BoL6/5NYMaXNqJuQRAEQRAEIS6+zOVIWQhEIDyEQfMyB628BEEQBEEQhDcEbZ4ZhPIGQhDawnqri/7lg2LoCYIgCIIgCJXgzAwDU1CrkCDkToD6XHBKShAEQRAE4S807yIYQYKQIMQjQF8ZCIIgCKGgNxRBCIe4gtDeeEPDE0EQBEEQBEEQhA5xBSEhNsGJUw8m1L4EQRA8oNFVbqh9sWG/QYRsQaEFoZA1ThAEQRAEQRAEgQShBSFBBBf6hkgQBEFgg95NBGEXDE8NCUKCIAiCIAiCIIiAgkUQYhDHBGaogxAEQRAEIRY0eyGEAIsgJAjCLvQZhSAIgsADvZUIQlBIEBLSQm8mgiAIgiBYQfMKgjluOhXDDslYENKjQhAEQRAEQRAEK0hf8IY8hGigvk4QBEEQBEEEB6azX4Um004hQSgYvvR1cR8v+qREEARBEIR7xJ1R+GI4aTPesO2QJAjlxGIvUZgPb7I8/uxrhiAIgiAIv5Hn/c58BmetZqSpP0ILe0EoQUdhr5LErxOCIAiCIAiC8BiaRXsAeQhdQQ5xgiAIgiAIgvAX63NyUpixkCAkfEOesA2CIAiCIAh30LyI8Jioig4b/lZK6CkjbEHjMkEQBEHIBL3ZCcIQ8hASrKHBliAIgiAIgh801/IE+x8QRG0YEoTG0CckgiAIgiAIgiCkRBsZqheEckeNEgRBEARBEARBEFFE9xCSfBUbW9H81NgEQRAEQYiCrXkLrW8UH4Fb0EAQkpOQIAiCIAiCIAgiCCDyENKXEVLiBEEQBEEQRCCgeS8aEAlCwiK+uHDpmSUIgiAIghALX+ZvFGxoETzOMFyCEE+9SIDFyhQrZl0kWz1BqNYjCIIgpIXeRzrEqg+Ls0FqZVnBJQgJgjluBi+x1DJBEARBEPFw806n6QAhNyQI3WLRLW51KKERhyAIgiAIgiCsx7tZnkDLoe2Zl4IEIUEQBEEQBEEQHiKFMJMGLoJQDvFN6BC3VeXukHKXjiAIgsCP3G8icUsnrOGEGTw6ZLA8hLZqUNzn33+o6giCIAiCIHhAsyxPCJQQCJYgJAiCIAiCIAgigARK49mClyCkGieIgEN7tBIEQbCFxlWCIHgggYfQ3uBIYyk26PXmHqpCgiAIwi/oHeQemgsRHqPbl1UCQUgQHKEx2g1UewRBEKygEdUNVHsEZ8TuYCQIhYTt4YdijZIi2eohQrUhQRAEIQn09jFErFqxOA9kfiQgZoLWseUQhAFrNIIgCIIgCIIghMVHzRkr2o0FoRziHhtWG57qnpAIsfzPBEEQOKGxlJAKqyFsnM0gykHnIRSx7X3Rzz5lSuBFxGeHIAiCEBd672AmOI0joh8L27ODThASvsD+0yOyjk4QBEEQBCE8zOdrTGeAImozAkwEIbUoIRPYvsQECop0IgiCcAONoj5CdU9IhqHEw+ghxPPs4bFEbpC/6pCbRxAEQRCECcjf48jNkwaqZhMwCkIRIYeql1BdEwRBEASBE5qlEPzgJGuDKAjpC4FHIKtnancfoc+fBEEQzqDx00fQ1T02ewhZ4CgI0T1FgYRagSAIgiAIgnBDoOaT9gsrfO0E0UNIIIS+gEoPNTFBEIRdaOSUHmpiwjr8Oos0glCuxwlxaRCbRhAEQRAEQeCeraE2LqDwFYT01UMH2wphu5MNfaMygSqHIAiCIESE3uAmYD6E0KJpCLZ19N0ABkjjISTiIuVIKGOZ5IfeygRBENahMVNEpGwz6onSQ4KQIAjvoPkNQRCEFWi0JAhZQfhwkyBMgPU2s+izRtgJ7CJ+CaRFgt5FEARBCAG9cdASnJaxHi9K3VUlXo2ZCUIfo3Kp2SSB2pEgCIIgCMI9NKeSApwahzyERIBw8xBS9A5BEARBiIWbdze99ongEFBBaOshpxHBG0hxMQF/LVJDEwRBmIN/nERvoBjgb+gAInGbmMR+JhCECPZyJQiCIAiCIAiCILgQUA8h4P8A4MfpK2J9qRLJVm8RqhkJgiAIwaC3TDzEqhh/DiG0eJVYVekJXOtEJkFIfScuojxXHihSUaqCIAiCIAi/8GC2IMpXeEHM9AtJaoe7IKRuRBAEQRAEQRAE4QzeekomD6H/MD6KELGWtmEaz1J4XEOifMwD+hBDEARB8EGg94vHb22+mdk4Flt4LLYbbXTCEMkEIfUMgiAIgiAIgiDKEOgrhl94IQidNQM1HkEQBEEQBEEQKJFHq0jmIeQFqVOCIAiCIAiCEAtUZ4+jFRQkCIVHgJMnkPV+N0UUaBkhQRAEQQQWN+9rdK96HlMzxGdOEDwwb6PEgtDHJZuBlek8CFRhCYIgCIIgCJfQ7DEgkIeQcAinIYJccARBEARByA2n2Q5NodwQ5BkoCUJ/kODkCSRQDREEQRAE4S80G0mMxahSqkoOJIz3tCQIhTrow2dTfakrAZYRIiMARURdxiD0MYIgCGdgHiERm8aMYJRR+EIKpU3c4kFzkYeQIAiCIAiCIAjCOlIpUo8EofhfIgh38OwAHncuCb6rYYCqkSAIIhYaG5ngcTXyzYx6BMEf8hBaRYIhWoIiELZA3uI07yEIgtCCfFTEbR3BHostjjl6E1WndWaMN0WQUhBianypCexGo/gtJAiCIIhggv8dTVuMEtjwThDilMXoBw2CF9T0GMD/2iYIgvAGGg8xQI0QWAKuOKT0EIoB25MnLPrrrXr/kXdbwjLUkgRBEIR76G0iDRbneIzjRenMCdwIIAiF6xyYY6lFgRRpcKC2JgiCoJEwOFBbu4dm2rawUl1WBaHEVU8PphtsVJ5EG42CUAM6fksFqkyCIAjm4B8D0RtYgfeViWSLUXGaSA5kq28BPIQEwQmB3nAuCU5JCYIgCLYE5w0SnJISwcGiS8+GIJTYSWgR6yMF1RVBEARBEARBsMX6HFsChe9ZEWT1EIrfBaSEmoWIA/6IKYIgCB7Q6EfEhboGUiRsGE8FoQSDHtsi0EajDBHMXIIgCIIgBEe4uQdtMepL1vjn1PYEIUVCErHQ8fQEE6g+CYIIGjTusQV/fdKR9IR1vOzOYoSMknAnOEFNTxAEQRAEzQcITgjRtcQQhBIjRC8h4oH/Y6RYUH0SBBEcaMRjC9Wn0EgcLyoEJAh5IUF4rXBjq2DmeosojSlcryMIgnCAKGOdIGb6g3B1I0qvMyFQW4x6icSCkDoCSuw0izcjFw0ZBEEQBBFkvJkJ2JvV0OQEKSI1jHX9LLEg5IU/+sGPjUatI9LDQaBHgk+YBEEQJtAoRzCEeWfyZYtRttATZhevBSG1EEH4BT19BEEQhHXorUEQ4mJr8ZptQSjU0jgbptKoZ4hwXzG9N1e4KiIIgiAIyfD+XSzcu5+mK2LhcXP5EDLqrIQSd2O2x9MLAL5lhMFBlOqkdicIQlZEGd8EMVMYaAGhCRJvMepX0ew68JwIQqGchH6CuaJoGaEWl7UhytudIAiCIOTD5VtY6He4yLbbBvO8WnRE2lRG6CfWM+hpIcyh54ggCIIwh94UgUWCHWV4Ilt5oogkCPFAA6VbeFags7QD1aaBKixBEARhi0C9IxyuY2Jthoepy0+gOjArSBASCfA9HtJ3AwiCIAiCIBzj+0zGdwMI5EgvCMXYaJTtvjJ+nUYYZGioJQiCIAjvofcvQ3yJFxVg+l1+OSczDHLyvE78EYTBeXgDtaIvQEUVn+A8gwRBEIR16O0gEIFqKxFn1KJsMQqOBaGIrUKIizff/+gtiAr66EsQhHzQyIYKb1qDGp2whS/9RbCQUTynhdDT7RZ8+8oQBEEQBEGYQzvKEPLhmyAMjqDC7E21GixuubXwFpU/9AmQOVSlBEHIBI1pzAlylVovucVakqMu8bh2BIoXBTeCELPOqYwYdvqyr4zE0OETCRGisEF+2RMEIRNCjGYi2MgMjAdOiIA0O8rYRBhDnSFYyChg6jp4LCGQIMT7XjioVgmCEB0ax3hAtRocyM/BG/EEISEPdp5uGvd5IEqlUusTBCEuooxggpgpGPZan5qA8AkShHpoQDSElhFaRJQXP0EQBEGIS8DftswXEAYNtLXil2F+CkK0jcEcxp5uOp7eGrSM0AqilJdeaQRBiIgoY5cgZjKDFhDq8OVIeotYn0Xj6cZi7SgDgfEQoukgpuDpx94RwCITThFlXkUQBKFCoxZhg+B1FnGeD48M9bFCXAlCv5Z44ulAeCzxAN9fbJ4Z4HdBvUag8vreCQmCICwi0HgljqVs8Ky8vvcB3w3wkiCVlT0+ewip8aQET6v6YomI46+AJhMEQRAMEHH89+U9i6ee8FhCGCJcvCi4F4Ti7ANrw04eDYl5RZ9ALwMRtRbBFuoDBEHgh0YqQqA+gHnyyUNoiNMy3hGQNYTSIdPx9CLYaBeBXgMEQRAEIRByvmFFKJMvO8ogQLbyGEKCkLCBiIdP0F6j8iHnbIAgCFmgMQozou8vSgdOyIq/zSWqIORda9bTl+Nxk6MUhBvE6gP0niMIAidijU5CGUtwQY4+IEcpfMR/QUhNqMNqhQQ1apT2GiVUxJp1EQQRBGhcQg7S/UVF6DVs40UlflBE3FEGmAhCcQ6f8HvzX78NYEJwokbdZirxaEcQBEEQfkD7i1q9UopJCIIdZYLihPDfQ0gQdiEnISeEK68cLzyCIORAuBFJNHvdgtQ9SBCuca+cUQhCnA+ONMsIMZ94ocne19z5IOIrQUCTCYIgCNuIONqL+FZNjK9l8vHsB4ZI2S88ho0gRN5RhIPtMkICqKrkRc75AUEQokFjkaxQu9oA/QJCPHtSYgOFh9BDaBkhA0RcRugXIk4RBDSZIAiCsIGI47yI71O20AJCH0zwJhvfCyq6IMRQgyp4LHGDQKWgZYQEQRAEQViEFhDGIo6lYiB0fWIRhB5Woo2cBGhaKYK/y+Dtx+ebvFQI0PMJgiAIR9AIbx3uVSVCW7A9cIJgDpNJPjNBKIbkQIAYW7wkIlBRoy7bQqCPhVoEslrQGiYIQhoEGoXEsbQSLmtY0FJrkSZelLl1ou8BicQqLB5CggBAekI9QRAEQRBEQuQ7jz7AiNE8rBxyJAiZIYc8kaMU8fCrcKRdeUM1TBCEX9D4wxu/aljudkXebeWIpxMIloLQl6hRibsC28MnmLcOhqhR2lqGK2KVmuZkBEF4j1gjj1DGMkOC7WR8jBelBYQWEf3hQuQhDM6+MrTe0kfISSgxVMkEQXgJjTkeQO5BmbDYmDzmyTb7UeD8DYgEoWPw1KYc+FyfWFszmN1MuFLT/IwgCG8QbrQRzV424C21r4bhrRbCJ3AJQpwdVID9i2Q6fMImwr2SCd5QlyAIgjc0zhA6pOwSyOeNMla5PRg2UJhtbSLvOsKBvK9jWEboAIoatYWIVgta1QRBCIGII4yAJgNQvCgACHHghEW3BKpqJSoThoC2kM9lRq6cKWrUkEA+KQBiFlzEGRtBEPgRcWwR0GQ24C04xYvGR8QFhL5UKduKwhUy6hjknRsPPgpRVHuNkpMwCFBtEwTBFhpVvEQg9yCG/UU5ZE293RKOGx/VcMJeELrsQKLvNYp8GSH7bDkVGNNDQgCyYcs6NHsjCIIVgo4nYlotNZzmTbjjRdlni39mLhSSeAglhvoxKtw3h6BTChC2K4pb4QRB4EHQkURMqwFYVLi4ZZcSag4d2CqEBKFvIPfF8zmAkRcCRY0S3iPoTI4gCCTQGBIcpI8XRd6XEcyNfTfAEmwrSlHKBSGqvUadGYO8i3uBT4dPBC1qlJyEIiJunRME4S/ijh7CGi61e1CQeFGrc0W09ewVeHuaTQLuIRRjGaE0vY0r5CQkzBF3VkcQhF/QuBEoULkHZcLHibGU7cPcPQhaQShllSEHgWfcDLGiRr0kyA+L0GWnNzdBENYResQQ2Xa3yFF2ihf1xwRvsvG9oDHw8hD60qh46hePJYZQ1KjvCD3PEBpFUajyCYIwhwYKH5G55iWLFyUkAmnIqMSjAV+CHa3qZdQorSQUGnErnyAI3kgwPohbAh9XD0ofL8reWPQHTvBGpk1PkApCD+GyjNBO9pYSxdl7tFgfFtEXhUgM/g5JEAQRTGh8lgDrbYhflFo0kIdb0mbdYK9JFR4LCEEnCNF3qsRIUARvECYewKaZtLWMZ4j+rOF/iRIE4T2ijwyCm+8bXrgHBWkaYeaHBFM4egil7FIC7DUqQtSoHD0jyFGjckD1TxCEFhoT/EXm0ybsIMZ2MhQv6oclnNyDECsIA1nRPpdZGuUcwK1lAq4JRba9DNo6giAIkGUoELoEkqtBQbaTYY6P8aI4QdtifNcQBnyvUeTI+vhR1KiXyPG44X+nEgTBDzlGACkK4Q/SbydjHZlmhlIuIOSHgSDE08nxWOIMiho1S5Pj1YIh63uFIAiCIKwg+XvQTuFkihf18Tx63uCxhBW0y6iKz3uN+oUwBxLyx8fzJ0RHjhoQt+sSBOEGOZ59KQrhCi9Pm0ACHT9ogpTuQX4LCIEEIRJkeggxINwLXjiDCYIgCIIJwr0BhTMYOcGZA2PuOMaCkKHFLptZpjMfPUUENz22zzfkJHQM1QBBEIRf0AiM2j0Y1HhRiZFsf1EV8hDyBX/8tKxRo0jMsI5wBusQ3HwA8ZuAIAi7SPDUi14C4ZoAicH440XxT4A9Brn9cQUhHiehV/i8jFCQWmIMtjKTkzDgIHnTEwThAfS8ywFq96AdsNnjDTxmv1IuIGSIYf0I4CGkqFGH+PdtBsmBhMK97IUzWIfg5pcheisQBGEFOZ500QshXCvYNpjTbMiyGRQvyhzR+qxVBBCEooPfaR5M52Q8yEnoBjkqQbg5CkEQtpDjGZeiEG6Rxj3oLxQvihwPJuoeCUJBTqinqNEECLe1jHBvfeEMjkX8EgAAKIoiQVsQBKFDmkdbgkII1xBc3YNibCfDmuDEi+Jpi3iWmAlC/NYTCfCv3oQb6LWQk9Al0tSD0N2YIAgd0jzRspTDLcF0D/rZjYWuOP9w2WLeuIsoZNQ5dtbU+Za11QR9fcplchK6z02aKYscUHMQhBzQs4wK983hcXsK5x60kzvFi1oFjyXOMLE/gSCkvUY9z5691GOcnu9bywQACapO/BJUIE2MGUEEE8keYQmKIlNzeIxM28kEJ15UCCT3EEo85khctMTwdxIGuXZZIVkXpRkMQYiIZE+uXKXxBwdViGRzUSGQuItKXDQQSBDibAYeUaN+uVJFihrFDZO+KsckRopCVCBHoxBEcJDsmZWjNEwaRY6qUJEsXpR5vj6uz2ICngWE5pYkFoQUNSo8FDXqCDemkyaUFclizwhCVuhRxYnvalDoPiFTvCgCJCySG4TxEILT/i3xG4G2lrFxuaPKkrfveIeUDyBNNAkCM1I+oTKWyWucVSFtJ2MjQXl7qS9F83JaLpIgxIkYvmxyEnoOOQmjSFEIPeR/IAiEyPpgylEm392DQhNM96AYc2wRSFg/lgRh8GpZur1GBQGhk5Bggqx1T52KIPAg6/MoabHEQGL3oI8gmOV6ZIBAD6/XHkKXnYCiRnUIETUq9EuaVhKyQpZy6JHVI0EQAiHxYyhNsXx3DwpdkTy6N8WL8gbPdjJW8CFkFMGHAd8IZtQoR9CvJCRNqEWWchggTRsRhHBI/PRJUzJB1aCIp00EM16UN3gscYYV+60KwiDUhe4Onolbyd63GhdpaxlCNEQfSUyQ2EdBEDiR+6GTt2QEgN+zHckmmXQevQkWK8eGhxDJ2ITEDMewD/IU4eMNx3c2OQkJTFBLEYQ30LMmCuQedImf28lYRuLHUfr9RVVol1ETpHMSCvK4CmIm4RCJXxsqcnstCMJ3gvCIyV6+oCNM8/q3UYXoj4Bw9vsjCIO8jJAHPm4tQ05Cazm6uLkiEXmeGomKEpcgzFkJwmMC8ljJVERyD7qEh3tQsu1k5IsX9UUl2ROESAYp0fcalWlrGU7wNlPQKYWgZhsiUVHMkKnJCMJfAvI0yVRKQZuMt9nCVAoFoAZJcfgWMiqIk1CYqNGgnz/hSW/y3UkIwr5fDZGoKGYExKdBEPwIzkMkUylZNZkAR00gcA/aSNM/9yBtJ+MxtionWGsIZRpq8cCpVuVrK+p+sQSnToIzoyUIhgTqwQlMQW0gX51wKpB8FUV4jG1BiKTPITFDh50FdZav9G9rGUG8uOWgX0nICsmmR3KVJgGBmt0ShBuC9rBIVlYMbSf66kEe2JjXibA5BW98iRf1a+7txEPILPjNXZm96jFoOmYihNhu2NZQK99KQjzDHCqCVi1Bm+kShC0C+IAErLhW8b5aUK0epNMmWOcuwGPGUA3abZpghYyC330XC7JWAvqVhMCoB8o3W5KuQIkJ4KyXIMwJ5kMhX4l931kUxF896DOylssO8j2Y5vgsCAUJSuSytYy/y3CZZx0oJyGGXivftEm6AllCvnYkCGcE81mQr9AY2tGjYFG76du6WITTJqzDZzLp0BiuILHKgRkOBSGSAhM6qF1QaLVE0I6j8ZCuQJYIpleEIKIE9hGQr9AYdhb1DiGM5IkYzVSGALb66yQTO2Q0OMeDcMjb+oU8tgkmJyFhDJ7H02MCOycmgkyQu31Qy82dQLkH7Rjg23Yy1sHzUAitL5yZ4VwQItlaxiu4RI3ayZ7WFlsGiRmmkJPQBBnLZJUgz4+JQBHwri5l0ck96D1CTPno+EEr+K6GxPYQOkaM4YY3HB5mWkloJ1N390tNwCtHKcdvQwiCMdS3IfDjmzm+7CUjqHuQiySjzhlUUAhCN7IY58Dq79YyOOvEU7yqAQw1HfCpldzQ1JmQBurMcoOhcb2zwP+y+ozcc9cAxosCQBWXuYZCbhJggzMz7N+lACAoLVsql2nWBxe4SWzwZV/ay1xRQpbbgHft2zKGXaZsniBfjOcNkuEFA+pMS74mJgICBqmABykrQ+hgUUHdg1wQpHNSvCgPQllZ1V3dz2iKEnI323dmhv27bNxgK3HrF1usKPMEZ33oSvjZZcjlcYWirTkuz+Yqv8NRT3L5EDB7iCQVDJIWyyGytjIhJSQFtchaGUjUoHfBojbvkDJe1GLunNyDXAWh437opgOzEoRubHArCAGHJkQoCG2lz1wQatP0WP5ZQSsROWpCrwSho6y0mbq4WZ+UnGpB0mK5Qta2JiSAdGAsslYJw7Z2N592nClfQcjPPcheEAqy1sl+i3khCDGoQZdmSCIIHZuBxEnIXBDO/gidCIzHaVd8Zf1ichImSkdakSBvyVwhcYsTIkJS0BCJa4Xcgwwvl8w9aCt3boIQuxoEEoQG6QRYENq6OF5FuReBgy6b7CxrlZkfjHVpgBVxKKWTEEgTWkDekjFA4nYn8EM60ASJ60ZoNQjkHoy51K+sRY8XRSIIXZrBQBACDk3olSAEbE5CBzpw0KUxwo9nzOrv79sWiibKkJyEFpKSWRtIXTgGyN36BCpIB5ojd/UgCRYFcg+aGUDuQXsENl4UsAlCEEMTonASWteBBvLPKEXrWVu9Mv6F1iWioTLkrQlFdxKC7KpA6sKxQe4OQPgOScGEyF1DoqtBcFAEHGoQBBGE5B60ejsO9yCwEoQQLCehn1vLzPlonJWkBl4y2W7uHmvCKBbFoVYZonUSOspKl6+7+yvSkVwPyF4+ZkjfEwgvIR1oEenriYJF2V5O7kG2V1ZYYetqEoQsLEEhCB2bgcRJaHKlFR0YFYHOcvdLEGouDs14b0zCy1RliFYTIhGEEAAlIHv5GCN9fyD4QTrQFtLXlujuQXHVIJAgtEGA4kWZPJHoBCFI5yR0GTWaUAoa6kCHBviqCbUT1oTKcKidvUkBgugkhABoANnLxwXpewXBCtKBDpC+zkRXgyCyIAyyGrR7MbkH7cJMEAIOJ6E0W8u414EOcsfgJNT9hqUyJE0oI7KXjyPS9w3CGaQDHSN9zZEaZH45uQeZX1lmgk0C7h4EnIIQxNCEvJyEcz82k4IDLvlCYwEHVYbGSajDXBlakoUOO4YPgaNAiwntEIAicicI/YQwgUSge4JQhUiWDoKXwaL2MyP3IPM07V5M7kEHsBSEECwnIfutZaxLwXILZBOEkGhi6lYWkpNQUgJQRI8IQm8hopAOZEUQKpLcg8wvJ/cg8ysrrLB1tbDuQZdmaJFQEDo2w0cnoYkUjNWBlS2QTRNanI+aKMMEspA0oaQEoIheE4RuE0BIBDInCDVKapDD5eQeZG9AmRW2rnbapTAIQoaDD2NBCDg0IUJBGC99x1Kw3ALZBCHYmYY6kYXiCEIgTWiTABTRN4LQfySGRCA/glC1eNQgSCQIyT3I/MoKK2xdTe5BACBB6PouV07CeGrQihTUWBBoTQjxZSFpwpikAjGnD0Yp/SQgHUl0SATyJiAVTGqQx+UBV4P2kqXtZDjYEAt7QQiMJmRyR43Gk4KnXvyFXUtIEKqXTrcuCz3cXcZpbtp83d2vTy0QU/lglBIFAelRokAi0DMCUtNse5RIwaL28yNBGJx4Ucm2k1HBKwhBUidhQinowBLShNFLrcpCD52EjnLTZe3ufn1qQZnBB6agiAhO70ICKUDvCU6Vy6EGgdyDRpf6mTu5B1nAfCDiIgghWJrQ6g3zPrEkBR1YIoogtGWAM0GoYkkWUuBoAAhSWTESqM7mDaQA/SVQ1U/Bopzu4LGXDIgjCMk96Op+RmbEQoLQ/V2WbjBUg/GkoF1LOEkyQZ2EUQxlYYUmFCpwFEgTuiBgxUVN0PqeS0j+4SFoTRFcNWg/P3IP2jKAtpNxD4/hiJcgBFpJWI5dx6AzS8hJCJY1IURlIQWOBoaAFVcwgtYbDSHth5mgNQ4Fi3K7nNyDVtO0e7E3atDNjUCC0G06IjsJHTgGnVlCTkKIb6yZqzCogaMQyFl48EosMBL3T9J+AhHAtkKlBiGowaIQePeg3YvJPegSyQWhMzNYbS0Tqwb7X/SF3fTJSWg9WTC1N1YWDr3iqyAHjoLUc+54BK/EcoK865Lkk4MANmOg1aD9/Mg9aCt3PGrQfvqu7iq7N7CCEHBoQl+chIaOQVUN2k3cZ0EIgjkJwaYmBIChV8Y5rtAkC/8CR4E0IQsCWWiiDIt9nkRdkAlm40ujBkHwYFHw2z3IyQA8glDc7WT4DU2hrMzqDKao8VIPkCCE6FQ/nmPQcfoBdxICo8DRKAauQtKEwSOQhSYIIjGkBlmk5joFV7kHJVgUyD2oWmETcg/GwlcQQrA0YQisqUG7iZOTkKGTUMVfTcjkmSBNyISglts5jUJJnSClTahK01CVepCUHQqnQSgZQhGAk6Acg8ghJbIXSrcpJeuV4jVKUSGjtyARhZqAH8GUgoBPDUKAg0WB3IPSuQdZqUGXZpgTysqsDsBoimqYQWAE4bxPxsf+0lAN2k1fykPq7RnA2kkIjMJHpVlMCKQJY5hZpb6D1G4rzV2hFLkyyIhWoSrvJNW2e9fgkr9YGdAulDwsVHVQqGr9UJL1u0oAVilF05UT0yOFBY7eiM5agS3xqjGhbZuVkqtLD7Iyw68miMVWoyxQTv6zNI9JvlaydtPnSQ2yS9B1Cs6z9kIN2r2D3IP2kiX3IAcbElKFY9oAAKAo/n+Dd2aDrbti1aCJFORqCZdkFasKRgHFuibk1zes2KvuMqqThdPfHePAVegAyzUaPwUET5YVpkz50uMcR48ea+t6dYRlVZnDQ2k8BOEZoTTmaVohDHBaqOqEcLVTQskObq8C0COU0iOUcnM484dI4SeRggNQytxIuRG9CfqGUs8Kpf2kFHqZqV0CKwV54G+wqDfws1AgNWgLPI8YHkuwUS4I3c9POWNLaXiMMzXIS+b5XVGcDFAUxZYLy2KPHnrFV240oV2rKt2LTBO6KYsJderUYZ4mZk4LV30hcvQk0wlDGOCMcFWGCVqkRyjl1nBWixCD74ZVITQmnH5uOO2zSMGHkYJiAaZ8KJCjCW5KylxUcjIXIp7lSFgHW7Co10sH7WfJNVjUjhk+j6KcDMAp2KR3D4ICYZ7Jl+fCqAxu6pSfg5irb9CWJXyT9d0AbqNq2YGEGqa/a3ycvSH+bkXINvMgb6uoKGwqMx1CA0KpDBLS0C2UUhtsRAm6Jw1C/whnPZdUk4kUiZIKocvDGW8n1WrFNFkpkakJsiB8Z1J1z7KzBasHX1CwqUF3uXsULGoveW7BonaM8NkAnh0D++pBMVAAQCsIpS8wB3RqsP9Fn9tSg7yePb/b0ncDVKwbMfSKr3Sy0JYmdAyTaiJNyBAms8OzwozDO4d7Gy/aKJT0WlKtEeF0Tuk3C1V5NanWkJAPPk9RkK8JBoRST0fW4gGXgoBSDXrdIJyXDvLD91lWoNyDGPCgZrzwEAKONmZrw7xPxseqQTUfltlo8P/Lje8G2H+B2bo6VhNalIVuXqukCRHisgJ6hVJrshtaUyE02MN40dah5FeSajXn7D5KhdBDSTVGcxM8QiNrE9yWlJXt1ZQjIYEf5GRTg968trgGi5J70EHa/JJmhe/S3TqVR2f0Zntfs4Zd2ShM9HOG6bvH9y7ouwHOcBw+SppQMtxUQBjgdHZOwv6h1HSvVgU3D1V5Lim7hiez9hDA38NZHjs/8SNxE2RB+I6kLG/yMoEcg0Bq0H2WvuL7/EpQ9yBtLhon9bL/e/e5Tpoh2IIaJCchNwM4OwlBZE3IFtKEbjiT3SR7OOsA1HhkQ/g/SdlZ3vpw/plUvYOjzTOlRPomGByq6mOoMElBFYRjuxBqkNyDTvIPtntQADS1GPPiQV/D/m4tw9A3aJg+Q8T6hiSHJvQX5h0J4bxBFFqHqjDZtCMLwjmst6gxJAzwQFKNut5uXQMAVQAeTqqRgSaS0EcC0gR3JGVV96O5aTBTQXjkoBDgUYNiTe1sJCude5AVntlgNGVReB1BIcrJafGwowZ5VaJAZxIC+H8GhmOcHUfh7ykUwKF7cDqLIgicGUp7RTnmMpHTwlW92QtybLhaj1CK9ev/VEpnKCdWKkXblZLDECkGJRVCtULhVpDcPZQyJFzV+mqxupB0Yzjz35EjjgyXh4A0QQ0I356U9XDpYQ/yUsEwpUMCTjUohHsQCfbEGLkHfcV36Z6YygaGsjKrG1zEbQbIam7pRmY4s2H+p3Z9g/aysW6VLfutV5S9arFurZ16sFc0mw3poNl1mhAArBxR6EZBMXk+mCs4VJqwVq1a3333dby/rl279tprb2CS0azk+m5uz4XI2JL9Lk9eezmpVicX4XyDS/6yclldSPqwSu2q1nrfLqXk9Uj+HOWEybsuGUJnhqteE860rkn+VnpovVJs8WITZlZJ0GqblZKrSw+6z4htXmI1QcKCJ+S+0sOzlRMObkyYtbbPkxTUQmrQcZZCugftRV1xMMBWsrYbxWaYGK0eNE690r8oUMcS9tUgyLyS0FaywgaOgpH8sxI76vtiQoljRxs1avTGG6/G++vmzZvvuOP/vLTHhJoQ7uUu2rNhKMmNGrTOtUkZFqXI1EjhVaWHZptKEQAoBuX7SOFlJQcXKSct2nBdONPilVIStCa4MymL61JJWi6og9Sg84zsXo9BDdpBrCmlmja/pANETC3GGZG51TarLuLlSkJHahALvHzWAXkeFYea0F2eLBLhoAl9l4UtWrR47bWXGjQwdhH89ddft99+Z35+gWf23FaSa37Bme72gznDdGeaBxgF3TUJVTnd2hY4H0by/x05UmS5hx6FyN2ledOsOYJ6hlICu7tMAJsgG8K38dlxlKSgDh5Dt+9qULRcPQfB93080OpBi8T/RIegLjDgTg3yc47ZuNj/ZEV2EjrThC5fwDg1IfjqKmzRovlLLz1fq1Ytw78WFhbeeec/c3PzvDRphVL0p1JqcsHAUGo1F1HAZ8Tfj/EIROY6iriLZVwo3Yqn5hel8K1Ivt3ESwGeKD28SimycvH5QT2WMJhNcHqoan9PNkwKMjxGbAxqkIJFWYFhMunBPM5jBFDORgYKvNmX99uNglC+wSi89BiODu+XJkx8E4LvS9JowoYNG/zvf89lZ2fHu+DRRx/ftm2blyYBgALwQ6TQ5IJUCA1yeqZ8u1Byk/j7lP4UKSxxlm5lqkLoDAtuzL+U0mdLjzrLogTgsdIjxy08eYNDVd3oZ0GRsgkmlB4otJDdnUnVaYNZfqBVg65tkEENcoTPyj0BRI4R4roHvcd0LA5kjWjRuQf7XchXDfL7puL7k8zPSegZOk0oxGJCkEITZmdn/+9/z8XzDQLAZ599/vvvs7w0KcrPSqF5XZzl9EBC85MMpypmQtQ6/aydev9K5JiV+X089kHpBxZcW6kQOtW/Q+r8Qsom+EspfTWSeIvd2hC+JSnQa0f5gVkNCrF0kDc0hXNwsRAIsJ1MnJT9+TgnhJPQUA3y3goJA5ychKIHjgJpwkppetSxU1NT//vfpxs2bBjvgs2bN7/66uveGBPLPqV0qWkwXtdQSj37J8slAZwW37W4VineoTBxEMIACw7MLUrJLNfhqV9Fjh+GxFuunhoOXAyhrE3wbeT4CgtxqmeF0vpS4ChrSA26z1XUYFE+7kE02JzsCese9F4NQmJByM0mDDVuAlPfIIovK3LvLoNZE7oh4JowFArde+897du3i3dBcXHxww8/VlzM4LgCx0yNHDf5a8jR1jK9QqkmpwX8oJjlaAsrB999pRx339InQfneNLw2ak/QYkZlbQIF4KnIkROWAkezAhgqzA9Z1aCXuUofLGozVRSTWCHw3ZfrhkCH78fri+ZqkHcPxvCECLe7jEc40oQYNpgBMTXhxInjTz99qMkF7733wZYtW7nakJDZkZMFpq1ksjdMPIbH15AnQJkWYbOdTONQUs1Er4ASgJmMsvvZQphrFoRNVk7Kh9xNsFcpfd1C4GhdSLoxbGnHUYwvBWRIrAalOYMew6d8DI+SfGcPCoBp6SwIQty1w/xp4bNukFclYhhZkLiRvXASliOoJuQBP03YpUvnm24yO2J+585dH330CafcrVMEyi+mjpemoSrtwcZu/mkQGhA/iG5G5ISbtWRa2liwarVSdMxCnKEVdioluyxEurazU1eiI30TfBM5vtJC4OiIcFovU08pHSZhBSx+KiP8UYPO8rJ7PbdgUZt2cEoVR+lQz4PKEGD1oCl+egjxrySMpwZROQkx7BpsI1meT7VngaNgdGZ9gvsQaEJOkyoer+pq1ao99ND94bDZAPXss8/5Gywa5cdEkXhnhtOsV/7AUFWTM8pZbScDAC0sOIIsHldgESuLypoHyUMofRNELAeO3pVU3XBzHZKCFuHkGxT4kAlHGaMKFhXLPYhh4uoyfQxDjY+fDKwJQhwuIA+IPXWQHSiKisFJiOaDE4A7TaiF9wYzcbJ1lI4ImvCOO26rX9/4AHqV2bPnLFq0hG2mjlmvFG8zdbwMC1dNhhBYm2ANj7/LyE6lZDU7edAwlHi3mw0KS8m9DhKnZsUqaQhCE/yplL5hIXC0HiTdEK604yhJQetQpCiTjHl3Nwx7ydgCzYo4JGaYgaaunCPJGkImTkKPD5kwB8O3FnvJ4ngWPAoscbSYEGTXhKwqv1+/vuecc5bJBZFI5JVXXmOSFyvMt+vIgnBfzeaN6kzXsLZqQrhn/HhRhu5BAKhvYfvTHcBmO1MVc9ms4mBTVnEJSBN8HTluxc85KpzePZRi8nQQsTAceCsnyygdt2Z4pwadZIKkm4o2XURSbQjxN6LYsiCUvf3sqkFxOzQGBx1XGzAvJnQPZk0ILF6QaWlV77rrTvNrvv/+hx07drrMiC2/RgpLTS8402hrmdiJ77BwWrxBuRTAfLGiXbItzPv3KWxWr6n8qZhXEgBADVk+U1ohIE2gBo6etDB63R2ubhIvTejgJEiQqEGP4R0simHHBww2eID38aLY68qadXbGfQTfFTihs8GibxDVFkkonvNABo56vJiQITg14ZVXXl6vXj2TC0pLSz/44EM3WfDgMETmmm4F2S+cmhVnvNXKQpMtSecrJ3MZbS6ikhFKMPPOh0gx07HiiIUEMxNZJRPBaYI9SumbkfyEl9UPJV1PR9VbA7kadA8Fi1q8mgeYjprwokdi6Pa+24DiWyyjVcvOU1nwGb+lg8ITkMDRAC4mBHyasHHjRhMnTjC/5ueff/3zz73O0ufKD6buu2QIDTM9glxRoClUOSUUd4NH8wMPHZCWyBVzjEP/OJqo/wbKQRSoJvgyUmBlBez54fSuFs5mDDj41aBAwaIOcsLyYZcCNWPwvpjY3YOWsSkIcZfaWavo1KCtpYPkJHQDqsBRhwi+mBCQacIbb7y+SpUEOxx+9NHHjizizkLlZJ6pBy/hCfVnxFeMByGyUDnp0LI4JCea91uJ8bNLQaIAyCpBEoSBagKLgaMhgLuTKHDUDFKDvDK2mImAwaK2ENc9SJuLGiVt9UIUHkLwrz3cqEGnIOh6NuHnJESlCR02DGnCuMna2+2gfft2Q4YMNr9m0aLF27fvcGcXL0oBfjZ1EnYIJZsc+R0CGB6Kqxh/SrRG0QEJR3/mOXJKU1yC1gS7IqVvlCYOHG0USrqOAkeN4LSFDARYDQq8dJDcgwjAIODNsGOdfUGIvezO7es70YkaRHWaCr+hJyCjCUNNaOk+2TUh2CnjNddclfCaL7740p05fDHfaxQAzozvA+wcSqkff7v/H1jHi4IFYcDjQMCEvSFQijEgTaDdOPTLSMFaCwdpjA2nd4ofPh1M+IW9kBqUGyQzQ3IPYrYB8HgIfcG/pYM4Gp8fOEYf8GwxoREWdxwlTajSpk2bfv36ml+zd+9f8+cvYGQUF3YqJeaT3eGhtHiRcCbxoiuUot1KKfPt+BMG76VyCNtLqHAKmW6cgxy5m8Cwx0YAniw9knBjGzVwNIUCR8shNcgcD5YOInEPiokAJZTJPQgOBSGvADNG6VizT6cGVfcgzg8MQjoJkZiBfjEhkCYEAICLL74wYSI//PBjJIJdLZhvLVM/lNTNaMOMZAidFl8QTq2cJitZmJ9o3p8ZYv/FsFqiNI8jf8UyRdYmMO+iO5WStywEjjYNVbkmKcOlJXJAapBv3hYzEVMNIpkToponu7yLLRhsUMHlIfSrXpwFi7qDY1GFW8FsF4EWE3qD6JqwTp06w4adljCFH3/8malFXJgeKTR3+ww32lqmb/xDKQpAmWl0oIX7ljqcaHORahBKuOuJLUIAWYkSzGV67B5yAtsEkyIF6ywEjo4PV+sY+MDRIKhB7/NGtXQQCZiWEQlQfdgnz/atcyoIsddDAvtMgkVxfmZAMrggcRJ6gBtNqMUbJ6FRzi6S4qkJDUs6cuS5SUkJTuhes2btn3/+ycculhSAMsv0QMLTwlVjd1AcHv/4wWmRwhN8no4DFiIDG8Vf1uiA6hBOKG/2B2kVYWCbIALwhIXA0TDAXUnV2UpigeC3hQwgU4MBXzqIxD3ID5wzZAyVw8sGR8m68BDiDhy1jh/uQRUhnYRINCHexYSKQydhQDQhxJQ0HA6PHDki4V0zZvzOyyDWmG8tkw6hU8Op2t9kQLh/5d9YT80Ne5XE8/5mTLc1aWxB21ixShqC3AQWA0dbhKpcEcjAUa6LHUgN2ruFgkVdpGwfBEItEdh8GEzAFTLKEJPWSriXDM6PDRg+ZqACsybUYtFJCEHVhD179qhXr27CW2bOnMXRIKasUIr+Mp1Sn105anRIODWeD2SrUrLeQmRdPMwbcQeUJEyhPdOAvdYWUttuwSppEK4J2G5rNClSYKV7Xxyu1i5ggaOkBjnljU0NBgGcc2N3S1bZFAmVexDcCkLxnYT+uQdVeH52QvJxSOTAUcc4XkmITRN6ED46fPgZCS/esmXrn3/u5WUKaxSAHxUzt16vUGpNzdh7RvwD6793fdpEdKfH2KbcaGEu3tVoCxzHWDlIYJMSIEEoRBOYdCGXWNxxNAxwd2ACR3mHiUqiBmVBevegfxu9E7aR1kMIcbq41j1oogZxOgntgmREoMBR605CQKYJgXOvrlKlypAhgxJetnDhIo5GcOCHSKFJtYU1W8vUjbPvKAAUg/KL6XJEu+im9VuUkoTHHrQLJWczek2EAXqF4kbGqhSCstWFR1Q4MDcBJxGoY5tS8n5pQcLLWoaqXJ5Uja8pCBDFMQi+q0Ep3IPSq0EPEHeujs09CAwEoVBOQv8OHjSBohFcgVkTaiFNaEjv3r2qVUs8zxNOEO5TSpcpRSYXRAXhGaGq8RwfsyMnj/I5lE+d6BcpyupE6isMYHIehi26hlISCpvlSlGA9hgFKAaMTVDKXwdq+TiSv8FS4GhGG3kDR7k6BoHUID41GASkdA8yCWTD2VVk9hCCacslDBYV98ODFiwfingGjqLVhEOvcH4ERUA04amn9k94TXFx8cqVq7hkzxPzAwlbh6q0ClWBOKdQqEzltp1MlHkWPJCjQ+lM3hMjw+kJr5mvnGSRlUjMU3A1wbyI101Qam3H0SSAt6vU8sYkj+EdOUlqEKEaJPege8RdPcgLd9axeMsI4iRE6R5UQfQVimN3x7SY0Ds/oQZbTkIIhiY89dR+Ca9Zv35DUZGZtw0nsyInCkxb4KxwWqtQlRYh4z0k9yulS/mro5nKyYQeueahKoPin4phkcahpNMSJVIKMJtpiKwQzIxQE1gNHJUSUoO8s/dADdpOn5sa5GiG3cRldA8yAWGwqAojDyHidjTs8Rb3kvHw8wOqx9L/lAHlhysHmbhxEgJKTciwqhs3blyvXr2El61evYZZlh5yEpRppi6+4eG0i8Nx99OfqhR6EDx5QCldYkF2Xh/OjD070RY3h7MSvmzmKSfy+ITIYuYgeNEEimKtCSK+NcHHkfxNQVo+Cp6EiZIa9GZyynHpoE0Ene85aChyDzIHdcgow/7nsXsQ2za7WEIIuApI/oGj7rHrJARGmhCnq7BHj25WLhNUEEKiIwSzIXx6nLVhSqKIU4Z8VZp4I9MGoaTbwlmOd5scGU7vl2gvEwD40vWWqoLytYWCNwgl3R7Osp6mtrEUBUZZa4LJ/jWBGjganB1mhXMMiqgGHWaFaumgmMGi2IJL8YDWPQgsBSHi5tf1e1tHTXjYrTGNQfwI3mJCl05C8Em7msPEoq5du1i5bP36DQwy84P1SvE2R4coLFWK9nl1Pvt85eQWC0aeE067NFyx/Y9Ob5jQO5R6WzgzYfrrlOLlptvwSIzFJjg7nHZJOO4OTCYt0juUeluSAE2wRSl538JR9aLD2zEIKKcHvqjBQC0dxIMHEytyD/IAtYcQGI1rCz+b4L0N2EZkPJ+ObCHfYkIHTkKQ1E/YsWOHhNfk5xfs27fPbU7+8aMjR5/74wetowC8XnrMypXXJmXenJRpuORRp0aifeOMUNqTSTWsnCD3WsSSDVKiALxhrfjXhjNvCmdWiV/hsZwRTnuqiqUmeNVaN+CK9IGjHnzdI9+g4/twLR20m7iYczwHYLPHOpjdg8BYEPIpKtsa9PskenMQOQkDEjgKnmhC905CYPSuwrOkMC0trWnTpgkv2759G0IHqXV+jhTa9fQdhchsb3d6XKCcnGstx/Hhaq9XqdXdwlHp9SDpgXCN+6ydJ/6bcmJlUN2DKguUk/Os7SE0PlzttSRLTVA/lPRgUo37LTZBBEUTlAA8VXrUI+e4t3jjGMS2aBCkVoNBCBa1C9q9ZMg9mBDsHkL3uHQPqgTQScgXTIGjznCTiTMnIaDUhOC0wlu2bBEKJZ6n7tq1G1AGzVokDyLzbaq7XyInEm7Bz5xnI0ctnnnYJpT8QpWab1WpdWG4WvtQsnankzBA41DSWeG0J5KyP6tSZ5i10/MOQuSF0qMO7ZaIZ0r9awIl8jyaJtikFH8QkS1wVDjHIGBQg44z9SaXYASLYnv3ijsbR+4eBADjHc+do4C7vejipKqAhaljYnC7B1Xs1aDdmrF1vQJKyLIxrNrIvSUOjFEUxYo4ibHKhk1Dr/hq+nsOdWClTB2Zqk+E9WPqoPVbtGhu5bLdu/eUZ6EAgPuye8+PSuEASLyfRxQv40WjHFBKHy858lSVbIv12zaU3Dap7JTwfIicUCA5BJkQtvuJsQTgoZLDRxQDISRgU1vFcGZwAPxrgtLDFrWoN3xUWjAoVLVVnBNZxMIbRSSnGnQ29XeWFaqlgzbBEyyK1j3oBtQn0TNNVn4PoRY37erhZwlEDjE8gaMIN5gBnwYzOfyEjRs3tnKZbgGhiK7C+Xa28l+vFG91tA+Ne+YrJ19xtIosA8K1Q+Hq9qWIAvBU6ZFVcSIVY5fJWV84hwdbZmNrAr8oBuXJ0iMSBI6SGvTYCEnUIAWLMsvC+V0BhMMXOExOQm28aJ+Jk1gahJXRQ1vedXVPv61wyF3PzFmw8i+/cmfifDNB6ySc/u6YoVc6X1gogZ+wfv3EJxACwKFDuTG5COYqLAH4JVI4If7+kFqmenXahCGTIgWpELomKe7piAyJAPyn9Mgv7sor3/xAuCbgxEal+ONI/mXxD+pEjmefrkgNugTdR0ZuatAu2CrGF4LjHgReHkLE3Uh6J2HdWukO8kNCjUyzyDoPFhN6uumoyzcmVj+hRbvq1q1r5bK8vLw4GSEeZWKweKjgSVB+83t2/kEk/7/8d/UoBOW+0jx/1S9aqAlU3i8t8Mtb7hLPHIOkBl3e58FGMniWDooeLOr957+A7CUTRaSQUbvtymQ7GZc2uLnLWRZ1a6Zxz4wb1U0FIcilCae/NwaJJvQlfDQ7O9tKUvn5cbeX8GDXPlZsU0rWWdhM//fIiQIEb6BvI8dvLcn9i9tBiJuU4utKDs3xdidVsaAmgPLAUURLGy3g2aDEQwqSGrRwi83r0YRo4rEEbRacEMU9CBwFIZ8qcFyz2nhRQUS/QyMl9hCqCL3pqMH5Ewg0oWsrjBJMlGKNGtWtpJOfX5AoIyEeZ0sHElp0JHrAaqXoipKDX0QK2DpoCkB5vfTY30oO7RDT8+Ml1AQAsEEp/jiSYATAQ8DDREEoNegkF2GXDtrFgz1xeWdQlo2s7kE+ponkIUQC8sBRoT2ENTITH67lAOwbzMirCU1Mq1rV0ob4hYWJNZIQrsJpkRMnTet4j1K6AtPeHsdBebH02KUlB6ZGCt0fg3EUIh9E8icWH/iYtcKRGGoCAHivNH8beu3qpWOQ1CCT+3hvJGMbChZlmYXzu9iCwQbr8BSEvjoJzbeTQS393SG0IEwYMqriQfPx04RaJ2HFQRSSakKI/8CmpFgS/yUlVueCyGVhPkRmRU6YXPBD5DhC6/copU+XHhlTfOCF0qOrlCK78XuFoMyKnHio9PCY4gNvleYfwXS2gSgEvAmQB456OezwyIfUICe4Lh3EEywqK6grjZtpnM/5UbjsOMoEu0fbVbrX0Zanju6yV4MZ6SlVUwU+u8lKyKgK75MJARzu5Om8y7t7WFhtkcrjkTWs/Hfffd/KvZGIvakgw61iBxUz3vD20dIjj5YeYZggcwvjcQQiX0aOfxk5Xg1CnUMp7ULJzUJVGoaSakI4MxSuCqEwQAlAIUSOKsoBKN2tlG5Viv9QijcqJe5dW7bwrE48zgtVE3hZcABYrxQP8TZHi3j5BYrUIKv7ArV0kHfi5B5EboMthBQPzvRYEBDaPQgAWRk2QkZJE+rvxq0JofJR42+99Q7rTKJ5KSDUuRQCUQDKAuXkAgX1ZiRyQ02AAdGlIJAatHGLzesxLR1EFiwqBoE6akIL/zWEfvQYi8cPyncERd1aYgvClesP2roe56ajkKjNjKNGrdyZMF92saNeho/yAHkEKUEQIuLxwMLJMUhq0PItNq/nqQbtgi/uUQD3IL5K8w5RN5URd6bHVRPWrSnwFqMA8O2MrbwfRiSakM+dAEznK5w0IclCgiCEw3spiDxMlNSgWzB55KQJFsWAiO5B8EgQcgp4YJGs905CrgjtIdywLW/Dtjy7dzloQek1ITB1FfLA42eHZCFBEI7xfgCRPEwU5FSDqJYOojLGS6R1D/I3zSsPoYeVbDFelAnYAkeFPoTw2xlby37CNPBV5MK02cyiRs3vtJ41+vBR72Whp/kRBCE+3ktBycNEQQA16CQXkYNFER48SHvJeI+oIaMqvjsJsSHupjLHT5T8Nn9Xxb85a0JPoxZ9uLM8AXblJFchQRCBghyDBkmJpgYd5oVs6SDXcyZoLxmVwO4lE8VDQYi4D0mzu4y4awh/mbuj8ETlE+fwaULH70LShGbJ+uEqJFlIEEQ8fJGCpAY53CfDRjKolg46y8T2DZ67B2XyDDlGbA8hxPQAL+NFXcJDE4q7hvDb6VsTX8QafzVh4qjReHfazRq9JgQ/PjqSLCQIQocvwwK/DEkN2r/FaWZ8QLV0EJzUj/BNYB2h3YPgtSDk9AHM78BRJN03Iz05TcxT6dduzt280+jAbv5DoTB+Qnd9jO3Wo9K4CoFkIUEQAOCfFOTnGGS4aJDBhqKSqsFALR3E/KqU1j3ooWnCewiRgCFwVNwdZczcg6QJ2dwMQK5Cs0xJFhJEQPHr8SfHIL9b5VCDqIJFvdlqXdz3sLiWR/FcEErqJHSeKbtnTNAdZQqOF89YuMvsCtKEbG4GEEcTkiwkCII3PkpBUoP8bg2mGsTn5vLOHt/dg6IHi6r4EWGoAIS4JOx+AaECSsipcYoCIT7lskhCD+HOvccef33x/kPHj+YXFRVHIqZd2G5Z4tXbS/cN6dqutsmNP8/dcaKoNEHqNvuMg3Z00HyKooQcNXm0NEOv+Cq6enD6e2O0qwoT3+wUx2Yb2gK8nmbfHih1MsGqigiCQIiPn36EkIJAatD8FsHVIM5gUXGPmpADIZecGSJun3A08TWQBQk9hHOW/blm0yFOVhlqsJzO9czVIAB8M43LdjJutL2NXFxrQke5ItKEwPELT9lDTbKQIAhWSCkFgdSgeiPOIwc5g1INihEsSu5BLWF/ejaup6kS4uwuo8+sXiIP4aJV+7gZY0AoBNeN72R+zeqNh7bvOWopOf7f8Jx+nRI1dlSI8FHwL4IUKIiUICTCx8eZ9yDGNkw0UGrQi8hMlO44ngQoWJQXfpgWBr8qBXFDuMFHl3cdUw/hiZOly9cfsJWgy4FyUK9Gp7TINr9lyvQttjLgTaA0IbBeUshbFvoFyUKCEBp/H2HeUhDXokGQWQ06gYJFueWC4bWMwQZWyLPL6KJJzE4gFHR3GXMP4fI/9hcXmy8bZGBVtOrC4dA1F3Q0v/hoftGMhXvsZuDMHhu3eKsJT7N4GqFxrs7yrJwG0/FMVlch+D2nJAjCAb5LQVEcg0Bq0MottHTQwk22bxA2WJQXPlVIOPqTL/mjRcTAUfM1hAucxos6G6GG92/avFGW+ZU/zd5RVFxqu7qk04SuQKkJSRYSBOEv0ktBUoNlN5Ia5JO+I8QIFkVtg3/lqvAQopbLwcBN38pIT06rarZF0MKVf7nPxSLJVcJXje2Q8LIpJscPmkOasFKuDEYQ5pMn3hXh78tAKcdPIwiCiAHDs8k7c+ZSkM2iQVKDlW8QHczBom4zxbyXjB+oFeJ3yCjiChXLSWh+5sTeAwU79x6ruIHzh6tzhzRvUKea+TXL/zgQNcmD6pJcEwK5Cv3B96knQRAqGB5Gcgx6eTdeNWgfbO5Bb4JFHUN7yTDNs3ypl+FvPbaFfZIImtvbNbKKebzoQtf7i1o3LDUl6crzbbsHeQeOAmlCi2mwNt4DV6HvzzsGpwRBBBMkT58HAxHz5EkNWroF37ai0gSL0l4ylRPlkKYd9B5C1NLZDowGOh9qw5nl5h7CBeXxom5ysXjL2DNa16xe1fyaI8dOzlqi306GNCG4HxACqQkBhywEHD4KgggISB43bwYfUoOVbiQ1yC19Z7c4gIJFMaCtkFBmpn7nDw+O8zbAXZ7aLUZzJpRtMcrqTGk3FeLMBgd31apRtVWTGtlZqTWyUmtkpWZnVc3OSq2RmZpdPTWzWsq423/IP17sPqOE11dLS578/DmZ1VLML/t06oZXPl3tLIuYG2xe76hBnbaj1dtmaPYXPe2Kr9z2XFY9n/Wx7B6MLHhOkqdD7QmCExh0oEpwpSCQGjS+x97lnNWgkyy8Chb1xT2IVxAikMcG25AooPigCRX2s0VF8X926MwGB3cdOnzi0OG/7Fai3YwSXn/huW0TqkFFgSnTt9nINUFytnuOgx7utB0VZ6rA7dOgPuOuO79j++MmCACcZaE6Uvv+4INm1kLKkCCYgEcHgphSEHA4Bt0kIJMa9ABSg5VuR6sGcWC8qQwFjlZKRJzAUQ8wMax6Zur4s9omTGHJ2n179uU7SD++TfZvcZCJ57GjSMJHKYLUJUjWOBGEoGB7gsSNEcWgBt282vCePg+O1rDgCxb1BnGDRXmBo0L83mVUC+rGcm6c9zuO2ruB3Sh22ah26aZHX6hMmZbgtAkPNKGzBvV+jxkMmhD4rCoMmiwENEueCEIUsD0ynklBChM1uNdDNejBIRMI1aDEO4uitgGHGgQTQUg7jvpug2f7kjCporo1084/vVXCy3KPnJi7bK83JiXIgjShrWQ4NIlH321RykJU01yCQAXCZ8SzYQRvmCiQGmSGB0sH7ULBorxtwEO82jDzEKJ2sHqO3IGj7gPNrzivQ0pyUsIbp87cXlIa4WGSN5uOgqCaEHH4aDBlIaCc9RKEj+B8IryUgqjDREkNxr/H3uUefO/GZ5LHGVXKFLOWwWQappBRFXISssjNizw0mTSul3Hu4BZWbvl2xjZnWVi7web1wdGEbJIAENlVCChlIeCLiyMIj8H5CHg5XEjsGHSZAKlBrEsHKVjUfaIc0kycZ9xcEwhC1MLaDsHbXcaLwNHoLVeP7ZiUlHgrxYWr/vrrQAFfq0gT8k0CgJsmJFmIc1pMEJxA2+c9loKkBuPeS2pQoqWD4roH8Q1RDjGvjcQeQh9UkM0MDQ8h5IQvu8tg1oQA0KpJ9dP7NbVy5TfTtnjRnQTUhKdd8VX0Z+2ZhPp7nWTIPAkAbl/0SRaCZpaMcKJMEC5B3r3lkIKkBm3fxV8NOoCWDrq5EZD7tPCZhi9kVIUCRxndyDsjRYFrx3WyctDagbzC+Sv3gjfxDwJqQqv3un842E1D+MlCz0ArC1UwT50Jwjr4e7LHQ4EAUtBdSi4TkE8NerCRjHxLBzEMGEEIFlWxJAhRi2w7iBs46hTupnZoXXNAj4ZWrvxuxrbS0jJ7SBO6fHPjcRWC+BGkgF4WggjzaYKIRYh+670URB0jCv47BkkNeqAGnYL6WdYi1FydO1Zqw6qHEH/gqJdQ4GiU68d3tnJZRFG+n7nNriVa5NOE4NpV6BbcmhBIFhohxAybCDii9FI5pCDIpQad3ujoLpRq0AFSLh3EECwqjXvQCjZCRuXQhBjeUNJowp4d6/bsWNfKlfOX791/6Hhlmzz5AEaaMGESuMNHgWRhHESZcxPBQaA+KZMUxBMmCqQGY+/gPwkhNcgJDDYwwWKPwrqGED3SO6OtPAkW3YMAMGX6VoMsSBOW3eirJmSWCgA3VyF4/k1NnS8K8T5AvksHITdidT9fnmt+uaFyDLpMg9RgeSbce6cIT6orUM/PffCsWc3SniAkJ2GldKQOHE3IwJ4NO7SuaeXKfYeOL1j1l+GfSBOW3+hKE2ILH5XDVViWqSCyUEWs2TkhKCJ2M18eZDEcg8DGMUhqUH+HJxMPzEsHKVg0JlEOaSbI0EaWtj2EpAl9twFD4Gg4FLrmgk4W0/l2xtZIJG5apAmZgCp8FDi7CkkWWkHEWTuBFnG7k2RSEJg7Bn0NEwVSgxWZeDEXomBRUWzwnip+G+AbigJWDktIkAgoIXCdincoYNPaeLV0er8mrZtWt5JCJKJ8//u2RGbZrkYmzZc4F0ft641tBvnabV2OqQCUv+ZDfOpCHa49ruboS8KX9nWDdsrFqUUI+RBO+2kR+NucSeJsS+V3mCgIoQYd5BJ4NegXFCxaOUN7WToRhD6oIHaTVOa4qQ3HysFLyRGbV5Wk8NUXdLR4++ylfx46fCJxLh50Kke9iDSh28Skk4VQ/loVVFiROCRMEFoEqpAUtJaiz2m4WijhpRrk350Qq0GHULBoTKIc0kyQoe0sHW4qg1qFWwbDiw9/4GhsXucMat64XobFe6dM3+IgRyt4EzgKfsSOolhSyPZLNM+HzZcgUhAzjlSHuHGABEOk6QZ+PZK8hyD2jkEWYaKkBo3v8EBAemcVBYsGCOcho177CSV1EoIPfkJXVZmSnHTlmA4WL957oGDJmv0WL/YocNRbPyE49SMpiuLGexM0VyH4N0KIG0eqQzdFI+ehxIgu/HT4WxqRpCD47xgEz8NEAbcaROxfEUkNIq5GMdyDINgaQg4zPlahfcFZTHj+6a3q1kyzeNe3M7ZG7Dzl8mlCcCX4cWhCYCwLuWpC8O/DkdBxpLGQPpQJyRRgFImlIPBwDCJIhtRg5UzQBouKNGJQsGjlDB1m6UoQiqaCjPFruRcTGzxeTJieVuXy0e0sXl9SGvluxjbbuZAmrHSjW00IgXQVgt+yECRShiqx0ziSiGiRVf5F8b18gklBQOEYBFKD+kzQqkGHULCo77jRxm49hBQ4GiUIgaMTz25bPTPV4sWzFu/JO3oS7M+MSRNWvtGtfELrKgR5ZSHIqwyjkEREgvTyLwqGggZTCrpPxvtFg0Bq0HnVUbAoIxCbFotQIaMqFDgam68nmjArI+XCc9tav/6b6VvLsrFvHmnCmHsRhI+yTKg8PZ4RpIBAFoJ0oaQmGM75SCUyJDjaTweGcntgAqlBo3ud3hh4NegUT9WgSyhYtHKGrrJkIAgpcFRkG2xM8C8Z2a5aWrLFi3ftPbZsXcV2MqQJy270VRNCIF2FgEkWQjCUoRZSic4IrPbTgqQOSAq6SoHUoD4Tj9SgEEsHMTzjGGxwj3ttzMZDSIGjUUQLHAWLtVmrRtVxZ7a2nui3M7a5f8ZIE8bc69afhtlVCJ7IQvB78AisMtRiMkcMlFYk1WcIklrxxgoufYDUoKPbbN/hiRp0hpdqkIJFDUBsWjwEDBlVkTdwFOcGM1ee3yE1JcnixcXFkamztut+6cw85JoQADw+th7LkkKWCWmS5C8LAYfDEEgZxsHKDFII0Uhizy54KkxgKQhY1KDL0jn0iTm2GrEapI1kjG+nYNFKGTLIkpkgpMBRDHBaTNiwTrVRQ1tYT27G4t1Hjp00yEY6TQhOe77LdWWyho+Wpcp5YWFZLgCAQBYCKUP7kNaSCVSN6Zkt5BiMf6/TG0kNOr1Fvc/JPZgeXgeIbr8KK20cZpKKitfeW04f11gk67Iq/OijZllefUHHKkk2usqUaVvjZuNV0Zxk5Pl7yE1tuJ9PMGsKhf3DqCiKN5N+DrY7R1HK/iMI6cHW2z0bCrgMbuysJzWY+A7E0xgv1aAbkLgHuYDYNHNYCkIfUAAAciZMiv5i0aQJvhlTGb80oZuh2PC3zRtlnTmgqfVUtu85unLDAbNsEH9ac/xadakJf39/bPQ3Qy7/0vK9DDQhS1nImmDKQsA3VyYIViDs22JLQWApBYOlBh0V2LNYVuTbigIFixonyiHNBBkyy5KxIESt2i2D6l3lALaa8LrxncJ2Qtm+nb41oQGoNSH4owmd3stghoHZVQiey0JUT3909iz6oEQ4oEoVYRf5VwZnN/byeecoBTE5BgVTgw5uwq0GhdhIBgmi26/CVnOx9xBS4GhFIv4FjrLq66e0yB7Su5H1608Wlf4we4eVK0kTMgSRJmScVgXDh58++YtPF8yfNWnSR8OGncYlj3KwycLatWvVr1+P7ZR69OiRkydPmjdv1jffTJ44cTybRIlE1K5dq169eiYX1KhRY+jQIXfeefsHH7w7ffovF198IcPEPQahCFTRPuDnjR751ZeTFsyfNeWbyRdeyP5B4Pg9i12q/joGQVI1OGbMqO++m7xs6dyffvjmkosn8svIzV3O8HF2itrt5LX6YZyfFB8gUXcPf3YcdYGi3Wjjhgmdbd08feGuYwVFVnPy5HBCZxmpmXl5HIVLmJxIAQw3IGWWFgDAgAH9H33kQfXn5s2aPfH4I7fm37lw4SJmGRjBuhDOefTRh7p373bs2LEtW7Zu2rR59uy5ixYtVv/krM3POmv43Xffpf5cr16922675cSJE9988y0rg4l4PPJIRVNu3lzWlNnZ2Tk5vbt169q9e9dmzZpprz/11P4ff/ypm8SZF8EchPJPi866s88afs89ZQ9C/fr1br/tlsJCZg8Cx7gGTFIQfAoTBdxq8Nxzzrz/vrvVn+vXr/d/d95WWHjiy6++YZ6Rm7u8nz0jUYNyBIsyh8saQtQK3jKseoy4iwm7tauT08Xe9+Yp0+NuJ2OcE/kJ2YErfBRYOtouveQi3W+uuOJSNkknwndvYZ8+Od27dwOAzMzMbt26Dhw4YMeOCie8MyfM5ZdfpvvNRRfZ8EQRzojXlGPHnv/QQ/efd94onRpkkrg3oHUGRjF8kK+4Qv8gXGLHJWuWHT+vICY16FeYKOBWgwBw9dWX635z+WX6txiTjBzf5X2wKKlBphmyz5LXpjKkCTHgUhP+bUInW/ds3XVk9cZDtnMiTai71+WgiWqnGUbJtW/fTv+bdu28PHtA8UkZhkKhm266PvrP3NzcW265fd++/bFX2lqm1bixPg68QYP67iwlEhAKhW680bgpt27dunz5ij179pSUlDBPnB84VwbqMH9yeTwI+JcLskrMrzBRQK8GAaBJk8a63zRs2IBHRqKoQSSIbr8KJ4XFMWRUjpMJmeBj4Kjje/t1q9/1lNq2bvl62lbPYlyFiB0FR8fWg+tQYSbn+DkqtAGLFs1JeE1OnwHmF6SkpMT8JhnKZyReHlPucRzp0KGntW3bRv352LFjt9769127die8S/vOM6ybPXv26JxRf/31lxs7iYTomvK22yqacvr036dP/x0A0tLSpk//hW3ibBFoOmXF0t179jRn9yAIESPKKjHBFg2Cp2pQAWXX7j0tmlfqWnv3sh9jBVKDSNyDXEBsmi0EP3aCP6IHjjq7NxSCv4235x48cbL05zk7nGXn2c5djvNy8Q5yPvJi2H0UyUC3b98+3W8OHqzwRXu2DWlFjp5UTlJS0vXXX6v+XFh44o47/rF58xa7iRi6cd5//yPdZdYXqhEOSEpK+tvfKpry7383bsoTJ07wS9wxQngCo9h6NmMfhA8/cvIg8N05Bp9j0GWYqPRqEADeeed93e/fe/9jtnmRGvTYjDiJckgzQYa8suQrCD3T9DnjOR5FiOQt6OXTOLRPk7bNs23d8uv8nfnHi+1loyHImnDmBxWHEA6+rNIhhL6Hj4Lr4e6KK6599tkXVAeIlkgkMnPm7Ndef/OWW/+eMJENGzbpfrN582bdb7yXhcBZGZ577tlq3FFxcfFdd92zZs1alwlGp/U//PDTk0/+e8+ePxVF2bdv/wsvvEg7ylhn0KABP/74/SuvvGj9Fm1T/vOfcZvSWQe2mLh1tAoQyesvIc6eRN2D8Lz9B0EUKQimiQ0ePPDXX6a+/tpLiRMRLkwUfFCDAPDd9z8+8thTu/fsURTlr337/vvMCyY7yuB/ynxUg6xAYoZLuKoq7ruMUuBoFPdV4U1AZjgcunacPfcgAHwzrWI7GWd2OrwLfewouGt6JOGj4DROct26P9at++Pzz79csGCW9ve7d+/5x133WExk5apVQ4YM0v5mtemU2ssg0rJ8AYBpKGkoFBo79nwAiEQi9977wOLFS9ilDQAwZcp3U6Z8VzlHtjlISFpa2u233zpq1Ahbd4VCoTFjypryvvsYNyWTxIWeKrm0/Zsp331T+UGwmi/XWvNKCqanp91xx63njR5pKR1SgwmyqnTbV19N+eqrKbzy8tY96Bj3TwkFi3qGFMdO8IeVEvNRHlsvwjmDmjdtkGkr8Y3bD/+xJddZdgzuIk2Y4HY2GsnNqsJIJKL7zdGjx6ynuGLFKt1vVsb8Rou/shBYKENFUa688tqePXukpqbMmTPPdXpWcqz0T9KHOjp0aP/www80bqzfKyIhiqJcddW1PXv2SElJmTuXcVM6S1xoBajiYwkEkoLm6XXs2OHRRx6I3f7EIBH3CxACpgb55iVOsKhLKFi0coZ8s/RCEMrhJESiCXlvMJNcJXz1mI52U/76N4MlK6QJY+5TwMU2M+Buju67q1BHcXGR9RTXr99QUFBQrVo19Z8nT56M5yHU4pcsBEbKMBKJ2HX4hMPhWO3tDNKHUZKSkq644rKrrroiHHa4yMJBU7JNXFwFqOvS/pZDGimYlJR01VWXX3O1pS7tpWMwprld6UgnN/mhBsPh8CmntGnVsuWvv00/efKk4cXhcLhly+Yd2rebNn1Wfn6+ExsdQUsHkeCBp9QjD6HXmtCNLwM9XDXheae3qlc73VaahSdKfp2301l2LO/yWBMCuQrdJaId3BLVZ2lp6dJlywcNLNuMdNmyFUVFRfEubtmyxaiR5/bq1bNJkyZVq6bm5xfs3Llz3rwF30z5VrsVDQAsXDDbxMI+fQfGu0b9U5RwONyxY4fevXrm5PTesnXrc8/9r6SkpE2b1pdccmHvXr2ys2scPnx43br1P/7484wZvycUbC1bthg58tyePXtE7d+1a9e8efO/+UZvfzT3U05p26NH9x49uvfo0W3lytW3334nALRp0/qqq67o3btXamrKypWrn3nmuW3btmtvTElJad++XdeuXdq1O2Xy5K+WLVtuy54pMfUZY9UpOTm9cnJ6r1277rXX3ohEIunp6aNGjRg69LSWLVukpaUdOHBw2bLln302aeNG/RpRHRkZ1c4668y+ffu0adMmO7tGUlLSsWPHduzYuXjxku++mxq751DU8hEjzu3Vq0fjxk2qVk0tKCjYuTOx5ToaNWr40EP3d+qkj6Lv3r3b/PmV+ka/fgN11zAxIB4miR844DZxQxo2bHDGGaf36NGtefPmNWtmJyUlnThxYt++/du2bV++fMVPP/1y7NixeKa679IKQJs2ra++6orevXulpKasWrn6vzFdWs2olyajnaYZqagPQreuXdq1O+ULowdBUZRwONyu3Sl9cnrn9Om9ds26V159Xe3P540eOXTokFatWqr9eemy5Z9+OmnDho3mNRlvjPr66ynOOkbLli1GjdInODdOgo0aNXz0kQc6d9Z36R49ui2uvCl0r96nJsw6HA536tihd06vPn16b9my9ZlnXigpKWnbpvWll12c07tndnb24cOH1679Y+oPP02bZjz6hcPhdu3a9uzZo1fP7j16dF+5ctXNt/wdANq0bXXtNVf1yemVkpK6cuWqp//z7Nat27Q3tmrZYvToEb1792rapHHVqlXz8wt27Nw5d+78L7/8Jl41hsPh9u1P6dsnp0/f3mtWr3vxpVcVRalXr+7FF00YNGhAw4YNTp4sWr9+w9fffPfjj79Erc3Kypw4cdzQ0wa3bNk8FAr9tW//woWLP/nkc9Uek5l6akpKhw7tu3fv2r79KZM+/3LJkmXRP6Ukp3Ts1KFnj27du3ft1rWz+rnzrDOH3Xzr/1Vck5LcsWOH7t269OjetWvXLllZmQAwduzqyy6/LrZcHdqf0rdfTr++OatXr33hf2XluvSSiUMGl5Xrj/Ubvv7626k//Kwt10UXjh86dHCrli1CodBff+1bsHDxxx9P2lJezxIs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";

// worker.js
var APK_URL = "https://github.com/manzilionellm-dotcom/tvking/releases/download/latest/7motion.apk";
var TV_APK_URL = "https://github.com/manzilionellm-dotcom/tvking/releases/download/tv-latest/defew-tv.apk";
async function proxyApk(upstreamUrl, suggestedFilename, bust) {
  let response;
  let target = upstreamUrl;
  if (bust) {
    target += (target.indexOf("?") >= 0 ? "&" : "?") + "cb=" + encodeURIComponent(bust);
  }
  try {
    response = await fetch(target, {
      cf: {
        cacheEverything: true,
        // Sans bust : APK (200) en cache 5 min (perf), erreurs non cachees.
        // Avec bust : on ne cache (presque) rien -> toujours frais.
        cacheTtlByStatus: bust ? { "200-299": 1, "300-399": 1, "400-599": 0 } : { "200-299": 300, "300-399": 10, "400-599": 0 }
      }
    });
  } catch (e) {
    return new Response(`APK upstream unreachable: ${e?.message ?? e}`, {
      status: 502,
      headers: { "Content-Type": "text/plain; charset=utf-8" }
    });
  }
  if (!response.ok) {
    return new Response(`APK upstream returned ${response.status}`, {
      status: 502,
      headers: { "Content-Type": "text/plain; charset=utf-8" }
    });
  }
  const headers = new Headers(response.headers);
  headers.set(
    "Content-Disposition",
    `attachment; filename="${suggestedFilename}"`
  );
  headers.set("Content-Type", "application/vnd.android.package-archive");
  headers.set("Cache-Control", "public, max-age=300");
  return new Response(response.body, {
    status: 200,
    headers
  });
}
__name(proxyApk, "proxyApk");
var TRIAL_DAYS2 = 7;
var DAY_MS2 = 24 * 60 * 60 * 1e3;
function computeStatus(client, now = Date.now()) {
  if (!client) {
    return {
      exists: false,
      status: "unknown",
      paid: false,
      trial_until: 0,
      days_left: 0,
      expired: false,
      frozen: false,
      banned: false
    };
  }
  const status = client.status || "active";
  const paid = client.paid === true;
  const trialUntil = client.trial_until || (client.added_at || now) + TRIAL_DAYS2 * DAY_MS2;
  const daysLeft = Math.ceil((trialUntil - now) / DAY_MS2);
  const expired = !paid && trialUntil <= now;
  const plan = client.plan || (paid ? "lifetime" : expired ? "expired" : "trial");
  const paidUntil = client.paid_until !== void 0 ? client.paid_until : null;
  return {
    exists: true,
    status,
    paid,
    plan,
    paid_until: paidUntil,
    trial_until: trialUntil,
    days_left: Math.max(0, daysLeft),
    expired,
    frozen: status === "frozen",
    banned: status === "banned"
  };
}
__name(computeStatus, "computeStatus");
async function getTrialDays(env) {
  return configuredTrialDays(env);
}
__name(getTrialDays, "getTrialDays");
async function touchTrialAnchor(env, mac, androidId) {
  if (!env.DB || !mac)
    return;
  try {
    const dev = await env.DB.prepare("SELECT first_seen_at FROM devices WHERE mac = ?").bind(mac).first();
    if (!dev)
      return;
    let aid = androidId || "";
    if (!aid) {
      try {
        const row = await env.DB.prepare("SELECT android_id FROM devices WHERE mac = ?").bind(mac).first();
        aid = row && row.android_id || "";
      } catch (_) {
      }
    }
    await rememberTrialStart(env, mac, aid, dev.first_seen_at);
  } catch (_) {
  }
}
__name(touchTrialAnchor, "touchTrialAnchor");
async function finishStatus(env, base, now) {
  if (!base || !trialEnforcementOn(env))
    return base;
  const copy = await loadBlockCopy(env);
  return shapeEnforcedStatus(base, now, copy);
}
__name(finishStatus, "finishStatus");
async function d1StatusForMac(env, mac, now = Date.now()) {
  if (!env.DB)
    return null;
  let dev;
  try {
    dev = await env.DB.prepare("SELECT id, first_seen_at, block_status FROM devices WHERE mac = ?").bind(mac).first();
  } catch (_) {
    return null;
  }
  if (!dev)
    return null;
  if (dev.block_status === "banned" || dev.block_status === "frozen") {
    const banned = dev.block_status === "banned";
    return finishStatus(env, {
      exists: true,
      status: dev.block_status,
      paid: false,
      plan: banned ? "banned" : "frozen",
      paid_until: null,
      trial_until: now,
      days_left: 0,
      expired: false,
      frozen: !banned,
      banned,
      source: "d1-block"
    }, now);
  }
  const lic = await env.DB.prepare(
    `SELECT status AS lstatus, expires_at FROM licenses
       WHERE device_id = ?
       ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`
  ).bind(dev.id).first();
  if (lic) {
    const lstatus = lic.lstatus || "active";
    const lifetime = lic.expires_at === null || lic.expires_at === void 0;
    const expiresAt = lifetime ? now + 36500 * DAY_MS2 : lic.expires_at;
    const dateExpired = !lifetime && expiresAt <= now;
    const banned = lstatus === "banned";
    const frozen = lstatus === "frozen";
    const revoked = !banned && !frozen && lstatus !== "active";
    const active = lstatus === "active" && !dateExpired;
    const expired2 = dateExpired || revoked;
    if (!active && !lifetime && !banned && !frozen && !revoked) {
      const ext2 = await readExtendedUntil(env, mac);
      if (ext2 > now) {
        return finishStatus(env, {
          exists: true,
          status: "active",
          paid: false,
          plan: "trial",
          paid_until: null,
          trial_until: ext2,
          days_left: Math.max(0, Math.ceil((ext2 - now) / DAY_MS2)),
          expired: false,
          frozen: false,
          banned: false,
          source: "d1-trial-extend"
        }, now);
      }
    }
    return finishStatus(env, {
      exists: true,
      status: banned ? "banned" : frozen ? "frozen" : revoked ? "inactive" : "active",
      paid: active,
      // licence active = debloque l'app
      // plan pour l'affichage app : 'lifetime' (à vie, expires_at NULL)
      // sinon 'paid' (abonnement à durée) ; paid_until = fin (null=à vie).
      plan: lifetime ? "lifetime" : "paid",
      paid_until: lifetime ? null : expiresAt,
      trial_until: active ? expiresAt : now,
      days_left: active ? lifetime ? 36500 : Math.max(0, Math.ceil((expiresAt - now) / DAY_MS2)) : 0,
      expired: expired2,
      frozen,
      banned,
      source: "d1"
    }, now);
  }
  let trialStart = dev.first_seen_at || now;
  let trialDays = await getTrialDays(env);
  if (trialEnforcementOn(env)) {
    let aid = "";
    try {
      const row = await env.DB.prepare("SELECT android_id FROM devices WHERE mac = ?").bind(mac).first();
      aid = row && row.android_id || "";
    } catch (_) {
    }
    trialStart = await rememberTrialStart(env, mac, aid, trialStart);
    trialDays = TRIAL_DAYS;
  }
  const win = trialWindow(trialStart, now, trialDays);
  const ext = await readExtendedUntil(env, mac);
  const until = combineTrialUntil(win.trialUntil, ext);
  const expired = now >= until;
  const base = {
    exists: true,
    status: "active",
    paid: false,
    plan: expired ? "expired" : "trial",
    paid_until: null,
    trial_until: until,
    days_left: expired ? 0 : Math.max(0, Math.ceil((until - now) / DAY_MS2)),
    expired,
    frozen: false,
    banned: false,
    source: ext > win.trialUntil ? "d1-trial-extend" : "d1-trial"
  };
  if (trialEnforcementOn(env))
    base.trial_started_at = win.start;
  return finishStatus(env, base, now);
}
__name(d1StatusForMac, "d1StatusForMac");
var _scaleSchemaReady = /* @__PURE__ */ new WeakSet();
var _presenceReady = /* @__PURE__ */ new WeakSet();
var _trendingCache = /* @__PURE__ */ new WeakMap();
var _SPORTSDB = "https://www.thesportsdb.com/api/v1/json/3";
var _sportsTeamCache = {};
var _sportsSearchCache = {};
async function ensureScaleSchema(env) {
  if (!env.DB || _scaleSchemaReady.has(env.DB))
    return;
  for (const col of [
    "device_model TEXT",
    "android_build TEXT",
    "android_release TEXT",
    "app_build INTEGER",
    "platform TEXT",
    "android_id TEXT",
    "app_version TEXT",
    "local_sources_json TEXT",
    "recent_json TEXT"
  ]) {
    try {
      await env.DB.prepare("ALTER TABLE devices ADD COLUMN " + col).run();
    } catch (_) {
    }
  }
  for (const idx of [
    "CREATE INDEX IF NOT EXISTS idx_presence_lastseen ON presence(last_seen)",
    "CREATE INDEX IF NOT EXISTS idx_presence_channel ON presence(channel)",
    "CREATE INDEX IF NOT EXISTS idx_devices_lastseen ON devices(last_seen_at)",
    "CREATE INDEX IF NOT EXISTS idx_devices_androidid ON devices(android_id)",
    "CREATE INDEX IF NOT EXISTS idx_devices_reseller ON devices(reseller_id)",
    "CREATE INDEX IF NOT EXISTS idx_licenses_device ON licenses(device_id)"
  ]) {
    try {
      await env.DB.prepare(idx).run();
    } catch (_) {
    }
  }
  _scaleSchemaReady.add(env.DB);
}
__name(ensureScaleSchema, "ensureScaleSchema");
async function recordPresence(env, mac, ip, country, now, channel) {
  if (!env.DB)
    return;
  try {
    if (!_presenceReady.has(env.DB)) {
      await env.DB.prepare(
        "CREATE TABLE IF NOT EXISTS presence (mac TEXT PRIMARY KEY, ip TEXT, country TEXT, last_seen INTEGER, channel TEXT)"
      ).run();
      try {
        await env.DB.prepare("ALTER TABLE presence ADD COLUMN channel TEXT").run();
      } catch (_) {
      }
      try {
        await env.DB.prepare("CREATE INDEX IF NOT EXISTS idx_presence_lastseen ON presence(last_seen)").run();
      } catch (_) {
      }
      _presenceReady.add(env.DB);
    }
    const chan = channel === void 0 || channel === null ? null : String(channel).slice(0, 120);
    await env.DB.prepare(
      "INSERT INTO presence (mac, ip, country, last_seen, channel) VALUES (?, ?, ?, ?, ?) ON CONFLICT(mac) DO UPDATE SET ip = excluded.ip, country = excluded.country, last_seen = excluded.last_seen, channel = excluded.channel"
    ).bind(mac, ip, country, now, chan).run();
  } catch (_) {
  }
}
__name(recordPresence, "recordPresence");
async function handleTrending(env) {
  if (!env.DB)
    return json2({ items: [] });
  const now = Date.now();
  const cached = _trendingCache.get(env.DB) || { at: 0, items: [] };
  if (now - cached.at < 6e4) {
    return json2({ items: cached.items });
  }
  try {
    const since = now - 15 * 60 * 1e3;
    const rs = await env.DB.prepare(
      "SELECT channel, COUNT(*) AS n FROM presence WHERE channel IS NOT NULL AND channel != '' AND last_seen >= ? GROUP BY channel ORDER BY n DESC LIMIT 25"
    ).bind(since).all();
    const items = (rs.results || []).map((r) => ({
      channel: r.channel,
      count: r.n
    }));
    _trendingCache.set(env.DB, { at: now, items });
    return json2({ items });
  } catch (_) {
    return json2({ items: cached.items });
  }
}
__name(handleTrending, "handleTrending");
async function handleSportsSearch(url) {
  const q = (url.searchParams.get("q") || "").trim();
  if (q.length < 2)
    return json2({ teams: [] });
  const key = q.toLowerCase();
  const now = Date.now();
  const c = _sportsSearchCache[key];
  if (c && now - c.at < 6e5)
    return json2(c.data);
  try {
    const r = await fetch(
      `${_SPORTSDB}/searchteams.php?t=${encodeURIComponent(q)}`
    );
    const j = await r.json().catch(() => ({}));
    const teams = (j && j.teams || []).slice(0, 20).map((t) => ({
      id: t.idTeam,
      name: t.strTeam,
      badge: t.strTeamBadge || t.strBadge || "",
      league: t.strLeague || "",
      sport: t.strSport || ""
    }));
    const data = { teams };
    _sportsSearchCache[key] = { at: now, data };
    return json2(data);
  } catch (_) {
    return json2({ teams: [] });
  }
}
__name(handleSportsSearch, "handleSportsSearch");
async function handleSportsTeam(id) {
  const now = Date.now();
  const c = _sportsTeamCache[id];
  if (c && now - c.at < 6e5)
    return json2(c.data);
  const mapEv = /* @__PURE__ */ __name((e) => ({
    id: e.idEvent,
    name: e.strEvent || "",
    home: e.strHomeTeam || "",
    away: e.strAwayTeam || "",
    homeScore: e.intHomeScore === null || e.intHomeScore === void 0 ? null : String(e.intHomeScore),
    awayScore: e.intAwayScore === null || e.intAwayScore === void 0 ? null : String(e.intAwayScore),
    date: e.dateEvent || "",
    time: e.strTime || "",
    timestamp: e.strTimestamp || "",
    // ISO UTC (pour programmer les alarmes)
    status: e.strStatus || "",
    league: e.strLeague || ""
  }), "mapEv");
  let last = [];
  let next = [];
  try {
    const r = await fetch(`${_SPORTSDB}/eventslast.php?id=${encodeURIComponent(id)}`);
    const j = await r.json().catch(() => ({}));
    last = (j && j.results || []).map(mapEv);
  } catch (_) {
  }
  try {
    const r = await fetch(`${_SPORTSDB}/eventsnext.php?id=${encodeURIComponent(id)}`);
    const j = await r.json().catch(() => ({}));
    next = (j && j.events || []).map(mapEv);
  } catch (_) {
  }
  const data = { last, next };
  _sportsTeamCache[id] = { at: now, data };
  return json2(data);
}
__name(handleSportsTeam, "handleSportsTeam");
async function ensureD1Device(env, mac, now = Date.now()) {
  if (!env.DB)
    return;
  try {
    const dev = await env.DB.prepare("SELECT id FROM devices WHERE mac = ?").bind(mac).first();
    if (dev) {
      await env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(now, dev.id).run();
      return false;
    }
    const cid = "cus_" + crypto.randomUUID().replace(/-/g, "").slice(0, 18);
    const did = "dev_" + crypto.randomUUID().replace(/-/g, "").slice(0, 18);
    await env.DB.batch([
      env.DB.prepare(
        "INSERT INTO customers (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)"
      ).bind(cid, "Auto " + mac, now, now),
      env.DB.prepare(
        "INSERT INTO devices (id, customer_id, mac, first_seen_at, last_seen_at) VALUES (?, ?, ?, ?, ?)"
      ).bind(did, cid, mac, now, now)
    ]);
    return true;
  } catch (_) {
    try {
      await env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE mac = ?").bind(now, mac).run();
    } catch (_2) {
    }
    return false;
  }
}
__name(ensureD1Device, "ensureD1Device");
async function updateDeviceInfo(env, mac, body) {
  if (!env.DB || !body)
    return;
  try {
    const model = (body.model ? String(body.model) : "").slice(0, 80);
    const build = (body.build ? String(body.build) : "").slice(0, 120);
    const release = (body.android ? String(body.android) : "").slice(0, 20);
    const appBuild = parseInt(body.appBuild, 10) || 0;
    const androidId = (body.androidId ? String(body.androidId) : "").slice(0, 32);
    const appVersion = (body.appVersion ? String(body.appVersion) : "").slice(0, 24);
    const platform = body.platform === "tv" || body.platform === "mobile" ? body.platform : "";
    let srcJson = "";
    if (Array.isArray(body.sources)) {
      const list = body.sources.slice(0, 5).map((s) => ({
        type: s && s.type === "m3u" ? "m3u" : "xtream",
        name: (s && s.name ? String(s.name) : "").slice(0, 60),
        server: (s && s.server ? String(s.server) : "").slice(0, 200),
        username: (s && s.username ? String(s.username) : "").slice(0, 80),
        channels: Number.isFinite(s && s.channels) ? s.channels | 0 : 0,
        active: !!(s && s.active)
      }));
      srcJson = JSON.stringify(list);
    }
    let recentJson = "";
    if (Array.isArray(body.recent)) {
      const ids = body.recent.slice(0, 50).map((x) => String(x || "").slice(0, 80)).filter((x) => x.length > 0);
      if (ids.length)
        recentJson = JSON.stringify(ids);
    }
    if (!model && !build && !release && !appBuild && !platform && !androidId && !appVersion && !srcJson && !recentJson)
      return;
    await env.DB.prepare(
      "UPDATE devices SET device_model = CASE WHEN ? != '' THEN ? ELSE device_model END, android_build = CASE WHEN ? != '' THEN ? ELSE android_build END, android_release = CASE WHEN ? != '' THEN ? ELSE android_release END, app_build = CASE WHEN ? != 0 THEN ? ELSE app_build END, android_id = CASE WHEN ? != '' THEN ? ELSE android_id END, app_version = CASE WHEN ? != '' THEN ? ELSE app_version END, platform = CASE WHEN ? != '' THEN ? ELSE platform END, local_sources_json = CASE WHEN ? != '' THEN ? ELSE local_sources_json END, recent_json = CASE WHEN ? != '' THEN ? ELSE recent_json END WHERE mac = ?"
    ).bind(
      model,
      model,
      build,
      build,
      release,
      release,
      appBuild,
      appBuild,
      androidId,
      androidId,
      appVersion,
      appVersion,
      platform,
      platform,
      srcJson,
      srcJson,
      recentJson,
      recentJson,
      mac
    ).run();
  } catch (_) {
  }
}
__name(updateDeviceInfo, "updateDeviceInfo");
var ADMIN_PANEL_HTML = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>BLACK7 ROYAL \u2014 Panel admin</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #0A0A0C;
      color: #F0EDE9;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      min-height: 100vh;
      padding: 24px;
    }
    h1 {
      font-size: 22px;
      letter-spacing: 4px;
      font-weight: 700;
      margin-bottom: 4px;
    }
    .tagline {
      color: #7E7872;
      font-size: 11px;
      letter-spacing: 2px;
      margin-bottom: 28px;
    }
    .card {
      background: linear-gradient(180deg, #14141A 0%, #0E0E12 100%);
      border: 1px solid rgba(214, 58, 48, 0.25);
      border-radius: 14px;
      padding: 20px;
      margin-bottom: 18px;
    }
    label {
      display: block;
      font-size: 11px;
      letter-spacing: 1.5px;
      color: #B6B0A8;
      margin-bottom: 6px;
      text-transform: uppercase;
    }
    input[type="text"], input[type="password"], textarea {
      width: 100%;
      padding: 12px 14px;
      background: #1C1C24;
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 10px;
      color: #F0EDE9;
      font-size: 14px;
      font-family: inherit;
    }
    input:focus, textarea:focus {
      outline: none;
      border-color: #D63A30;
    }
    button {
      padding: 10px 16px;
      background: #D63A30;
      color: #050507;
      border: 0;
      border-radius: 10px;
      font-weight: 700;
      cursor: pointer;
      font-family: inherit;
      font-size: 13px;
    }
    button:hover { background: #FF5A4A; }
    button.ghost {
      background: transparent;
      color: #B6B0A8;
      border: 1px solid rgba(255,255,255,0.12);
    }
    button.ghost:hover { color: #F0EDE9; border-color: #D63A30; }
    button.danger { background: #8E1F1D; color: #F0EDE9; }
    button.danger:hover { background: #B02E2A; }
    .row-actions button {
      margin-right: 6px;
      margin-bottom: 4px;
      padding: 6px 10px;
      font-size: 11px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      padding: 12px 10px;
      text-align: left;
      border-bottom: 1px solid rgba(255,255,255,0.06);
      vertical-align: top;
    }
    th {
      font-size: 10px;
      letter-spacing: 1.5px;
      color: #7E7872;
      text-transform: uppercase;
      font-weight: 600;
    }
    .mac {
      font-family: monospace;
      color: #D63A30;
      font-weight: 700;
    }
    .badge {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 10px;
      letter-spacing: 1px;
      font-weight: 700;
      text-transform: uppercase;
    }
    .badge.active { background: rgba(95,169,117,0.18); color: #5FA975; }
    .badge.frozen { background: rgba(214,152,71,0.18); color: #D69847; }
    .badge.banned { background: rgba(232,74,62,0.18); color: #E84A3E; }
    .badge.paid { background: rgba(214,58,48,0.18); color: #D63A30; }
    .badge.unpaid { background: rgba(126,120,114,0.18); color: #7E7872; }
    .filter-bar {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-bottom: 14px;
    }
    .filter-bar button {
      padding: 6px 12px;
      font-size: 11px;
      background: transparent;
      color: #B6B0A8;
      border: 1px solid rgba(255,255,255,0.10);
    }
    .filter-bar button.active {
      background: #D63A30;
      color: #050507;
      border-color: #D63A30;
    }
    #empty {
      padding: 40px;
      text-align: center;
      color: #7E7872;
      font-size: 13px;
    }
    .stat {
      display: inline-block;
      margin-right: 22px;
      padding: 4px 0;
    }
    .stat strong {
      font-size: 18px;
      color: #D63A30;
      display: block;
    }
    .stat span {
      font-size: 10px;
      letter-spacing: 1.5px;
      color: #7E7872;
      text-transform: uppercase;
    }
    @media (max-width: 720px) {
      table { font-size: 11px; }
      th, td { padding: 8px 6px; }
    }
  </style>
</head>
<body>
  <h1>BLACK7 ROYAL</h1>
  <div class="tagline">PANEL ADMIN</div>

  <!-- ===== \xC9CRAN LOGIN ===== -->
  <div id="login-card" class="card">
    <label>Secret admin (ADMIN_SECRET du Worker)</label>
    <input type="password" id="secret-input" placeholder="\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022" autocomplete="off">
    <div style="margin-top:14px">
      <button onclick="login()">Se connecter</button>
      <button class="ghost" onclick="document.getElementById('secret-input').value=''">Effacer</button>
    </div>
    <div id="login-error" style="color:#E84A3E;font-size:12px;margin-top:10px;display:none"></div>
  </div>

  <!-- ===== \xC9CRAN PRINCIPAL (cach\xE9 tant que pas logg\xE9) ===== -->
  <div id="main" style="display:none">
    <div class="card">
      <div class="stat"><strong id="stat-total">0</strong><span>Clients total</span></div>
      <div class="stat"><strong id="stat-active">0</strong><span>Actifs</span></div>
      <div class="stat"><strong id="stat-paid">0</strong><span>Payants</span></div>
      <div class="stat"><strong id="stat-frozen">0</strong><span>Gel\xE9s</span></div>
      <div class="stat"><strong id="stat-expired">0</strong><span>Essai expir\xE9</span></div>
      <button class="ghost" style="float:right" onclick="refresh()">\u21BB Actualiser</button>
      <button class="ghost" style="float:right;margin-right:6px" onclick="logout()">D\xE9connexion</button>
    </div>

    <!-- ===== ANNONCE BROADCAST (notif \xE0 tous les utilisateurs) ===== -->
    <div class="card">
      <strong style="display:block;margin-bottom:8px">\u{1F4E3} Envoyer une annonce</strong>
      <div style="font-size:12px;color:#9aa;margin-bottom:8px">
        Notifie TOUS les utilisateurs (ceux qui ont laiss\xE9 les annonces
        activ\xE9es). Ex. nouveau contenu, info importante.
      </div>
      <input id="ann-title" placeholder="Titre (ex. Nouveau contenu ajout\xE9)"
        style="width:100%;margin-bottom:6px;padding:8px;border-radius:8px;border:1px solid #333;background:#111;color:#fff">
      <textarea id="ann-body" placeholder="Message" rows="2"
        style="width:100%;margin-bottom:6px;padding:8px;border-radius:8px;border:1px solid #333;background:#111;color:#fff"></textarea>
      <button class="ghost" onclick="sendAnnouncement()">Envoyer \xE0 tous</button>
      <button class="ghost" style="margin-left:6px" onclick="clearAnnouncement()">Retirer l'annonce</button>
      <span id="ann-status" style="font-size:12px;margin-left:8px"></span>
    </div>

    <div class="card">
      <div class="filter-bar">
        <button data-filter="all" class="active" onclick="setFilter('all')">Tous</button>
        <button data-filter="trial" onclick="setFilter('trial')">En essai</button>
        <button data-filter="paid" onclick="setFilter('paid')">Payants</button>
        <button data-filter="expired" onclick="setFilter('expired')">Essai expir\xE9</button>
        <button data-filter="frozen" onclick="setFilter('frozen')">Gel\xE9s</button>
        <button data-filter="banned" onclick="setFilter('banned')">Bannis</button>
      </div>
      <table>
        <thead>
          <tr>
            <th>MAC</th>
            <th>Nom</th>
            <th>Statut</th>
            <th>Essai</th>
            <th>Vu</th>
            <th>Note</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="tbody"></tbody>
      </table>
      <div id="empty" style="display:none">Aucun client dans cette cat\xE9gorie.</div>
    </div>
  </div>

<script>
const SECRET_KEY = '_7m_admin_secret';
let allClients = [];
let currentFilter = 'all';

function getSecret() {
  return sessionStorage.getItem(SECRET_KEY) || '';
}

function setSecret(s) {
  sessionStorage.setItem(SECRET_KEY, s);
}

function clearSecret() {
  sessionStorage.removeItem(SECRET_KEY);
}

function login() {
  const s = document.getElementById('secret-input').value.trim();
  if (!s) return showLoginError('Entre le secret admin.');
  setSecret(s);
  refresh();
}

function logout() {
  clearSecret();
  document.getElementById('login-card').style.display = 'block';
  document.getElementById('main').style.display = 'none';
  document.getElementById('secret-input').value = '';
}

function showLoginError(msg) {
  const el = document.getElementById('login-error');
  el.textContent = msg;
  el.style.display = 'block';
}

async function api(path, opts = {}) {
  const headers = Object.assign(
    { 'X-Admin-Secret': getSecret(), 'Content-Type': 'application/json' },
    opts.headers || {},
  );
  const resp = await fetch(path, Object.assign({}, opts, { headers }));
  if (resp.status === 401) {
    clearSecret();
    logout();
    showLoginError('Secret invalide ou expir\xE9.');
    throw new Error('unauthorized');
  }
  return resp;
}

async function sendAnnouncement() {
  const title = document.getElementById('ann-title').value.trim();
  const body = document.getElementById('ann-body').value.trim();
  const status = document.getElementById('ann-status');
  if (!title && !body) {
    status.textContent = 'Titre ou message requis.';
    status.style.color = '#E84A3E';
    return;
  }
  status.textContent = 'Envoi\u2026';
  status.style.color = '#9aa';
  try {
    const resp = await api('/api/announcement', {
      method: 'POST',
      body: JSON.stringify({ title, body }),
    });
    if (resp.ok) {
      status.textContent = '\u2705 Annonce envoy\xE9e.';
      status.style.color = '#3DD68C';
      document.getElementById('ann-title').value = '';
      document.getElementById('ann-body').value = '';
    } else {
      status.textContent = 'Erreur ' + resp.status;
      status.style.color = '#E84A3E';
    }
  } catch (e) {
    status.textContent = 'Erreur r\xE9seau.';
    status.style.color = '#E84A3E';
  }
}

async function clearAnnouncement() {
  const status = document.getElementById('ann-status');
  status.textContent = 'Suppression\u2026';
  status.style.color = '#9aa';
  try {
    const resp = await api('/api/announcement', { method: 'DELETE' });
    status.textContent = resp.ok ? '\u2705 Annonce retir\xE9e.' : 'Erreur ' + resp.status;
    status.style.color = resp.ok ? '#3DD68C' : '#E84A3E';
  } catch (e) {
    status.textContent = 'Erreur r\xE9seau.';
    status.style.color = '#E84A3E';
  }
}

async function refresh() {
  try {
    const resp = await api('/admin/clients');
    if (!resp.ok) {
      showLoginError('Erreur ' + resp.status + ' \u2014 secret correct ?');
      logout();
      return;
    }
    const list = await resp.json();
    allClients = list;
    document.getElementById('login-card').style.display = 'none';
    document.getElementById('main').style.display = 'block';
    render();
  } catch (e) {
    console.error(e);
  }
}

function setFilter(f) {
  currentFilter = f;
  document.querySelectorAll('.filter-bar button').forEach(b => {
    b.classList.toggle('active', b.dataset.filter === f);
  });
  render();
}

function filterClients(list) {
  const now = Date.now();
  switch (currentFilter) {
    case 'trial':
      return list.filter(c => !c.paid && (c.status || 'active') === 'active' && (c.trial_until || 0) > now);
    case 'paid':
      return list.filter(c => c.paid);
    case 'expired':
      return list.filter(c => !c.paid && (c.trial_until || 0) <= now && (c.status || 'active') !== 'banned');
    case 'frozen':
      return list.filter(c => c.status === 'frozen');
    case 'banned':
      return list.filter(c => c.status === 'banned');
    default:
      return list;
  }
}

function daysLeft(client) {
  const now = Date.now();
  const trial = client.trial_until || 0;
  return Math.ceil((trial - now) / (24 * 60 * 60 * 1000));
}

function formatDate(ts) {
  if (!ts) return '\u2014';
  const d = new Date(ts);
  const day = String(d.getDate()).padStart(2, '0');
  const month = String(d.getMonth() + 1).padStart(2, '0');
  return day + '/' + month + ' ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
}

function escapeHtml(s) {
  return String(s || '').replace(/[&<>"']/g, ch => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[ch]));
}

function render() {
  const filtered = filterClients(allClients);
  const tbody = document.getElementById('tbody');
  const empty = document.getElementById('empty');

  // Stats globales
  const now = Date.now();
  document.getElementById('stat-total').textContent = allClients.length;
  document.getElementById('stat-active').textContent = allClients.filter(c => (c.status || 'active') === 'active').length;
  document.getElementById('stat-paid').textContent = allClients.filter(c => c.paid).length;
  document.getElementById('stat-frozen').textContent = allClients.filter(c => c.status === 'frozen').length;
  document.getElementById('stat-expired').textContent = allClients.filter(c => !c.paid && (c.trial_until || 0) <= now && c.status !== 'banned').length;

  if (filtered.length === 0) {
    tbody.innerHTML = '';
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';

  tbody.innerHTML = filtered.map(c => {
    const days = daysLeft(c);
    const status = c.status || 'active';
    const paid = c.paid === true;
    const statusBadge = '<span class="badge ' + status + '">' + status + '</span>';
    const paidBadge = paid
      ? '<span class="badge paid">Pay\xE9</span>'
      : days > 0
        ? '<span class="badge unpaid">Essai ' + days + 'j</span>'
        : '<span class="badge unpaid">Expir\xE9</span>';
    return '<tr>' +
      '<td class="mac">' + escapeHtml(c.mac) + '</td>' +
      '<td>' + escapeHtml(c.name || '\u2014') + '</td>' +
      '<td>' + statusBadge + ' ' + paidBadge + '</td>' +
      '<td>' + (days > 0 ? days + 'j' : '\u2014') + '</td>' +
      '<td>' + formatDate(c.last_seen_at) + '</td>' +
      '<td style="max-width:160px;font-size:11px;color:#B6B0A8">' + escapeHtml(c.note || '') + '</td>' +
      '<td class="row-actions">' +
        (paid ? '<button class="ghost" onclick="action(\\''+c.mac+'\\',\\'mark_unpaid\\')">Annuler pay\xE9</button>' : '<button onclick="action(\\''+c.mac+'\\',\\'mark_paid\\')">\u2713 Marquer pay\xE9</button>') +
        '<button class="ghost" onclick="renew(\\''+c.mac+'\\')">\u21BB Renouveler</button>' +
        (status === 'frozen' ? '<button onclick="action(\\''+c.mac+'\\',\\'unfreeze\\')">\u25B6 R\xE9activer</button>' : '<button class="ghost" onclick="action(\\''+c.mac+'\\',\\'freeze\\')">\u2744 Geler</button>') +
        (status === 'banned' ? '<button onclick="action(\\''+c.mac+'\\',\\'unfreeze\\')">\u25B6 D\xE9bannir</button>' : '<button class="danger" onclick="action(\\''+c.mac+'\\',\\'ban\\')">\u26D4 Bannir</button>') +
        '<button class="ghost" onclick="editNote(\\''+c.mac+'\\')">\u{1F4DD} Note</button>' +
      '</td>' +
    '</tr>';
  }).join('');
}

async function action(mac, act) {
  try {
    const resp = await api('/admin/clients/' + encodeURIComponent(mac) + '/action', {
      method: 'POST',
      body: JSON.stringify({ action: act }),
    });
    if (!resp.ok) return alert('Erreur ' + resp.status);
    await refresh();
  } catch (e) {
    if (e.message !== 'unauthorized') alert(e.message);
  }
}

async function renew(mac) {
  const days = prompt('Renouveler de combien de jours ?', '365');
  if (!days) return;
  try {
    const resp = await api('/admin/clients/' + encodeURIComponent(mac) + '/action', {
      method: 'POST',
      body: JSON.stringify({ action: 'renew', days: Number(days) }),
    });
    if (!resp.ok) return alert('Erreur ' + resp.status);
    await refresh();
  } catch (e) {
    if (e.message !== 'unauthorized') alert(e.message);
  }
}

async function editNote(mac) {
  const current = (allClients.find(c => c.mac === mac) || {}).note || '';
  const note = prompt('Note pour ' + mac + ' :', current);
  if (note === null) return; // annul\xE9
  try {
    const resp = await api('/admin/clients/' + encodeURIComponent(mac) + '/action', {
      method: 'POST',
      body: JSON.stringify({ action: 'note', note }),
    });
    if (!resp.ok) return alert('Erreur ' + resp.status);
    await refresh();
  } catch (e) {
    if (e.message !== 'unauthorized') alert(e.message);
  }
}

// Boot : si on a d\xE9j\xE0 un secret en session, on tente direct
if (getSecret()) {
  refresh();
}
// Touche Enter dans le champ secret = login
document.getElementById('secret-input').addEventListener('keydown', e => {
  if (e.key === 'Enter') login();
});
<\/script>
</body>
</html>`;
var PRIVACY_HTML = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>The Few \u2014 Politique de confidentialit\xE9</title>
<style>
  body{background:#0A0A0C;color:#EDEAE3;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6;margin:0;padding:32px}
  .wrap{max-width:780px;margin:0 auto}
  h1{color:#CCB089;font-size:28px;margin:0 0 4px}
  h2{color:#E6CFA4;font-size:19px;margin:28px 0 8px}
  p,li{color:#CFC9BF;font-size:15px}
  a{color:#CCB089}
  .muted{color:#8A8377;font-size:13px}
  code{color:#E6CFA4}
</style>
</head>
<body><div class="wrap">
  <h1>Politique de confidentialit\xE9 \u2014 The Few</h1>
  <p class="muted">\xC9diteur : 7 MOTION \xB7 Derni\xE8re mise \xE0 jour : 2026.</p>

  <p>The Few (\xAB l'application \xBB) est un lecteur multim\xE9dia pour t\xE9l\xE9phones,
  t\xE9l\xE9viseurs et box (Android, Android TV, Fire TV, Google TV). L'application ne fournit, n'h\xE9berge ni
  ne revend aucun contenu : l'utilisateur charge sa propre source (liste M3U ou
  identifiants Xtream). Cette politique explique les donn\xE9es trait\xE9es et leur
  finalit\xE9.</p>

  <h2>1. Donn\xE9es que nous traitons</h2>
  <ul>
    <li><b>Identifiant d'appareil</b> (adresse virtuelle d\xE9riv\xE9e de l'appareil) :
      pour reconna\xEEtre l'appareil et g\xE9rer son abonnement/activation.</li>
    <li><b>Mod\xE8le de l'appareil, version d'Android et version de l'application</b> :
      pour le support technique et la compatibilit\xE9.</li>
    <li><b>Adresse IP et pays</b> (fournis par le r\xE9seau) : pour la s\xE9curit\xE9, la
      pr\xE9sence \xAB en ligne \xBB et le bon acheminement du service.</li>
    <li><b>Historique de visionnage</b> (identifiants de cha\xEEnes r\xE9cemment
      ouvertes) : pour proposer \xAB R\xE9cemment \xBB / \xAB Pour vous \xBB et synchroniser
      votre historique entre vos appareils.</li>
  </ul>
  <p>Nous ne collectons <b>pas</b> votre nom, votre adresse postale, vos
  contacts, ni de donn\xE9es biom\xE9triques. Les identifiants de votre source IPTV
  (mot de passe) ne sont <b>pas</b> transmis pour l'historique.</p>

  <h2>2. Finalit\xE9s</h2>
  <p>Gestion de l'abonnement/activation, fonctionnement et s\xE9curit\xE9 du service,
  synchronisation de l'exp\xE9rience entre vos appareils, support technique et
  am\xE9lioration de l'application.</p>

  <h2>3. Partage</h2>
  <p>Nous ne <b>vendons pas</b> vos donn\xE9es et ne les partageons pas \xE0 des fins
  publicitaires. Les donn\xE9es transitent par notre infrastructure d'h\xE9bergement
  (Cloudflare) strictement pour faire fonctionner le service.</p>

  <h2>4. Conservation</h2>
  <p>Donn\xE9es d'activation/abonnement : conserv\xE9es pendant la dur\xE9e du service
  puis jusqu'\xE0 24 mois. Journaux techniques et pr\xE9sence : environ 6 mois.</p>

  <h2>5. Vos droits</h2>
  <p>Vous pouvez demander l'acc\xE8s, la rectification ou la suppression des
  donn\xE9es li\xE9es \xE0 votre appareil en nous contactant. La suppression de
  l'appareil dans notre syst\xE8me efface les donn\xE9es associ\xE9es.</p>

  <h2>6. \xC2ge minimum</h2>
  <p>L'application s'adresse aux personnes de 16 ans et plus. Un
  <b>Mode Enfants</b> prot\xE9g\xE9 par code permet de masquer le contenu adulte.</p>

  <h2>7. Contact</h2>
  <p>Pour toute question relative \xE0 cette politique ou \xE0 vos donn\xE9es :
  <a href="mailto:contact@7themotion.com">contact@7themotion.com</a>.</p>

  <p class="muted">En utilisant The Few, vous acceptez la pr\xE9sente politique.
  Vous devez disposer des droits n\xE9cessaires pour le contenu que vous lisez via
  vos propres sources.</p>
</div></body>
</html>`;
var HTML_HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "public, max-age=300",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy": "frame-ancestors 'none'"
};
var JSON_HEADERS2 = {
  "Content-Type": "application/json; charset=utf-8",
  "Access-Control-Allow-Origin": "*",
  // X-Request-Id, X-Client-Sent-At, Idempotency-Key : envoyés par le panel
  // à chaque écriture depuis le 06/10/2026 (suivi et anti double débit).
  // Absents ici, le navigateur bloquait la requête : « Connexion
  // impossible » sur toute modification (cors_panel.test.mjs).
  "Access-Control-Allow-Headers": "Authorization, X-Admin-Secret, Content-Type, X-Request-Id, X-Client-Sent-At, Idempotency-Key",
  "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff"
};
var TEXT_HEADERS = {
  "Content-Type": "text/plain; charset=utf-8",
  "Access-Control-Allow-Origin": "*"
};
var MAC_RX3 = /^MK(?::[0-9A-F]{2}){5}$/i;
function decodeMacPath(mac) {
  try {
    return decodeURIComponent(String(mac || ""));
  } catch (_) {
    return String(mac || "");
  }
}
__name(decodeMacPath, "decodeMacPath");
var CAST_PROXY_UA = "VLC/3.0.20 LibVLC/3.0.20";
async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
__name(hmacHex, "hmacHex");
function isSafeUpstream(rawUrl) {
  let u;
  try {
    u = new URL(rawUrl);
  } catch (_) {
    return false;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:")
    return false;
  let host = u.hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal"))
    return false;
  if (host.startsWith("["))
    host = host.slice(1, -1);
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const o = m.slice(1).map((n) => parseInt(n, 10));
    if (o.some((n) => n > 255))
      return false;
    const [a, b] = o;
    if (a === 10)
      return false;
    if (a === 127)
      return false;
    if (a === 0)
      return false;
    if (a === 169 && b === 254)
      return false;
    if (a === 172 && b >= 16 && b <= 31)
      return false;
    if (a === 192 && b === 168)
      return false;
    if (a === 100 && b >= 64 && b <= 127)
      return false;
    if (a >= 224)
      return false;
    return true;
  }
  if (host.includes(":")) {
    if (host === "::1" || host === "::")
      return false;
    if (host.startsWith("fc") || host.startsWith("fd"))
      return false;
    if (host.startsWith("fe8") || host.startsWith("fe9") || host.startsWith("fea") || host.startsWith("feb"))
      return false;
    return true;
  }
  return true;
}
__name(isSafeUpstream, "isSafeUpstream");
async function handleCastSign(env, url) {
  const secret = env.CAST_PROXY_SECRET;
  if (!secret)
    return json2({ ok: false, error: "proxy_unconfigured" }, 503);
  const u = url.searchParams.get("u") || "";
  if (!u || !isSafeUpstream(u))
    return badRequest("invalid or private upstream url");
  const exp = Math.floor(Date.now() / 1e3) + 12 * 3600;
  const sig = (await hmacHex(secret, u + "\n" + exp)).slice(0, 32);
  const origin = url.origin || "https://app.7themotion.com";
  const proxyUrl = origin + "/cast-proxy?u=" + encodeURIComponent(u) + "&e=" + exp + "&t=" + sig;
  return json2({ ok: true, url: proxyUrl, expires_at: exp });
}
__name(handleCastSign, "handleCastSign");
async function handleCastProxy(env, url, method) {
  const secret = env.CAST_PROXY_SECRET;
  if (!secret)
    return new Response("proxy unconfigured", { status: 503 });
  const u = url.searchParams.get("u") || "";
  const e = url.searchParams.get("e") || "";
  const t = url.searchParams.get("t") || "";
  if (!u || !e || !t)
    return new Response("missing params", { status: 400 });
  const exp = parseInt(e, 10);
  const now = Math.floor(Date.now() / 1e3);
  if (!Number.isFinite(exp) || exp < now || exp > now + 24 * 3600) {
    return new Response("token expired", { status: 403 });
  }
  const expected = (await hmacHex(secret, u + "\n" + e)).slice(0, 32);
  if (!safeEqual2(t, expected))
    return new Response("bad token", { status: 403 });
  if (!isSafeUpstream(u))
    return new Response("forbidden upstream", { status: 403 });
  let target = u;
  let resp = null;
  for (let i = 0; i <= 3; i++) {
    resp = await fetch(target, {
      method: method === "HEAD" ? "HEAD" : "GET",
      redirect: "manual",
      headers: { "User-Agent": CAST_PROXY_UA, Accept: "*/*" }
    });
    if (resp.status >= 300 && resp.status < 400) {
      const loc = resp.headers.get("location");
      if (!loc)
        break;
      let next;
      try {
        next = new URL(loc, target).toString();
      } catch (_) {
        break;
      }
      if (!isSafeUpstream(next))
        return new Response("forbidden redirect", { status: 403 });
      target = next;
      continue;
    }
    break;
  }
  if (!resp || resp.status >= 400) {
    return new Response("upstream error", { status: 502 });
  }
  const headers = {
    "Content-Type": "video/mp2t",
    "Access-Control-Allow-Origin": "*",
    "Cache-Control": "no-store"
  };
  if (method === "HEAD")
    return new Response(null, { status: 200, headers });
  return new Response(resp.body, { status: 200, headers });
}
__name(handleCastProxy, "handleCastProxy");
function json2(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS2 });
}
__name(json2, "json");
function privacyHtml() {
  const updated = "10 juin 2026";
  return `<!doctype html><html lang="fr"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>7 MOTION \u2014 Politique de confidentialit\xE9</title>
<style>
  body{margin:0;background:#0A0A0C;color:#E8E8EC;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6}
  .wrap{max-width:760px;margin:0 auto;padding:32px 20px 64px}
  h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 8px;color:#fff}
  .muted{color:#9A9AA2;font-size:13px}a{color:#FF5A4A}
  code{background:#16121C;padding:1px 6px;border-radius:5px}
</style></head><body><div class="wrap">
<h1>Politique de confidentialit\xE9 \u2014 7 MOTION</h1>
<p class="muted">Derni\xE8re mise \xE0 jour : ${updated}</p>

<h2>1. Nature de l'application</h2>
<p>7 MOTION est un <strong>lecteur multim\xE9dia</strong>. L'application ne vend,
n'h\xE9berge et ne fournit AUCUN contenu, flux, cha\xEEne, playlist (M3U) ni
abonnement. L'utilisateur fournit lui-m\xEAme sa propre source (lien M3U ou
identifiants Xtream) et reste seul responsable de son contenu et de sa lic\xE9it\xE9.</p>

<h2>2. Donn\xE9es que nous traitons</h2>
<ul>
<li><strong>Identifiant d'appareil</strong> : un identifiant technique
(\xAB MAC virtuelle \xBB d\xE9riv\xE9e de l'appareil) sert \xE0 reconna\xEEtre l'installation et
\xE0 activer le service. Il ne contient pas votre nom.</li>
<li><strong>Adresse IP et pays</strong> : fournis automatiquement par le r\xE9seau
lors des connexions, utilis\xE9s pour la s\xE9curit\xE9, la pr\xE9sence \xAB en ligne \xBB et des
messages cibl\xE9s par pays. L'IP n'est pas revendue.</li>
<li><strong>Mod\xE8le et version d'appareil</strong> : pour le support et les
statistiques techniques.</li>
<li><strong>Vos sources IPTV</strong> (URL M3U / identifiants Xtream) : stock\xE9es
<strong>localement sur votre appareil</strong> ; une copie peut \xEAtre sauvegard\xE9e,
li\xE9e \xE0 votre identifiant d'appareil, pour vous permettre de la retrouver apr\xE8s
r\xE9installation.</li>
<li><strong>Avis</strong> que vous envoyez volontairement.</li>
</ul>

<h2>3. Ce que nous NE faisons PAS</h2>
<p>Pas de vente de donn\xE9es personnelles, pas de pistage publicitaire tiers, pas
de collecte de contacts, photos ou localisation pr\xE9cise.</p>

<h2>4. Lecture & cast</h2>
<p>Les flux que vous chargez sont lus localement ou diffus\xE9s (cast) vers un
appareil de votre r\xE9seau (TV DLNA, Chromecast). Le contenu transite directement
entre votre source et votre appareil/TV.</p>

<h2>5. Conservation & suppression</h2>
<p>Vos sources locales sont effac\xE9es si vous d\xE9sinstallez l'application ou les
retirez. Pour supprimer les donn\xE9es li\xE9es \xE0 votre identifiant d'appareil,
contactez-nous (voir ci-dessous).</p>

<h2>6. S\xE9curit\xE9</h2>
<p>Les \xE9changes avec nos serveurs se font en HTTPS. Les mots de passe
administrateurs sont stock\xE9s sous forme hach\xE9e.</p>

<h2>7. Enfants</h2>
<p>L'application n'est pas destin\xE9e aux enfants de moins de 13 ans.</p>

<h2>8. Contact</h2>
<p>Pour toute question ou demande de suppression : <a href="mailto:lionel930031@gmail.com">lionel930031@gmail.com</a>.</p>

<p class="muted">En utilisant 7 MOTION, vous acceptez la pr\xE9sente politique.</p>
</div></body></html>`;
}
__name(privacyHtml, "privacyHtml");
function termsHtml() {
  const updated = "22 juin 2026";
  return `<!doctype html><html lang="fr"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>7 MOTION \u2014 Conditions d'utilisation</title>
<style>
  body{margin:0;background:#0A0A0C;color:#E8E8EC;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;line-height:1.6}
  .wrap{max-width:760px;margin:0 auto;padding:32px 20px 64px}
  h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 8px;color:#fff}
  .muted{color:#9A9AA2;font-size:13px}a{color:#FF5A4A}
  strong{color:#fff}
</style></head><body><div class="wrap">
<h1>Conditions d'utilisation \u2014 7 MOTION</h1>
<p class="muted">Derni\xE8re mise \xE0 jour : ${updated}</p>

<h2>1. Nature de l'application \u2014 un LECTEUR, rien d'autre</h2>
<p>7 MOTION est un <strong>lecteur multim\xE9dia</strong> (player) permettant de lire
des flux audio/vid\xE9o fournis par l'utilisateur. L'application
<strong>ne fournit pas, ne vend pas, n'h\xE9berge pas, ne diffuse pas et n'indexe
aucune</strong> cha\xEEne de t\xE9l\xE9vision, flux, contenu audiovisuel, ni liste de
lecture (M3U) ou identifiants de portail (Xtream). <strong>Aucun contenu n'est
inclus, pr\xE9charg\xE9 ou commercialis\xE9</strong> avec l'application.</p>

<h2>2. Contenu fourni par l'utilisateur</h2>
<p>L'utilisateur fournit lui-m\xEAme ses propres sources (lien M3U / identifiants
Xtream), obtenues aupr\xE8s de son propre fournisseur. L'utilisateur est
<strong>seul responsable</strong> des contenus qu'il ajoute, lit ou diffuse,
ainsi que de la d\xE9tention des droits, licences et abonnements n\xE9cessaires.</p>

<h2>3. Abonnement = le LOGICIEL, pas le contenu</h2>
<p>Tout paiement ou abonnement \xE9ventuel r\xE9mun\xE8re <strong>uniquement
l'utilisation de l'application</strong> (le lecteur et ses fonctionnalit\xE9s :
interface, favoris, enregistrement local, EPG, etc.). Il ne constitue
<strong>en aucun cas</strong> l'achat, la vente, la location ou la fourniture de
cha\xEEnes, de flux ou de contenus audiovisuels.</p>

<h2>4. Usage licite</h2>
<p>L'utilisateur s'engage \xE0 utiliser l'application <strong>conform\xE9ment aux lois
en vigueur</strong> dans son pays et \xE0 ne pas l'utiliser pour acc\xE9der \xE0 des
contenus ill\xE9gaux ou portant atteinte aux droits d'auteur. Toute utilisation
illicite est strictement interdite et rel\xE8ve de la seule responsabilit\xE9 de
l'utilisateur.</p>

<h2>5. Contenus tiers \u2014 absence de responsabilit\xE9</h2>
<p>L'\xE9diteur n'a aucun contr\xF4le sur les contenus tiers accessibles via les
sources fournies par l'utilisateur et ne saurait en \xEAtre tenu responsable. Il ne
garantit ni la disponibilit\xE9, ni la l\xE9galit\xE9, ni la qualit\xE9 de ces contenus.</p>

<h2>6. Propri\xE9t\xE9 intellectuelle & r\xE9clamations</h2>
<p>Toutes les marques, logos et contenus appartiennent \xE0 leurs propri\xE9taires
respectifs. L'application n'h\xE9bergeant aucun contenu, toute r\xE9clamation relative
\xE0 des droits d'auteur doit \xEAtre adress\xE9e au <strong>fournisseur de la source
concern\xE9e</strong>. Pour signaler un usage abusif de l'application :
<a href="mailto:lionel930031@gmail.com">lionel930031@gmail.com</a>.</p>

<h2>7. Fourniture \xAB en l'\xE9tat \xBB</h2>
<p>L'application est fournie \xAB telle quelle \xBB, sans garantie de disponibilit\xE9
continue ni d'absence d'erreurs. L'\xE9diteur peut faire \xE9voluer ou suspendre tout
ou partie des fonctionnalit\xE9s.</p>

<h2>8. Donn\xE9es personnelles</h2>
<p>Le traitement des donn\xE9es est d\xE9crit dans notre
<a href="/privacy">politique de confidentialit\xE9</a>.</p>

<h2>9. Acceptation</h2>
<p>En installant ou en utilisant 7 MOTION, l'utilisateur reconna\xEEt avoir lu et
accept\xE9 les pr\xE9sentes conditions.</p>

<p class="muted">Contact : <a href="mailto:lionel930031@gmail.com">lionel930031@gmail.com</a></p>
</div></body></html>`;
}
__name(termsHtml, "termsHtml");
function notFound2(msg = "Not found") {
  return new Response(msg, { status: 404, headers: TEXT_HEADERS });
}
__name(notFound2, "notFound");
function badRequest(msg) {
  return json2({ error: msg }, 400);
}
__name(badRequest, "badRequest");
function unauthorized() {
  return json2({ error: "unauthorized" }, 401);
}
__name(unauthorized, "unauthorized");
function safeEqual2(a, b) {
  if (typeof a !== "string" || typeof b !== "string")
    return false;
  if (a.length !== b.length)
    return false;
  let diff2 = 0;
  for (let i = 0; i < a.length; i++) {
    diff2 |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff2 === 0;
}
__name(safeEqual2, "safeEqual");
function checkAdmin(request, env) {
  const provided = request.headers.get("X-Admin-Secret") || "";
  const expected = env.ADMIN_SECRET || "";
  if (!expected) {
    return false;
  }
  return safeEqual2(provided, expected);
}
__name(checkAdmin, "checkAdmin");
function clientIp2(request) {
  return request.headers.get("CF-Connecting-IP") || request.headers.get("X-Forwarded-For") || "unknown";
}
__name(clientIp2, "clientIp");
async function rateLimitOk(env, request, bucket, maxAttempts, windowMs) {
  if (!env || !env.DB)
    return true;
  try {
    await env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS rate_limits (k TEXT PRIMARY KEY, count INTEGER NOT NULL, window_start INTEGER NOT NULL)"
    ).run();
    const k = `${bucket}:${clientIp2(request)}`;
    const now = Date.now();
    const row = await env.DB.prepare("SELECT count, window_start FROM rate_limits WHERE k = ?").bind(k).first();
    if (!row || now - row.window_start > windowMs) {
      await env.DB.prepare(
        "INSERT INTO rate_limits (k, count, window_start) VALUES (?, 1, ?) ON CONFLICT(k) DO UPDATE SET count = 1, window_start = ?"
      ).bind(k, now, now).run();
      return true;
    }
    if (row.count >= maxAttempts)
      return false;
    await env.DB.prepare("UPDATE rate_limits SET count = count + 1 WHERE k = ?").bind(k).run();
    return true;
  } catch (_) {
    return true;
  }
}
__name(rateLimitOk, "rateLimitOk");
function tooManyRequests() {
  return json2(
    { error: "rate_limited", message: "Trop de requ\xEAtes, r\xE9essaie dans un instant." },
    429
  );
}
__name(tooManyRequests, "tooManyRequests");
var JSON_HEADERS_PRIVATE = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff"
};
function jsonPrivate(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS_PRIVATE });
}
__name(jsonPrivate, "jsonPrivate");
async function ensureAnnouncementsTable2(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS app_broadcasts (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT, url TEXT, created_at INTEGER)"
  ).run();
  for (const col of [
    "kind TEXT",
    "cta TEXT",
    "country TEXT",
    "expires_at INTEGER",
    "active INTEGER DEFAULT 1"
  ]) {
    try {
      await env.DB.prepare(
        "ALTER TABLE app_broadcasts ADD COLUMN " + col
      ).run();
    } catch (_) {
    }
  }
}
__name(ensureAnnouncementsTable2, "ensureAnnouncementsTable");
function publicAnnouncement(row) {
  return {
    id: row.id,
    title: row.title || "",
    body: row.body || "",
    url: row.url || "",
    kind: row.kind || "",
    cta: row.cta || "",
    country: row.country || "",
    created_at: row.created_at || 0
  };
}
__name(publicAnnouncement, "publicAnnouncement");
async function handleGetAnnouncement(env, request) {
  if (!env.DB)
    return json2({});
  try {
    await ensureAnnouncementsTable2(env);
    await ensureAppConfigTable2(env);
    const sw = await env.DB.prepare("SELECT value FROM app_config WHERE key = 'announcements_enabled'").first();
    if (sw && sw.value === "0")
      return json2({});
    const reqCountry = request && request.headers.get("CF-IPCountry") || "";
    const nowMs = Date.now();
    let after = 0;
    try {
      after = parseInt(new URL(request.url).searchParams.get("after") || "0", 10) || 0;
    } catch (_) {
      after = 0;
    }
    const cols = "id, title, body, url, kind, cta, country, created_at, expires_at, active";
    const where = "WHERE (country IS NULL OR country = '' OR country = ?) AND (expires_at IS NULL OR expires_at = 0 OR expires_at > ?) AND (active IS NULL OR active = 1) ";
    const latestRs = await env.DB.prepare(
      "SELECT " + cols + " FROM app_broadcasts " + where + "ORDER BY id DESC LIMIT 20"
    ).bind(reqCountry, nowMs).all();
    const pageRs = await env.DB.prepare(
      "SELECT " + cols + " FROM app_broadcasts " + where + "AND id > ? ORDER BY id ASC LIMIT 30"
    ).bind(reqCountry, nowMs, after).all();
    const latestPick = selectAnnouncements(latestRs.results || [], {
      after: 0,
      now: nowMs,
      country: reqCountry
    });
    const pagePick = selectAnnouncements(pageRs.results || [], {
      after,
      now: nowMs,
      country: reqCountry
    });
    const row = latestPick.latest;
    if (!row)
      return json2({});
    return json2({
      ...publicAnnouncement(row),
      pending: pagePick.pending.map(publicAnnouncement)
    });
  } catch (_) {
    return json2({});
  }
}
__name(handleGetAnnouncement, "handleGetAnnouncement");
async function handleGetHomeLayout(env) {
  if (!env.DB)
    return json2({ items: [], version: 0 });
  try {
    await env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS home_layout (key TEXT PRIMARY KEY, position INTEGER, enabled INTEGER DEFAULT 1, ribbon TEXT DEFAULT '', featured INTEGER DEFAULT 0, updated_at INTEGER)"
    ).run();
    const rs = await env.DB.prepare(
      "SELECT key, position, enabled, ribbon, featured, updated_at FROM home_layout ORDER BY position ASC, key ASC"
    ).all();
    const items = rs.results || [];
    let version = 0;
    for (const it of items) {
      if ((it.updated_at || 0) > version)
        version = it.updated_at;
    }
    return json2({ items, version });
  } catch (_) {
    return json2({ items: [], version: 0 });
  }
}
__name(handleGetHomeLayout, "handleGetHomeLayout");
async function ensureAppConfigTable2(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT)"
  ).run();
}
__name(ensureAppConfigTable2, "ensureAppConfigTable");
async function handleGetFeatured(env) {
  if (!env.DB)
    return json2({ name: "", note: "" });
  try {
    await ensureAppConfigTable2(env);
    const n = await env.DB.prepare("SELECT value FROM app_config WHERE key = 'featured_name'").first();
    const note = await env.DB.prepare("SELECT value FROM app_config WHERE key = 'featured_note'").first();
    return json2({
      name: n && n.value || "",
      note: note && note.value || ""
    });
  } catch (_) {
    return json2({ name: "", note: "" });
  }
}
__name(handleGetFeatured, "handleGetFeatured");
async function handleGreeting(request) {
  const cf = request.cf || {};
  const city = cf.city ? String(cf.city) : "";
  const country = cf.country ? String(cf.country) : "";
  const lat = cf.latitude;
  const lon = cf.longitude;
  let tempC = null;
  let weatherCode = null;
  if (lat && lon) {
    try {
      const r = await fetch(
        "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon + "&current=temperature_2m,weather_code",
        { cf: { cacheTtl: 900, cacheEverything: true } }
      );
      if (r.ok) {
        const j = await r.json();
        if (j && j.current) {
          tempC = j.current.temperature_2m;
          weatherCode = j.current.weather_code;
        }
      }
    } catch (_) {
    }
  }
  return json2({ city, country, tempC, weatherCode });
}
__name(handleGreeting, "handleGreeting");
async function handleGetTheme(env, platform) {
  const empty = { appName: "", accent: "", bg: "" };
  if (!env.DB)
    return json2(empty);
  const sfx = platform === "tv" ? "_tv" : "";
  try {
    await ensureAppConfigTable2(env);
    const get = /* @__PURE__ */ __name((k) => env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(k).first(), "get");
    const name = await get("theme_name" + sfx);
    const accent = await get("theme_accent" + sfx);
    const bg = await get("theme_bg" + sfx);
    const theme = {
      appName: name && name.value || "",
      accent: accent && accent.value || "",
      bg: bg && bg.value || ""
    };
    try {
      const autoRow = await get("theme_automations" + sfx);
      const rules = autoRow && autoRow.value ? JSON.parse(autoRow.value) : [];
      const hit = pickActiveThemeRule(rules, /* @__PURE__ */ new Date());
      if (hit) {
        if (hit.accent)
          theme.accent = hit.accent;
        if (hit.bg)
          theme.bg = hit.bg;
        if (hit.appName)
          theme.appName = hit.appName;
      }
    } catch (_) {
    }
    return json2(theme);
  } catch (_) {
    return json2(empty);
  }
}
__name(handleGetTheme, "handleGetTheme");
function pickActiveThemeRule(rules, now) {
  if (!Array.isArray(rules))
    return null;
  const md = (now.getUTCMonth() + 1) * 100 + now.getUTCDate();
  const month = now.getUTCMonth() + 1;
  for (const r of rules) {
    if (!r || !r.enabled)
      continue;
    if (r.month && Number(r.month) === month)
      return r;
    if (r.from && r.to && /^\d{4}$/.test(r.from) && /^\d{4}$/.test(r.to)) {
      const from = parseInt(r.from, 10);
      const to = parseInt(r.to, 10);
      const inRange = from <= to ? md >= from && md <= to : md >= from || md <= to;
      if (inRange)
        return r;
    }
  }
  return null;
}
__name(pickActiveThemeRule, "pickActiveThemeRule");
async function handleGetAd(env) {
  const empty = { enabled: false, url: "", skip: 5, freq: "always" };
  if (!env.DB)
    return json2(empty);
  try {
    await ensureAppConfigTable2(env);
    const get = /* @__PURE__ */ __name(async (k) => {
      const r = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(k).first();
      return r && r.value != null ? String(r.value) : "";
    }, "get");
    const url = await get("ad_url");
    const enabled = await get("ad_enabled") === "1" && url.length > 0;
    const skipRaw = parseInt(await get("ad_skip"), 10);
    const freq = await get("ad_freq") || "always";
    return json2({
      enabled,
      url,
      skip: Number.isFinite(skipRaw) && skipRaw >= 0 ? skipRaw : 5,
      freq
    });
  } catch (_) {
    return json2(empty);
  }
}
__name(handleGetAd, "handleGetAd");
async function handleGetPricing(env) {
  const def = {
    currency: "\u20AC",
    lifetime: "9,9",
    yearly: "4,9",
    trialDays: 7,
    promoEnabled: false,
    promoMessage: ""
  };
  if (!env.DB)
    return json2(def);
  try {
    await ensureAppConfigTable2(env);
    const get = /* @__PURE__ */ __name(async (k) => {
      const r = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(k).first();
      return r && r.value != null ? String(r.value) : "";
    }, "get");
    const currency = await get("price_currency") || def.currency;
    const lifetime = await get("price_lifetime") || def.lifetime;
    const yearly = await get("price_yearly") || def.yearly;
    const td = parseInt(await get("trial_days"), 10);
    const trialDays = Number.isFinite(td) && td >= 0 ? td : def.trialDays;
    const promoMessage = await get("promo_msg");
    const promoEnabled = await get("promo_enabled") === "1" && promoMessage.length > 0;
    return json2({ currency, lifetime, yearly, trialDays, promoEnabled, promoMessage });
  } catch (_) {
    return json2(def);
  }
}
__name(handleGetPricing, "handleGetPricing");
async function handleGetFeedbackPrompt(env) {
  const empty = { enabled: false, message: "" };
  if (!env.DB)
    return json2(empty);
  try {
    await ensureAppConfigTable2(env);
    const e = await env.DB.prepare("SELECT value FROM app_config WHERE key = 'feedback_enabled'").first();
    const m = await env.DB.prepare("SELECT value FROM app_config WHERE key = 'feedback_msg'").first();
    return json2({
      enabled: !!(e && e.value === "1"),
      message: m && m.value || ""
    });
  } catch (_) {
    return json2(empty);
  }
}
__name(handleGetFeedbackPrompt, "handleGetFeedbackPrompt");
async function ensureFeedbackTable(env) {
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS feedback (id INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT, country TEXT, rating INTEGER, message TEXT, created_at INTEGER)"
  ).run();
}
__name(ensureFeedbackTable, "ensureFeedbackTable");
async function handlePostFeedback(request, env) {
  if (!env.DB)
    return json2({ ok: false }, 503);
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest("bad json");
  }
  const message = (body && body.message ? String(body.message) : "").trim().slice(0, 2e3);
  if (!message)
    return badRequest("message vide");
  const mac = (body && body.mac ? String(body.mac) : "").slice(0, 64);
  let rating = parseInt(body && body.rating, 10);
  if (!Number.isFinite(rating) || rating < 0 || rating > 5)
    rating = 0;
  const country = request.cf && request.cf.country ? String(request.cf.country) : "";
  try {
    await ensureFeedbackTable(env);
    await env.DB.prepare("INSERT INTO feedback (mac, country, rating, message, created_at) VALUES (?, ?, ?, ?, ?)").bind(mac, country, rating, message, Date.now()).run();
    return json2({ ok: true });
  } catch (_) {
    return json2({ ok: false }, 500);
  }
}
__name(handlePostFeedback, "handlePostFeedback");
async function handleGetAppVersion(request, env) {
  if (!env.DB)
    return json2({ minBuildTs: 0, latestBuildTs: 0 });
  try {
    await ensureAppConfigTable2(env);
    const url = new URL(request.url);
    const sfx = url.searchParams.get("platform") === "tv" ? "_tv" : "";
    const latestKey = "latest_build_ts" + sfx;
    const minKey = "min_build_ts" + sfx;
    const build = parseInt(url.searchParams.get("build") || "0", 10);
    if (Number.isFinite(build) && build > 0) {
      const row = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(latestKey).first();
      const cur = row ? parseInt(row.value, 10) || 0 : 0;
      if (build > cur) {
        await env.DB.prepare(
          "INSERT INTO app_config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        ).bind(latestKey, String(build)).run();
      }
    }
    const minRow = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(minKey).first();
    const latRow = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(latestKey).first();
    return json2({
      minBuildTs: minRow ? parseInt(minRow.value, 10) || 0 : 0,
      latestBuildTs: latRow ? parseInt(latRow.value, 10) || 0 : 0
    });
  } catch (_) {
    return json2({ minBuildTs: 0, latestBuildTs: 0 });
  }
}
__name(handleGetAppVersion, "handleGetAppVersion");
async function handlePostAnnouncement(request, env) {
  if (!env.DB)
    return json2({ error: "db_unbound" }, 500);
  let payload = {};
  try {
    payload = await request.json();
  } catch (_) {
  }
  const title = (payload.title || "").toString().slice(0, 120);
  const body = (payload.body || "").toString().slice(0, 500);
  const url = (payload.url || "").toString().slice(0, 300);
  if (!title && !body)
    return badRequest("title or body required");
  try {
    await ensureAnnouncementsTable2(env);
    const res = await env.DB.prepare(
      "INSERT INTO app_broadcasts (title, body, url, created_at) VALUES (?, ?, ?, ?)"
    ).bind(title, body, url, Date.now()).run();
    return json2({ ok: true, id: res.meta && res.meta.last_row_id || null });
  } catch (e) {
    return json2({ error: String(e) }, 500);
  }
}
__name(handlePostAnnouncement, "handlePostAnnouncement");
async function handleClearAnnouncements(env) {
  if (!env.DB)
    return json2({ error: "db_unbound" }, 500);
  try {
    await ensureAnnouncementsTable2(env);
    await env.DB.prepare("DELETE FROM app_broadcasts").run();
    return json2({ ok: true });
  } catch (e) {
    return json2({ error: String(e) }, 500);
  }
}
__name(handleClearAnnouncements, "handleClearAnnouncements");
async function readIndex(env) {
  const raw = await env.KV_7MOTION.get("_index");
  if (!raw)
    return [];
  try {
    return JSON.parse(raw);
  } catch (_) {
    return [];
  }
}
__name(readIndex, "readIndex");
async function writeIndex(env, list) {
  const dedup = Array.from(new Set(list));
  await env.KV_7MOTION.put("_index", JSON.stringify(dedup));
}
__name(writeIndex, "writeIndex");
async function readClient(env, mac) {
  const raw = await env.KV_7MOTION.get(`client:${mac}`);
  if (!raw)
    return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}
__name(readClient, "readClient");
async function writeClient(env, mac, data) {
  await env.KV_7MOTION.put(`client:${mac}`, JSON.stringify(data));
  const idx = await readIndex(env);
  if (!idx.includes(mac)) {
    idx.push(mac);
    await writeIndex(env, idx);
  }
}
__name(writeClient, "writeClient");
async function deleteClient(env, mac) {
  await env.KV_7MOTION.delete(`client:${mac}`);
  const idx = await readIndex(env);
  await writeIndex(env, idx.filter((m) => m !== mac));
}
__name(deleteClient, "deleteClient");
function validateClientBody(body) {
  if (!body || typeof body !== "object")
    return "body must be a JSON object";
  if (!body.mac || !MAC_RX3.test(body.mac)) {
    return "invalid mac, expected MK:XX:XX:XX:XX:XX";
  }
  if (body.playlists !== void 0) {
    if (!Array.isArray(body.playlists)) {
      return "playlists must be an array";
    }
    for (const p of body.playlists) {
      if (!p || typeof p !== "object")
        return "each playlist must be an object";
      if (p.type !== "m3u" && p.type !== "xtream") {
        return 'playlist.type must be "m3u" or "xtream"';
      }
      if (p.type === "m3u" && !p.url) {
        return "m3u playlist requires url";
      }
      if (p.type === "xtream" && (!p.server || !p.username || !p.password)) {
        return "xtream playlist requires server, username, password";
      }
    }
  }
  if (body.status !== void 0) {
    if (!["active", "frozen", "banned"].includes(body.status)) {
      return "status must be active, frozen or banned";
    }
  }
  return null;
}
__name(validateClientBody, "validateClientBody");
async function handleGetClientsList(env) {
  const macs = await readIndex(env);
  const out = [];
  for (const mac of macs) {
    const data = await readClient(env, mac);
    if (data)
      out.push({ mac, ...data });
  }
  out.sort((a, b) => (b.added_at || 0) - (a.added_at || 0));
  return json2(out);
}
__name(handleGetClientsList, "handleGetClientsList");
async function handleGetClient(env, mac) {
  const data = await readClient(env, mac);
  if (!data)
    return notFound2(`Client ${mac} introuvable`);
  return json2({ mac, ...data });
}
__name(handleGetClient, "handleGetClient");
async function handleUpsertClient(request, env, mac) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest("invalid JSON body");
  }
  if (mac)
    body.mac = mac;
  const err = validateClientBody(body);
  if (err)
    return badRequest(err);
  const now = Date.now();
  const existing = await readClient(env, body.mac);
  const addedAt = existing?.added_at || now;
  const merged = {
    name: body.name !== void 0 ? body.name : existing?.name || "",
    playlists: body.playlists !== void 0 ? body.playlists : existing?.playlists || [],
    added_at: addedAt,
    updated_at: now,
    // Monétisation
    status: body.status || existing?.status || "active",
    paid: body.paid !== void 0 ? !!body.paid : existing?.paid === true,
    trial_until: body.trial_until !== void 0 ? body.trial_until : existing?.trial_until || addedAt + TRIAL_DAYS2 * DAY_MS2,
    note: body.note !== void 0 ? body.note : existing?.note || "",
    last_seen_at: existing?.last_seen_at || 0
  };
  await writeClient(env, body.mac, merged);
  return json2({ ok: true, mac: body.mac, ...merged });
}
__name(handleUpsertClient, "handleUpsertClient");
async function handleHeartbeat(request, env, _ctx) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest("invalid JSON body");
  }
  const mac = body?.mac;
  if (!mac || !MAC_RX3.test(mac)) {
    return badRequest("invalid mac, expected MK:XX:XX:XX:XX:XX");
  }
  const now = Date.now();
  const ip = request.headers.get("CF-Connecting-IP") || "";
  const country = request.headers.get("CF-IPCountry") || "";
  const channel = typeof body.channel === "string" ? body.channel : "";
  await recordPresence(env, mac, ip, country, now, channel);
  if (env.DB) {
    await ensureScaleSchema(env);
    const created = await ensureD1Device(env, mac, now);
    const hintedId = body && body.androidId ? String(body.androidId) : "";
    await touchTrialAnchor(env, mac, hintedId);
    await updateDeviceInfo(env, mac, body);
    const d1 = await d1StatusForMac(env, mac, now);
    if (d1)
      return json2({ ok: true, created: !!created, ...d1 });
  }
  const existing = await readClient(env, mac);
  if (!existing) {
    const fresh = {
      name: "",
      playlists: [],
      added_at: now,
      updated_at: now,
      status: "active",
      paid: false,
      trial_until: now + TRIAL_DAYS2 * DAY_MS2,
      note: "",
      last_seen_at: now,
      first_seen_at: now
    };
    await writeClient(env, mac, fresh);
    return json2({ ok: true, created: true, ...computeStatus(fresh, now) });
  }
  const updated = { ...existing, last_seen_at: now };
  await writeClient(env, mac, updated);
  return json2({ ok: true, created: false, ...computeStatus(updated, now) });
}
__name(handleHeartbeat, "handleHeartbeat");
async function handleBlackboxPost(request, env) {
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest("invalid JSON body");
  }
  const mac = String(body?.mac || "").trim().toUpperCase();
  if (!MAC_RX3.test(mac)) {
    return badRequest("invalid mac, expected MK:XX:XX:XX:XX:XX");
  }
  if (typeof body?.text !== "string")
    return badRequest("text required");
  if (!env.DB) {
    return json2({ error: "no_db", message: "Base indisponible." }, 503);
  }
  const saved = await saveBlackBox(env, mac, body.text, Date.now());
  if (saved.error === "empty")
    return json2({ ok: true, skipped: true });
  if (saved.error)
    return json2({ error: "store_failed" }, 500);
  return json2({ ok: true, updated_at: saved.updated_at });
}
__name(handleBlackboxPost, "handleBlackboxPost");
async function attachBlackboxPull(env, mac, payload) {
  const out = payload && typeof payload === "object" ? { ...payload } : {};
  out.blackbox_pull = await blackboxRequestedAt(env, String(mac || "").toUpperCase());
  return out;
}
__name(attachBlackboxPull, "attachBlackboxPull");
async function handlePublicStatus(env, mac) {
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  if (env.DB) {
    let d1 = await d1StatusForMac(env, mac);
    if (!d1) {
      await ensureD1Device(env, mac);
      await touchTrialAnchor(env, mac, "");
      d1 = await d1StatusForMac(env, mac);
    }
    if (d1) {
      d1.reset_at = await resetAtFor(env, mac);
      return json2(await attachBlackboxPull(env, mac, d1));
    }
  }
  const data = await readClient(env, mac);
  return json2(await attachBlackboxPull(env, mac, computeStatus(data)));
}
__name(handlePublicStatus, "handlePublicStatus");
async function handleAdminAction(request, env, mac) {
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest("invalid JSON body");
  }
  const action = body?.action;
  const now = Date.now();
  if (env.DB) {
    await ensureD1Device(env, mac, now);
    const dev = await env.DB.prepare("SELECT id, customer_id FROM devices WHERE mac = ?").bind(mac).first();
    if (!dev)
      return notFound2(`Device ${mac} introuvable`);
    const APP_ID = "app_7motion";
    async function setLicense(plan, expiresAt) {
      const lic = await env.DB.prepare(
        `SELECT id FROM licenses WHERE device_id = ?
           ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`
      ).bind(dev.id).first();
      if (lic) {
        await env.DB.prepare(
          `UPDATE licenses SET status='active', plan=?, expires_at=?, updated_at=? WHERE id=?`
        ).bind(plan, expiresAt, now, lic.id).run();
      } else {
        const lid = "lic_" + crypto.randomUUID().replace(/-/g, "").slice(0, 18);
        await env.DB.prepare(
          `INSERT INTO licenses
            (id, customer_id, device_id, app_id, status, plan, started_at,
             expires_at, auto_renew, reseller_id, created_at, updated_at)
           VALUES (?, ?, ?, ?, 'active', ?, ?, ?, 0, ?, ?, ?)`
        ).bind(lid, dev.customer_id, dev.id, APP_ID, plan, now, expiresAt, null, now, now).run();
      }
      await env.DB.prepare("UPDATE devices SET block_status = NULL WHERE id = ?").bind(dev.id).run();
    }
    __name(setLicense, "setLicense");
    switch (action) {
      case "freeze":
        await env.DB.prepare("UPDATE devices SET block_status=? WHERE id=?").bind("frozen", dev.id).run();
        break;
      case "unfreeze":
        await env.DB.prepare("UPDATE devices SET block_status=NULL WHERE id=?").bind(dev.id).run();
        break;
      case "ban":
        await env.DB.prepare("UPDATE devices SET block_status=? WHERE id=?").bind("banned", dev.id).run();
        break;
      case "mark_paid":
      case "activate_lifetime":
        await setLicense("lifetime", null);
        break;
      case "activate_year":
        await setLicense("1y", now + 365 * DAY_MS2);
        break;
      case "renew": {
        const days = Number(body?.days) > 0 ? Number(body.days) : 365;
        const cur = await env.DB.prepare(
          `SELECT expires_at FROM licenses WHERE device_id = ?
             ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`
        ).bind(dev.id).first();
        if (cur && cur.expires_at === null) {
          await setLicense("lifetime", null);
        } else {
          const base = cur && cur.expires_at && cur.expires_at > now ? cur.expires_at : now;
          await setLicense(days >= 365 ? "1y" : "custom", base + days * DAY_MS2);
        }
        break;
      }
      case "mark_unpaid":
        await env.DB.prepare(
          `UPDATE licenses SET status='inactive', updated_at=? WHERE device_id=?`
        ).bind(now, dev.id).run();
        break;
      case "note": {
        const ex = await readClient(env, mac) || { mac, added_at: now };
        await writeClient(env, mac, { ...ex, note: String(body?.note || ""), updated_at: now });
        break;
      }
      default:
        return badRequest(
          "action must be one of: freeze, unfreeze, ban, mark_paid, activate_lifetime, activate_year, mark_unpaid, renew, note"
        );
    }
    if (action !== "note") {
      try {
        const ex = await readClient(env, mac) || { mac, added_at: now, name: "" };
        const m = { ...ex, updated_at: now };
        switch (action) {
          case "freeze":
            m.status = "frozen";
            break;
          case "unfreeze":
            m.status = "active";
            break;
          case "ban":
            m.status = "banned";
            break;
          case "mark_paid":
          case "activate_lifetime":
            m.status = "active";
            m.paid = true;
            m.plan = "lifetime";
            m.paid_until = null;
            break;
          case "activate_year":
            m.status = "active";
            m.paid = true;
            m.plan = "1y";
            m.paid_until = now + 365 * DAY_MS2;
            m.trial_until = m.paid_until;
            break;
          case "renew": {
            const days = Number(body?.days) > 0 ? Number(body.days) : 365;
            const base = m.paid_until && m.paid_until > now ? m.paid_until : now;
            m.status = "active";
            m.paid = true;
            m.plan = days >= 365 ? "1y" : "custom";
            m.paid_until = base + days * DAY_MS2;
            m.trial_until = m.paid_until;
            break;
          }
          case "mark_unpaid":
            m.paid = false;
            m.plan = null;
            m.paid_until = null;
            break;
        }
        await writeClient(env, mac, m);
      } catch (_) {
      }
    }
    const fresh = await d1StatusForMac(env, mac, now);
    return json2({ ok: true, mac, action, ...fresh || {} });
  }
  const existing = await readClient(env, mac);
  if (!existing)
    return notFound2(`Client ${mac} introuvable`);
  const updated = { ...existing, updated_at: now };
  switch (action) {
    case "freeze":
      updated.status = "frozen";
      break;
    case "unfreeze":
      updated.status = "active";
      break;
    case "ban":
      updated.status = "banned";
      break;
    case "mark_paid":
    case "activate_lifetime":
      updated.paid = true;
      updated.plan = "lifetime";
      updated.paid_until = null;
      break;
    case "activate_year":
      updated.paid = true;
      updated.plan = "1y";
      updated.paid_until = now + 365 * DAY_MS2;
      updated.trial_until = updated.paid_until;
      break;
    case "mark_unpaid":
      updated.paid = false;
      updated.plan = null;
      updated.paid_until = null;
      break;
    case "renew": {
      const days = Number(body?.days) > 0 ? Number(body.days) : 365;
      const base = updated.paid_until && updated.paid_until > now ? updated.paid_until : now;
      updated.paid = true;
      updated.plan = days >= 365 ? "1y" : "custom";
      updated.paid_until = base + days * DAY_MS2;
      updated.trial_until = updated.paid_until;
      break;
    }
    case "note":
      updated.note = String(body?.note || "");
      break;
    default:
      return badRequest(
        "action must be one of: freeze, unfreeze, ban, mark_paid, activate_lifetime, activate_year, mark_unpaid, renew, note"
      );
  }
  await writeClient(env, mac, updated);
  return json2({ ok: true, mac, ...updated });
}
__name(handleAdminAction, "handleAdminAction");
async function handleDeleteClient(env, mac) {
  await deleteClient(env, mac);
  return new Response(null, { status: 204, headers: JSON_HEADERS2 });
}
__name(handleDeleteClient, "handleDeleteClient");
async function handlePublicConfig(env, mac) {
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  const data = await readClient(env, mac);
  if (!data)
    return notFound2(`Aucun playlist configur\xE9e pour ${mac}`);
  return jsonPrivate({
    name: data.name || "",
    playlists: data.playlists || []
  });
}
__name(handlePublicConfig, "handlePublicConfig");
async function handlePublicServers(env) {
  if (env.DB) {
    try {
      const rs = await env.DB.prepare(
        `SELECT id, label, url FROM default_servers
            WHERE enabled = 1
            ORDER BY position ASC, created_at ASC`
      ).all();
      const rows = rs && rs.results || [];
      if (rows.length > 0) {
        return json2({
          servers: rows.map((r) => ({
            id: String(r.id),
            label: String(r.label),
            url: String(r.url).trim()
          }))
        });
      }
    } catch (_) {
    }
  }
  let servers = [];
  const raw = env.DEFAULT_SERVERS;
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        servers = parsed.filter((s) => s && typeof s.url === "string" && s.url.trim()).map((s, i) => ({
          id: String(s.id || `srv${i + 1}`),
          label: String(s.label || `Serveur ${i + 1}`),
          url: String(s.url).trim()
        }));
      }
    } catch (_) {
    }
  }
  return json2({ servers });
}
__name(handlePublicServers, "handlePublicServers");
async function handlePublicDeviceSource(env, mac) {
  const res = await handlePublicDeviceSourceInner(env, mac);
  if (res.status !== 200 || !env.DB || !MAC_RX3.test(mac))
    return res;
  try {
    const rev = await currentRevision(env, mac.toUpperCase());
    if (rev == null)
      return res;
    const body = await res.clone().json();
    return jsonPrivate({ ...body, rev });
  } catch (_) {
    return res;
  }
}
__name(handlePublicDeviceSource, "handlePublicDeviceSource");
async function handlePublicDeviceSourceInner(env, mac) {
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  const MAC = mac.toUpperCase();
  if (env.DB) {
    try {
      const st = await d1StatusForMac(env, MAC);
      if (st && (st.expired || st.frozen || st.banned)) {
        return jsonPrivate({
          mac: MAC,
          source: null,
          sources: [],
          blocked: st.banned ? "banned" : st.frozen ? "frozen" : "expired"
        });
      }
    } catch (_) {
    }
  }
  if (env.DB) {
    try {
      const row = await env.DB.prepare(
        `SELECT type, label, server_url, username, password, m3u_url, epg_url, sources_json, updated_at
             FROM device_sources WHERE mac = ?`
      ).bind(MAC).first();
      if (row) {
        let sources = [];
        if (row.sources_json) {
          try {
            sources = JSON.parse(row.sources_json) || [];
          } catch (_) {
            sources = [];
          }
        }
        if (!sources.length) {
          const { sources_json, updated_at, ...single } = row;
          sources = [single];
        }
        sources = await openSourceList(env, sources);
        const live = resolvePublicSource({
          d1Sources: sources,
          kvSource: null,
          clearedAt: 0
        });
        return jsonPrivate({
          mac: MAC,
          source: live.source,
          sources: live.sources,
          updated_at: row.updated_at || 0,
          cleared: false
        });
      }
    } catch (_) {
    }
  }
  const clearedAt = await readSourceTombstone(env, MAC);
  let kvSource = null;
  try {
    const client = await readClient(env, MAC);
    const pls = client && Array.isArray(client.playlists) ? client.playlists : [];
    if (pls.length > 0) {
      const p = pls[0] || {};
      const label = p.name || client && client.name || "Mon abonnement";
      const updatedAt = client && client.updated_at || 0;
      let source = null;
      if (p.type === "xtream" && p.server && p.username && p.password) {
        source = {
          type: "xtream",
          label,
          server_url: p.server,
          username: p.username,
          password: p.password,
          m3u_url: null,
          epg_url: p.epg_url || null,
          updated_at: updatedAt
        };
      } else if (p.type === "m3u" && p.url) {
        source = {
          type: "m3u",
          label,
          server_url: null,
          username: null,
          password: null,
          m3u_url: p.url,
          epg_url: p.epg_url || null,
          updated_at: updatedAt
        };
      }
      kvSource = source;
    }
  } catch (_) {
  }
  const decided = resolvePublicSource({
    d1Sources: [],
    kvSource,
    clearedAt
  });
  return jsonPrivate({
    mac: MAC,
    source: decided.source,
    sources: decided.sources,
    cleared: decided.cleared,
    cleared_at: clearedAt || 0
  });
}
__name(handlePublicDeviceSourceInner, "handlePublicDeviceSourceInner");
var MAX_SELF_SOURCES = 20;
async function ensureDeviceSourcesTable(env) {
  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS device_sources (
         mac TEXT PRIMARY KEY, type TEXT NOT NULL, label TEXT, server_url TEXT,
         username TEXT, password TEXT, m3u_url TEXT, epg_url TEXT,
         sources_json TEXT, updated_at INTEGER NOT NULL)`
    ).run();
  } catch (_) {
  }
  try {
    await env.DB.prepare("ALTER TABLE device_sources ADD COLUMN origin TEXT").run();
  } catch (_) {
  }
}
__name(ensureDeviceSourcesTable, "ensureDeviceSourcesTable");
async function readDeviceSourceItems(env, MAC) {
  let row;
  try {
    row = await env.DB.prepare(
      `SELECT type, label, server_url, username, password, m3u_url, epg_url, sources_json, origin
         FROM device_sources WHERE mac = ?`
    ).bind(MAC).first();
  } catch (_) {
    row = null;
  }
  if (!row)
    return { items: [], needsPersist: false };
  let items = [];
  if (row.sources_json) {
    try {
      items = JSON.parse(row.sources_json) || [];
    } catch (_) {
      items = [];
    }
  }
  if (!Array.isArray(items) || !items.length) {
    items = [{
      type: row.type,
      label: row.label,
      server_url: row.server_url,
      username: row.username,
      password: row.password,
      m3u_url: row.m3u_url,
      epg_url: row.epg_url
    }];
  }
  const rowSelf = String(row.origin || "") === "self";
  let needsPersist = false;
  let unreadable = false;
  const opened = [];
  for (const s of items) {
    const it = await openSource(env, { ...s });
    if (it.origin !== "self" && it.origin !== "panel") {
      it.origin = rowSelf ? "self" : "panel";
      needsPersist = true;
    }
    if (it.origin === "self" && !it.id) {
      it.id = crypto.randomUUID();
      needsPersist = true;
    }
    for (const field of ["password", "m3u_url"]) {
      const raw = s && s[field];
      if (typeof raw === "string" && (raw.startsWith("enc1.") || raw.startsWith("enc1:")) && !it[field]) {
        unreadable = true;
      }
    }
    opened.push(it);
  }
  return { items: opened, needsPersist: needsPersist && !unreadable };
}
__name(readDeviceSourceItems, "readDeviceSourceItems");
function normalizeStoredOrigins(row, items) {
  const rowSelf = row && String(row.origin || "") === "self";
  let changed = false;
  const out = items.map((s) => {
    const it = { ...s };
    if (it.origin !== "self" && it.origin !== "panel") {
      it.origin = rowSelf ? "self" : "panel";
      changed = true;
    }
    if (it.origin === "self" && !it.id) {
      it.id = crypto.randomUUID();
      changed = true;
    }
    return it;
  });
  return { items: out, changed };
}
__name(normalizeStoredOrigins, "normalizeStoredOrigins");
async function writeSelfChange(env, MAC, mutate, revision) {
  const out = await casWriteSources(env, MAC, mutate, { revision });
  if (out.abort !== void 0 || out.conflict)
    return out;
  if (!out.items.length)
    await markSourcesCleared(env, MAC, Date.now());
  else
    await clearSourceTombstone(env, MAC);
  return out;
}
__name(writeSelfChange, "writeSelfChange");
function publicItemView(it, idx) {
  const locked = it.origin !== "self";
  return {
    id: it.id || (locked ? "panel-" + idx : null),
    origin: it.origin,
    locked,
    type: it.type || "m3u",
    label: it.label || "Ma playlist",
    server_url: it.server_url || null,
    username: it.username || null,
    m3u_url: it.m3u_url || null,
    epg_url: it.epg_url || null,
    has_password: !!it.password
  };
}
__name(publicItemView, "publicItemView");
function buildSourceFromBody(body) {
  const type = String(body.type || "").trim().toLowerCase();
  const label = (String(body.label || "").trim() || "Ma playlist").slice(0, 80);
  const epgRaw = String(body.epg_url || "").trim();
  let epg = null;
  if (epgRaw) {
    const epgErr = httpUrlError(epgRaw, "epg_url");
    if (epgErr)
      return { error: epgErr };
    epg = epgRaw;
  }
  if (type === "xtream") {
    const server = String(body.server_url || "").trim();
    const user = String(body.username || "").trim().slice(0, 256);
    const pass = String(body.password || "").trim().slice(0, 256);
    if (!server || !user || !pass)
      return { error: "xtream requires server_url, username, password" };
    const serverErr = sourceUrlProblem(server, "server_url");
    if (serverErr)
      return { error: serverErr };
    const credErr = sourceTextProblem(user, "username") || sourceTextProblem(pass, "password");
    if (credErr)
      return { error: credErr };
    return { source: { type: "xtream", label, server_url: server, username: user, password: pass, m3u_url: null, epg_url: epg } };
  }
  if (type === "m3u") {
    const m3u = String(body.m3u_url || "").trim();
    if (!m3u)
      return { error: "m3u requires m3u_url" };
    const m3uErr = sourceUrlProblem(m3u, "m3u_url");
    if (m3uErr)
      return { error: m3uErr };
    return { source: { type: "m3u", label, server_url: null, username: null, password: null, m3u_url: m3u, epg_url: epg } };
  }
  return { error: "type must be 'xtream' or 'm3u'" };
}
__name(buildSourceFromBody, "buildSourceFromBody");
async function handleSelfSourceGet(env, mac) {
  if (!env.DB)
    return jsonPrivate({ ok: false, error: "db_unavailable" }, 503);
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  const MAC = mac.toUpperCase();
  await ensureDeviceSourcesTable(env);
  const { items, needsPersist } = await readDeviceSourceItems(env, MAC);
  if (needsPersist && items.length) {
    try {
      await writeSelfChange(env, MAC, (row, stored) => {
        const n = normalizeStoredOrigins(row, stored);
        return n.changed ? { items: n.items } : { abort: null };
      }, null);
    } catch (_) {
    }
    const again = await readDeviceSourceItems(env, MAC);
    items.splice(0, items.length, ...again.items);
  }
  const view = items.map(publicItemView);
  const selfCount = items.filter((s) => s.origin === "self").length;
  return jsonPrivate({
    ok: true,
    mac: MAC,
    items: view,
    count: view.length,
    canAdd: selfCount < MAX_SELF_SOURCES,
    maxItems: MAX_SELF_SOURCES
  });
}
__name(handleSelfSourceGet, "handleSelfSourceGet");
async function handleSelfSource(env, mac, request) {
  if (!env.DB)
    return jsonPrivate({ ok: false, error: "db_unavailable" }, 503);
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  const MAC = mac.toUpperCase();
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest("invalid json");
  }
  const built = buildSourceFromBody(body);
  if (built.error)
    return badRequest(built.error);
  const source = built.source;
  await ensureDeviceSourcesTable(env);
  const editId = body.id ? String(body.id) : null;
  const newId = crypto.randomUUID();
  let out;
  try {
    out = await writeSelfChange(env, MAC, (row, stored) => {
      const { items } = normalizeStoredOrigins(row, stored);
      if (editId) {
        const idx = items.findIndex((s) => s.origin === "self" && s.id === editId);
        if (idx < 0) {
          return { abort: jsonPrivate({ ok: false, reason: "not_found", message: "Cette playlist n'existe pas ou est prot\xE9g\xE9e." }, 404) };
        }
        items[idx] = { ...source, origin: "self", id: editId };
        return { items };
      }
      const selfCount = items.filter((s) => s.origin === "self").length;
      if (selfCount >= MAX_SELF_SOURCES) {
        return { abort: jsonPrivate({
          ok: false,
          reason: "too_many",
          message: "Limite atteinte (" + MAX_SELF_SOURCES + " playlists). Supprimez-en une pour en ajouter une autre."
        }, 409) };
      }
      items.push({ ...source, origin: "self", id: newId });
      return { items };
    }, { actor: { type: "customer", id: MAC } });
  } catch (_) {
    return jsonPrivate({ ok: false, error: "db_write_failed" }, 500);
  }
  if (out.abort !== void 0)
    return out.abort;
  if (out.conflict)
    return jsonPrivate({ ok: false, error: "conflict", message: "Vos listes changent en ce moment. R\xE9essayez." }, 409);
  return jsonPrivate({
    ok: true,
    message: editId ? "Playlist mise \xE0 jour ! Ouvrez (ou red\xE9marrez) l'app." : "Playlist ajout\xE9e ! Ouvrez l'app (ou red\xE9marrez-la) : vos cha\xEEnes vont appara\xEEtre."
  });
}
__name(handleSelfSource, "handleSelfSource");
async function handleSelfSourceDelete(env, mac, request) {
  if (!env.DB)
    return jsonPrivate({ ok: false, error: "db_unavailable" }, 503);
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  const MAC = mac.toUpperCase();
  await ensureDeviceSourcesTable(env);
  let delId = null;
  try {
    delId = new URL(request.url).searchParams.get("id");
  } catch (_) {
    delId = null;
  }
  const out = await removeSelfSourceItem(env, MAC, delId);
  return jsonPrivate(out.body, out.status);
}
__name(handleSelfSourceDelete, "handleSelfSourceDelete");
async function removeSelfSourceItem(env, MAC, delId, actor = { type: "customer", id: MAC }) {
  let out;
  try {
    out = await writeSelfChange(env, MAC, (row, stored) => {
      const { items } = normalizeStoredOrigins(row, stored);
      if (!items.length)
        return { abort: { status: 200, body: { ok: true, message: "Aucune playlist \xE0 supprimer." } } };
      if (delId) {
        const target = items.find((s) => s.id === delId);
        if (!target)
          return { abort: { status: 404, body: { ok: false, reason: "not_found", message: "Playlist introuvable." } } };
        if (target.origin !== "self") {
          return { abort: { status: 409, body: { ok: false, reason: "locked", message: "Cette playlist est g\xE9r\xE9e par votre conseiller." } } };
        }
        return { items: items.filter((s) => s.id !== delId) };
      }
      return { items: items.filter((s) => s.origin !== "self") };
    }, { actor });
  } catch (_) {
    return { status: 500, body: { ok: false, error: "db_write_failed" } };
  }
  if (out.abort !== void 0)
    return out.abort;
  if (out.conflict)
    return { status: 409, body: { ok: false, error: "conflict", message: "Les listes changent en ce moment. R\xE9essayez." } };
  return { status: 200, body: { ok: true, message: "Playlist supprim\xE9e.", remaining: out.items.length, rev: out.rev } };
}
__name(removeSelfSourceItem, "removeSelfSourceItem");
async function handlePanelRemoveSelfSource(request, env, mac, id) {
  const auth = request.headers.get("Authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  const user = m ? await panelActorFromToken(env, m[1]) : null;
  if (!user)
    return json2({ error: "no_auth", message: "Missing Authorization header" }, 401);
  const MAC = String(mac || "").toUpperCase();
  if (!MAC_RX3.test(MAC))
    return badRequest("invalid mac");
  if (!env.DB)
    return json2({ error: "no_db" }, 503);
  if (user.role === "reseller") {
    const dev = await env.DB.prepare("SELECT reseller_id FROM devices WHERE mac = ?").bind(MAC).first();
    if (!dev || dev.reseller_id !== user.sub) {
      return json2({ error: "forbidden", message: "Cet appareil ne vous appartient pas" }, 403);
    }
  }
  await ensureDeviceSourcesTable(env);
  const out = await removeSelfSourceItem(
    env,
    MAC,
    String(id || ""),
    { type: user.role === "reseller" ? "reseller" : "admin", id: user.sub }
  );
  if (out.status === 200) {
    const traceId = panelTraceId(request);
    request = withTraceHeader(request, traceId);
    await notifyBox(env, MAC, "source", { traceId });
    await logAudit(
      env,
      request,
      { type: user.role === "reseller" ? "reseller" : "admin", id: user.sub },
      "source.self_remove",
      { type: "device", id: MAC },
      null,
      { source_id: String(id || "") }
    );
  }
  return json2(out.body, out.status);
}
__name(handlePanelRemoveSelfSource, "handlePanelRemoveSelfSource");
function withTraceHeader(request, traceId) {
  const headers = new Headers(request.headers);
  headers.set("X-Request-Id", traceId);
  return new Request(request, { headers });
}
__name(withTraceHeader, "withTraceHeader");
function panelTraceId(request) {
  const given = (request.headers.get("X-Request-Id") || "").trim();
  return /^[A-Za-z0-9_.:-]{8,64}$/.test(given) ? given : crypto.randomUUID();
}
__name(panelTraceId, "panelTraceId");
async function handlePanelResetBox(request, env, mac) {
  const t1 = Date.now();
  const auth = request.headers.get("Authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  const user = m ? await panelActorFromToken(env, m[1]) : null;
  if (!user)
    return json2({ error: "no_auth", message: "Missing Authorization header" }, 401);
  const MAC = String(mac || "").toUpperCase();
  if (!MAC_RX3.test(MAC))
    return badRequest("invalid mac");
  if (!env.DB)
    return json2({ error: "no_db" }, 503);
  if (user.role === "reseller") {
    const dev = await env.DB.prepare("SELECT reseller_id FROM devices WHERE mac = ?").bind(MAC).first();
    if (!dev || dev.reseller_id !== user.sub) {
      return json2({ error: "forbidden", message: "Cet appareil ne vous appartient pas" }, 403);
    }
  }
  await ensureDeviceSourcesTable(env);
  await ensureResetColumn(env);
  const now = Date.now();
  const traceId = panelTraceId(request);
  request = withTraceHeader(request, traceId);
  const actorRef = { type: user.role === "reseller" ? "reseller" : "admin", id: user.sub };
  const wiped = await casWriteSources(env, MAC, () => ({ items: [] }), { revision: { traceId, actor: actorRef } });
  if (wiped.conflict)
    return json2({ error: "conflict", message: "Les listes changent en ce moment. R\xE9essaie." }, 409);
  const rev = wiped.rev;
  await markSourcesCleared(env, MAC, now);
  const upd = await env.DB.prepare("UPDATE devices SET reset_at = ? WHERE mac = ?").bind(now, MAC).run();
  if (!upd || !upd.meta || !upd.meta.changes) {
    return json2({ error: "not_found", message: "Appareil inconnu" }, 404);
  }
  const order = await notifyBox(env, MAC, "reset", { traceId, t1, configRev: rev });
  await notifyBox(env, MAC, "source", { traceId, t1, configRev: rev });
  await logAudit(
    env,
    request,
    { type: user.role === "reseller" ? "reseller" : "admin", id: user.sub },
    "device.reset",
    { type: "device", id: MAC },
    null,
    { reset_at: now, rev, order_id: order }
  );
  return json2({ ok: true, mac: MAC, reset_at: now, rev, order_id: order, trace_id: traceId });
}
__name(handlePanelResetBox, "handlePanelResetBox");
var _resetColumnReady = /* @__PURE__ */ new WeakSet();
async function ensureResetColumn(env) {
  if (!env.DB || _resetColumnReady.has(env.DB))
    return;
  try {
    await env.DB.prepare("ALTER TABLE devices ADD COLUMN reset_at INTEGER").run();
  } catch (_) {
  }
  _resetColumnReady.add(env.DB);
}
__name(ensureResetColumn, "ensureResetColumn");
async function resetAtFor(env, mac) {
  if (!env.DB)
    return 0;
  try {
    const row = await env.DB.prepare("SELECT reset_at FROM devices WHERE mac = ?").bind(mac).first();
    const v = row && row.reset_at;
    return typeof v === "number" && v > 0 ? v : 0;
  } catch (_) {
    return 0;
  }
}
__name(resetAtFor, "resetAtFor");
async function handlePublicHistory(env, mac) {
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  const MAC = mac.toUpperCase();
  let recent = [];
  if (env.DB) {
    try {
      const row = await env.DB.prepare("SELECT recent_json FROM devices WHERE mac = ?").bind(MAC).first();
      if (row && row.recent_json) {
        try {
          recent = JSON.parse(row.recent_json) || [];
        } catch (_) {
          recent = [];
        }
      }
    } catch (_) {
    }
  }
  return json2({ mac: MAC, recent });
}
__name(handlePublicHistory, "handlePublicHistory");
async function handlePublicFamilyM3u(env, rawToken) {
  if (!env.DB)
    return new Response("not found", { status: 404 });
  const token = String(rawToken || "").replace(/\.(m3u8?|ts)$/i, "").trim();
  if (!token)
    return new Response("not found", { status: 404 });
  try {
    const link = await env.DB.prepare("SELECT family_id FROM family_links WHERE token = ?").bind(token).first();
    if (!link)
      return new Response("lien invalide", { status: 404 });
    const fam = await env.DB.prepare("SELECT source_json FROM families WHERE id = ?").bind(link.family_id).first();
    if (!fam || !fam.source_json)
      return new Response("source absente", { status: 404 });
    let src;
    try {
      src = JSON.parse(fam.source_json);
    } catch (_) {
      src = null;
    }
    src = await openSource(env, src);
    if (!src)
      return new Response("source invalide", { status: 404 });
    let target = null;
    if (src.type === "xtream" && src.server_url && src.username && src.password) {
      const base = String(src.server_url).replace(/\/+$/, "");
      if (!/^https?:\/\//i.test(base))
        return new Response("source invalide", { status: 400 });
      const u = encodeURIComponent(src.username);
      const p = encodeURIComponent(src.password);
      target = `${base}/get.php?username=${u}&password=${p}&type=m3u_plus&output=ts`;
    } else if (src.type === "m3u" && src.m3u_url) {
      target = src.m3u_url;
    }
    if (!target || !/^https?:\/\//i.test(target) || /[\s<>]/.test(target)) {
      return new Response("source invalide", { status: 400 });
    }
    return Response.redirect(target, 302);
  } catch (_) {
    return new Response("erreur", { status: 500 });
  }
}
__name(handlePublicFamilyM3u, "handlePublicFamilyM3u");
async function handleDeviceBackup(request, env, mac, method) {
  if (!MAC_RX3.test(mac))
    return badRequest("invalid mac");
  const MAC = mac.toUpperCase();
  if (!env.DB)
    return jsonPrivate({ mac: MAC, data: null, updated_at: 0 });
  try {
    await env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS device_backups (
         mac        TEXT PRIMARY KEY,
         data_json  TEXT,
         updated_at INTEGER
       )`
    ).run();
  } catch (_) {
  }
  if (method === "GET") {
    try {
      const row = await env.DB.prepare("SELECT data_json, updated_at FROM device_backups WHERE mac = ?").bind(MAC).first();
      if (!row)
        return jsonPrivate({ mac: MAC, data: null, updated_at: 0 });
      let data = null;
      try {
        data = row.data_json ? JSON.parse(row.data_json) : null;
      } catch (_) {
        data = null;
      }
      return jsonPrivate({ mac: MAC, data, updated_at: row.updated_at || 0 });
    } catch (_) {
      return jsonPrivate({ mac: MAC, data: null, updated_at: 0 });
    }
  }
  if (method === "PUT") {
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return badRequest("invalid JSON body");
    }
    const data = body && body.data !== void 0 ? body.data : body;
    let str;
    try {
      str = JSON.stringify(data);
    } catch (_) {
      return badRequest("data not serializable");
    }
    if (str && str.length > 256 * 1024)
      return badRequest("backup too large");
    const now = Date.now();
    try {
      await env.DB.prepare(
        `INSERT INTO device_backups (mac, data_json, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(mac) DO UPDATE SET
           data_json = excluded.data_json,
           updated_at = excluded.updated_at`
      ).bind(MAC, str, now).run();
      return jsonPrivate({ ok: true, mac: MAC, updated_at: now });
    } catch (e) {
      try {
        console.error("[backup] put failed", String(e && e.stack ? e.stack : e));
      } catch (_) {
      }
      return jsonPrivate({ ok: false, error: "backup_failed" }, 500);
    }
  }
  return badRequest("only GET/PUT supported on /api/backup/:mac");
}
__name(handleDeviceBackup, "handleDeviceBackup");
async function handleAiSearch(request, env) {
  if (request.method !== "POST") {
    return badRequest("only POST supported on /api/ai/search");
  }
  const key = env.MISTRAL_API_KEY;
  if (!key) {
    return json2(
      { error: "ai_disabled", message: "Recherche IA non configur\xE9e." },
      503
    );
  }
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return badRequest("invalid JSON body");
  }
  const query = body && typeof body.query === "string" ? body.query.trim() : "";
  if (!query)
    return badRequest("query required");
  if (query.length > 300)
    return badRequest("query too long");
  const model = env.AI_MODEL || "mistral-small-latest";
  const system = `Tu convertis une requ\xEAte utilisateur en langage naturel en un FILTRE de recherche pour une application de lecteur multim\xE9dia (IPTV). R\xE9ponds UNIQUEMENT par un objet JSON valide, sans texte autour, sans bloc de code. Champs obligatoires : keywords (tableau de mots-cl\xE9s simples, en minuscules, sans articles, dans la langue de la requ\xEAte) ; type ('live' pour cha\xEEnes/direct, 'movie' pour films, 'series' pour s\xE9ries, 'any' si ind\xE9termin\xE9) ; genres (tableau ; ex: sport, football, actualit\xE9s, enfants, musique, cin\xE9ma, documentaire) ; title_contains (un titre pr\xE9cis si l'utilisateur en cite un, sinon cha\xEEne vide) ; language (langue si mentionn\xE9e, sinon cha\xEEne vide). Laisse un champ vide ([] ou '') s'il n'est pas pertinent. Exemple de r\xE9ponse : {"keywords":["foot","ligue 1"],"type":"live","genres":["sport","football"],"title_contains":"","language":"fr"}`;
  try {
    const resp = await fetch("https://api.mistral.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${key}`
      },
      body: JSON.stringify({
        model,
        max_tokens: 400,
        temperature: 0,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system },
          { role: "user", content: query }
        ]
      }),
      // Time-out dur : une recherche doit rester rapide, et un amont qui pend
      // ne doit pas bloquer le worker. AbortSignal.timeout est supporté sur
      // le runtime Workers.
      signal: AbortSignal.timeout(8e3)
    });
    if (!resp.ok) {
      console.error("[ai] upstream error", resp.status);
      return json2({ error: "ai_upstream", status: resp.status }, 502);
    }
    const data = await resp.json();
    let filter = null;
    const content = data && Array.isArray(data.choices) && data.choices[0] && data.choices[0].message && typeof data.choices[0].message.content === "string" ? data.choices[0].message.content : null;
    if (content) {
      try {
        filter = JSON.parse(content);
      } catch (_) {
        filter = null;
      }
    }
    if (!filter)
      return json2({ error: "ai_parse" }, 502);
    return json2({ ok: true, filter });
  } catch (e) {
    try {
      console.error("[ai] error", String(e && e.stack ? e.stack : e));
    } catch (_) {
    }
    return json2({ error: "ai_error" }, 502);
  }
}
__name(handleAiSearch, "handleAiSearch");
async function ensureScreenTable(env) {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS screen_sessions (
       code        TEXT PRIMARY KEY,
       state_json  TEXT,
       created_at  INTEGER,
       updated_at  INTEGER,
       expires_at  INTEGER
     )`
  ).run();
}
__name(ensureScreenTable, "ensureScreenTable");
function newScreenCode() {
  const ALPHA = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  const r = crypto.getRandomValues(new Uint8Array(4));
  let c = "";
  for (let i = 0; i < 4; i++)
    c += ALPHA[r[i] % ALPHA.length];
  return c;
}
__name(newScreenCode, "newScreenCode");
function screenB64Url(str) {
  const b = btoa(unescape(encodeURIComponent(str)));
  return b.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
__name(screenB64Url, "screenB64Url");
async function handleScreen(request, env, segments) {
  if (!env.DB)
    return json2({ error: "db_unbound" }, 503);
  await ensureScreenTable(env);
  const now = Date.now();
  const TTL = 6 * 60 * 60 * 1e3;
  const origin = new URL(request.url).origin;
  if (segments[2] === "new" && request.method === "POST") {
    let code2 = "";
    for (let i = 0; i < 6; i++) {
      code2 = newScreenCode();
      const ex = await env.DB.prepare(
        "SELECT code FROM screen_sessions WHERE code = ?"
      ).bind(code2).first();
      if (!ex)
        break;
    }
    await env.DB.prepare(
      `INSERT INTO screen_sessions (code, state_json, created_at, updated_at, expires_at)
       VALUES (?, ?, ?, ?, ?)`
    ).bind(code2, JSON.stringify({ action: "idle", seq: 0 }), now, now, now + TTL).run();
    return json2({ ok: true, code: code2, url: `${origin}/e/${code2}` });
  }
  const code = String(segments[2] || "").toUpperCase();
  if (!/^[2-9A-Z]{4}$/.test(code))
    return badRequest("bad code");
  if (segments.length === 3 && request.method === "GET") {
    const row = await env.DB.prepare(
      "SELECT state_json, expires_at FROM screen_sessions WHERE code = ?"
    ).bind(code).first();
    if (!row || (row.expires_at || 0) < now)
      return json2({ action: "expired" });
    let st;
    try {
      st = JSON.parse(row.state_json || "{}");
    } catch (_) {
      st = { action: "idle", seq: 0 };
    }
    return json2(st);
  }
  if (segments[3] === "command" && request.method === "POST") {
    const row = await env.DB.prepare(
      "SELECT state_json FROM screen_sessions WHERE code = ?"
    ).bind(code).first();
    if (!row)
      return json2({ error: "no_session" }, 404);
    let body;
    try {
      body = await request.json();
    } catch (_) {
      return badRequest("bad json");
    }
    let prev;
    try {
      prev = JSON.parse(row.state_json || "{}");
    } catch (_) {
      prev = {};
    }
    const seq = (prev.seq || 0) + 1;
    const action = String(body && body.action || "");
    let state;
    if (action === "play") {
      const raw = String(body && body.url || "");
      if (!raw)
        return badRequest("url required");
      const playUrl = `${origin}/cs/${screenB64Url(raw)}.ts`;
      state = {
        action: "play",
        type: "ts",
        playUrl,
        title: String(body && body.title || ""),
        paused: false,
        seq
      };
    } else if (action === "pause") {
      state = { ...prev, action: "control", paused: true, seq };
    } else if (action === "resume") {
      state = { ...prev, action: "control", paused: false, seq };
    } else if (action === "stop") {
      state = { action: "idle", seq };
    } else {
      return badRequest("bad action");
    }
    const t = Date.now();
    await env.DB.prepare(
      "UPDATE screen_sessions SET state_json = ?, updated_at = ?, expires_at = ? WHERE code = ?"
    ).bind(JSON.stringify(state), t, t + TTL, code).run();
    return json2({ ok: true, seq });
  }
  return badRequest("unsupported screen route");
}
__name(handleScreen, "handleScreen");
var worker_default = {
  async fetch(request, env, ctx) {
    try {
      return await handleRequest(request, env, ctx);
    } catch (e) {
      const requestId = globalThis.crypto && crypto.randomUUID && crypto.randomUUID() || Date.now().toString(36);
      try {
        console.error(
          "[worker] unhandled error",
          requestId,
          e && e.stack ? e.stack : String(e)
        );
      } catch (_) {
      }
      return json2({ error: "internal_error", request_id: requestId }, 500);
    }
  }
};
async function handleRequest(request, env, ctx) {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: JSON_HEADERS2 });
  }
  const url = new URL(request.url);
  {
    const slug = url.pathname.replace(/^\/+|\/+$/g, "").toLowerCase();
    const GH = "https://github.com/manzilionellm-dotcom/tvking/releases/download";
    const DOWNLOADS = {
      royal: `${GH}/latest/7motion.apk`,
      get: `${GH}/latest/7motion.apk`,
      black7: `${GH}/latest/7motion.apk`
    };
    if (DOWNLOADS[slug]) {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return badRequest("only GET supported on download links");
      }
      return Response.redirect(DOWNLOADS[slug], 302);
    }
  }
  if (url.pathname === "/api/v1/rt/ws") {
    const token = url.searchParams.get("token") || "";
    const user = await panelActorFromToken(env, token);
    if (!user)
      return json2({ error: "no_auth" }, 401);
    return openPanelSocket(request, env, { id: user.sub, role: user.role });
  }
  {
    const selfRemove = url.pathname.match(/^\/api\/v1\/sources\/([^/]+)\/self\/([^/]+)$/);
    if (selfRemove && request.method === "DELETE") {
      return handlePanelRemoveSelfSource(
        request,
        env,
        decodeURIComponent(selfRemove[1]),
        decodeURIComponent(selfRemove[2])
      );
    }
    const resetBox = url.pathname.match(/^\/api\/v1\/sources\/([^/]+)\/reset$/);
    if (resetBox && request.method === "POST") {
      return handlePanelResetBox(request, env, decodeURIComponent(resetBox[1]));
    }
  }
  if (url.pathname.startsWith("/api/v1/")) {
    return apiV1(request, env);
  }
  const segments = url.pathname.split("/").filter(Boolean);
  {
    const seg0 = segments[0] || "";
    const seg1 = segments[1] || "";
    let rl = null;
    if (seg0 === "api") {
      if (seg1 === "ai")
        rl = ["ai", 30];
      else if (seg1 === "device-source" || seg1 === "backup" || seg1 === "status" || seg1 === "history" || seg1 === "self-source")
        rl = ["dev", 120];
      else if (seg1 === "heartbeat" || seg1 === "trending" || seg1 === "announcement" || seg1 === "sports" || seg1 === "feedback" || seg1 === "m3u" || seg1 === "blackbox")
        rl = ["pub", 240];
      else if (seg1 === "screen")
        rl = ["scr", 600];
    } else if (seg0 === "config") {
      rl = ["cfg", 120];
    } else if (seg0 === "cast-proxy" || seg0 === "cast-sign") {
      rl = ["dev", 240];
    }
    if (rl && !await rateLimitOk(env, request, rl[0], rl[1], 60 * 1e3)) {
      return tooManyRequests();
    }
  }
  if (segments[0] === "config" && segments.length === 2) {
    if (request.method !== "GET") {
      return badRequest("only GET supported on /config/:mac");
    }
    return handlePublicConfig(env, segments[1]);
  }
  if (segments[0] === "api" && segments[1] === "blackbox") {
    if (request.method !== "POST" || segments.length !== 2) {
      return badRequest("only POST supported on /api/blackbox");
    }
    return handleBlackboxPost(request, env);
  }
  if (segments[0] === "api" && segments[1] === "heartbeat" && segments.length === 2) {
    if (request.method !== "POST") {
      return badRequest("only POST supported on /api/heartbeat");
    }
    return handleHeartbeat(request, env, ctx);
  }
  if (segments[0] === "api" && segments[1] === "status" && segments.length === 3) {
    if (request.method !== "GET") {
      return badRequest("only GET supported on /api/status/:mac");
    }
    return handlePublicStatus(env, segments[2]);
  }
  if (segments[0] === "api" && segments[1] === "servers" && segments.length === 2) {
    if (request.method !== "GET") {
      return badRequest("only GET supported on /api/servers");
    }
    return await handlePublicServers(env);
  }
  if (segments[0] === "api" && segments[1] === "box" && (segments[2] === "ws" || segments[2] === "wait" || segments[2] === "ack")) {
    const isAck = segments[2] === "ack";
    if (!await rateLimitOk(env, request, isAck ? "boxack" : "box", isAck ? 600 : 60, 60 * 1e3)) {
      return tooManyRequests();
    }
    const boxed = await handleBoxRoute(request, env, segments);
    if (boxed)
      return boxed;
  }
  if (segments[0] === "api" && segments[1] === "device-source" && segments.length === 3) {
    if (request.method !== "GET") {
      return badRequest("only GET supported on /api/device-source/:mac");
    }
    if (!await rateLimitOk(env, request, "devsrc", 120, 60 * 1e3)) {
      return tooManyRequests();
    }
    return await handlePublicDeviceSource(env, segments[2]);
  }
  if (segments[0] === "api" && segments[1] === "self-source" && segments.length === 3) {
    const smac = decodeMacPath(segments[2]);
    if (request.method === "GET")
      return await handleSelfSourceGet(env, smac);
    if (request.method === "POST")
      return await handleSelfSource(env, smac, request);
    if (request.method === "DELETE")
      return await handleSelfSourceDelete(env, smac, request);
    return badRequest("only GET, POST or DELETE supported on /api/self-source/:mac");
  }
  if (segments[0] === "api" && segments[1] === "history" && segments.length === 3) {
    if (request.method !== "GET") {
      return badRequest("only GET supported on /api/history/:mac");
    }
    return await handlePublicHistory(env, segments[2]);
  }
  if (segments[0] === "api" && segments[1] === "trending" && segments.length === 2) {
    if (request.method !== "GET") {
      return badRequest("only GET supported on /api/trending");
    }
    return await handleTrending(env);
  }
  if (segments[0] === "api" && segments[1] === "sports" && segments[2] === "search" && segments.length === 3) {
    if (request.method !== "GET")
      return badRequest("only GET");
    return await handleSportsSearch(url);
  }
  if (segments[0] === "api" && segments[1] === "sports" && segments[2] === "team" && segments.length === 4) {
    if (request.method !== "GET")
      return badRequest("only GET");
    return await handleSportsTeam(segments[3]);
  }
  if (segments[0] === "api" && segments[1] === "m3u" && segments.length === 3) {
    return await handlePublicFamilyM3u(env, segments[2]);
  }
  if (segments[0] === "api" && segments[1] === "backup" && segments.length === 3) {
    if (request.method !== "GET" && request.method !== "PUT") {
      return badRequest("only GET/PUT supported on /api/backup/:mac");
    }
    return await handleDeviceBackup(request, env, segments[2], request.method);
  }
  if (segments[0] === "api" && segments[1] === "ai" && segments[2] === "search" && segments.length === 3) {
    return await handleAiSearch(request, env);
  }
  if (segments[0] === "api" && segments[1] === "announcement" && segments.length === 2) {
    if (request.method === "GET") {
      return await handleGetAnnouncement(env, request);
    }
    if (request.method === "POST") {
      if (!checkAdmin(request, env))
        return unauthorized();
      return await handlePostAnnouncement(request, env);
    }
    if (request.method === "DELETE") {
      if (!checkAdmin(request, env))
        return unauthorized();
      return await handleClearAnnouncements(env);
    }
    return badRequest("only GET/POST/DELETE supported on /api/announcement");
  }
  if (segments[0] === "api" && segments[1] === "home-layout" && segments.length === 2) {
    if (request.method === "GET") {
      return await handleGetHomeLayout(env);
    }
    return badRequest("only GET supported on /api/home-layout");
  }
  if (segments[0] === "api" && segments[1] === "app-version" && segments.length === 2) {
    if (request.method === "GET") {
      return await handleGetAppVersion(request, env);
    }
    return badRequest("only GET supported on /api/app-version");
  }
  if (segments[0] === "api" && segments[1] === "theme" && segments.length === 2) {
    if (request.method === "GET") {
      return await handleGetTheme(env, url.searchParams.get("platform"));
    }
    return badRequest("only GET supported on /api/theme");
  }
  if (segments[0] === "api" && segments[1] === "greeting" && segments.length === 2) {
    return await handleGreeting(request);
  }
  if (segments[0] === "api" && segments[1] === "ad" && segments.length === 2) {
    if (request.method === "GET")
      return await handleGetAd(env);
    return badRequest("only GET supported on /api/ad");
  }
  if (segments[0] === "api" && segments[1] === "pricing" && segments.length === 2) {
    if (request.method === "GET")
      return await handleGetPricing(env);
    return badRequest("only GET supported on /api/pricing");
  }
  if (segments[0] === "api" && segments[1] === "feedback-prompt" && segments.length === 2) {
    if (request.method === "GET")
      return await handleGetFeedbackPrompt(env);
    return badRequest("only GET supported on /api/feedback-prompt");
  }
  if (segments[0] === "api" && segments[1] === "feedback" && segments.length === 2) {
    if (request.method === "POST")
      return await handlePostFeedback(request, env);
    return badRequest("only POST supported on /api/feedback");
  }
  if (segments[0] === "api" && segments[1] === "featured" && segments.length === 2) {
    if (request.method === "GET") {
      return await handleGetFeatured(env);
    }
    return badRequest("only GET supported on /api/featured");
  }
  if (segments[0] === "admin" && segments[1] === "panel" && segments.length === 2) {
    if (request.method !== "GET")
      return badRequest("only GET");
    return new Response(ADMIN_PANEL_HTML, { headers: HTML_HEADERS });
  }
  if (segments[0] === "admin" && segments[1] === "migrate-to-d1" && segments.length === 2) {
    if (!checkAdmin(request, env))
      return unauthorized();
    if (request.method !== "POST")
      return badRequest("only POST");
    let body = {};
    try {
      body = await request.json();
    } catch (_) {
    }
    const result = await runMigration(env, { dryRun: !!body.dry_run });
    return json2(result);
  }
  if (segments[0] === "admin" && segments[1] === "clients") {
    if (!checkAdmin(request, env))
      return unauthorized();
    if (segments.length === 2) {
      if (request.method === "GET")
        return handleGetClientsList(env);
      if (request.method === "POST")
        return handleUpsertClient(request, env, null);
      return badRequest("method not allowed");
    }
    if (segments.length === 3) {
      const mac = segments[2];
      if (!MAC_RX3.test(mac))
        return badRequest("invalid mac in URL");
      if (request.method === "GET")
        return handleGetClient(env, mac);
      if (request.method === "PUT")
        return handleUpsertClient(request, env, mac);
      if (request.method === "DELETE")
        return handleDeleteClient(env, mac);
      return badRequest("method not allowed");
    }
    if (segments.length === 4 && segments[3] === "action") {
      const mac = segments[2];
      if (request.method === "POST")
        return handleAdminAction(request, env, mac);
      return badRequest("only POST on action");
    }
  }
  if (segments.length === 0) {
    return new Response(landingHtml(), { headers: HTML_HEADERS });
  }
  if (segments.length === 1 && (segments[0] === "mon-espace" || segments[0] === "espace")) {
    return new Response(portalHtml(), { headers: HTML_HEADERS });
  }
  if (segments.length === 1) {
    const f = segments[0];
    if (f === "manifest.webmanifest") {
      return new Response(PWA_MANIFEST, {
        headers: {
          "Content-Type": "application/manifest+json; charset=utf-8",
          "Cache-Control": "public, max-age=3600",
          "Access-Control-Allow-Origin": "*"
        }
      });
    }
    if (f === "sw.js") {
      return new Response(PWA_SW, {
        headers: {
          "Content-Type": "application/javascript; charset=utf-8",
          "Cache-Control": "no-cache",
          "Service-Worker-Allowed": "/"
        }
      });
    }
    if (f === "icon-192.png" || f === "icon-512.png" || f === "apple-touch-icon.png" || f === "og-image.png") {
      const b64 = f === "icon-192.png" ? PWA_ICON_192 : f === "icon-512.png" ? PWA_ICON_512 : f === "og-image.png" ? OG_IMAGE : PWA_APPLE_ICON;
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      return new Response(bytes, {
        headers: {
          "Content-Type": "image/png",
          "Cache-Control": "public, max-age=31536000, immutable"
        }
      });
    }
    if (f === "robots.txt") {
      return new Response(
        "User-agent: *\nAllow: /\nSitemap: https://app.7themotion.com/sitemap.xml\n",
        { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=3600" } }
      );
    }
    if (f === "sitemap.xml") {
      const sm = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n  <url><loc>https://app.7themotion.com/</loc><changefreq>weekly</changefreq><priority>1.0</priority></url>\n</urlset>\n';
      return new Response(sm, { headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, max-age=3600" } });
    }
  }
  if (segments.length === 1 && (segments[0] === "confidentialite" || segments[0] === "privacy")) {
    return new Response(PRIVACY_HTML, { headers: HTML_HEADERS });
  }
  if (segments.length === 2 && segments[0] === "cs") {
    const file = segments[1];
    const dotIdx = file.lastIndexOf(".");
    const b64 = dotIdx > 0 ? file.slice(0, dotIdx) : file;
    const ext = dotIdx > 0 ? file.slice(dotIdx + 1) : "";
    let upstream;
    try {
      let s = b64.replace(/-/g, "+").replace(/_/g, "/");
      while (s.length % 4)
        s += "=";
      upstream = decodeURIComponent(escape(atob(s)));
    } catch (e) {
      return new Response("bad token", { status: 400 });
    }
    if (ext === "m3u8") {
      const manifest = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:EVENT\n#EXTINF:10.0,\n" + b64 + ".ts\n";
      return new Response(manifest, {
        headers: {
          "Content-Type": "application/vnd.apple.mpegurl",
          "Cache-Control": "no-store, no-cache",
          "Access-Control-Allow-Origin": "*"
        }
      });
    }
    if (ext === "ts") {
      let dst;
      try {
        dst = new URL(upstream);
      } catch (e) {
        return new Response("bad url", { status: 400 });
      }
      if (dst.protocol !== "http:" && dst.protocol !== "https:") {
        return new Response("bad proto", { status: 400 });
      }
      const up = await fetch(dst.toString(), {
        headers: {
          "User-Agent": "VLC/3.0.18 LibVLC/3.0.18",
          // Certains serveurs Xtream filtrent sur Referer/Accept ; on
          // se présente comme un lecteur normal du même hôte.
          "Referer": `${dst.protocol}//${dst.host}/`,
          "Accept": "*/*"
        },
        redirect: "follow"
      });
      const h = new Headers();
      h.set("Content-Type", "video/mp2t");
      h.set("Cache-Control", "no-store, no-cache");
      h.set("Access-Control-Allow-Origin", "*");
      h.set("X-Upstream-Status", String(up.status));
      h.set("Access-Control-Expose-Headers", "X-Upstream-Status");
      h.set("transferMode.dlna.org", "Streaming");
      h.set(
        "contentFeatures.dlna.org",
        "DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"
      );
      return new Response(up.body, { status: up.status, headers: h });
    }
    return new Response("bad ext", { status: 400 });
  }
  if (segments.length === 1 && segments[0] === "dl" || segments.length === 2 && segments[0] === "dl" && segments[1] === "release") {
    return proxyApk(APK_URL, "7motion.apk", url.searchParams.get("v"));
  }
  if (segments.length === 1 && ["install", "vip", "thefew", "few", "app"].includes(segments[0])) {
    return proxyApk(APK_URL, "TheFew.apk", url.searchParams.get("v"));
  }
  if (segments.length === 1 && ["tv", "defewtv", "tvbox", "defew", "777", "7777", "tv7"].includes(segments[0].toLowerCase())) {
    return proxyApk(TV_APK_URL, "DeFewTV.apk", url.searchParams.get("v"));
  }
  if (segments.length === 1 && segments[0] === "privacy") {
    return new Response(privacyHtml(), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=3600"
      }
    });
  }
  if (segments.length === 1 && (segments[0] === "terms" || segments[0] === "conditions" || segments[0] === "cgu")) {
    return new Response(termsHtml(), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=3600"
      }
    });
  }
  if (segments.length === 1 && segments[0] === "cast-sign") {
    if (request.method !== "GET")
      return badRequest("only GET on /cast-sign");
    return await handleCastSign(env, url);
  }
  if (segments.length === 1 && segments[0] === "cast-proxy") {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return badRequest("only GET/HEAD on /cast-proxy");
    }
    return await handleCastProxy(env, url, request.method);
  }
  if (segments.length === 1 && segments[0] === "cast-receiver") {
    const flavor = url.searchParams.get("app") || "7motion";
    return new Response(castReceiverHtml(flavor), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        // Cache 10 minutes — la page receiver bouge peu, et le
        // Chromecast la recharge a chaque session de cast.
        "Cache-Control": "public, max-age=600",
        "Access-Control-Allow-Origin": "*"
      }
    });
  }
  if (segments.length === 1 && (segments[0] === "ecran" || segments[0] === "screen")) {
    return new Response(screenPairHtml(), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=600",
        "Access-Control-Allow-Origin": "*"
      }
    });
  }
  if (segments.length === 2 && segments[0] === "e") {
    const sc = String(segments[1] || "").toUpperCase();
    if (!/^[2-9A-Z]{4}$/.test(sc)) {
      return new Response("code invalide", { status: 400 });
    }
    return new Response(screenReceiverHtml(sc), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
        "Access-Control-Allow-Origin": "*"
      }
    });
  }
  if (segments[0] === "api" && segments[1] === "screen") {
    return handleScreen(request, env, segments);
  }
  if (segments.length === 1 && segments[0] === "cast-skin.css") {
    const css = `cast-media-player{--background-color:#0A0A0C;--logo-image:url('https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_7motion.jpg');--logo-background-color:#0A0A0C;--splash-image:url('https://raw.githubusercontent.com/manzilionellm-dotcom/tvking/main/assets/branding/logo_7motion.jpg');--splash-background-color:#0A0A0C;--progress-color:#D63A30;--break-color:#D63A30;--buffer-color:rgba(255,90,74,0.45);--play-icon-color:#F2F2F4;--pause-icon-color:#F2F2F4;}`;
    return new Response(css, {
      headers: {
        "Content-Type": "text/css; charset=utf-8",
        "Cache-Control": "public, max-age=3600",
        "Access-Control-Allow-Origin": "*"
      }
    });
  }
  const RESERVED = /* @__PURE__ */ new Set([
    "admin",
    "config",
    "dl",
    "install",
    "api",
    "panel",
    "redroom",
    "tv",
    "defewtv",
    "tvbox",
    "defew",
    "777",
    "7777",
    "tv7",
    "cast-receiver",
    "cast-skin.css",
    "favicon.ico",
    "robots.txt",
    "sitemap.xml"
  ]);
  if (segments.length === 1 && !RESERVED.has(segments[0].toLowerCase())) {
    return proxyApk(APK_URL, "7motion.apk", url.searchParams.get("v"));
  }
  return notFound2("Unknown route. Try /, /dl, /config/:mac or /admin/clients");
}
__name(handleRequest, "handleRequest");
export {
  RealtimeHub,
  worker_default as default
};
//# sourceMappingURL=worker.js.map