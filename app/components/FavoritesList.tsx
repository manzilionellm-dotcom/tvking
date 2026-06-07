"use client";

import Link from "next/link";
import ChannelCard from "./ChannelCard";
import { useFavorites } from "../lib/favorites";
import { useSource, channelsByIds, nowNextFor } from "../lib/client-source";
import { useT } from "../lib/i18n";
import type { Channel } from "../lib/iptv-types";

/*
 * Favorites live in localStorage (per device). We resolve those ids to channel
 * details from the loaded client source — no server round-trip.
 */
export default function FavoritesList() {
  const { favorites } = useFavorites();
  const { status } = useSource();
  const t = useT();

  if (status === "loading" || status === "idle") {
    return <p className="text-[1.1rem] text-[var(--text-medium)]">{t("loading")}</p>;
  }

  if (favorites.length === 0) {
    return (
      <div className="max-w-[44rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.4rem]">
        <p className="text-[1.15rem] text-[var(--text-high)]">{t("favorites_empty_title")}</p>
        <p className="mt-[0.5rem] text-[1.05rem] text-[var(--text-medium)]">
          {t("fav_body_pre")}{" "}
          <kbd className="rounded bg-[var(--surface-3)] px-[0.4rem]">F</kbd> {t("fav_body_post")}
        </p>
        <Link
          href="/"
          data-focusable
          className="focusable mt-[1rem] inline-block rounded-[var(--radius)] px-[1.2rem] py-[0.7rem] text-[1.05rem] font-bold text-black"
          style={{ background: "var(--accent-grad)" }}
        >
          {t("browse_channels")}
        </Link>
      </div>
    );
  }

  const channels = channelsByIds(favorites) as Channel[];

  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(20rem,1fr))] gap-[0.7rem] pb-[4rem]">
      {channels.map((c) => (
        <ChannelCard key={c.id} channel={c} nowNext={nowNextFor(c.id) ?? undefined} />
      ))}
    </div>
  );
}
