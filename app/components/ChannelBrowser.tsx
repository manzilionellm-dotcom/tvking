"use client";

import { useMemo, useState } from "react";
import ChannelCard from "./ChannelCard";
import { useFavorites, useRecents } from "../lib/favorites";
import { useT } from "../lib/i18n";
import type { Channel, ChannelGroup } from "../lib/iptv-types";
import type { NowNextMap } from "../lib/view-types";

/*
 * The home browser, modelled on TiViMate: a column of groups on the left, a grid
 * of channels on the right. Two virtual groups are layered in client-side from
 * localStorage — "Favoris" and "Récemment vues" — so the user's own selections
 * lead, per the engagement research (recents + favorites = the investment that
 * brings people back). The active group switches when a group gains focus, so a
 * single D-pad sweep reveals everything.
 */

const MAX_PER_GROUP = 600; // keep the DOM sane on huge "Undefined" buckets

export default function ChannelBrowser({
  groups,
  nowNext,
}: {
  groups: ChannelGroup[];
  nowNext: NowNextMap;
}) {
  const { favorites } = useFavorites();
  const recents = useRecents();
  const t = useT();

  const byId = useMemo(() => {
    const m = new Map<string, Channel>();
    for (const g of groups) for (const c of g.channels) m.set(c.id, c);
    return m;
  }, [groups]);

  const favChannels = favorites.map((id) => byId.get(id)).filter(Boolean) as Channel[];
  const recentChannels = recents.map((id) => byId.get(id)).filter(Boolean) as Channel[];

  // Build the full group list: virtual groups first, then the real ones.
  const allGroups: ChannelGroup[] = useMemo(() => {
    const list: ChannelGroup[] = [];
    if (favChannels.length) list.push({ id: "@fav", name: `★ ${t("nav_favorites")}`, channels: favChannels });
    if (recentChannels.length)
      list.push({ id: "@recent", name: t("recently_viewed"), channels: recentChannels });
    return [...list, ...groups];
    // favChannels/recentChannels derive from favorites/recents ; t rerend les
    // noms des groupes virtuels quand la langue change :
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groups, favorites, recents, t]);

  const [activeId, setActiveId] = useState<string>(groups[0]?.id ?? "");
  const active = allGroups.find((g) => g.id === activeId) ?? allGroups[0];
  const channels = active?.channels.slice(0, MAX_PER_GROUP) ?? [];

  return (
    <div className="flex h-screen gap-[1.5rem] pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      {/* Group column */}
      <aside className="no-scrollbar flex w-[16rem] shrink-0 flex-col gap-[0.3rem] overflow-y-auto">
        <h2 className="mb-[0.6rem] px-[0.6rem] text-[0.85rem] font-bold uppercase tracking-[0.25em] text-[var(--text-disabled)]">
          {t("categories")}
        </h2>
        {allGroups.map((g) => {
          const sel = g.id === active?.id;
          return (
            <button
              key={g.id}
              data-focusable
              onFocus={() => setActiveId(g.id)}
              onClick={() => setActiveId(g.id)}
              className={`focusable flex items-center justify-between gap-[0.5rem] rounded-[var(--radius)] px-[0.8rem] py-[0.65rem] text-left text-[1.05rem] font-semibold ${
                sel ? "text-[var(--accent-strong)]" : "text-[var(--text-medium)]"
              }`}
              style={sel ? { background: "rgba(61,169,252,0.12)" } : undefined}
            >
              <span className="truncate">{g.name}</span>
              <span className="shrink-0 text-[0.85rem] tabular-nums text-[var(--text-disabled)]">
                {g.channels.length}
              </span>
            </button>
          );
        })}
      </aside>

      {/* Channel grid */}
      <section className="no-scrollbar flex-1 overflow-y-auto">
        <div className="mb-[1rem] flex items-baseline gap-[0.8rem]">
          <h1 className="font-display text-[2.2rem] font-extrabold text-[var(--text-high)]">
            {active?.name ?? t("channels_title")}
          </h1>
          <span className="text-[1rem] text-[var(--text-medium)]">
            {active?.channels.length ?? 0} {t("channels")}
          </span>
        </div>

        {channels.length === 0 ? (
          <p className="text-[1.1rem] text-[var(--text-medium)]">{t("guide_no_channels")}</p>
        ) : (
          <div className="grid grid-cols-[repeat(auto-fill,minmax(20rem,1fr))] gap-[0.7rem] pb-[4rem]">
            {channels.map((c) => (
              <ChannelCard key={c.id} channel={c} nowNext={nowNext[c.id]} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
