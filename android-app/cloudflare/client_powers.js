// =========================================================
//  client_powers.js — « Pouvoirs clients » du panel Zuno TV
// =========================================================
//  Donne à l'ADMIN (super_admin) la main sur un client, par appareil :
//    - bloquer / débloquer (avec motif) ;
//    - demande de paiement (« merci de payer ») affichée dans l'app ;
//    - message personnalisé affiché dans l'app ;
//    - prolonger / suspendre / reprendre ;
//    - forcer la relecture (la box relit statut + listes tout de suite) ;
//    - notes internes ;
//    - journal des actions d'un client (lecture de audit_logs).
//  Changer la liste M3U/Xtream = route existante PUT /api/v1/sources/:mac.
//
//  RÈGLES
//    - INTERRUPTEUR DE REPLI : variable Worker CLIENT_POWERS. Coupé par
//      défaut → les routes répondent « désactivé » et /api/status/<mac>
//      reste IDENTIQUE à avant (aucun champ ajouté).
//    - Toute écriture est réservée à l'admin (super_admin) et journalisée
//      dans audit_logs (qui / quoi / quand).
//    - Aucun mot de passe ni URL de flux dans les réponses ni le journal.
//    - Ce fichier n'importe PAS api_v1.js (pas de cycle) : les aides
//      (réponses, audit, id) sont injectées par api_v1.js via `deps`.
// =========================================================

import { parseExtendDays } from './trial_access.js';

const DAY_MS = 24 * 60 * 60 * 1000;
const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/i;

/// Limites de texte : un message affiché sur une TV doit rester court.
export const LIMITS = {
  title: 80,
  body: 500,
  amount: 32,
  currency: 8,
  reason: 200,
  note: 1000,
};

/// true seulement si l'opérateur a ALLUMÉ l'interrupteur.
export function clientPowersOn(env) {
  const v = String((env && env.CLIENT_POWERS) || '').trim().toLowerCase();
  return v === '1' || v === 'true' || v === 'on' || v === 'yes';
}

/// Nettoie un texte libre : retire les caractères de contrôle, coupe la
/// longueur. Renvoie '' si le texte n'est pas une chaîne.
export function cleanText(value, max) {
  if (typeof value !== 'string') return '';
  // eslint-disable-next-line no-control-regex
  const s = value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '').trim();
  return s.length > max ? s.slice(0, max) : s;
}

/// Lien de paiement : https uniquement, sans identifiants intégrés.
export function cleanPayLink(value) {
  if (value === undefined || value === null || value === '') return { link: null };
  if (typeof value !== 'string') return { error: 'Lien de paiement invalide.' };
  let u;
  try { u = new URL(value.trim()); } catch (_) {
    return { error: 'Lien de paiement invalide.' };
  }
  if (u.protocol !== 'https:' || u.username || u.password) {
    return { error: 'Le lien de paiement doit être en https, sans identifiants.' };
  }
  if (u.href.length > 300) return { error: 'Lien de paiement trop long.' };
  return { link: u.href };
}

/// Retire récursivement ce qui ressemble à un secret ou à une URL de
/// flux avant d'afficher une ligne du journal.
export function scrubAudit(value, depth = 0) {
  if (value === null || value === undefined || depth > 4) return null;
  if (Array.isArray(value)) return value.slice(0, 20).map((v) => scrubAudit(v, depth + 1));
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (/pass|secret|token|url|m3u|server|user/i.test(k)) continue;
      out[k] = scrubAudit(v, depth + 1);
    }
    return out;
  }
  if (typeof value === 'string') return value.slice(0, 200);
  return value;
}

/// Numéro de révision : strictement croissant par (MAC, genre), pour que
/// la box ne montre un avis qu'une fois par envoi.
export function nextRev(prev, now = Date.now()) {
  const p = Number(prev) || 0;
  return p >= now ? p + 1 : now;
}

let tablesReady = false;

/// Crée les tables si la migration 010 n'a pas encore été appliquée.
export async function ensureClientPowersTables(env) {
  if (tablesReady) return;
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS client_notices (
       mac TEXT NOT NULL, kind TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
       title TEXT, body TEXT, amount TEXT, currency TEXT, link TEXT,
       due_at INTEGER, expires_at INTEGER, rev INTEGER NOT NULL, actor_id TEXT,
       created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
       PRIMARY KEY (mac, kind))`,
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS client_notes (
       id TEXT PRIMARY KEY, mac TEXT NOT NULL, body TEXT NOT NULL,
       actor_id TEXT, created_at INTEGER NOT NULL)`,
  ).run();
  tablesReady = true;
}

/// Pour les tests : oublie le cache « tables créées ».
export function resetClientPowersCache() { tablesReady = false; }

// ---------------------------------------------------------
//  Partie PUBLIQUE — champs ajoutés à GET /api/status/<mac>
// ---------------------------------------------------------
//  Ce que la box lit (voir docs/CONTRAT-API-POUVOIRS-CLIENTS.md) :
//    payment_request : null | {id, message, amount, currency, link, due_at}
//    client_message  : null | {id, title, body, expires_at}
//    refresh_rev     : nombre (change quand l'admin force la relecture)
//  Interrupteur coupé ou erreur D1 → {} (réponse inchangée).
export async function readPublicNotices(env, mac, now = Date.now()) {
  if (!clientPowersOn(env) || !env.DB || !MAC_RX.test(String(mac || ''))) return {};
  try {
    await ensureClientPowersTables(env);
    const rs = await env.DB
      .prepare(
        `SELECT kind, active, title, body, amount, currency, link, due_at,
                expires_at, rev
           FROM client_notices WHERE mac = ?`,
      )
      .bind(String(mac).toUpperCase())
      .all();
    const rows = (rs && rs.results) || [];
    const out = { payment_request: null, client_message: null, refresh_rev: 0 };
    for (const r of rows) {
      if (r.kind === 'refresh') {
        out.refresh_rev = Number(r.rev) || 0;
      } else if (r.kind === 'payment' && r.active) {
        out.payment_request = {
          id: String(r.rev),
          message: r.body || '',
          amount: r.amount || '',
          currency: r.currency || '',
          link: r.link || '',
          due_at: r.due_at || null,
        };
      } else if (r.kind === 'message' && r.active
        && !(r.expires_at && r.expires_at <= now)) {
        out.client_message = {
          id: String(r.rev),
          title: r.title || '',
          body: r.body || '',
          expires_at: r.expires_at || null,
        };
      }
    }
    return out;
  } catch (_) {
    // Une panne de ce module ne doit JAMAIS casser /api/status.
    return {};
  }
}

// ---------------------------------------------------------
//  Partie ADMIN — routes /api/v1/devices/:id/...
// ---------------------------------------------------------
//  Renvoie une Response si la route est reconnue, sinon null (le
//  routeur d'api_v1.js continue alors normalement).
//    parts = ['devices', ':id', ...]
export async function handleClientPowers({ request, env, parts, user, actor, deps }) {
  if (parts[0] !== 'devices' || parts.length < 3) return null;
  const { errResp, jsonResp } = deps;
  const sub = String(parts[2]);
  const method = request.method;
  const known = {
    powers: ['GET'],
    block: ['POST'],
    'payment-request': ['PUT', 'DELETE'],
    message: ['POST', 'DELETE'],
    extend: ['POST'],
    suspend: ['POST'],
    refresh: ['POST'],
    notes: ['GET', 'POST', 'DELETE'],
    actions: ['GET'],
  };
  if (!Object.prototype.hasOwnProperty.call(known, sub) || !known[sub].includes(method)) return null;
  // Longueur attendue : /devices/:id/<sub> (3) ; suppression d'une note : +1 (id de la note).
  const expectedLen = sub === 'notes' && method === 'DELETE' ? 4 : 3;
  if (parts.length !== expectedLen) return null;

  // Réservé à l'admin authentifié (JWT super_admin). Revendeur = refusé.
  if (!user || user.role !== 'super_admin') {
    return errResp('forbidden', 'Réservé à l’administrateur.', 403);
  }
  const enabled = clientPowersOn(env);
  if (!enabled) {
    if (sub === 'powers') return jsonResp({ enabled: false });
    return errResp('client_powers_off',
      'Pouvoirs clients désactivés (interrupteur CLIENT_POWERS coupé).', 404);
  }
  await ensureClientPowersTables(env);

  const id = parts[1];
  const dev = await env.DB
    .prepare('SELECT id, mac, block_status FROM devices WHERE id = ?')
    .bind(id).first();
  if (!dev) return errResp('not_found', 'Appareil introuvable.', 404);
  const mac = String(dev.mac).toUpperCase();
  // Le journal garde l'IP et le navigateur de la requête admin.
  const audited = {
    ...deps,
    logAudit: (e, _r, ...rest) => deps.logAudit(e, request, ...rest),
  };
  const ctx = { request, env, dev, mac, actor, deps: audited };

  switch (sub) {
    case 'powers': return getPowers(ctx);
    case 'block': return setBlock(ctx);
    case 'payment-request': return method === 'PUT' ? setPayment(ctx) : clearNotice(ctx, 'payment');
    case 'message': return method === 'POST' ? sendMessage(ctx) : clearNotice(ctx, 'message');
    case 'extend': return extendAccess(ctx);
    case 'suspend': return suspendAccess(ctx);
    case 'refresh': return forceRefresh(ctx);
    case 'notes':
      if (method === 'GET') return listNotes(ctx);
      if (method === 'POST') return addNote(ctx);
      return deleteNote(ctx, parts[3]);
    case 'actions': return listActions(ctx);
    default: return null;
  }
}

async function readBody(request) {
  try {
    const b = await request.json();
    return b && typeof b === 'object' ? b : {};
  } catch (_) { return null; }
}

/// Lit une ligne de client_notices (ou null).
async function getNotice(env, mac, kind) {
  return env.DB
    .prepare('SELECT * FROM client_notices WHERE mac = ? AND kind = ?')
    .bind(mac, kind).first();
}

/// Écrit (ou remplace) un avis et renvoie la nouvelle révision.
async function putNotice(env, mac, kind, f, actorId, now = Date.now()) {
  const prev = await getNotice(env, mac, kind);
  const rev = nextRev(prev && prev.rev, now);
  await env.DB.prepare(
    `INSERT OR REPLACE INTO client_notices
       (mac, kind, active, title, body, amount, currency, link, due_at,
        expires_at, rev, actor_id, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    mac, kind, f.active === 0 ? 0 : 1, f.title || null, f.body || null,
    f.amount || null, f.currency || null, f.link || null, f.due_at || null,
    f.expires_at || null, rev, actorId || null,
    (prev && prev.created_at) || now, now,
  ).run();
  return rev;
}

/// Demande à la box de relire statut + listes (révision de relecture).
async function bumpRefresh(env, mac, actorId) {
  return putNotice(env, mac, 'refresh', { active: 1 }, actorId);
}

/// Relecture forcée déclenchée par une autre route (ex. changement de
/// `hidden` sur une liste). Sans effet si CLIENT_POWERS est coupé ;
/// une panne ici ne casse jamais l'écriture appelante.
export async function bumpRefreshRev(env, mac, actorId) {
  if (!clientPowersOn(env) || !env || !env.DB) return 0;
  try {
    await ensureClientPowersTables(env);
    return await bumpRefresh(env, String(mac).toUpperCase(), actorId);
  } catch (_) {
    return 0;
  }
}

// ----- GET /devices/:id/powers : tout l'état « pouvoirs » en un appel -----
async function getPowers({ env, dev, mac, deps }) {
  const rs = await env.DB
    .prepare('SELECT * FROM client_notices WHERE mac = ?')
    .bind(mac).all();
  const by = {};
  for (const r of (rs && rs.results) || []) by[r.kind] = r;
  const pay = by.payment && by.payment.active ? {
    message: by.payment.body || '', amount: by.payment.amount || '',
    currency: by.payment.currency || '', link: by.payment.link || '',
    due_at: by.payment.due_at || null, sent_at: by.payment.updated_at,
  } : null;
  const msg = by.message && by.message.active ? {
    title: by.message.title || '', body: by.message.body || '',
    expires_at: by.message.expires_at || null, sent_at: by.message.updated_at,
  } : null;
  const lic = await env.DB
    .prepare(
      `SELECT status, plan, expires_at FROM licenses WHERE device_id = ?
        ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`,
    ).bind(dev.id).first().catch(() => null);
  return deps.jsonResp({
    enabled: true,
    mac,
    block_status: dev.block_status || 'active',
    suspended: !!(lic && lic.status === 'suspended'),
    lifetime: !!(lic && (lic.expires_at === null || lic.expires_at === undefined)),
    payment_request: pay,
    message: msg,
    refresh_rev: by.refresh ? by.refresh.rev : 0,
  });
}

// ----- POST /devices/:id/block {status, reason?} -----
async function setBlock({ request, env, dev, mac, actor, deps }) {
  const b = await readBody(request);
  if (!b) return deps.errResp('bad_json', 'Invalid JSON body', 400);
  const status = b.status;
  if (!['active', 'frozen', 'banned'].includes(status)) {
    return deps.errResp('bad_status', "status doit être 'active', 'frozen' ou 'banned'", 400);
  }
  const reason = cleanText(b.reason, LIMITS.reason);
  const next = status === 'active' ? null : status;
  await env.DB.prepare('UPDATE devices SET block_status = ? WHERE id = ?')
    .bind(next, dev.id).run();
  const rev = await bumpRefresh(env, mac, actor.id);
  await deps.logAudit(env, null, actor, 'client.block', { type: 'device', id: dev.id },
    { block_status: dev.block_status || 'active' }, { block_status: status, reason });
  return deps.jsonResp({ ok: true, block_status: status, refresh_rev: rev });
}

// ----- PUT /devices/:id/payment-request -----
async function setPayment({ request, env, dev, mac, actor, deps }) {
  const b = await readBody(request);
  if (!b) return deps.errResp('bad_json', 'Invalid JSON body', 400);
  const message = cleanText(b.message, LIMITS.body)
    || 'Merci de régler votre abonnement pour continuer à profiter du service.';
  const link = cleanPayLink(b.link);
  if (link.error) return deps.errResp('bad_link', link.error, 400);
  let dueAt = null;
  if (b.due_at !== undefined && b.due_at !== null && b.due_at !== '') {
    dueAt = Number(b.due_at);
    if (!Number.isFinite(dueAt) || dueAt <= 0) {
      return deps.errResp('bad_due', 'Échéance invalide (ms epoch).', 400);
    }
  }
  const rev = await putNotice(env, mac, 'payment', {
    body: message,
    amount: cleanText(String(b.amount ?? ''), LIMITS.amount),
    currency: cleanText(String(b.currency ?? ''), LIMITS.currency),
    link: link.link,
    due_at: dueAt,
  }, actor.id);
  await deps.logAudit(env, null, actor, 'client.payment_request.set',
    { type: 'device', id: dev.id }, null, { message, amount: b.amount ?? null, has_link: !!link.link, rev });
  return deps.jsonResp({ ok: true, id: String(rev) });
}

// ----- POST /devices/:id/message -----
async function sendMessage({ request, env, dev, mac, actor, deps }) {
  const b = await readBody(request);
  if (!b) return deps.errResp('bad_json', 'Invalid JSON body', 400);
  const body = cleanText(b.body, LIMITS.body);
  if (!body) return deps.errResp('missing_body', 'Le message est vide.', 400);
  const title = cleanText(b.title, LIMITS.title);
  let expiresAt = null;
  if (b.expires_in_hours !== undefined && b.expires_in_hours !== null && b.expires_in_hours !== '') {
    const h = Number(b.expires_in_hours);
    if (!Number.isFinite(h) || h <= 0 || h > 24 * 90) {
      return deps.errResp('bad_expiry', 'Durée d’affichage invalide (1 à 2160 heures).', 400);
    }
    expiresAt = Date.now() + Math.round(h * 3600 * 1000);
  }
  const rev = await putNotice(env, mac, 'message', { title, body, expires_at: expiresAt }, actor.id);
  await deps.logAudit(env, null, actor, 'client.message.send',
    { type: 'device', id: dev.id }, null, { title, body, expires_at: expiresAt, rev });
  return deps.jsonResp({ ok: true, id: String(rev) });
}

// ----- DELETE /devices/:id/payment-request | /message -----
async function clearNotice({ env, dev, mac, actor, deps }, kind) {
  const prev = await getNotice(env, mac, kind);
  if (!prev || !prev.active) return deps.jsonResp({ ok: true, cleared: 0 });
  await env.DB.prepare(
    'UPDATE client_notices SET active = 0, updated_at = ? WHERE mac = ? AND kind = ?',
  ).bind(Date.now(), mac, kind).run();
  await deps.logAudit(env, null, actor,
    kind === 'payment' ? 'client.payment_request.clear' : 'client.message.clear',
    { type: 'device', id: dev.id }, { rev: prev.rev }, null);
  return deps.jsonResp({ ok: true, cleared: 1 });
}

// ----- POST /devices/:id/extend {days} -----
//  Licence datée → on repousse sa fin ; licence à vie → refus ;
//  pas de licence (essai) → on délègue à l'ajout de jours d'essai existant.
async function extendAccess({ request, env, dev, mac, actor, deps }) {
  const b = await readBody(request);
  if (!b) return deps.errResp('bad_json', 'Invalid JSON body', 400);
  const parsed = parseExtendDays(b.days);
  if (parsed.error) return deps.errResp('bad_days', parsed.error, 400);
  const lic = await env.DB
    .prepare(
      `SELECT id, status, plan, expires_at FROM licenses WHERE device_id = ?
        ORDER BY (expires_at IS NULL) DESC, expires_at DESC LIMIT 1`,
    ).bind(dev.id).first();
  if (!lic) {
    // Essai : logique existante (trial_anchors + trial_extensions + journal « trial.extend »).
    const req = new Request('https://internal.invalid/trial-extend', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ mac, days: parsed.days }),
    });
    const res = await deps.trialExtend(req, env, actor);
    if (res.ok) await bumpRefresh(env, mac, actor.id);
    return res;
  }
  if (lic.expires_at === null || lic.expires_at === undefined) {
    return deps.errResp('already_lifetime', 'Licence à vie : rien à prolonger.', 409);
  }
  const now = Date.now();
  const base = lic.expires_at > now ? lic.expires_at : now;
  const next = base + parsed.days * DAY_MS;
  // On ne touche PAS au statut : une licence suspendue reste suspendue.
  await env.DB.prepare('UPDATE licenses SET expires_at = ?, updated_at = ? WHERE id = ?')
    .bind(next, now, lic.id).run();
  const rev = await bumpRefresh(env, mac, actor.id);
  await deps.logAudit(env, null, actor, 'client.extend', { type: 'device', id: dev.id },
    { expires_at: lic.expires_at }, { expires_at: next, days: parsed.days });
  return deps.jsonResp({ ok: true, expires_at: next, days: parsed.days, refresh_rev: rev });
}

// ----- POST /devices/:id/suspend {suspend: true|false, reason?} -----
//  Suspendre = licence 'suspended' (l'app voit « expiré/inactif ») sans perdre
//  la date de fin. Reprendre = 'active'. Sans licence : utiliser « bloquer ».
async function suspendAccess({ request, env, dev, mac, actor, deps }) {
  const b = await readBody(request);
  if (!b) return deps.errResp('bad_json', 'Invalid JSON body', 400);
  if (typeof b.suspend !== 'boolean') {
    return deps.errResp('bad_suspend', 'suspend doit être true ou false.', 400);
  }
  const reason = cleanText(b.reason, LIMITS.reason);
  const now = Date.now();
  const from = b.suspend ? 'active' : 'suspended';
  const to = b.suspend ? 'suspended' : 'active';
  const cnt = await env.DB
    .prepare('SELECT COUNT(*) AS n FROM licenses WHERE device_id = ?')
    .bind(dev.id).first();
  if (!cnt || !cnt.n) {
    return deps.errResp('no_license',
      'Aucune licence à suspendre (essai) : utilise « bloquer ».', 409);
  }
  const r = await env.DB
    .prepare('UPDATE licenses SET status = ?, updated_at = ? WHERE device_id = ? AND status = ?')
    .bind(to, now, dev.id, from).run();
  const changed = (r && r.meta && r.meta.changes) || 0;
  const rev = await bumpRefresh(env, mac, actor.id);
  await deps.logAudit(env, null, actor, b.suspend ? 'client.suspend' : 'client.resume',
    { type: 'device', id: dev.id }, { status: from }, { status: to, reason, changed });
  return deps.jsonResp({ ok: true, suspended: b.suspend, changed, refresh_rev: rev });
}

// ----- POST /devices/:id/refresh -----
async function forceRefresh({ env, dev, mac, actor, deps }) {
  const rev = await bumpRefresh(env, mac, actor.id);
  await deps.logAudit(env, null, actor, 'client.refresh',
    { type: 'device', id: dev.id }, null, { rev });
  return deps.jsonResp({ ok: true, refresh_rev: rev });
}

// ----- Notes internes -----
async function listNotes({ env, mac, deps }) {
  const rs = await env.DB
    .prepare('SELECT id, body, actor_id, created_at FROM client_notes WHERE mac = ? ORDER BY created_at DESC LIMIT 50')
    .bind(mac).all();
  return deps.jsonResp({ items: (rs && rs.results) || [] });
}

async function addNote({ request, env, dev, mac, actor, deps }) {
  const b = await readBody(request);
  if (!b) return deps.errResp('bad_json', 'Invalid JSON body', 400);
  const body = cleanText(b.body, LIMITS.note);
  if (!body) return deps.errResp('missing_body', 'La note est vide.', 400);
  const id = deps.genId('note');
  await env.DB.prepare(
    'INSERT INTO client_notes (id, mac, body, actor_id, created_at) VALUES (?, ?, ?, ?, ?)',
  ).bind(id, mac, body, actor.id, Date.now()).run();
  await deps.logAudit(env, null, actor, 'client.note.add',
    { type: 'device', id: dev.id }, null, { note_id: id });
  return deps.jsonResp({ ok: true, id }, 201);
}

async function deleteNote({ env, dev, mac, actor, deps }, noteId) {
  const r = await env.DB
    .prepare('DELETE FROM client_notes WHERE id = ? AND mac = ?')
    .bind(String(noteId || ''), mac).run();
  const n = (r && r.meta && r.meta.changes) || 0;
  if (!n) return deps.errResp('not_found', 'Note introuvable.', 404);
  await deps.logAudit(env, null, actor, 'client.note.delete',
    { type: 'device', id: dev.id }, { note_id: noteId }, null);
  return deps.jsonResp({ ok: true, deleted: 1 });
}

// ----- GET /devices/:id/actions : journal des actions de ce client -----
//  Lignes d'audit visant l'appareil (blocage, licence, essai, messages…)
//  ou sa source (liste poussée). Sans IP ni secret.
async function listActions({ request, env, dev, mac, deps }) {
  const url = new URL(request.url);
  let limit = Number(url.searchParams.get('limit')) || 50;
  limit = Math.max(1, Math.min(200, Math.floor(limit)));
  const rs = await env.DB.prepare(
    `SELECT id, actor_type, actor_id, action, target_type, target_id,
            after_json, created_at
       FROM audit_logs
      WHERE (target_type = 'device' AND target_id = ?)
         OR (target_type = 'device_source' AND target_id = ?)
      ORDER BY created_at DESC LIMIT ?`,
  ).bind(dev.id, mac, limit).all();
  const items = ((rs && rs.results) || []).map((r) => {
    let after = null;
    try { after = r.after_json ? JSON.parse(r.after_json) : null; } catch (_) { after = null; }
    return {
      id: r.id,
      action: r.action,
      actor_type: r.actor_type,
      actor_id: r.actor_id,
      created_at: r.created_at,
      detail: scrubAudit(after),
    };
  });
  return deps.jsonResp({ items });
}
