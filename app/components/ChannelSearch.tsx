"use client";

import { useDeferredValue, useEffect, useRef, useState } from "react";
import ChannelCard from "./ChannelCard";
import { useSource, searchChannels, nowNextFor } from "../lib/client-source";
import { useT } from "../lib/i18n";

/*
 * Channel search over the loaded client source. Text entry on a remote is
 * high-friction, so the field is a real (focusable) input the TV's on-screen
 * keyboard / voice dictation drives; results filter as you type.
 */
export default function ChannelSearch() {
  const [q, setQ] = useState("");
  const { status } = useSource();
  const t = useT();
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // useDeferredValue : la frappe reste fluide, le calcul des résultats suit
  // sans bloquer l'input (utile sur une box TV avec de longues playlists).
  const deferredQ = useDeferredValue(q);
  const term = deferredQ.trim();
  const results = status === "ready" && term.length >= 2 ? searchChannels(term) : [];

  return (
    <>
      <input
        ref={inputRef}
        data-focusable
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder={t("search_placeholder")}
        className="focusable mb-[1.6rem] w-full max-w-[44rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[0.9rem] text-[1.25rem] text-[var(--text-high)] placeholder:text-[var(--text-disabled)]"
      />

      {status !== "ready" && (
        <p className="text-[1.05rem] text-[var(--text-medium)]">{t("loading_channels")}</p>
      )}

      {status === "ready" && term.length >= 2 && results.length === 0 && (
        <p className="text-[1.05rem] text-[var(--text-medium)]">{t("search_no_results", { q })}</p>
      )}

      {results.length > 0 && (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(20rem,1fr))] gap-[0.7rem] pb-[4rem]">
          {results.map((c) => (
            <ChannelCard key={c.id} channel={c} nowNext={nowNextFor(c.id) ?? undefined} />
          ))}
        </div>
      )}
    </>
  );
}
