// =========================================================
//  device_sources_store.js — Écriture des listes d'une MAC, sûre en
//  concurrence, avec révision dans la MÊME transaction
// =========================================================
//  Défaut racine (06/10/2026, prouvé sur workerd) : cinq chemins
//  réécrivaient `device_sources.sources_json` par « lire → modifier en
//  JavaScript → écrire » (envoi panel, effacement panel, ajout / retrait
//  par le client, remise à neuf). Deux écritures simultanées se perdaient
//  l'une l'autre (une liste ajoutée par le client pendant un envoi du panel
//  disparaissait), et la révision était numérotée par « MAX(rev)+1 lu puis
//  inséré » : 10 envois simultanés → révisions 1..5 seulement, réponses 200.
//
//  Ici, un seul chemin d'écriture :
//    1. lire la ligne ET son `version` ;
//    2. calculer la nouvelle liste (fonction `mutate`, sans effet de bord) ;
//    3. un lot D1 (une transaction) :
//         écriture CONDITIONNELLE `WHERE mac = ? AND version = ?`
//         (ou INSERT … ON CONFLICT DO NOTHING si la ligne n'existait pas) ;
//         puis la révision, numérotée PAR SQLite dans l'insertion même
//         (`COALESCE(MAX(rev), 0) + 1`, clé primaire (mac, rev)), gardée par
//         `changes() = 1` : pas de révision sans écriture, pas d'écriture
//         sans révision ;
//    4. si la ligne a changé entre 1 et 3 : relire et recommencer (boucle de
//       comparaison-échange, PAS un « retry aveugle » : chaque tour repart
//       de l'état réel). Épuisé → `{ conflict: true }`, que l'appelant rend
//       en 409 explicite. Jamais de perte silencieuse.
// =========================================================
import { sealSource } from './secret_box.js';
import { ensureOrderTables } from './box_orders.js';

const _versionReady = new WeakSet();

/// Colonnes que ce module LIT et ÉCRIT (ajouts additifs, une fois PAR BASE).
///
/// Défaut trouvé le 06/10/2026 (audit sécurité rejoué sur une vraie base
/// SQLite) : la table peut avoir été créée par la route self-source du
/// Worker, qui ne pose ni `reseller_id` ni `version`. Seule la route panel
/// ajoutait `reseller_id`. Sur une base où le panel n'a jamais écrit, chaque
/// ajout de liste par le client finissait en 500 (« no such column:
/// reseller_id »). Ce module garantit donc lui-même TOUTES les colonnes
/// qu'il touche, quel que soit le chemin qui a créé la table.
const STORE_COLUMNS = [
  'sources_json TEXT',
  'origin TEXT',
  'reseller_id TEXT',
  'version INTEGER NOT NULL DEFAULT 0',
];
export async function ensureSourcesVersion(env) {
  if (!env || !env.DB || _versionReady.has(env.DB)) return;
  for (const col of STORE_COLUMNS) {
    try {
      await env.DB.prepare(`ALTER TABLE device_sources ADD COLUMN ${col}`).run();
    } catch (_) { /* déjà là (ou table absente : vérifié juste après) */ }
  }
  // On ne retient « prêt » que si la table a VRAIMENT ces colonnes : appelé
  // avant la création de la table, on réessaiera au prochain appel au lieu
  // de rester bloqué sans colonnes (même défaut que les drapeaux globaux).
  try {
    await env.DB.prepare('SELECT sources_json, origin, reseller_id, version FROM device_sources LIMIT 0').all();
    _versionReady.add(env.DB);
  } catch (_) { /* table pas encore créée */ }
}

/// Liste stockée d'une ligne (scellée). Repli sur les colonnes plates.
export function storedItems(row) {
  if (!row) return [];
  let items = [];
  if (row.sources_json) {
    try { items = JSON.parse(row.sources_json) || []; } catch (_) { items = []; }
  }
  if (!Array.isArray(items) || !items.length) {
    if (!row.type && !row.m3u_url && !row.server_url) return [];
    items = [{
      type: row.type, label: row.label, server_url: row.server_url,
      username: row.username, password: row.password, m3u_url: row.m3u_url, epg_url: row.epg_url,
    }];
  }
  return items;
}

function hostsOf(items) {
  const out = [];
  for (const s of items || []) {
    const raw = s && (s.server_url || s.m3u_url);
    if (!raw || typeof raw !== 'string' || raw.startsWith('enc1')) continue;
    try { out.push(new URL(raw).host); } catch (_) { /* invalide */ }
  }
  return out;
}

/// Lit les listes ET leur révision dans la même instruction SQLite. Deux
/// lectures séparées pourraient associer les anciennes listes à une nouvelle
/// révision et autoriser malgré tout leur écrasement. L'historique conserve
/// la révision même après effacement de la ligne device_sources : une ancienne
/// version de ligne ne redevient donc pas valide après recréation.
export async function readSourcesSnapshot(env, mac) {
  await ensureSourcesVersion(env);
  await ensureOrderTables(env);
  const snapshot = await env.DB.prepare(
    'SELECT d.*, COALESCE((SELECT MAX(rev) FROM source_revisions WHERE mac = ?), 0) AS snapshot_rev '
    + 'FROM (SELECT ? AS requested_mac) q LEFT JOIN device_sources d ON d.mac = q.requested_mac',
  ).bind(mac, mac).first();
  if (!snapshot) return { row: null, rev: 0 };
  const { snapshot_rev, ...row } = snapshot;
  return { row: row.mac ? row : null, rev: Number(snapshot_rev) || 0 };
}

/// `mutate(row, items)` rend { items } (liste complète à stocker, en clair
/// ou déjà scellée), ou { abort: <valeur rendue telle quelle> }.
/// Options : { revision: { traceId, actor, rollbackOf, kind }, resellerId,
///             maxAttempts, expectedRev }. La précondition reste optionnelle
/// pour les anciens clients ; si elle existe, un snapshot périmé est refusé.
/// Rend { ok, items, rev, version, attempts } | { abort } | { conflict, attempts }.
export async function casWriteSources(env, mac, mutate, opts = {}) {
  await ensureSourcesVersion(env);
  const expectedRev = opts.expectedRev;
  const guarded = expectedRev !== undefined;
  if (opts.revision || guarded) await ensureOrderTables(env);
  const maxAttempts = opts.maxAttempts || 50;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const snapshot = guarded ? await readSourcesSnapshot(env, mac) : null;
    if (guarded && snapshot.rev !== expectedRev) return { conflict: true, attempts: attempt };
    const row = guarded ? snapshot.row : await env.DB.prepare(
      'SELECT mac, type, label, server_url, username, password, m3u_url, epg_url, '
      + 'sources_json, origin, reseller_id, version FROM device_sources WHERE mac = ?',
    ).bind(mac).first();
    const out = await mutate(row, storedItems(row));
    if (out && out.abort !== undefined) return { abort: out.abort };
    const sealed = [];
    for (const item of (out && out.items) || []) sealed.push(await sealSource(env, item));
    const now = Date.now();
    const stmts = [];
    // Vérification DANS la transaction aussi : une autre écriture peut arriver
    // après la lecture ci-dessus, avant le lot. Ce contrôle couvre également
    // le cas où la ligne a été effacée puis recréée avec version = 1.
    const revisionGuard = guarded
      ? ' AND COALESCE((SELECT MAX(rev) FROM source_revisions WHERE mac = ?), 0) = ?' : '';
    const guardParams = guarded ? [mac, expectedRev] : [];
    let writes = true;
    if (row && sealed.length) {
      const first = sealed[0];
      const rowOrigin = sealed.every((s) => s.origin === 'self') ? 'self' : 'panel';
      stmts.push(env.DB.prepare(
        `UPDATE device_sources SET
           type = ?, label = ?, server_url = ?, username = ?, password = ?, m3u_url = ?, epg_url = ?,
           sources_json = ?, origin = ?, reseller_id = COALESCE(?, reseller_id),
           updated_at = ?, version = version + 1
         WHERE mac = ? AND version = ?${revisionGuard}`,
      ).bind(first.type || null, first.label || null, first.server_url || null, first.username || null,
        first.password || null, first.m3u_url || null, first.epg_url || null,
        JSON.stringify(sealed), rowOrigin, opts.resellerId || null, now, mac, Number(row.version) || 0, ...guardParams));
    } else if (row && !sealed.length) {
      stmts.push(env.DB.prepare('DELETE FROM device_sources WHERE mac = ? AND version = ?' + revisionGuard)
        .bind(mac, Number(row.version) || 0, ...guardParams));
    } else if (!row && sealed.length) {
      const first = sealed[0];
      const rowOrigin = sealed.every((s) => s.origin === 'self') ? 'self' : 'panel';
      stmts.push(env.DB.prepare(
        `INSERT INTO device_sources
           (mac, type, label, server_url, username, password, m3u_url, epg_url, sources_json, origin,
            reseller_id, updated_at, version)
         SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1 WHERE 1${revisionGuard}
         ON CONFLICT(mac) DO NOTHING`,
      ).bind(mac, first.type || null, first.label || null, first.server_url || null, first.username || null,
        first.password || null, first.m3u_url || null, first.epg_url || null,
        JSON.stringify(sealed), rowOrigin, opts.resellerId || null, now, ...guardParams));
    } else {
      writes = false; // ni ligne ni liste : rien à écrire
    }
    const revIdx = stmts.length;
    if (opts.revision) {
      const panelSealed = sealed.filter((s) => s.origin !== 'self');
      const panelClear = ((out && out.items) || []).filter((s) => s && s.origin !== 'self');
      const r = opts.revision;
      stmts.push(env.DB.prepare(
        `INSERT INTO source_revisions
           (mac, rev, state, panel_json, item_count, hosts, trace_id, actor_type, actor_id,
            rollback_of, validated_at, published_at, created_at)
         SELECT ?, COALESCE((SELECT MAX(rev) FROM source_revisions WHERE mac = ?), 0) + 1,
                'published', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
         WHERE ${writes ? 'changes() = 1' : '1' + revisionGuard}
         RETURNING rev`,
      ).bind(mac, mac, JSON.stringify(panelSealed), panelSealed.length, JSON.stringify(hostsOf(panelClear)),
        r.traceId || null, r.actor ? r.actor.type : null, r.actor ? r.actor.id : null,
        r.rollbackOf || null, now, now, now, ...(!writes ? guardParams : [])));
    }
    if (!stmts.length) return { ok: true, items: sealed, rev: null, version: null, attempts: attempt };
    const res = await env.DB.batch(stmts);
    const wrote = writes ? (res[0] && res[0].meta && res[0].meta.changes === 1)
      : !opts.revision || !!(res[revIdx] && res[revIdx].results && res[revIdx].results.length);
    if (wrote) {
      const revRow = opts.revision && res[revIdx] && res[revIdx].results ? res[revIdx].results[0] : null;
      return {
        ok: true,
        items: sealed,
        rev: revRow ? revRow.rev : null,
        version: row ? (Number(row.version) || 0) + 1 : (sealed.length ? 1 : null),
        attempts: attempt,
      };
    }
    // La ligne a changé depuis la lecture (autre écriture engagée) : relire.
  }
  return { conflict: true, attempts: maxAttempts };
}
