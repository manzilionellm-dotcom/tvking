// Le panel déployé possède la page Analyses, mais la baseline 317 n'a pas
// encore son handler. On ajoute cette seule lecture sans remplacer son auth.
import { readInsights } from './insights.js';

export async function readNovatubePanelActor(request, env, ctx, original) {
  // /auth/me réutilise exactement JWT, session, rôle hydraté, origine CORS
  // et quotas du Worker actuellement déployé. Une clé appareil ne suffit pas.
  const gate = await original.fetch(new Request(new URL('/api/v1/auth/me', request.url), {
    method: 'GET', headers: request.headers,
  }), env, ctx);
  if (!gate.ok) return { error: gate };
  const headers = new Headers(gate.headers);
  headers.delete('Content-Length');
  headers.set('Cache-Control', 'no-store, private');
  headers.set('Content-Type', 'application/json; charset=utf-8');
  let user;
  try { user = (await gate.json())?.user; } catch (_) { user = null; }
  return { user, headers };
}

export async function handleNovatubePanelAdmin(request, env, ctx, original) {
  const path = new URL(request.url).pathname.split('/').filter(Boolean).join('/');
  if (path !== 'api/v1/insights' || request.method !== 'GET') return null;
  const actor = await readNovatubePanelActor(request, env, ctx, original);
  if (actor.error) return actor.error;
  const { user, headers } = actor;
  // Identique au garde de la route /insights dans les sources du panel.
  if (user?.role !== 'super_admin') {
    return Response.json({ error: 'forbidden', message: 'Owner only' }, { status: 403, headers });
  }
  return Response.json(await readInsights(env), { headers });
}
