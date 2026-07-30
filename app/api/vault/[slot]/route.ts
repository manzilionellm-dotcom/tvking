/*
 * Coffre aveugle — dépôt/retrait d'enveloppes chiffrées côté client.
 *
 * Le serveur ne déchiffre RIEN et ne journalise RIEN : il accepte une
 * enveloppe opaque de taille fixe sous un slot ID aveuglé, la restitue à qui
 * connaît ce slot ID, et l'efface sur demande. Les réponses sont volontairement
 * pauvres (ok / absent / invalide) — aucune quantité, aucune métadonnée.
 */

import { deleteSlot, getSlot, putSlot } from "../../../lib/vault";
import { serverVault } from "../../../lib/vaultStore";

/** Borne le corps AVANT parsing JSON : une enveloppe valide tient largement dedans. */
const MAX_BODY_BYTES = 32 * 1024;

export async function PUT(req: Request, ctx: RouteContext<"/api/vault/[slot]">) {
  const { slot } = await ctx.params;
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) {
    return Response.json({ error: "invalide" }, { status: 400 });
  }
  let body: unknown = null;
  try {
    body = JSON.parse(raw);
  } catch {
    // corps illisible → rejet uniforme ci-dessous
  }
  if (putSlot(serverVault(), slot, body) === "rejected") {
    return Response.json({ error: "invalide" }, { status: 400 });
  }
  return Response.json({ ok: true });
}

export async function GET(_req: Request, ctx: RouteContext<"/api/vault/[slot]">) {
  const { slot } = await ctx.params;
  const env = getSlot(serverVault(), slot);
  if (!env) return Response.json({ error: "absent" }, { status: 404 });
  return Response.json(env);
}

export async function DELETE(_req: Request, ctx: RouteContext<"/api/vault/[slot]">) {
  const { slot } = await ctx.params;
  deleteSlot(serverVault(), slot);
  // Idempotent : effacer un slot déjà vide répond pareil (pas d'oracle d'existence).
  return Response.json({ ok: true });
}
