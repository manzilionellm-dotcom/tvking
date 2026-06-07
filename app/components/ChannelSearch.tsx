"use client";

import { useDeferredValue, useState } from "react";
import ChannelCard from "./ChannelCard";
import { useKeyboard } from "./Keyboard";
import { useSource, searchChannels, nowNextFor } from "../lib/client-source";
import { useT } from "../lib/i18n";

/*
 * Channel search over the loaded client source. La saisie au clavier système
 * d'une TV est pénible : on ouvre plutôt le clavier à l'écran INTÉGRÉ (piloté à
 * la télécommande). On valide la requête à « OK », puis les résultats filtrent.
 */
export default function ChannelSearch() {
  const [q, setQ] = useState("");
  const { status } = useSource();
  const t = useT();
  const kb = useKeyboard();

  // useDeferredValue : le calcul des résultats suit sans bloquer le rendu
  // (utile sur une box TV avec de longues playlists).
  const deferredQ = useDeferredValue(q);
  const term = deferredQ.trim();
  const results = status === "ready" && term.length >= 2 ? searchChannels(term) : [];

  return (
    <>
      <button
        type="button"
        data-focusable
        onClick={() => kb.open({ title: t("search_placeholder"), value: q, onCommit: setQ })}
        className="focusable mb-[1.6rem] flex w-full max-w-[44rem] items-center rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[0.9rem] text-left text-[1.25rem] text-[var(--text-high)]"
      >
        {q || <span className="text-[var(--text-disabled)]">{t("search_placeholder")}</span>}
      </button>

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
