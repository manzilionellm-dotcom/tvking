"use client";

import Link from "next/link";
import { useMemo } from "react";
import GuideGrid from "../components/GuideGrid";
import type { GuideRow } from "../components/GuideGrid";
import { useSource } from "../lib/client-source";
import { useNow } from "../lib/use-now";

const GUIDE_MAX_CHANNELS = 150;
const WINDOW_HOURS = 4;

export default function GuidePage() {
  const { status, playlist, epg } = useSource();
  const now = useNow();

  const { rows, windowStart, windowEnd } = useMemo(() => {
    const half = 30 * 60_000;
    const ws = Math.floor(now / half) * half;
    const we = ws + WINDOW_HOURS * 3600_000;
    const channels = playlist.channels.slice(0, GUIDE_MAX_CHANNELS);
    const r: GuideRow[] = channels.map((ch) => ({
      id: ch.id,
      name: ch.name,
      number: ch.number,
      logo: ch.logo,
      programmes: (epg.get(ch.epgId) ?? [])
        .filter((p) => p.stop > ws && p.start < we)
        .map((p) => ({ start: p.start, stop: p.stop, title: p.title })),
    }));
    return { rows: r, windowStart: ws, windowEnd: we };
  }, [playlist, epg, now]);

  const hasEpg = epg.size > 0;

  return (
    <div className="min-h-screen pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <div className="mb-[1.2rem] flex items-baseline gap-[0.9rem]">
        <h1 className="font-display text-[2.4rem] font-extrabold text-[var(--text-high)]">Guide TV</h1>
        <span className="text-[1rem] text-[var(--text-medium)]">{playlist.total} chaînes</span>
      </div>

      {status === "loading" || status === "idle" ? (
        <p className="text-[1.1rem] text-[var(--text-medium)]">Chargement…</p>
      ) : playlist.total === 0 ? (
        <p className="text-[1.1rem] text-[var(--text-medium)]">
          Aucune chaîne. Configurez votre source dans{" "}
          <Link href="/settings" className="text-[var(--accent)] underline">Réglages</Link>.
        </p>
      ) : !hasEpg ? (
        <div className="max-w-[44rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.4rem]">
          <p className="text-[1.15rem] text-[var(--text-high)]">Pas de guide (EPG) chargé.</p>
          <p className="mt-[0.5rem] text-[1.05rem] text-[var(--text-medium)]">
            Ajoutez l’URL XMLTV de votre fournisseur dans{" "}
            <Link href="/settings" className="text-[var(--accent)] underline">Réglages</Link>{" "}
            pour afficher les programmes.
          </p>
        </div>
      ) : (
        <GuideGrid rows={rows} windowStart={windowStart} windowEnd={windowEnd} now={now} />
      )}
    </div>
  );
}
