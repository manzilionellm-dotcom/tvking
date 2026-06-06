"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import ChannelCard from "./ChannelCard";
import { useFavorites } from "../lib/favorites";
import type { Channel } from "../lib/iptv-types";
import type { NowNextMap } from "../lib/view-types";

/*
 * Favorites live in localStorage (per device); we resolve those ids to channel
 * details via /api/channels so we don't ship the whole catalog to the client.
 * State is only set inside the async callback (loading is derived) to keep the
 * effect pure.
 */
interface Loaded {
  forKey: string;
  channels: Channel[];
  nowNext: NowNextMap;
}

export default function FavoritesList() {
  const { favorites } = useFavorites();
  const [data, setData] = useState<Loaded>({ forKey: "", channels: [], nowNext: {} });

  const key = favorites.join(",");
  useEffect(() => {
    if (!key) return;
    let cancelled = false;
    fetch(`/api/channels?ids=${encodeURIComponent(key)}`)
      .then((r) => r.json())
      .then((d) => {
        if (!cancelled) setData({ forKey: key, channels: d.channels ?? [], nowNext: d.nowNext ?? {} });
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [key]);

  if (favorites.length === 0) {
    return (
      <div className="max-w-[44rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.4rem]">
        <p className="text-[1.15rem] text-[var(--text-high)]">Aucun favori pour l’instant.</p>
        <p className="mt-[0.5rem] text-[1.05rem] text-[var(--text-medium)]">
          Sur une chaîne (Accueil ou pendant la lecture), appuyez sur{" "}
          <kbd className="rounded bg-[var(--surface-3)] px-[0.4rem]">F</kbd> pour l’ajouter.
        </p>
        <Link
          href="/"
          data-focusable
          className="focusable mt-[1rem] inline-block rounded-[var(--radius)] px-[1.2rem] py-[0.7rem] text-[1.05rem] font-bold text-black"
          style={{ background: "var(--accent-grad)" }}
        >
          Parcourir les chaînes
        </Link>
      </div>
    );
  }

  if (data.forKey !== key) {
    return <p className="text-[1.1rem] text-[var(--text-medium)]">Chargement…</p>;
  }

  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(20rem,1fr))] gap-[0.7rem] pb-[4rem]">
      {data.channels.map((c) => (
        <ChannelCard key={c.id} channel={c} nowNext={data.nowNext[c.id]} />
      ))}
    </div>
  );
}
