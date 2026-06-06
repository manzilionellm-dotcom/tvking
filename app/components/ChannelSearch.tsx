"use client";

import { useEffect, useRef, useState } from "react";
import ChannelCard from "./ChannelCard";
import type { Channel } from "../lib/iptv-types";
import type { NowNextMap } from "../lib/view-types";

/*
 * Channel search. Text entry on a remote is high-friction, so the field is a
 * real (focusable) input the TV's on-screen keyboard / voice dictation drives,
 * and results stream in as you type (debounced) against /api/channels?q=.
 * State is set only inside async callbacks; "loading" is derived from the query.
 */
interface Loaded {
  forTerm: string;
  channels: Channel[];
  nowNext: NowNextMap;
}

export default function ChannelSearch() {
  const [q, setQ] = useState("");
  const [data, setData] = useState<Loaded>({ forTerm: "", channels: [], nowNext: {} });
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const term = q.trim().toLowerCase();
  useEffect(() => {
    if (term.length < 2) return;
    let cancelled = false;
    const t = setTimeout(() => {
      fetch(`/api/channels?q=${encodeURIComponent(term)}`)
        .then((r) => r.json())
        .then((d) => {
          if (!cancelled)
            setData({ forTerm: term, channels: d.channels ?? [], nowNext: d.nowNext ?? {} });
        })
        .catch(() => {});
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [term]);

  const ready = term.length >= 2 && data.forTerm === term;
  const loading = term.length >= 2 && !ready;

  return (
    <>
      <input
        ref={inputRef}
        data-focusable
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Nom de chaîne…"
        className="focusable mb-[1.6rem] w-full max-w-[44rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[0.9rem] text-[1.25rem] text-[var(--text-high)] placeholder:text-[var(--text-disabled)]"
      />

      {loading && <p className="text-[1.05rem] text-[var(--text-medium)]">Recherche…</p>}

      {ready && data.channels.length === 0 && (
        <p className="text-[1.05rem] text-[var(--text-medium)]">Aucune chaîne pour « {q} ».</p>
      )}

      {ready && data.channels.length > 0 && (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(20rem,1fr))] gap-[0.7rem] pb-[4rem]">
          {data.channels.map((c) => (
            <ChannelCard key={c.id} channel={c} nowNext={data.nowNext[c.id]} />
          ))}
        </div>
      )}
    </>
  );
}
