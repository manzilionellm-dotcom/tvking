// Extension du DO déjà déployé : même namespace, même anneau et mêmes ordres.
// Les sockets ne transportent que des signaux ; les secrets restent en HTTP.
import { RealtimeHub as ExportedHub, goldNotifyBox } from './production/worker.runtime.js';
import { secretMatches } from './device_guard.js';

const PANEL = 'panel-v1';
const LEASE_MS = 35_000;
const json = (body, status = 200) => Response.json(body, { status });
const macOf = raw => {
  let value;
  try { value = decodeURIComponent(String(raw || '')).toUpperCase(); } catch { return ''; }
  return /^MK(?::[0-9A-F]{2}){5}$/.test(value) ? value : '';
};
const hub = (env, name) => env.RT_HUB?.get(env.RT_HUB.idFromName(name));
const attachment = ws => { try { return ws.deserializeAttachment() || {}; } catch { return {}; } };
const live = ws => ws.readyState === 1;

export async function deviceChannelAllowed(request, env, mac) {
  if (!mac) return false;
  const row = await env.DB.prepare('SELECT secret_hash FROM device_secrets WHERE mac=?').bind(mac).first();
  return !!row && await secretMatches(request.headers.get('X-Device-Secret'), row.secret_hash);
}

export class RealtimeHub extends ExportedHub {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/ticket' && request.method === 'POST') {
      const actor = await request.json();
      const ticket = crypto.randomUUID();
      await this.ctx.storage.put(`ticket:${ticket}`, { ...actor, expires: Date.now() + 60_000 });
      await this.armAlarm();
      return json({ ticket });
    }
    if (url.pathname === '/presence') return json(this.presence());
    if (url.pathname === '/panel-event' && request.method === 'POST') {
      await this.sendPanel(await request.json());
      return json({ ok: true });
    }
    if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      let att;
      if (url.pathname === '/api/v1/rt/ws') {
        const ticket = url.searchParams.get('ticket') || '';
        if (!/^[a-f0-9-]{36}$/.test(ticket)) return json({ error: 'unauthorized' }, 401);
        // La consommation et la suppression se font dans la même transaction.
        att = await this.ctx.storage.transaction(async tx => {
          const value = await tx.get(`ticket:${ticket}`);
          await tx.delete(`ticket:${ticket}`);
          return value;
        });
        if (!att || att.expires < Date.now()) return json({ error: 'unauthorized' }, 401);
      } else {
        const mac = macOf(url.searchParams.get('mac'));
        if (!mac) return json({ error: 'bad_mac' }, 400);
        att = { role: 'box', mac };
      }
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].serializeAttachment({ ...att, seen: Date.now() });
      pair[1].send(JSON.stringify({ v: 1, type: 'hello' }));
      if (att.role === 'box') {
        // Reprendre TOUS les ordres manqués, pas seulement le dernier.
        for (const event of await this.mailbox.since(Number(url.searchParams.get('after')) || 0)) {
          pair[1].send(JSON.stringify(event));
        }
        await this.publishPresence();
      }
      await this.armAlarm();
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    return super.fetch(request);
  }

  presence() {
    const sockets = this.ctx.getWebSockets().filter(ws => attachment(ws).role === 'box');
    const active = sockets.filter(ws => live(ws) && Date.now() - (attachment(ws).seen || 0) < LEASE_MS);
    return { online: active.length > 0, last_seen_at: Math.max(0, ...sockets.map(ws => attachment(ws).seen || 0)) };
  }

  async publishPresence(mac) {
    mac ||= this.ctx.getWebSockets().map(ws => attachment(ws).mac).find(Boolean);
    if (!mac) return;
    await hub(this.env, PANEL).fetch('https://hub/panel-event', {
      method: 'POST', body: JSON.stringify({ type: 'presence', mac, ...this.presence(), at: Date.now() }),
    });
  }

  async sendPanel(event) {
    if (!macOf(event.mac)) return;
    const owner = await this.env.DB.prepare('SELECT reseller_id FROM devices WHERE mac=?').bind(event.mac).first();
    for (const ws of this.ctx.getWebSockets()) {
      const att = attachment(ws);
      if (!live(ws) || !['super_admin', 'admin', 'reseller'].includes(att.role)) continue;
      if (att.role === 'reseller' && (!owner?.reseller_id || owner.reseller_id !== att.id)) continue;
      try { ws.send(JSON.stringify(event)); } catch { /* Fermeture concurrente. */ }
    }
  }

  async webSocketMessage(ws, message) {
    let data;
    try { data = JSON.parse(typeof message === 'string' ? message : ''); } catch { return; }
    if (data.type !== 'hello') return;
    const att = attachment(ws);
    ws.serializeAttachment({ ...att, seen: Date.now() });
    ws.send(JSON.stringify({ v: 1, type: 'hello' }));
    await this.armAlarm();
  }

  async webSocketClose(ws, code) {
    const att = attachment(ws);
    try { ws.close(code === 1005 ? 1000 : code, 'closed'); } catch { /* Déjà fermé. */ }
    if (att.role === 'box') await this.publishPresence(att.mac);
  }

  async webSocketError(ws) {
    try { ws.close(1011, 'error'); } catch { /* Déjà fermé. */ }
    const att = attachment(ws);
    if (att.role === 'box') await this.publishPresence(att.mac);
  }

  async armAlarm() {
    if (!await this.ctx.storage.getAlarm()) await this.ctx.storage.setAlarm(Date.now() + 10_000);
  }

  async alarm() {
    const changed = new Set();
    for (const ws of this.ctx.getWebSockets()) {
      const att = attachment(ws);
      if (Date.now() - (att.seen || 0) >= LEASE_MS) {
        try { ws.close(4000, 'heartbeat timeout'); } catch { /* Déjà fermé. */ }
        if (att.mac) changed.add(att.mac);
      }
    }
    for (const mac of changed) await this.publishPresence(mac);
    const tickets = await this.ctx.storage.list({ prefix: 'ticket:' });
    for (const [key, value] of tickets) if (value.expires < Date.now()) await this.ctx.storage.delete(key);
    if (this.ctx.getWebSockets().some(live) || tickets.size) await this.ctx.storage.setAlarm(Date.now() + 10_000);
  }
}

export function createRealtimeRoutes({ original, actorFor }) {
  return async (request, env, ctx) => {
    const url = new URL(request.url), path = url.pathname;
    if (/^\/api\/box\/(ws|wait|ack)(\/|$)/.test(path)) {
      const mac = macOf(path.split('/')[4] || url.searchParams.get('mac'));
      if (!await deviceChannelAllowed(request, env, mac)) return json({ error: 'device_proof_required' }, 401);
      // Les en-têtes de rôle ne sont jamais acceptés depuis une app.
      const headers = new Headers(request.headers);
      headers.delete('X-Panel-Role'); headers.delete('X-Panel-Id');
      const response = await original.fetch(new Request(request, { headers }), env, ctx);
      if (path.includes('/ack/') && response.ok && env.RT_HUB) {
        const value = await response.clone().json();
        for (const item of value.results || []) {
          if (item.status !== 200 || !item.changed) continue;
          const row = await env.DB.prepare(`SELECT order_id,kind,state,config_rev,applied_rev,trace_id,
            received_srv,applied_srv,failed_srv,t1_api FROM box_orders WHERE order_id=? AND mac=?`)
            .bind(item.order_id, mac).first();
          if (!row) continue;
          await hub(env, PANEL).fetch('https://hub/panel-event', { method: 'POST', body: JSON.stringify({
            type: 'receipt', mac, ...row, at: Date.now(),
            elapsed_ms: row.applied_srv && row.t1_api ? row.applied_srv - row.t1_api : null,
          }) });
        }
      }
      return response;
    }
    if (path === '/api/v1/rt/ws') {
      if (!env.RT_HUB) return json({ error: 'unavailable' }, 503);
      return hub(env, PANEL).fetch(request);
    }
    if (path === '/api/v1/rt/ticket' || path === '/api/v1/boxes/live' || path === '/api/v1/online') {
      const actor = await actorFor(request, env, ctx, ['super_admin', 'admin', 'reseller']);
      if (!actor) return json({ error: 'unauthorized' }, 401);
      if (!env.RT_HUB) return json({ error: 'unavailable' }, 503);
      const id = actor.sub || actor.id;
      if (path.endsWith('/ticket')) {
        if (request.method !== 'POST') return json({ error: 'method' }, 405);
        return hub(env, PANEL).fetch('https://hub/ticket', { method: 'POST', body: JSON.stringify({ role: actor.role, id }) });
      }
      if (request.method !== 'GET') return json({ error: 'method' }, 405);
      const args = [], where = [];
      if (actor.role === 'reseller') { where.push('d.reseller_id=?'); args.push(id); }
      if (url.searchParams.has('mac')) {
        const mac = macOf(url.searchParams.get('mac'));
        if (!mac) return json({ error: 'bad_mac' }, 400);
        where.push('d.mac=?'); args.push(mac);
      }
      const devices = await env.DB.prepare(`SELECT d.id,d.mac,d.label,d.block_status,
        COALESCE(p.country,'') AS country,COALESCE(p.ip,'') AS ip,COALESCE(p.channel,'') AS channel
        FROM devices d LEFT JOIN presence p ON p.mac=d.mac
        ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY d.last_seen_at DESC LIMIT 500`).bind(...args).all();
      const items = [];
      // Limiter la concurrence D1/DO tout en répondant aux parcs importants.
      for (let start = 0; start < devices.results.length; start += 20) {
        items.push(...await Promise.all(devices.results.slice(start, start + 20).map(async device => {
          const presence = await (await hub(env, device.mac).fetch('https://hub/presence')).json();
          const orders = await env.DB.prepare(`SELECT order_id AS id,kind,created_at,applied_srv AS applied_at,state,config_rev,applied_rev
            FROM box_orders WHERE mac=? ORDER BY created_at DESC LIMIT 20`).bind(device.mac).all();
          const applied = order => order.state === 'applied' && (order.config_rev == null ||
            (order.applied_rev != null && order.applied_rev >= order.config_rev));
          return { ...device, ...presence, pending: orders.results.filter(o => ['queued', 'sent', 'received'].includes(o.state) || (o.state === 'applied' && !applied(o))),
            last_applied: orders.results.find(applied) || null, fleet_pending: [], fleet_last_applied: null };
        })));
      }
      if (path === '/api/v1/online') {
        const online = items.filter(item => item.online);
        const byCountry = {};
        for (const item of online) if (item.country) byCountry[item.country] = (byCountry[item.country] || 0) + 1;
        const today = await env.DB.prepare(`SELECT COUNT(*) AS n FROM devices d WHERE d.last_seen_at>=?
          ${actor.role === 'reseller' ? 'AND d.reseller_id=?' : ''}`)
          .bind(Date.now() - 86400_000, ...(actor.role === 'reseller' ? [id] : [])).first();
        return json({ onlineCount: online.length, todayCount: today.n, byCountry,
          items: online.map(item => ({ mac: item.mac, ip: item.ip, country: item.country,
            channel: item.channel, lastSeen: item.last_seen_at })) });
      }
      return json({ now: Date.now(), items: items.map(({ country, ip, channel, ...item }) => item) });
    }
    return null;
  };
}

// Seules les routes de réglage effectivement présentes dans le panel sont
// diffusées. L'autorisation et la validation restent celles du Worker exporté.
export function globalPanelChange(path) {
  const route=/^\/api\/v1\/([^/]+)(?:\/.*)?$/.exec(path)?.[1];
  return ({announcements:'message','home-layout':'home','force-update':'force_update',
    featured:'featured',theme:'theme',ad:'ad',pricing:'pricing',
    'feedback-prompt':'feedback',servers:'servers','grant-trial-all':'license'})[route] || null;
}

// Chaque appareil reçoit son ordre durable et son accusé, même hors ligne.
export async function pushPanelSettingChange(env,kind) {
  let after = '';
  while (true) {
    const rows = await env.DB.prepare('SELECT mac FROM devices WHERE mac>? ORDER BY mac LIMIT 100').bind(after).all();
    if (!rows.results.length) return;
    for (let start = 0; start < rows.results.length; start += 20) {
      await Promise.all(rows.results.slice(start, start + 20).map(row => goldNotifyBox(env, row.mac, kind)));
    }
    after = rows.results.at(-1).mac;
  }
}
