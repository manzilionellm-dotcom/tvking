"use client";

import Link from "next/link";
import ChannelLogo from "./ChannelLogo";
import { useFavorites } from "../lib/favorites";
import type { Channel } from "../lib/iptv-types";
import type { NowNextLite } from "../lib/view-types";

/*
 * Carte de chaîne pour les rails de l'accueil (lean-back). Format paysage à
 * dimensions FIXES (aucune secousse de layout, le logo lazy ne « pop » pas) :
 * média avec logo centré + nom + sous-ligne (programme en cours) + barre de
 * progression. OK ouvre le lecteur ; « F » bascule le favori (comme la grille).
 */
function progress(nn?: NowNextLite): number {
  if (!nn || nn.stop <= nn.start) return 0;
  return Math.min(1, Math.max(0, (Date.now() - nn.start) / (nn.stop - nn.start)));
}

export default function RailCard({
  channel,
  nowNext,
  badge,
  subtitle,
}: {
  channel: Channel;
  nowNext?: NowNextLite;
  badge?: string; // pastille (ex. heure « 20:45 »)
  subtitle?: string; // remplace la ligne « en cours » (ex. titre d'événement)
}) {
  const { favoriteSet, toggle } = useFavorites();
  const fav = favoriteSet.has(channel.id);
  const pct = progress(nowNext);
  const sub = subtitle ?? nowNext?.title ?? channel.group;

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
      className="card focusable group relative flex h-[12.5rem] w-[14rem] shrink-0 flex-col gap-[0.5rem] rounded-[var(--radius)] bg-[var(--surface-1)] p-[0.7rem]"
    >
      <div className="relative flex h-[7rem] items-center justify-center overflow-hidden rounded-[0.6rem] bg-[var(--surface-2)]">
        <ChannelLogo src={channel.logo} name={channel.name} size="4.4rem" />
        {badge && (
          <span className="absolute start-[0.4rem] top-[0.4rem] rounded-full bg-black/65 px-[0.55rem] py-[0.15rem] text-[0.78rem] font-bold tabular-nums text-white">
            {badge}
          </span>
        )}
        {fav && (
          <span className="absolute end-[0.4rem] top-[0.4rem] text-[1rem] text-[var(--accent-strong)]" aria-label="Favori">
            ★
          </span>
        )}
      </div>
      <div className="min-w-0 flex-1">
        <span className="block truncate text-[1.05rem] font-semibold text-[var(--text-high)]">{channel.name}</span>
        <span className="block truncate text-[0.9rem] text-[var(--text-medium)]">{sub}</span>
      </div>
      {nowNext && (
        <span className="block h-[0.25rem] overflow-hidden rounded-full bg-white/12">
          <span className="block h-full rounded-full" style={{ width: `${pct * 100}%`, background: "var(--accent)" }} />
        </span>
      )}
    </Link>
  );
}
