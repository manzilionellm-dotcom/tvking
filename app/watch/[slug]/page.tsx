import { notFound } from "next/navigation";
import Player from "../../components/Player";
import { loadSource } from "../../lib/source";
import { nowNext } from "../../lib/epg";
import type { NowNextLite } from "../../lib/view-types";

// Streams depend on the user's configured source — always render per request.
export const dynamic = "force-dynamic";

export default async function WatchPage({ params }: PageProps<"/watch/[slug]">) {
  // The dynamic segment carries the channel id (see ChannelCard links).
  const { slug } = await params;
  const { playlist, epg } = await loadSource();

  const channel = playlist.channels.find((c) => c.id === slug);
  if (!channel) notFound();

  // Zapping scope = the channel's own group (TiViMate-style), kept small enough
  // to pass to the client without shipping the whole catalog.
  const group = playlist.groups.find((g) => g.id === channel.group || g.name === channel.group);
  const channels = group?.channels ?? [channel];

  const { current, next } = nowNext(epg, channel.epgId);
  const initialNowNext: NowNextLite | null = current
    ? { title: current.title, start: current.start, stop: current.stop, nextTitle: next?.title }
    : null;

  return <Player channels={channels} startId={channel.id} initialNowNext={initialNowNext} />;
}
