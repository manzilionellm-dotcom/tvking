import { NextRequest } from "next/server";
import { loadSource } from "../../lib/source";
import { nowNext } from "../../lib/epg";
import type { NowNextLite } from "../../lib/view-types";

/*
 * now/next for a single channel, used by the player to refresh the info bar when
 * the user zaps. Reads from the in-process source cache, so it's cheap. Not
 * cached at the HTTP layer (the "now" changes minute to minute).
 */
export async function GET(req: NextRequest) {
  const id = req.nextUrl.searchParams.get("channel");
  if (!id) return Response.json({ error: "missing channel" }, { status: 400 });

  const { playlist, epg } = await loadSource();
  const channel = playlist.channels.find((c) => c.id === id);
  if (!channel) return Response.json({ error: "unknown channel" }, { status: 404 });

  const { current, next } = nowNext(epg, channel.epgId);
  const payload: { current: NowNextLite | null; nextTitle: string | null } = {
    current: current
      ? { title: current.title, start: current.start, stop: current.stop, nextTitle: next?.title }
      : null,
    nextTitle: next?.title ?? null,
  };
  return Response.json(payload);
}
