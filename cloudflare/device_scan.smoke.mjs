// Scan MAC : le panel DIT ce qui cloche (licence, playlist, version, journaux).
import { diagnoseDevice } from './api_v1.js';

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

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
