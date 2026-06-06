import { NextRequest } from "next/server";
import { loadSource } from "../../lib/source";
import { nowNext } from "../../lib/epg";
import type { Channel } from "../../lib/iptv-types";
import type { NowNextMap } from "../../lib/view-types";

/*
 * Channel lookup used by the client-only screens (Favoris, Recherche), so they
 * can resolve localStorage ids / query strings to channel details without us
 * shipping the whole catalog to the browser.
 *   ?ids=a,b,c  → those channels, in that order
 *   ?q=france   → name search (capped)
 * Each response includes a now/next map for the returned channels.
 */
const SEARCH_LIMIT = 80;

export async function GET(req: NextRequest) {
  const { playlist, epg } = await loadSource();
  const sp = req.nextUrl.searchParams;
  const idsParam = sp.get("ids");
  const q = sp.get("q")?.trim().toLowerCase();

  let result: Channel[] = [];

  if (idsParam !== null) {
    const ids = idsParam.split(",").filter(Boolean);
    const byId = new Map(playlist.channels.map((c) => [c.id, c]));
    result = ids.map((id) => byId.get(id)).filter(Boolean) as Channel[];
  } else if (q) {
    result = playlist.channels.filter((c) => c.name.toLowerCase().includes(q)).slice(0, SEARCH_LIMIT);
  }

  const now: NowNextMap = {};
  for (const c of result) {
    if (!c.epgId) continue;
    const { current, next } = nowNext(epg, c.epgId);
    if (current)
      now[c.id] = { title: current.title, start: current.start, stop: current.stop, nextTitle: next?.title };
  }

  return Response.json({ channels: result, nowNext: now });
}
