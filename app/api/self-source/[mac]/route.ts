/*
 * Relais serveur « Activer ma liste » → panel Zuno.
 *
 * Pourquoi un relais : l'API du panel (/api/self-source/:mac) répond bien à la
 * pré-vérification CORS, mais ses RÉPONSES n'ont pas l'en-tête
 * Access-Control-Allow-Origin → un navigateur sur ce site ne peut pas les
 * lire (« Failed to fetch », constaté le 27/09/2026). Le panel ne pouvant pas
 * être redéployé d'ici, le site parle au panel CÔTÉ SERVEUR (pas de CORS).
 *
 * Garde-fous : MAC au format exact du panel, 3 méthodes seulement, corps
 * limité à 4 Ko, aucune réponse mise en cache, rien n'est stocké ici. Le
 * panel reste seul juge (licence obligatoire, plafond, anti-abus).
 */
import { PANEL_API } from "../../../lib/self-source";

const MAC_RX = /^MK(?::[0-9A-F]{2}){5}$/;
const MAX_BODY = 4096;

type Ctx = { params: Promise<{ mac: string }> };

async function forward(request: Request, ctx: Ctx, method: "GET" | "POST" | "DELETE") {
  const mac = decodeURIComponent((await ctx.params).mac).toUpperCase();
  if (!MAC_RX.test(mac)) {
    return Response.json({ ok: false, error: "invalid mac" }, { status: 400 });
  }
  const url = new URL(`${PANEL_API}/api/self-source/${mac}`);
  const id = new URL(request.url).searchParams.get("id");
  if (method === "DELETE" && id) url.searchParams.set("id", id.slice(0, 128));

  let body: string | undefined;
  if (method === "POST") {
    body = await request.text();
    if (body.length > MAX_BODY) {
      return Response.json({ ok: false, error: "body too large" }, { status: 413 });
    }
  }

  try {
    const upstream = await fetch(url, {
      method,
      headers: body ? { "Content-Type": "application/json" } : undefined,
      body,
      cache: "no-store",
      signal: AbortSignal.timeout(10_000),
    });
    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
    });
  } catch {
    return Response.json({ ok: false, error: "panel_unreachable" }, { status: 502 });
  }
}

export function GET(request: Request, ctx: Ctx) {
  return forward(request, ctx, "GET");
}
export function POST(request: Request, ctx: Ctx) {
  return forward(request, ctx, "POST");
}
export function DELETE(request: Request, ctx: Ctx) {
  return forward(request, ctx, "DELETE");
}
