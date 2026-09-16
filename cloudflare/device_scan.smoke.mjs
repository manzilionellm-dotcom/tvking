// Scan MAC : le panel DIT ce qui cloche (licence, playlist, version, journaux).
import { diagnoseDevice, playlistTarget, interpretProbe, safeHost } from './api_v1.js';

let pass = 0;
let fail = 0;
const ok = (c, m) => {
  if (c) { pass++; console.log('PASS', m); }
  else { fail++; console.log('FAIL', m); }
};

const now = Date.UTC(2026, 8, 16, 12, 0, 0);

{
  const r = diagnoseDevice({
    license: { status: 'active', expires_at: now + 86400000 },
    sources: [{ type: 'm3u' }],
    localSources: [{ type: 'm3u' }],
    presence: { online: true, last_seen: now - 1000 },
    device: { block_status: 'active' },
    errors: [],
  }, now);
  ok(r.verdict === 'ok', '1 tout va → ok');
}

{
  const r = diagnoseDevice({
    license: null,
    sources: [],
    localSources: [],
    device: { block_status: 'active' },
    errors: [],
  }, now);
  ok(r.verdict === 'critique', '2 pas d’abo + pas de liste → critique');
  ok(r.findings.some((f) => f.code === 'no_license'), '2 no_license');
  ok(r.findings.some((f) => f.code === 'no_playlist'), '2 no_playlist');
}

{
  const r = diagnoseDevice({
    license: { status: 'active', expires_at: now + 86400000 },
    sources: [{ type: 'm3u', m3u_url: 'http://x/list.m3u' }],
    localSources: [],
    presence: { last_seen: now - 60_000 },
    device: { block_status: 'active' },
    errors: [],
  }, now);
  ok(r.findings.some((f) => f.code === 'playlist_not_loaded'),
    '3 playlist panel pas chargée sur l’appareil');
}

{
  const r = diagnoseDevice({
    license: { status: 'active', expires_at: now + 86400000 },
    sources: [{ type: 'm3u' }],
    localSources: [{ type: 'm3u' }],
    device: { block_status: 'banned' },
    errors: [{ level: 'error', tag: 'player', message: 'image noire FLAG_SECURE SurfaceView' }],
  }, now);
  ok(r.verdict === 'critique', '4 banni → critique');
  ok(r.findings.some((f) => f.code === 'black_video'), '4 image noire détectée');
}

{
  const r = diagnoseDevice({
    license: { status: 'expired', expires_at: now - 86400000 },
    sources: [{ type: 'm3u' }],
    localSources: [{ type: 'm3u' }],
    errors: [{ message: 'HTTP 403 Forbidden' }],
  }, now);
  ok(r.findings.some((f) => f.code === 'expired'), '5 abo expiré');
  ok(r.findings.some((f) => f.code === 'iptv_denied'), '5 403 fournisseur');
}

{
  // expires_at = 16/09 00:00, now = 16/09 12:00 → le 16 EST encore payé.
  const r = diagnoseDevice({
    license: { status: 'active', expires_at: Date.UTC(2026, 8, 16, 0, 0, 0) },
    sources: [{ type: 'm3u' }],
    localSources: [{ type: 'm3u' }],
    presence: { online: true, last_seen: now - 1000 },
    device: { block_status: 'active' },
    errors: [],
  }, now);
  ok(r.verdict === 'ok', '6 dernier jour payé → encore OK');
  ok(!r.findings.some((f) => f.code === 'expired'), '6 pas expired le jour même');
}

{
  const t = playlistTarget({ type: 'm3u', m3u_url: 'exemple.com/list.m3u' });
  ok(!!t && t.url.startsWith('http://exemple.com/'), '7 m3u sans schéma → http://');
  ok(safeHost('http://u:p@cdn.tv/x.m3u') === 'cdn.tv', '7 hôte sans user:pass');
}

{
  const xt = playlistTarget({
    type: 'xtream', server_url: 'http://host.tv:8080', username: 'bob', password: 's3cr',
  });
  ok(!!xt && xt.kind === 'xtream' && xt.url.includes('player_api.php'), '8 cible xtream');
}

{
  const live = interpretProbe('m3u', 200, '#EXTM3U\n#EXTINF:-1,TF1\nhttp://x/1\n#EXTINF:-1,M6\nhttp://x/2\n');
  ok(live.ok && live.channels === 2, '9 m3u 2 chaînes → ok');
  const denied = interpretProbe('m3u', 403, 'Forbidden');
  ok(!denied.ok && denied.code === 'denied', '9 m3u 403 → denied');
  const xtOk = interpretProbe('xtream', 200, JSON.stringify({ user_info: { auth: 1, status: 'Active' } }));
  ok(xtOk.ok, '9 xtream auth=1 → ok');
  const xtNo = interpretProbe('xtream', 200, JSON.stringify({ user_info: { auth: 0, status: 'Expired' } }));
  ok(!xtNo.ok && xtNo.code === 'denied', '9 xtream expiré → denied');
}

{
  const r = diagnoseDevice({
    license: { status: 'active', expires_at: now + 86400000 },
    sources: [{ type: 'm3u', m3u_url: 'http://dead.example/list.m3u' }],
    localSources: [{ type: 'm3u' }],
    presence: { online: true, last_seen: now - 1000 },
    device: { block_status: 'active' },
    errors: [],
    probes: [{ ok: false, status: 404, host: 'dead.example', code: 'dead', detail: 'HTTP 404' }],
  }, now);
  ok(r.verdict === 'critique', '10 playlist morte → critique');
  ok(r.findings.some((f) => f.code === 'playlist_dead'), '10 playlist_dead');
  ok(r.findings.some((f) => f.action), '10 constat grave a une action');
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
