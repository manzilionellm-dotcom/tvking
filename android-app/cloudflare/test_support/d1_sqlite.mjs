// =========================================================
//  d1_sqlite.mjs — Base D1 de test, fidèle, sur SQLite réel (node:sqlite)
// =========================================================
//  UN seul harnais pour tous les bancs Worker (avant le 06/10/2026 : six
//  copies divergentes ; l'une rendait `run()` sans `results`, ce qui a
//  masqué un défaut jusqu'au test sur workerd).
//
//  Sémantique D1 reproduite (d'après l'API D1 de Cloudflare) :
//    • prepare(sql).bind(...) ; valeurs `undefined` refusées comme D1
//      (D1_TYPE_ERROR) au lieu d'être changées en NULL en silence ;
//    • first()        → première ligne ou null ; first('col') → valeur ;
//    • all()          → { results, success, meta: { changes, last_row_id, rows_read, rows_written } } ;
//    • run()          → même forme ; `results` rempli pour SELECT et RETURNING ;
//    • batch([...])   → UNE transaction : tout ou rien, rejet = ROLLBACK,
//                       résultats dans l'ordre des requêtes ;
//    • erreurs        → Error dont le message commence par « D1_ERROR: » ;
//    • changes()      → même connexion pour tout le lot (comme D1).
//
//  NON reproduit (et donc prouvé ailleurs, sur workerd + D1 local, par
//  concurrency.e2e.mjs) : la vraie concurrence entre requêtes. Ici les
//  appels s'exécutent dans l'ordre de la boucle d'événements.
//
//  Injection de pannes : `faults.add({ match: /regex/, times: 1, when:
//  'before' | 'after', error })` fait échouer la prochaine requête dont le
//  SQL correspond — 'before' : rien n'est écrit ; 'after' : la requête a été
//  exécutée (et engagée hors lot) puis l'erreur est levée (« réponse perdue
//  après écriture »). Dans un lot, toute erreur annule le lot entier.
// =========================================================
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

function d1Error(e) {
  const msg = e && e.message ? e.message : String(e);
  const err = new Error(msg.startsWith('D1_') ? msg : `D1_ERROR: ${msg}`);
  err.cause = e;
  return err;
}

const RETURNS_ROWS = (sql) => /^\s*(select|with|pragma)\b/i.test(sql) || /\breturning\b/i.test(sql);

/// `jitterMs` : chaque appel D1 attend 0..jitterMs ms avant de s'exécuter
/// (D1 est distant : chaque requête est un aller-retour). Des requêtes
/// lancées en même temps s'entrelacent alors à chaque `await`, comme sur
/// Cloudflare. Un lot reste indivisible (D1 l'exécute d'un bloc).
export function createD1({ schema = true, extraSql = [], jitterMs = 0 } = {}) {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  if (schema) db.exec(readFileSync(join(here, '..', 'schema.sql'), 'utf8'));
  for (const sql of extraSql) {
    try { db.exec(sql); } catch (_) { /* colonne déjà présente */ }
  }
  const faults = [];
  const pause = () => (jitterMs > 0
    ? new Promise((res) => setTimeout(res, Math.random() * jitterMs))
    : Promise.resolve());
  const stats = { statements: 0, batches: 0 };
  let inBatch = false;

  function takeFault(sql) {
    const i = faults.findIndex((f) => f.match.test(sql) && f.times > 0);
    if (i < 0) return null;
    const f = faults[i];
    f.times -= 1;
    f.hits = (f.hits || 0) + 1;
    return f;
  }

  function exec(sql, params) {
    stats.statements += 1;
    const fault = takeFault(sql);
    if (fault && fault.when !== 'after') throw d1Error(fault.error || new Error('injected failure (before)'));
    let out;
    try {
      if (RETURNS_ROWS(sql)) {
        const rows = db.prepare(sql).all(...params);
        const write = !/^\s*(select|with|pragma)\b/i.test(sql);
        out = { rows, changes: write ? rows.length : 0, lastRowId: 0 };
      } else {
        const info = db.prepare(sql).run(...params);
        out = { rows: [], changes: Number(info.changes), lastRowId: Number(info.lastInsertRowid) };
      }
    } catch (e) {
      throw d1Error(e);
    }
    if (fault && fault.when === 'after') throw d1Error(fault.error || new Error('injected failure (after)'));
    return out;
  }

  function result(out) {
    return {
      success: true,
      results: out.rows,
      meta: { changes: out.changes, last_row_id: out.lastRowId, rows_read: out.rows.length, rows_written: out.changes, duration: 0 },
    };
  }

  function statement(sql, params) {
    for (const p of params) {
      if (p === undefined) throw d1Error(new Error('D1_TYPE_ERROR: Type \'undefined\' not supported for value \'undefined\''));
    }
    return {
      sql,
      params,
      bind(...args) { return statement(sql, args); },
      async first(col) {
        await pause();
        const out = exec(sql, params);
        const row = out.rows[0];
        if (row === undefined) return null;
        if (col !== undefined) {
          if (!(col in row)) throw d1Error(new Error(`D1_COLUMN_NOTFOUND: Column not found (${col})`));
          return row[col];
        }
        return row;
      },
      async all() { await pause(); return result(exec(sql, params)); },
      async run() { await pause(); return result(exec(sql, params)); },
      async raw() { await pause(); return exec(sql, params).rows.map((r) => Object.values(r)); },
    };
  }

  const DB = {
    prepare(sql) { return statement(sql, []); },
    async batch(stmts) {
      await pause();
      if (inBatch) throw d1Error(new Error('nested batch'));
      stats.batches += 1;
      inBatch = true;
      db.exec('BEGIN');
      try {
        const out = [];
        for (const s of stmts) out.push(result(exec(s.sql, s.params)));
        db.exec('COMMIT');
        return out;
      } catch (e) {
        try { db.exec('ROLLBACK'); } catch (_) { /* déjà annulée */ }
        throw d1Error(e);
      } finally {
        inBatch = false;
      }
    },
    async exec(sql) { db.exec(sql); return { count: 1, duration: 0 }; },
  };

  return {
    DB,
    db,
    stats,
    faults: {
      add(f) { const entry = { times: 1, when: 'before', ...f }; faults.push(entry); return entry; },
      clear() { faults.length = 0; },
    },
  };
}

/// Durable Object de canal sur stockage mémoire (la vraie classe RealtimeHub).
export function fakeRealtimeHub(env, RealtimeHub) {
  const hubs = new Map();
  const storage = () => {
    const map = new Map();
    return { async get(k) { return map.get(k); }, async put(k, v) { map.set(k, v); } };
  };
  return {
    idFromName(name) { return name; },
    get(id) {
      if (!hubs.has(id)) {
        hubs.set(id, new RealtimeHub({ storage: storage(), getWebSockets: () => [], acceptWebSocket() {} }, env));
      }
      const hub = hubs.get(id);
      return { fetch: (url, init) => hub.fetch(url instanceof Request ? url : new Request(url, init)) };
    },
  };
}
