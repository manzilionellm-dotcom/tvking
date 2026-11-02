// Le bundle original filtre déjà pays, activation et expiration, mais oublie
// expires_at dans son JSON public. On complète seulement les annonces qu'il
// vient d'autoriser : aucune nouvelle annonce ni aucun pays supplémentaire.
export async function attachAnnouncementExpiry(env, response) {
  if (!response.ok || !env.DB) return response;
  try {
    const value = await response.clone().json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) return response;
    const validId = row => Number.isSafeInteger(row?.id) && row.id > 0;
    const records = [value, ...(Array.isArray(value.pending) ? value.pending.slice(0, 30) : [])];
    const ids = [...new Set(records.filter(validId).map(row => row.id))];
    // {} = interrupteur coupé / rien pour ce pays : ne rien relire ni ajouter.
    if (!ids.length) return response;
    const rows = await env.DB.prepare(`SELECT id,expires_at FROM app_broadcasts
      WHERE id IN (${ids.map(() => '?').join(',')})`).bind(...ids).all();
    const expiry = new Map((rows.results || []).map(row => [row.id,
      Number.isSafeInteger(row.expires_at) && row.expires_at > 0 ? row.expires_at : 0]));
    const enrich = row => validId(row) && expiry.has(row.id)
      ? { ...row, expires_at: expiry.get(row.id) } : row;
    const next = enrich(value);
    if (Array.isArray(value.pending)) next.pending = value.pending.map(enrich);
    const headers = new Headers(response.headers);
    headers.delete('Content-Length');
    return new Response(JSON.stringify(next), { status: response.status, headers });
  } catch {
    // Métadonnée facultative : le sondage compatible continue à retirer les
    // annonces expirées même si cette lecture additionnelle échoue.
    return response;
  }
}
