"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { LevelBadge, LiveBadge } from "../components/Badge";
import { allItems } from "../lib/data";

/*
 * On TV, search stays browse-first and minimal: text entry on a remote is
 * high-friction, so we surface quick category chips rather than a keyboard.
 * On a phone the keyboard is free — so the pocket UI gets a real search field
 * with instant, accent-insensitive results. The chips fill the query on tap.
 */
const SUGGESTIONS = ["Football", "Basket", "Tennis", "F1", "Leadership", "Yoga", "Nutrition", "HIIT"];

/** Case- and accent-insensitive ("Précision" matches "precision"). */
function norm(s: string) {
  return s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

export default function SearchPage() {
  const [query, setQuery] = useState("");

  const results = useMemo(() => {
    const q = norm(query.trim());
    if (!q) return [];
    return allItems.filter(
      (it) =>
        it.shape !== "1:1" &&
        [it.title, it.subtitle, it.league, it.instructor, it.level].some(
          (field) => field && norm(field).includes(q)
        )
    );
  }, [query]);

  const searching = query.trim().length > 0;

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--page-top)]">
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)] max-md:mb-[0.9rem] max-md:text-[1.8rem]">
        Rechercher
      </h1>

      {/* Pocket UI: a real search field, instant results. */}
      <div className="relative mb-[1.4rem] md:hidden">
        <svg
          className="pointer-events-none absolute left-[1rem] top-1/2 h-[1.15rem] w-[1.15rem] -translate-y-1/2 text-[var(--text-medium)]"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3-3" strokeLinecap="round" />
        </svg>
        <input
          type="search"
          inputMode="search"
          enterKeyHint="search"
          autoComplete="off"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Titre, équipe, thème…"
          aria-label="Rechercher un contenu"
          className="w-full rounded-[1.3rem] border border-[var(--hairline)] bg-[var(--surface-2)] py-[0.85rem] pl-[2.7rem] pr-[2.7rem] text-[1.05rem] text-[var(--text-high)] outline-none placeholder:text-[var(--text-medium)] focus:border-[var(--gold)]"
        />
        {searching && (
          <button
            onClick={() => setQuery("")}
            aria-label="Effacer la recherche"
            className="absolute right-[0.55rem] top-1/2 flex h-[1.9rem] w-[1.9rem] -translate-y-1/2 items-center justify-center rounded-full bg-white/10 text-[0.95rem] text-[var(--text-high)]"
          >
            ✕
          </button>
        )}
      </div>

      {/* TV: browse-first entry point (voice / chips), untouched. */}
      <div
        data-focusable
        className="focusable mb-[2rem] flex max-w-[40rem] items-center gap-[0.8rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[1rem] text-[1.3rem] text-[var(--text-medium)] max-md:hidden"
      >
        <svg className="h-[1.5rem] w-[1.5rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="11" cy="11" r="7" /><path d="m20 20-3-3" strokeLinecap="round" />
        </svg>
        Dites un titre, une équipe ou un thème…
      </div>

      {searching ? (
        <section aria-live="polite">
          <p className="mb-[1rem] text-[1.3rem] font-semibold text-[var(--text-high)] max-md:text-[1.02rem] max-md:font-medium max-md:text-[var(--text-medium)]">
            {results.length > 0
              ? `${results.length} résultat${results.length > 1 ? "s" : ""}`
              : `Aucun résultat pour « ${query.trim()} »`}
          </p>
          <ul className="flex flex-col gap-[0.7rem]">
            {results.map((it) => (
              <li key={it.id}>
                <Link
                  href={`/title/${it.id}`}
                  data-focusable
                  className="focusable flex items-center gap-[1rem] rounded-[var(--radius)] bg-[var(--surface-1)] p-[0.6rem] pr-[1rem]"
                >
                  <span
                    className="relative block h-[4rem] w-[7.1rem] shrink-0 overflow-hidden rounded-[0.55rem] ring-1 ring-[var(--hairline)]"
                    style={{ background: `linear-gradient(140deg, ${it.art.from}, ${it.art.to})` }}
                  >
                    {it.live && (
                      <span className="absolute left-[0.35rem] top-[0.35rem] scale-90">
                        <LiveBadge state={it.live} />
                      </span>
                    )}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[1.1rem] font-semibold text-[var(--text-high)] max-md:text-[1rem]">
                      {it.title}
                    </span>
                    <span className="mt-[0.15rem] flex items-center gap-[0.5rem] text-[0.9rem] text-[var(--text-medium)] max-md:text-[0.82rem]">
                      {it.level && <LevelBadge level={it.level} />}
                      {(it.league ?? it.instructor ?? it.subtitle) && (
                        <span className="truncate">{it.league ?? it.instructor ?? it.subtitle}</span>
                      )}
                      {it.duration && <span className="shrink-0">{it.duration}</span>}
                    </span>
                  </span>
                  <svg
                    className="h-[1rem] w-[1rem] shrink-0 text-[var(--text-medium)]"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.5"
                  >
                    <path d="m9 5 7 7-7 7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ) : (
        <>
          <p className="mb-[1rem] text-[1.3rem] font-semibold text-[var(--text-high)] max-md:text-[1.05rem]">
            Suggestions
          </p>
          <div className="flex flex-wrap gap-[0.8rem] max-md:gap-[0.6rem]">
            {SUGGESTIONS.map((s) => (
              <button
                key={s}
                data-focusable
                onClick={() => setQuery(s)}
                className="focusable rounded-full bg-[var(--surface-2)] px-[1.4rem] py-[0.7rem] text-[1.15rem] font-semibold text-[var(--text-high)] max-md:px-[1.1rem] max-md:py-[0.6rem] max-md:text-[0.95rem]"
              >
                {s}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
