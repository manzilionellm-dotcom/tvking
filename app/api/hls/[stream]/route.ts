/*
 * Relais HLS — manifeste d'un flux.
 *
 *   PUT    : dépose le manifeste d'indexation (rejeté si l'URI de clé n'est pas
 *            aveugle — le relais ne peut pas devenir une source de clé).
 *   GET    : rend la playlist M3U8 dynamique (text/vnd.apple.mpegurl), avec des
 *            URLs de segments pointant vers ce même relais.
 *   DELETE : retire le flux (droit à l'effacement).
 *
 * Le relais ne détient jamais la clé de contenu ; les segments restent chiffrés.
 */

import { buildMediaPlaylist } from "../../../lib/hls";
import { deleteStream, getManifest, putManifest, serverRelay } from "../../../lib/hlsStore";

const MAX_BODY_BYTES = 512 * 1024;

export async function PUT(req: Request, ctx: RouteContext<"/api/hls/[stream]">) {
  const { stream } = await ctx.params;
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) {
    return Response.json({ error: "invalide" }, { status: 400 });
  }
  let body: unknown = null;
  try {
    body = JSON.parse(raw);
  } catch {
    // corps illisible → rejet uniforme
  }
  if (putManifest(serverRelay(), stream, body) === "rejected") {
    return Response.json({ error: "invalide" }, { status: 400 });
  }
  return Response.json({ ok: true });
}

export async function GET(_req: Request, ctx: RouteContext<"/api/hls/[stream]">) {
  const { stream } = await ctx.params;
  const manifest = getManifest(serverRelay(), stream);
  if (!manifest) return Response.json({ error: "absent" }, { status: 404 });

  const playlist = buildMediaPlaylist(manifest, (slot) => `/api/hls/${stream}/seg/${slot}`);
  return new Response(playlist, {
    status: 200,
    headers: {
      "content-type": "application/vnd.apple.mpegurl",
      "cache-control": "no-store",
    },
  });
}

export async function DELETE(_req: Request, ctx: RouteContext<"/api/hls/[stream]">) {
  const { stream } = await ctx.params;
  deleteStream(serverRelay(), stream);
  return Response.json({ ok: true });
}
