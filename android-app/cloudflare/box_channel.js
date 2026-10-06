// =========================================================
//  box_channel.js — Canal panel → box (Durable Object)
// =========================================================
//  Une instance par MAC (`idFromName(mac)`) tient :
//    - les WebSocket de la box (hibernation : le DO dort tant
//      qu'aucun message n'arrive) ;
//    - les attentes longues GET /api/box/wait (repli si le
//      WebSocket n'est pas là).
//  Une instance « panel-v1 » répète le même signal aux écrans
//  du panel, pour qu'ils n'aient plus à sonder toutes les 2 s.
//
//  Le message ne contient JAMAIS un mot de passe, un identifiant
//  Xtream ni une adresse de flux. Seulement :
//    { v, seq, type, mac, at }
//  La box relit ensuite GET /api/device-source/<mac> elle-même.
//
//  Interrupteur de repli : variable Worker REALTIME_PUSH_OFF=1.
//  Absente ou autre chose : le canal est ouvert (le repli est
//  coupé). Avec « 1 », les routes répondent 404 et aucune
//  notification n'est envoyée : la box et le panel gardent
//  leur lecture régulière.
//
//  La classe DO s'appelle RealtimeHub. La production en a déjà
//  (migration v1-rt-hub). Un script qui ne l'exporte plus est
//  refusé au déploiement (erreur 10064, le 3 octobre 2026).
// =========================================================

import { createOrder, markOrderSent, recordAck } from './box_orders.js';

/// Noms d'ordres connus. Inconnu = refusé, pour qu'un appelant
/// ne glisse pas un texte libre (ni un secret) dans le canal.
export const CHANNEL_KINDS = Object.freeze([
  'source',
  'source_clear',
  'activate',
  'renew',
  'expire',
  'suspend',
  'resume',
  'block',
  'license',
  'transfer',
  'device_delete',
  'message',
  'theme',
  'home',
  'force_update',
  'featured',
  'ad',
  'pricing',
  'feedback',
  'servers',
  'banner',
  // Remise à neuf de la box depuis le panel (06/10/2026) : la box relit
  // son statut, y lit `reset_at`, efface tout, puis relit ses listes.
  'reset',
]);

const KIND_SET = new Set(CHANNEL_KINDS);
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/;
const RING_MAX = 32;
const HOLD_DEFAULT_MS = 20 * 1000;
const HOLD_MIN_MS = 200;
const HOLD_MAX_MS = 20 * 1000;
const PANEL_NAME = 'panel-v1';

/// Vrai seulement si l'interrupteur de repli est explicitement allumé.
export function realtimePushOff(env) {
  return !!(env && String(env.REALTIME_PUSH_OFF) === '1');
}

/// MAC canonique, ou chaîne vide si la forme n'est pas la nôtre.
export function normalizeMac(raw) {
  let text = '';
  try {
    text = decodeURIComponent(String(raw || ''));
  } catch (_) {
    text = String(raw || '');
  }
  const mac = text.trim().toUpperCase();
  return MAC_RX.test(mac) ? mac : '';
}

/// Nom d'ordre accepté, ou chaîne vide.
export function canonicalKind(raw) {
  const kind = String(raw || '').trim();
  return KIND_SET.has(kind) ? kind : '';
}

/// Durée d'attente demandée par la box, bornée. Absente = 20 s.
export function clampTimeout(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return HOLD_DEFAULT_MS;
  if (n < HOLD_MIN_MS) return HOLD_MIN_MS;
  if (n > HOLD_MAX_MS) return HOLD_MAX_MS;
  return Math.floor(n);
}

/// Événements encore dans l'anneau, plus récents que `after`.
export function eventsAfter(ring, after) {
  const cursor = Number(after);
  const min = Number.isFinite(cursor) ? cursor : 0;
  const out = [];
  for (const item of ring || []) {
    if (!item || typeof item !== 'object') continue;
    const seq = Number(item.seq);
    if (!Number.isFinite(seq) || seq <= min) continue;
    out.push(item);
  }
  return out;
}

/// Corps public. Les seules clés sont celles du contrat.
export function publicEvent(event) {
  const out = {
    v: 1,
    seq: Number(event.seq) || 0,
    type: String(event.type || ''),
    mac: String(event.mac || ''),
    at: Number(event.at) || 0,
  };
  // Suivi de bout en bout (06/10/2026) : identifiants aléatoires, jamais
  // un secret. Absents pour un ancien ordre de l'anneau.
  if (safeId(event.order_id)) out.order_id = event.order_id;
  if (safeId(event.trace_id)) out.trace_id = event.trace_id;
  return out;
}

function safeId(v) {
  return typeof v === 'string' && /^[A-Za-z0-9_.:-]{8,80}$/.test(v);
}

/// Réponse de GET /api/box/wait. `box` reprend la forme déjà lue
/// par l'app (id + kind) ; `events` est la forme du contrat.
export function waitBody(events, timeout) {
  const list = Array.isArray(events) ? events.map(publicEvent) : [];
  return {
    v: 1,
    timeout: timeout === true,
    box: list.map((event) => ({
      id: event.seq,
      kind: event.type,
      created_at: event.at,
      ...(event.order_id ? { order_id: event.order_id } : {}),
      ...(event.trace_id ? { trace_id: event.trace_id } : {}),
    })),
    fleet: [],
    events: list,
  };
}

/// Vrai si un objet (n'importe quelle profondeur) porte un secret
/// ou une adresse de flux. Sert aux tests et au filet d'envoi.
const SECRET_KEYS = new Set([
  'password',
  'username',
  'server_url',
  'm3u_url',
  'epg_url',
  'secret',
  'token',
]);

export function containsSecretKey(value) {
  if (!value || typeof value !== 'object') return false;
  for (const [key, child] of Object.entries(value)) {
    if (SECRET_KEYS.has(String(key).toLowerCase())) return true;
    if (containsSecretKey(child)) return true;
  }
  return false;
}

/// Un revendeur ne voit que les MAC qui lui sont rattachées.
/// L'admin voit tout. Sans fiche appareil, le revendeur ne voit rien.
export function panelMaySee(actor, deviceResellerId) {
  if (!actor || !actor.role) return false;
  if (actor.role !== 'reseller') return true;
  if (!actor.id || !deviceResellerId) return false;
  return String(deviceResellerId) === String(actor.id);
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

/// Boîte aux lettres d'une MAC : anneau + attentes longues.
/// `storage` a get / put / transaction (l'API du Durable Object,
/// ou un faux en mémoire pour les tests).
export function createMacMailbox(storage) {
  const waiters = [];
  // Les Durable Objects SQLite n'ont pas storage.transaction.
  // Cette file sérialise les écritures dans l'isolate, sans bloquer
  // une attente longue déjà ouverte (sinon : interblocage).
  let chain = Promise.resolve();
  function enqueue(fn) {
    const run = chain.then(fn, fn);
    chain = run.then(() => {}, () => {});
    return run;
  }

  async function readRing() {
    const ring = await storage.get('ring');
    return Array.isArray(ring) ? ring : [];
  }

  async function since(after) {
    return eventsAfter(await readRing(), after);
  }

  async function push(kind, mac, ids = {}) {
    const type = canonicalKind(kind);
    const clean = normalizeMac(mac);
    if (!type || !clean) return null;
    const event = await enqueue(async () => {
      const seq = (Number(await storage.get('seq')) || 0) + 1;
      const ring = eventsAfter(await storage.get('ring'), 0);
      const next = { v: 1, seq, type, mac: clean, at: Date.now() };
      if (safeId(ids.order_id)) next.order_id = ids.order_id;
      if (safeId(ids.trace_id)) next.trace_id = ids.trace_id;
      ring.push(next);
      while (ring.length > RING_MAX) ring.shift();
      await storage.put('seq', seq);
      await storage.put('ring', ring);
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

  function wait(after, timeoutMs) {
    const limit = clampTimeout(timeoutMs);
    return since(after).then((first) => {
      if (first.length) return waitBody(first, false);
      return new Promise((resolve) => {
        const waiter = { after: Number(after) || 0, resolve, done: false, timer: null };
        waiter.timer = setTimeout(() => {
          if (waiter.done) return;
          waiter.done = true;
          const idx = waiters.indexOf(waiter);
          if (idx >= 0) waiters.splice(idx, 1);
          resolve(waitBody([], true));
        }, limit);
        waiters.push(waiter);
        since(after).then((second) => {
          if (waiter.done || !second.length) return;
          waiter.done = true;
          clearTimeout(waiter.timer);
          const idx = waiters.indexOf(waiter);
          if (idx >= 0) waiters.splice(idx, 1);
          resolve(waitBody(second, false));
        });
      });
    });
  }

  return { push, since, wait };
}

function stub(env, name) {
  if (!env || !env.RT_HUB || typeof env.RT_HUB.idFromName !== 'function') return null;
  return env.RT_HUB.get(env.RT_HUB.idFromName(name));
}

/// Préviens la box (et le panel) qu'il faut relire. N'échoue jamais
/// l'action du panel : la liste est déjà écrite, la lecture
/// régulière la verra quand même.
///
/// Suivi (06/10/2026) : chaque appel crée un ordre `box_orders` (CREATED,
/// T2 = fin de la transaction métier), le publie au Durable Object de la
/// box avec son `order_id` et son `trace_id` (SENT, T3), et rend
/// l'`order_id`. `opts` : { traceId, t0, t1, t2, configRev }. Sans canal
/// temps réel, l'ordre reste CREATED puis EXPIRED : « jamais envoyé » se
/// voit au lieu d'être supposé.
export async function notifyBox(env, mac, kind, opts = {}) {
  let orderId = null;
  try {
    const clean = normalizeMac(mac);
    const type = canonicalKind(kind);
    if (!clean || !type) return null;
    orderId = await createOrder(env, {
      mac: clean, kind: type, traceId: opts.traceId, t0: opts.t0, t1: opts.t1,
      t2: opts.t2 || Date.now(), configRev: opts.configRev,
    });
    if (realtimePushOff(env)) return orderId;
    const ids = { order_id: orderId || undefined, trace_id: opts.traceId || undefined };
    const body = JSON.stringify({ kind: type, mac: clean, ...ids });
    const macStub = stub(env, clean);
    const panelStub = stub(env, PANEL_NAME);
    // Deux instances : l'échec de l'une ne doit pas empêcher l'autre.
    if (macStub) {
      try {
        const res = await macStub.fetch('https://hub/notify', { method: 'POST', body });
        let seq = null;
        try { seq = (await res.json()).seq || null; } catch (_) { seq = null; }
        if (res.ok && orderId) await markOrderSent(env, orderId, seq);
      } catch (_) { /* la box relira au prochain tour ; l'ordre reste CREATED */ }
    }
    if (panelStub) {
      try {
        await panelStub.fetch('https://hub/fanout', { method: 'POST', body });
      } catch (_) { /* le panel garde son sondage de secours */ }
    }
  } catch (_) {
    // Filet : le PUT / l'activation restent valides.
  }
  return orderId;
}

function notFound() {
  return json({ error: 'not_found' }, 404);
}

/// GET /api/box/ws, GET /api/box/wait/:mac, POST /api/box/ack/:mac.
/// Répond null si ce n'est pas notre chemin (le routeur continue).
export async function handleBoxRoute(request, env, segments) {
  if (!segments || segments[0] !== 'api' || segments[1] !== 'box') return null;
  const action = segments[2] || '';
  if (action !== 'ws' && action !== 'wait' && action !== 'ack') return null;

  // ACCUSÉ RÉEL (06/10/2026). Avant : `{ ok: true }` sans rien écrire.
  // Corps : { orders: [{ order_id, state: received|applied|failed,
  // received_at, applied_at, config_rev, result, error_code,
  // error_message, trace_id, app_version }] }. Persisté dans box_orders.
  // Un ancien corps ({ box: [...], fleet: [...] }) reste accepté tel quel.
  // Fonctionne même sans canal temps réel (une box en sondage accuse aussi).
  if (action === 'ack') {
    if (request.method !== 'POST') return json({ error: 'method' }, 405);
    const ackMac = normalizeMac(segments[3] || new URL(request.url).searchParams.get('mac'));
    if (!ackMac) return json({ error: 'bad_mac' }, 400);
    let payload = null;
    try { payload = await request.json(); } catch (_) { payload = null; }
    const list = payload && Array.isArray(payload.orders) ? payload.orders.slice(0, 20) : null;
    if (!list || !env || !env.DB) return json({ ok: true });
    const results = [];
    for (const item of list) {
      try {
        const r = await recordAck(env, ackMac, item);
        results.push({ order_id: item && item.order_id, status: r.status, ...r.body });
      } catch (_) {
        results.push({ order_id: item && item.order_id, status: 500, error: 'ack_failed' });
      }
    }
    return json({ ok: true, results });
  }

  if (realtimePushOff(env) || !env || !env.RT_HUB) return notFound();

  const url = new URL(request.url);
  if (action === 'ws') {
    if (request.method !== 'GET') return json({ error: 'method' }, 405);
    if (request.headers.get('Upgrade') !== 'websocket') {
      return json({ error: 'upgrade_required' }, 426);
    }
    const mac = normalizeMac(url.searchParams.get('mac'));
    if (!mac) return json({ error: 'bad_mac' }, 400);
    const target = stub(env, mac);
    if (!target) return notFound();
    return target.fetch(request);
  }

  const mac = normalizeMac(segments[3] || url.searchParams.get('mac'));
  if (!mac) return json({ error: 'bad_mac' }, 400);
  const target = stub(env, mac);
  if (!target) return notFound();


  if (request.method !== 'GET') return json({ error: 'method' }, 405);
  const after = url.searchParams.get('after') || '0';
  const timeout = url.searchParams.get('timeout') || '';
  const inner = new URL('https://hub/wait');
  inner.searchParams.set('after', after);
  inner.searchParams.set('timeout', timeout);
  return target.fetch(new Request(inner.toString(), { method: 'GET' }));
}

/// WebSocket du panel. `actor` = { id, role } déjà vérifié (JWT).
export function openPanelSocket(request, env, actor) {
  if (realtimePushOff(env) || !env || !env.RT_HUB) return notFound();
  if (!actor || !actor.id || !actor.role) return json({ error: 'no_auth' }, 401);
  if (request.headers.get('Upgrade') !== 'websocket') {
    return json({ error: 'upgrade_required' }, 426);
  }
  const target = stub(env, PANEL_NAME);
  if (!target) return notFound();
  const headers = new Headers(request.headers);
  headers.set('X-Panel-Role', String(actor.role));
  headers.set('X-Panel-Id', String(actor.id));
  const forwarded = new Request(request.url, { method: request.method, headers });
  return target.fetch(forwarded);
}

async function deviceResellerId(env, mac) {
  if (!env || !env.DB) return '';
  try {
    const row = await env.DB
      .prepare('SELECT reseller_id FROM devices WHERE mac = ?')
      .bind(mac)
      .first();
    return row && row.reseller_id ? String(row.reseller_id) : '';
  } catch (_) {
    return '';
  }
}

export class RealtimeHub {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.mailbox = createMacMailbox(ctx.storage);
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (request.headers.get('Upgrade') === 'websocket') {
      return this.#socket(request);
    }
    if (url.pathname === '/notify' && request.method === 'POST') {
      return this.#notify(request, false);
    }
    if (url.pathname === '/fanout' && request.method === 'POST') {
      return this.#notify(request, true);
    }
    if (url.pathname === '/wait' && request.method === 'GET') {
      const body = await this.mailbox.wait(
        url.searchParams.get('after'),
        url.searchParams.get('timeout'),
      );
      if (containsSecretKey(body)) return json({ error: 'blocked' }, 500);
      return json(body);
    }
    return notFound();
  }

  async #notify(request, fanout) {
    let payload = {};
    try {
      payload = await request.json();
    } catch (_) {
      return json({ error: 'bad_json' }, 400);
    }
    const event = await this.mailbox.push(payload.kind, payload.mac, {
      order_id: payload.order_id, trace_id: payload.trace_id,
    });
    if (!event) return json({ error: 'ignored' }, 400);
    const text = JSON.stringify(publicEvent(event));
    if (containsSecretKey(JSON.parse(text))) return json({ error: 'blocked' }, 500);
    if (fanout) await this.#sendPanel(text, event.mac);
    else this.#sendAll(text);
    return json({ ok: true, seq: event.seq });
  }

  #sendAll(text) {
    for (const ws of this.ctx.getWebSockets()) {
      try { ws.send(text); } catch (_) { /* socket déjà parti */ }
    }
  }

  async #sendPanel(text, mac) {
    const resellerId = await deviceResellerId(this.env, mac);
    for (const ws of this.ctx.getWebSockets()) {
      let att = {};
      try { att = ws.deserializeAttachment() || {}; } catch (_) { att = {}; }
      const allowed = panelMaySee(
        { id: att.id, role: att.role },
        resellerId,
      );
      if (!allowed) continue;
      try { ws.send(text); } catch (_) { /* socket déjà parti */ }
    }
  }

  #socket(request) {
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.ctx.acceptWebSocket(server);
    const role = request.headers.get('X-Panel-Role') || '';
    const id = request.headers.get('X-Panel-Id') || '';
    if (role && id) {
      server.serializeAttachment({ role, id });
    } else {
      server.serializeAttachment({ role: 'box' });
    }
    // La box qui se connecte juste après un clic reçoit le dernier
    // signal, sans attendre le prochain. Le curseur `seq` évite
    // de rejouer un signal déjà vu.
    this.mailbox.since(0).then((events) => {
      const last = events.length ? events[events.length - 1] : null;
      if (!last) return;
      try { server.send(JSON.stringify(publicEvent(last))); } catch (_) { /* fermé */ }
    });
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    // « hello » garde le chemin ouvert à travers les proxys.
    // Tout autre texte est ignoré. On ne le journalise pas :
    // un client pourrait y coller un mot de passe par erreur.
    let hello = false;
    try {
      const text = typeof message === 'string' ? message : '';
      const parsed = JSON.parse(text);
      hello = !!(parsed && parsed.type === 'hello' && !containsSecretKey(parsed));
    } catch (_) {
      hello = false;
    }
    if (!hello) return;
    try { ws.send(JSON.stringify({ v: 1, type: 'hello' })); } catch (_) { /* fermé */ }
  }

  async webSocketClose() {
    // Hibernation : rien à libérer, les sockets sont tenus par le DO.
  }

  async webSocketError(ws) {
    try { ws.close(1011, 'error'); } catch (_) { /* déjà fermé */ }
  }
}
