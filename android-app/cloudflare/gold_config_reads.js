// Les handlers historiques avalent certaines pannes D1 et rendent un 200
// vide. On garde leurs filtres exacts mais observe les opérations réellement
// exécutées : un échec ne doit pas devenir un accusé « appliqué » dans l'app.
export const publicConfigPaths = new Set([
  '/api/announcement', '/api/home-layout', '/api/theme', '/api/ad',
  '/api/featured', '/api/pricing', '/api/feedback-prompt', '/api/banners',
]);

export function observeDatabase(db, { onError = () => {}, firstOverride } = {}) {
  const originals = new WeakMap();
  const observe = async (sql, operation) => {
    try { return await operation(); }
    catch (error) {
      // L'ancien bootstrap tente volontairement les ADD COLUMN déjà posés.
      // Seul ce doublon connu est attendu ; panne SQL, lecture ou réseau ne
      // sont jamais ignorées (y compris l'automatisation du thème).
      const duplicate = /^\s*ALTER\s+TABLE\b[\s\S]*\bADD\s+COLUMN\b/i.test(sql) &&
        /duplicate column name/i.test(String(error?.message || error));
      if (!duplicate) onError(error);
      throw error;
    }
  };
  const statement = (source, sql, args = []) => {
    const wrapped = {
      bind(...values) { return statement(source.bind(...values), sql, values); },
      first(...values) {
        const override = firstOverride?.(sql, args, values);
        if (override !== undefined) return Promise.resolve(override);
        return observe(sql, () => source.first(...values));
      },
      all(...values) { return observe(sql, () => source.all(...values)); },
      run(...values) { return observe(sql, () => source.run(...values)); },
      raw(...values) { return observe(sql, () => source.raw(...values)); },
    };
    originals.set(wrapped, source);
    return wrapped;
  };
  return {
    prepare(sql) {
      try { return statement(db.prepare(sql), sql); }
      catch (error) { onError(error); throw error; }
    },
    batch(values) { return observe('BATCH', () => db.batch(values.map(value => originals.get(value) || value))); },
    exec(sql) { return observe(sql, () => db.exec(sql)); },
  };
}

export function unavailableConfig(response) {
  const headers = new Headers(response?.headers);
  headers.delete('Content-Length');
  headers.set('Content-Type', 'application/json; charset=utf-8');
  headers.set('Cache-Control', 'no-store');
  return new Response(JSON.stringify({ error: 'configuration_unavailable' }), { status: 503, headers });
}

export async function strictConfigRead(env, run) {
  if (!env.DB) return unavailableConfig();
  let failed = false;
  const DB = observeDatabase(env.DB, { onError: () => { failed = true; } });
  const response = await run({ ...env, DB });
  return failed && response.ok ? unavailableConfig(response) : response;
}
