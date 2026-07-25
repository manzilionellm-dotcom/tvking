"use client";

import { useCallback, useState } from "react";
import { allItems } from "../lib/data";
import { searchItems } from "../lib/search";
import MediaCard from "./MediaCard";

/*
 * TV search. The research is clear (docs/RESEARCH-TV-UX.md §5): browse comes
 * first and remote text entry is painful — so the entry point stays the
 * suggestion chips, and the on-screen keyboard is a D-pad grid right below,
 * never a hidden system keyboard the remote cannot drive.
 *
 * Everything is local and instant (no network round-trip), matching is
 * accent-insensitive (lib/search.ts), and the result grid reuses the standard
 * card so focus behaves exactly as everywhere else.
 */

const SUGGESTIONS = [
  "Football",
  "Basket",
  "Tennis",
  "F1",
  "Leadership",
  "Yoga",
  "Nutrition",
  "HIIT",
];

/* Alphabet grid: short rows keep every key within a few D-pad presses. */
const ROWS = ["ABCDEFG", "HIJKLMN", "OPQRSTU", "VWXYZ", "0123456789"];

export default function SearchClient() {
  const [query, setQuery] = useState("");
  const results = query.trim() ? searchItems(allItems, query) : [];

  const push = useCallback((c: string) => setQuery((q) => (q + c).slice(0, 40)), []);
  const back = useCallback(() => setQuery((q) => q.slice(0, -1)), []);
  const clear = useCallback(() => setQuery(""), []);

  return (
    <>
      {/* Current query — big enough to read from the sofa. */}
      <div
        className="mb-[1.4rem] flex min-h-[4rem] max-w-[52rem] items-center gap-[0.8rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[0.9rem]"
        role="status"
        aria-live="polite"
      >
        <svg
          className="h-[1.5rem] w-[1.5rem] shrink-0 text-[var(--text-medium)]"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3-3" strokeLinecap="round" />
        </svg>
        <span
          className={`text-[1.5rem] ${query ? "font-semibold text-[var(--text-high)]" : "text-[var(--text-medium)]"}`}
        >
          {query || "Choisissez une suggestion ou saisissez un titre…"}
        </span>
      </div>

      {/* Suggestions first — one press, no typing. */}
      <div className="mb-[1.6rem] flex flex-wrap gap-[0.8rem]">
        {SUGGESTIONS.map((s) => (
          <button
            key={s}
            type="button"
            data-focusable
            data-focus-default={s === SUGGESTIONS[0] ? "" : undefined}
            onClick={() => setQuery(s)}
            className="focusable rounded-full bg-[var(--surface-2)] px-[1.4rem] py-[0.7rem] text-[1.15rem] font-semibold text-[var(--text-high)]"
          >
            {s}
          </button>
        ))}
      </div>

      {/* D-pad keyboard. */}
      <div className="mb-[2rem] flex flex-col gap-[0.5rem]">
        {ROWS.map((row) => (
          <div key={row} className="flex flex-wrap gap-[0.5rem]">
            {[...row].map((c) => (
              <button
                key={c}
                type="button"
                data-focusable
                onClick={() => push(c)}
                aria-label={`Lettre ${c}`}
                className="focusable h-[2.8rem] w-[2.8rem] rounded-[var(--radius)] bg-[var(--surface-2)] text-[1.2rem] font-bold text-[var(--text-high)]"
              >
                {c}
              </button>
            ))}
          </div>
        ))}
        <div className="mt-[0.3rem] flex gap-[0.5rem]">
          <button
            type="button"
            data-focusable
            onClick={() => push(" ")}
            className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[2.4rem] py-[0.6rem] text-[1.1rem] font-semibold text-[var(--text-high)]"
          >
            Espace
          </button>
          <button
            type="button"
            data-focusable
            onClick={back}
            className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.4rem] py-[0.6rem] text-[1.1rem] font-semibold text-[var(--text-high)]"
          >
            ⌫ Effacer
          </button>
          <button
            type="button"
            data-focusable
            onClick={clear}
            className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.4rem] py-[0.6rem] text-[1.1rem] font-semibold text-[var(--text-medium)]"
          >
            Tout effacer
          </button>
        </div>
      </div>

      {/* Results. */}
      {query.trim() && (
        <section>
          <h2 className="mb-[1rem] text-[1.5rem] font-bold text-[var(--text-high)]">
            {results.length > 0
              ? `${results.length} résultat${results.length > 1 ? "s" : ""} pour « ${query} »`
              : `Aucun résultat pour « ${query} »`}
          </h2>
          {results.length > 0 ? (
            <div className="flex flex-wrap gap-[1.2rem] pb-[1rem]">
              {results.map((item) => (
                <MediaCard key={item.id} item={item} />
              ))}
            </div>
          ) : (
            <p className="max-w-[52ch] text-[1.25rem] text-[var(--text-medium)]">
              Essayez une discipline (Football, Tennis…), un thème (Nutrition,
              Leadership…) ou le nom d&apos;un intervenant.
            </p>
          )}
        </section>
      )}
    </>
  );
}
