/*
 * Panel maître — vue AVEUGLE du coffre.
 *
 * Data masking strict : la réponse ne contient que des états binaires
 * présence/absence (`Presence`), calculés via l'unique goulot `presenceOf`.
 * Jamais de compte, de taille, de date ou de liste de slots — le maître ne
 * peut interroger que des slot IDs qu'il possède déjà.
 *
 * Auth : `Authorization: Bearer <ADMIN_SECRET>` (le secret posé par le
 * workflow « Set admin password »). Comparaison en temps constant ;
 * fail-closed si le secret n'est pas configuré.
 */

import { serverRelay, streamPresence } from "../../../lib/hlsStore";
import { slotPresence, vaultPresence } from "../../../lib/vault";
import { serverVault } from "../../../lib/vaultStore";
import { type Presence, isSlotId, timingSafeEqual } from "../../../lib/zk";

/** Nombre maximal de slots interrogeables par requête. */
const MAX_QUERIES = 16;

export async function POST(req: Request) {
  const secret = process.env.ADMIN_SECRET;
  if (!secret) {
    return Response.json({ error: "panel non configuré" }, { status: 503 });
  }
  const auth = req.headers.get("authorization") ?? "";
  const given = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!(await timingSafeEqual(given, secret))) {
    return Response.json({ error: "refusé" }, { status: 401 });
  }

  let body: unknown = null;
  try {
    body = await req.json();
  } catch {
    // corps absent/illisible → interrogation globale seule
  }
  const asked =
    typeof body === "object" && body !== null && Array.isArray((body as Record<string, unknown>).slotIds)
      ? ((body as Record<string, unknown>).slotIds as unknown[]).slice(0, MAX_QUERIES)
      : [];

  const vault = serverVault();
  const relay = serverRelay();
  const slots: Record<string, Presence> = {};
  const streams: Record<string, Presence> = {};
  for (const id of asked) {
    if (!isSlotId(id)) continue;
    // Un même slot aveuglé peut désigner un dépôt (coffre) et/ou un flux (HLS) ;
    // on n'expose que présent/absent pour chacun, jamais un compte.
    slots[id] = slotPresence(vault, id);
    streams[id] = streamPresence(relay, id);
  }

  return Response.json({ vault: vaultPresence(vault), slots, streams });
}
