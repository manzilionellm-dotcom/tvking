// =========================================================
//  insights.js — Pilotage : santé, argent, fraude (LECTURE SEULE)
// =========================================================
//  Une seule réponse pour la page « Pilotage » du panel :
//    • santé    : qualité de lecture par chaîne, version, pays + alerte
//    • argent   : activations par jour, par plan, par revendeur,
//                 abonnements qui expirent, clients perdus
//    • fraude   : la même box vue sous plusieurs MAC
//
//  RÈGLES
//   • Aucune écriture. Aucune table créée ici.
//   • Chaque bloc a son propre try/catch : une table absente ou une
//     colonne manquante vide SON bloc, pas la page.
//   • Les listes sont plafonnées (pas de requête sans LIMIT).
//   • Un essai gratuit n'est jamais compté comme une vente.
// =========================================================

import { epochSql, epochMs } from './page_query.js';

const DAY = 86400000;
const ONLINE_MS = 15 * 60 * 1000;

/// Alerte « panne probable » : au moins 5 box regardent, et 40 % ou plus
/// ont une mauvaise qualité (< 70 %). En dessous de 5, pas d'alerte : une
/// seule box en Wi-Fi faible n'est pas une panne.
export function outageAlert(watching, bad) {
  const w = Number(watching) || 0;
  const b = Number(bad) || 0;
  return w >= 5 && b / w >= 0.4;
}

/// Masque un identifiant matériel : on garde de quoi comparer deux lignes,
/// pas de quoi le réutiliser.
export function maskId(raw) {
  const s = String(raw || '');
  if (s.length <= 6) return s ? '…' : '';
  return s.slice(0, 3) + '…' + s.slice(-3);
}

function rows(res) { return (res && res.results) || []; }
function int(v) { const n = Number(v); return Number.isFinite(n) ? Math.round(n) : 0; }

async function health(env, now) {
  const seen = epochSql('p.last_seen');
  const since = now - ONLINE_MS;
  const base =
    `FROM presence p WHERE ${seen} > ? AND p.quality IS NOT NULL ` +
    `AND p.channel IS NOT NULL AND p.channel != ''`;
  const total = await env.DB.prepare(
    `SELECT COUNT(*) AS n, AVG(p.quality) AS q, ` +
    `SUM(CASE WHEN p.quality < 70 THEN 1 ELSE 0 END) AS bad ${base}`,
  ).bind(since).first();
  const byChannel = await env.DB.prepare(
    `SELECT p.channel AS k, COUNT(*) AS n, AVG(p.quality) AS q ${base} ` +
    `GROUP BY p.channel ORDER BY n DESC, q ASC LIMIT 20`,
  ).bind(since).all();
  const byCountry = await env.DB.prepare(
    `SELECT UPPER(p.country) AS k, COUNT(*) AS n, AVG(p.quality) AS q ${base} ` +
    `AND LENGTH(TRIM(p.country)) = 2 GROUP BY UPPER(p.country) ORDER BY n DESC LIMIT 20`,
  ).bind(since).all();
  let byVersion = { results: [] };
  try {
    byVersion = await env.DB.prepare(
      `SELECT COALESCE(NULLIF(d.app_version, ''), '?') AS k, COUNT(*) AS n, AVG(p.quality) AS q ` +
      `FROM presence p JOIN devices d ON d.mac = p.mac WHERE ${seen} > ? ` +
      `AND p.quality IS NOT NULL AND p.channel IS NOT NULL AND p.channel != '' ` +
      `GROUP BY k ORDER BY n DESC LIMIT 12`,
    ).bind(since).all();
  } catch (_) { /* colonne app_version absente : pas de détail par version */ }
  const shape = (r) => ({ key: String(r.k || ''), count: int(r.n), quality: int(r.q) });
  const watching = int(total && total.n);
  const bad = int(total && total.bad);
  return {
    watching,
    bad,
    quality: watching ? int(total.q) : null,
    alert: outageAlert(watching, bad),
    byChannel: rows(byChannel).map(shape),
    byCountry: rows(byCountry).map(shape),
    byVersion: rows(byVersion).map(shape),
  };
}

async function money(env, now) {
  // Une box n'a qu'UNE ligne de licence par application : un renouvellement
  // repousse sa date, il ne crée pas de ligne. Donc :
  //   • « nouveaux abonnés » = lignes payées créées dans la période ;
  //   • les renouvellements se lisent dans le journal des crédits, qui
  //     ne contient que les activations faites par un revendeur.
  const created = epochSql('l.created_at');
  const exp = epochSql('l.expires_at');
  const paid = `l.plan IS NOT NULL AND l.plan != 'trial'`;
  const since30 = now - 30 * DAY;
  const perDay = await env.DB.prepare(
    `SELECT CAST(${created} / ${DAY} AS INTEGER) AS day, COUNT(*) AS n FROM licenses l ` +
    `WHERE ${paid} AND ${created} > ? GROUP BY day ORDER BY day ASC LIMIT 40`,
  ).bind(since30).all();
  const byPlan = await env.DB.prepare(
    `SELECT l.plan AS k, COUNT(*) AS n FROM licenses l ` +
    `WHERE ${paid} AND ${created} > ? GROUP BY l.plan ORDER BY n DESC LIMIT 12`,
  ).bind(since30).all();
  const byReseller = await env.DB.prepare(
    `SELECT COALESCE(r.name, r.email, 'Direct') AS k, COUNT(*) AS n FROM licenses l ` +
    `LEFT JOIN resellers r ON r.id = l.reseller_id ` +
    `WHERE ${paid} AND ${created} > ? GROUP BY k ORDER BY n DESC LIMIT 20`,
  ).bind(since30).all();
  const totals = await env.DB.prepare(
    `SELECT SUM(CASE WHEN l.expires_at IS NULL OR ${exp} > ? THEN 1 ELSE 0 END) AS active, ` +
    `SUM(CASE WHEN l.expires_at IS NOT NULL AND ${exp} <= ? THEN 1 ELSE 0 END) AS expired ` +
    `FROM licenses l WHERE ${paid}`,
  ).bind(now, now).first();
  const listCols =
    `d.mac AS mac, l.plan AS plan, l.expires_at AS expires_at, ` +
    `c.name AS customer, COALESCE(r.name, r.email, '') AS reseller ` +
    `FROM licenses l JOIN devices d ON d.id = l.device_id ` +
    `LEFT JOIN customers c ON c.id = l.customer_id ` +
    `LEFT JOIN resellers r ON r.id = l.reseller_id`;
  const expiring = await env.DB.prepare(
    `SELECT ${listCols} WHERE ${paid} AND l.expires_at IS NOT NULL ` +
    `AND ${exp} > ? AND ${exp} <= ? ORDER BY ${exp} ASC LIMIT 200`,
  ).bind(now, now + 7 * DAY).all();
  const lost = await env.DB.prepare(
    `SELECT ${listCols} WHERE ${paid} AND l.expires_at IS NOT NULL ` +
    `AND ${exp} <= ? AND ${exp} > ? ORDER BY ${exp} DESC LIMIT 200`,
  ).bind(now - 30 * DAY, now - 180 * DAY).all();
  // Journal des crédits (revendeurs seulement). Table absente : zéro.
  let ledger = null;
  try {
    ledger = await env.DB.prepare(
      `SELECT SUM(CASE WHEN reason = 'activation' THEN 1 ELSE 0 END) AS first, ` +
      `SUM(CASE WHEN reason = 'renew' THEN 1 ELSE 0 END) AS renew ` +
      `FROM credit_ledger WHERE ${epochSql('created_at')} > ?`,
    ).bind(since30).first();
  } catch (_) { /* pas de journal des crédits */ }
  const person = (r) => ({
    mac: String(r.mac || ''),
    plan: String(r.plan || ''),
    expires_at: epochMs(r.expires_at) || 0,
    customer: String(r.customer || ''),
    reseller: String(r.reseller || ''),
  });
  const kv = (r) => ({ key: String(r.k || ''), count: int(r.n) });
  const days = rows(perDay).map((r) => ({ day: int(r.day) * DAY, count: int(r.n) }));
  return {
    newPaid30: days.reduce((sum, d) => sum + d.count, 0),
    perDay: days,
    byPlan: rows(byPlan).map(kv),
    byReseller: rows(byReseller).map(kv),
    paidActive: int(totals && totals.active),
    paidExpired: int(totals && totals.expired),
    expiring: rows(expiring).map(person),
    lost: rows(lost).map(person),
    resellerActivations30: int(ledger && ledger.first),
    resellerRenewals30: int(ledger && ledger.renew),
  };
}

async function fraud(env) {
  const same = await env.DB.prepare(
    `SELECT android_id AS id, COUNT(*) AS n, GROUP_CONCAT(mac, ' ') AS macs FROM devices ` +
    `WHERE android_id IS NOT NULL AND android_id != '' ` +
    `GROUP BY android_id HAVING COUNT(*) > 1 ORDER BY n DESC LIMIT 100`,
  ).all();
  return {
    sameBox: rows(same).map((r) => ({
      id: maskId(r.id),
      count: int(r.n),
      macs: String(r.macs || '').split(' ').filter(Boolean).slice(0, 12),
    })),
  };
}

const EMPTY_HEALTH = {
  watching: 0, bad: 0, quality: null, alert: false,
  byChannel: [], byCountry: [], byVersion: [],
};
const EMPTY_MONEY = {
  newPaid30: 0, perDay: [], byPlan: [], byReseller: [],
  paidActive: 0, paidExpired: 0, expiring: [], lost: [],
  resellerActivations30: 0, resellerRenewals30: 0,
};

/// Tout le pilotage. Ne lève jamais : un bloc en échec revient vide,
/// avec son nom dans `unavailable` pour que le panel le dise.
export async function readInsights(env, now = Date.now()) {
  const out = {
    generated_at: now, health: EMPTY_HEALTH, money: EMPTY_MONEY,
    fraud: { sameBox: [] }, unavailable: [],
  };
  if (!env || !env.DB) { out.unavailable = ['health', 'money', 'fraud']; return out; }
  try { out.health = await health(env, now); } catch (_) { out.unavailable.push('health'); }
  try { out.money = await money(env, now); } catch (_) { out.unavailable.push('money'); }
  try { out.fraud = await fraud(env); } catch (_) { out.unavailable.push('fraud'); }
  return out;
}
