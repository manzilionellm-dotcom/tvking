"use client";

import Link from "next/link";
import ChannelLogo from "./ChannelLogo";
import { useFavorites } from "../lib/favorites";
import type { Channel } from "../lib/iptv-types";
import type { NowNextLite } from "../lib/view-types";

/*
 * One channel row in the browser grid: number + logo + name + (now playing),
 * with a favorite toggle. Pressing Enter opens the full-screen player. The "now"
 * line + progress come from the EPG when available (degrades gracefully).
 *
 * Favorite shortcut: press "f" / "F" while the card is focused (a stand-in for
 * the remote's long-press OK → context menu we wire up in the player overlay).
 */
function progress(nn?: NowNextLite): number {
  if (!nn || nn.stop <= nn.start) return 0;
  const p = (Date.now() - nn.start) / (nn.stop - nn.start);
  return Math.min(1, Math.max(0, p));
}

export default function ChannelCard({
  channel,
  nowNext,
}: {
  channel: Channel;
  nowNext?: NowNextLite;
}) {
  const { favoriteSet, toggle } = useFavorites();
  const fav = favoriteSet.has(channel.id);
  const pct = progress(nowNext);

  return (
    <Link
      href={`/watch?c=${encodeURIComponent(channel.id)}`}
      data-focusable
      onKeyDown={(e) => {
        if (e.key === "f" || e.key === "F") {
          e.preventDefault();
          toggle(channel.id);
        }
      }}
      className="card focusable group relative flex items-center gap-[0.9rem] rounded-[var(--radius)] bg-[var(--surface-1)] px-[0.9rem] py-[0.8rem]"
    >
      <span className="w-[2.2rem] shrink-0 text-right text-[1rem] font-bold tabular-nums text-[var(--text-disabled)]">
        {channel.number}
      </span>
      <ChannelLogo src={channel.logo} name={channel.name} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[1.15rem] font-semibold text-[var(--text-high)]">
          {channel.name}
        </span>
        {nowNext ? (
          <>
            <span className="block truncate text-[0.95rem] text-[var(--text-medium)]">
              {nowNext.title}
            </span>
            <span className="mt-[0.35rem] block h-[0.25rem] overflow-hidden rounded-full bg-white/12">
              <span
                className="block h-full rounded-full"
                style={{ width: `${pct * 100}%`, background: "var(--accent)" }}
              />
            </span>
          </>
        ) : (
          <span className="block truncate text-[0.9rem] text-[var(--text-disabled)]">
            {channel.group}
          </span>
        )}
      </span>
      {fav && (
        <span className="shrink-0 text-[1.1rem] text-[var(--accent-strong)]" aria-label="Favori">
          ★
        </span>
      )}
    </Link>
  );
}
