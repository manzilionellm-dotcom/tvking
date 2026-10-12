// Chat privé indépendant du canal des ordres : aucun notifyBox, aucun
// changement de curseur, heartbeat, WebSocket ou activation.
const schemas = new WeakMap();
const reply = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'private, no-store' } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const macPattern = /^[a-f0-9]{64}$/;

// Borne la lecture elle-même, même sans Content-Length fiable.
async function messageBody(request) {
  if (!request.body) return '';
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 10000) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder().decode(bytes);
}

async function ensure(db) {
  if (!schemas.has(db)) {
    const pending = db.batch([
      db.prepare(`CREATE TABLE IF NOT EXISTS support_threads (
        mac TEXT PRIMARY KEY, device_label TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL,
        client_read_seq INTEGER NOT NULL DEFAULT 0, owner_read_seq INTEGER NOT NULL DEFAULT 0)`),
      db.prepare(`CREATE TABLE IF NOT EXISTS support_messages (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, mac TEXT NOT NULL,
        client_id TEXT NOT NULL, sender TEXT NOT NULL CHECK(sender IN ('client','owner')),
        body TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(mac, sender, client_id))`),
      db.prepare('CREATE INDEX IF NOT EXISTS support_message_thread ON support_messages(mac, seq)'),
      db.prepare('CREATE INDEX IF NOT EXISTS support_message_rate ON support_messages(mac, sender, created_at)'),
    ]);
    schemas.set(db, pending);
    try { await pending; } catch (error) { schemas.delete(db); throw error; }
  }
  await schemas.get(db);
}

async function thread(request, env, mac, sender) {
  if (!macPattern.test(mac)) return reply({ error: 'invalid_device', message: 'Appareil invalide.' }, 400);
  if (!env.DB) return reply({ error: 'unavailable', message: 'Chat temporairement indisponible.' }, 503);
  await ensure(env.DB);
  const column = sender === 'owner' ? 'owner_read_seq' : 'client_read_seq';
  const other = sender === 'owner' ? 'client' : 'owner';
  if (request.method === 'GET') {
    const params = new URL(request.url).searchParams;
    const row = await env.DB.prepare('SELECT * FROM support_threads WHERE mac = ?').bind(mac).first();
    const unread = await env.DB.prepare('SELECT COUNT(*) AS n FROM support_messages WHERE mac = ? AND sender = ? AND seq > ?')
      .bind(mac, other, row?.[column] || 0).first();
    const info = { unread: unread.n, client_read_seq: row?.client_read_seq || 0, owner_read_seq: row?.owner_read_seq || 0 };
    if (params.get('summary') === '1') return reply(info);
    const before = Number(params.get('before') || Number.MAX_SAFE_INTEGER);
    const after = Number(params.get('after') || 0);
    if (!Number.isSafeInteger(before) || before < 1 || !Number.isSafeInteger(after) || after < 0) return reply({ error: 'invalid_cursor' }, 400);
    // Une première ouverture voit les messages récents ; après un curseur,
    // lecture ascendante pour ne jamais sauter une page reçue hors ligne.
    const order = after ? 'ASC' : 'DESC';
    const data = await env.DB.prepare(`SELECT seq, client_id, sender, body, created_at FROM support_messages
      WHERE mac = ? AND seq > ? AND seq < ? ORDER BY seq ${order} LIMIT 101`).bind(mac, after, before).all();
    const more = data.results.length > 100;
    const items = data.results.slice(0, 100);
    if (!after) items.reverse();
    return reply({ ...info, items, more });
  }
  if (!['POST', 'PATCH'].includes(request.method)) return reply({ error: 'method_not_allowed' }, 405);
  const raw = await messageBody(request);
  if (raw === null) return reply({ error: 'too_large', message: 'Message trop long.' }, 413);
  let body;
  try { body = JSON.parse(raw); } catch { return reply({ error: 'bad_json' }, 400); }
  if (request.method === 'PATCH') {
    const seq = body?.read_through;
    if (!Number.isSafeInteger(seq) || seq < 1) return reply({ error: 'invalid_cursor' }, 400);
    // On ne peut accuser lecture que d'un message DE CE fil.
    const known = await env.DB.prepare('SELECT 1 FROM support_messages WHERE mac = ? AND seq = ?').bind(mac, seq).first();
    if (!known) return reply({ error: 'invalid_cursor' }, 400);
    await env.DB.prepare(`UPDATE support_threads SET ${column} = MAX(${column}, ?) WHERE mac = ?`).bind(seq, mac).run();
    return reply({ ok: true });
  }
  if (!body || !uuid.test(body.client_id || '') || typeof body.body !== 'string' ||
      !body.body.trim() || body.body.trim().length > 2000) return reply({ error: 'invalid_message', message: 'Écris un message de 1 à 2 000 caractères.' }, 400);
  const text = body.body.trim();
  const now = Date.now();
  const read = env.DB.prepare('SELECT seq, client_id, sender, body, created_at FROM support_messages WHERE mac = ? AND sender = ? AND client_id = ?')
    .bind(mac, sender, body.client_id);
  const result = await env.DB.batch([
    env.DB.prepare(`INSERT INTO support_threads(mac, device_label, updated_at) VALUES (?, ?, ?) ON CONFLICT(mac) DO NOTHING`).bind(mac, /^MK(?::[A-F0-9]{2}){5}$/.test(body.device_label || '') ? body.device_label : '', now),
    // Limite atomique : même 30 envois simultanés ne dépassent pas 20/min.
    env.DB.prepare(`INSERT INTO support_messages(mac, client_id, sender, body, created_at)
      SELECT ?, ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM support_messages
        WHERE mac = ? AND sender = ? AND created_at > ?) < 20
      ON CONFLICT(mac, sender, client_id) DO NOTHING`).bind(mac, body.client_id, sender, text, now, mac, sender, now - 60000),
    env.DB.prepare('UPDATE support_threads SET updated_at = ? WHERE mac = ? AND changes() = 1').bind(now, mac), read,
  ]);
  const item = result[3].results[0];
  if (!item) return reply({ error: 'rate_limited', message: 'Trop de messages. Réessaie dans une minute.' }, 429);
  if (item.body !== text) return reply({ error: 'conflict', message: 'Cet envoi existe déjà avec un autre texte.' }, 409);
  return reply({ item }, result[1].meta.changes ? 201 : 200);
}

export async function handleDeviceSupport(request, env, mac) {
  // Identité de chat dédiée : aucun changement de preuve de licence/source.
  // Le chemin est SHA-256(secret aléatoire 256 bits), PAS la MAC publique.
  // Sans ce secret, on ne peut ni usurper ni récupérer un fil existant.
  const token = request.headers.get('X-Support-Token') || '';
  if (!/^[A-Za-z0-9_-]{43}$/.test(token) || !macPattern.test(mac)) return reply({ error: 'chat_auth_required' }, 401);
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token)));
  const expected = [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
  if (expected !== mac) return reply({ error: 'chat_auth_required' }, 401);
  return thread(request, env, mac, 'client');
}

export async function handleOwnerSupport(request, env, parts) {
  // L'appelant exige super_admin : aucun revendeur n'entre dans ce module.
  if (!env.DB) return reply({ error: 'unavailable' }, 503);
  await ensure(env.DB);
  if (request.method === 'GET' && parts.length === 1) {
    const q = (new URL(request.url).searchParams.get('q') || '').trim().slice(0, 64);
    const rows = await env.DB.prepare(`SELECT t.*,
      (SELECT body FROM support_messages WHERE mac = t.mac ORDER BY seq DESC LIMIT 1) AS preview,
      (SELECT COUNT(*) FROM support_messages WHERE mac = t.mac AND sender = 'client' AND seq > t.owner_read_seq) AS unread
      FROM support_threads t WHERE (t.mac LIKE ? OR t.device_label LIKE ?) ORDER BY t.updated_at DESC, t.mac LIMIT 100`).bind(`%${q}%`, `%${q.toUpperCase()}%`).all();
    return reply({ items: rows.results });
  }
  if (parts.length !== 2) return reply({ error: 'not_found' }, 404);
  let mac;
  try { mac = decodeURIComponent(parts[1]); } catch { return reply({ error: 'invalid_device' }, 400); }
  return thread(request, env, mac, 'owner');
}
