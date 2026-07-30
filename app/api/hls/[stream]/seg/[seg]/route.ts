/*
 * Relais HLS — segments média chiffrés (opaques).
 *
 *   PUT    : dépose les octets AES-128 d'un segment (bruts, application/octet-stream).
 *   GET    : restitue ces octets tels quels — le relais ne les déchiffre jamais.
 *   DELETE : retire le segment.
 *
 * Le segment est chiffré côté client ; ce module ne fait que du transport
 * d'octets opaques. Le paramètre [stream] n'est là que pour la forme d'URL
 * (les slots de segment sont déjà globalement aveuglés et uniques).
 */

import { deleteSegment, getSegment, MAX_SEGMENT_BYTES, putSegment, serverRelay } from "../../../../../lib/hlsStore";

export async function PUT(req: Request, ctx: RouteContext<"/api/hls/[stream]/seg/[seg]">) {
  const { seg } = await ctx.params;
  const buf = new Uint8Array(await req.arrayBuffer());
  if (buf.length > MAX_SEGMENT_BYTES) {
    return Response.json({ error: "trop gros" }, { status: 413 });
  }
  if (putSegment(serverRelay(), seg, buf) === "rejected") {
    return Response.json({ error: "invalide" }, { status: 400 });
  }
  return Response.json({ ok: true });
}

export async function GET(_req: Request, ctx: RouteContext<"/api/hls/[stream]/seg/[seg]">) {
  const { seg } = await ctx.params;
  const bytes = getSegment(serverRelay(), seg);
  if (!bytes) return Response.json({ error: "absent" }, { status: 404 });
  return new Response(bytes as BodyInit, {
    status: 200,
    headers: {
      "content-type": "application/octet-stream",
      "cache-control": "no-store",
    },
  });
}

export async function DELETE(_req: Request, ctx: RouteContext<"/api/hls/[stream]/seg/[seg]">) {
  const { seg } = await ctx.params;
  deleteSegment(serverRelay(), seg);
  return Response.json({ ok: true });
}
