// Le catalogue du panel devient la source de vérité dès que sa table existe.
// Une liste explicitement vidée/masquée ne doit jamais ressusciter un ancien
// serveur de DEFAULT_SERVERS. Le bundle d'origine reste inchangé.
export async function attachPublicServers(env, response) {
  if (!response.ok) return response;
  const headers = new Headers(response.headers);
  headers.delete('Content-Length');
  headers.set('Cache-Control', 'no-store');
  try {
    if (!env.DB) throw new Error('database_unavailable');
    const columns = await env.DB.prepare('PRAGMA table_info(default_servers)').all();
    // Ancien déploiement sans catalogue D1 : conserver le contrat historique.
    // Une erreur D1, elle, n'est jamais assimilée à une table absente.
    if (!(columns.results || []).length) return response;
    const rows = await env.DB.prepare(`SELECT id, label, url FROM default_servers
      WHERE enabled = 1 ORDER BY position ASC, created_at ASC`).all();
    const servers = (rows.results || []).map(row => ({
      id: String(row.id), label: String(row.label), url: String(row.url).trim(),
    }));
    return new Response(JSON.stringify({ servers }), { status: response.status, headers });
  } catch {
    // Les apps gardent leur dernier état sur une vraie panne. Envoyer un faux
    // succès avec le repli réactiverait un serveur supprimé depuis le panel.
    return new Response(JSON.stringify({ error: 'servers_unavailable' }), { status: 503, headers });
  }
}
