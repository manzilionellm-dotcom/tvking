// Entrée EXCLUSIVEMENT locale. wrangler.toml reste sur gold.js.
import gold from '../gold.js';
import { RealtimeHub as ApplicationHub } from '../gold.js';

export class RealtimeHub extends ApplicationHub {
  async fetch(request) {
    if (new URL(request.url).pathname === '/__fixture/close') {
      for (const socket of this.ctx.getWebSockets()) socket.close(1012, 'fixture outage');
      await this.publishPresence();
      return Response.json({ ok: true });
    }
    return super.fetch(request);
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === '/__fixture/socket-mode' && request.method === 'POST') {
      const { mac, blocked } = await request.json();
      await env.DB.prepare('INSERT INTO app_config(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value')
        .bind(`fixture.socket.${mac}`, blocked ? '1' : '0').run();
      if (blocked) await env.RT_HUB.get(env.RT_HUB.idFromName(mac)).fetch('https://hub/__fixture/close');
      return Response.json({ ok: true });
    }
    if (url.pathname === '/api/box/ws') {
      const flag = await env.DB.prepare('SELECT value FROM app_config WHERE key=?').bind(`fixture.socket.${url.searchParams.get('mac')}`).first();
      if (flag?.value === '1') return new Response('fixture outage', { status: 503 });
    }
    if (url.pathname === '/__fixture/info') return Response.json({ token: env.FIXTURE_TOKEN });
    if (url.pathname === '/__fixture/register' && request.method === 'POST') {
      const { mac, androidId } = await request.json();
      if (!/^MK(?::[A-F0-9]{2}){5}$/.test(mac)) return new Response('bad mac', { status: 400 });
      const now = Date.now();
      await env.DB.batch([
        env.DB.prepare(`INSERT OR IGNORE INTO devices(id,customer_id,mac,first_seen_at,last_seen_at,android_id)
          VALUES (?,'fixture-customer',?,?,?,?)`).bind(`fixture-${mac}`, mac, now, now, androidId),
        env.DB.prepare('INSERT OR IGNORE INTO trial_anchors(mac,android_id,started_at) VALUES (?,?,?)')
          .bind(mac, androidId, now - 30 * 86400_000),
      ]);
      return Response.json({ ok: true, id: `fixture-${mac}` });
    }
    if (['/__fixture/list.m3u','/__fixture/golden.m3u'].includes(url.pathname)) return new Response(
      `#EXTM3U\n#EXTINF:-1 tvg-id="realtime" group-title="Recette",${url.pathname.includes('golden')?'Chaîne Golden locale':'Chaîne RT locale'}\n${url.origin}/__fixture/stream.ts\n`,
      { headers: { 'Content-Type': 'audio/x-mpegurl' } });
    return gold.fetch(request, env, ctx);
  },
};
