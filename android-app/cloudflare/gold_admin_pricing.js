// L'API historique remplaçait un prix volontairement vidé par 9,9 / 4,9.
// On conserve son authentification propriétaire, sa validation et ses autres
// réglages. Ce raccord ne répare QUE les montants explicitement vidés après
// une écriture autorisée ; aucune licence ou durée d'accès n'est touchée.
const emptyPriceKeys = body => ['lifetime', 'yearly'].filter(key =>
  body && Object.hasOwn(body, key) && (body[key] == null ||
    (typeof body[key] === 'string' && !body[key].trim())));

export function prepareAdminPricingWrite(request, body) {
  if (request.method !== 'PUT' || !emptyPriceKeys(body).length) return request;
  // Une corrélation fournie par le client peut être réutilisée : elle ne
  // permettrait pas d'identifier UNE ligne d'audit sous concurrence. Pour
  // cette réparation, l'original reçoit un UUID serveur neuf, également
  // renvoyé dans X-Request-Id. Aucun rôle/jeton ni contenu n'est changé.
  const headers = new Headers(request.headers);
  headers.set('X-Request-Id', crypto.randomUUID());
  return new Request(request, { headers });
}

export async function attachAdminPricing(env, response, body) {
  if (!response.ok || !env.DB) return response;
  const value = await response.clone().json();
  if (!value || typeof value !== 'object' || Array.isArray(value)) return response;
  const emptyKeys = emptyPriceKeys(body);
  if (emptyKeys.length) {
    const statements = emptyKeys.map(key => env.DB.prepare(
      'UPDATE app_config SET value = ? WHERE key = ?',
    ).bind('', `price_${key}`));
    const correlation = response.headers.get('X-Request-Id');
    if (!correlation) throw new Error('pricing_audit_correlation_missing');
    const audits = await env.DB.prepare(`SELECT id,after_json FROM audit_logs
      WHERE action = 'pricing.save' AND correlation_id = ?`).bind(correlation).all();
    if (audits.results.length > 1) throw new Error('pricing_audit_ambiguous');
    const audit = audits.results[0];
    if (audit) {
      const after = JSON.parse(audit.after_json);
      for (const key of emptyKeys) after[key] = '';
      statements.push(env.DB.prepare('UPDATE audit_logs SET after_json = ? WHERE id = ?')
        .bind(JSON.stringify(after), audit.id));
    }
    // L'audit exact et les montants changent dans le même lot D1 : le journal
    // ne raconte plus un prix de remplacement que le panel n'a pas demandé.
    // L'original garde son comportement best-effort si aucun audit n'a pu
    // être écrit ; on n'invente jamais un acteur ni une ancienne trace.
    await env.DB.batch(statements);
  }
  const rows = await env.DB.prepare(`SELECT key,value FROM app_config
    WHERE key IN ('price_lifetime','price_yearly')`).all();
  const prices = Object.fromEntries((rows.results || []).map(row => [row.key, row.value]));
  const next = { ...value,
    lifetime: typeof prices.price_lifetime === 'string' ? prices.price_lifetime : '',
    yearly: typeof prices.price_yearly === 'string' ? prices.price_yearly : '',
  };
  const headers = new Headers(response.headers);
  headers.delete('Content-Length');
  headers.set('Cache-Control', 'no-store');
  return new Response(JSON.stringify(next), { status: response.status, headers });
}
