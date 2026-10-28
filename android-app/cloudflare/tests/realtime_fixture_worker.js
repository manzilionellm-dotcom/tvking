// Entrée EXCLUSIVEMENT locale. wrangler.toml reste sur gold.js.
import gold from '../gold.js';
export { RealtimeHub } from '../gold.js';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
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
    if (url.pathname === '/__fixture/list.m3u') return new Response(
      `#EXTM3U\n#EXTINF:-1 tvg-id="realtime" group-title="Recette",Chaîne RT locale\n${url.origin}/__fixture/stream.ts\n`,
      { headers: { 'Content-Type': 'audio/x-mpegurl' } });
    return gold.fetch(request, env, ctx);
  },
};
