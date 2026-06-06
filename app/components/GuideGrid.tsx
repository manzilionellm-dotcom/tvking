"use client";

import Link from "next/link";
import ChannelLogo from "./ChannelLogo";

/** One channel's row in the guide grid (programmes clipped to the window). */
export interface GuideRow {
  id: string;
  name: string;
  number: number;
  logo?: string;
  programmes: { start: number; stop: number; title: string }[];
}

/*
 * EPG grid (TiViMate-style): rows = channels, X axis = time. Programme blocks
 * are positioned/sized by their start + duration over the visible window. Each
 * block is focusable and opens the channel; the "now" line marks the present.
 */

function hhmm(ms: number) {
  const d = new Date(ms);
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

export default function GuideGrid({
  rows,
  windowStart,
  windowEnd,
  now,
}: {
  rows: GuideRow[];
  windowStart: number;
  windowEnd: number;
  /** Server's "now" (epoch ms) — passed in so render stays pure. */
  now: number;
}) {
  const span = windowEnd - windowStart;
  const pct = (t: number) => ((Math.min(Math.max(t, windowStart), windowEnd) - windowStart) / span) * 100;

  // Half-hour tick marks across the header.
  const ticks: number[] = [];
  for (let t = windowStart; t <= windowEnd; t += 30 * 60_000) ticks.push(t);

  return (
    <div className="no-scrollbar overflow-x-auto pb-[3rem]">
      <div className="min-w-[60rem]">
        {/* Time header */}
        <div className="sticky top-0 z-10 ml-[13rem] flex border-b border-[var(--hairline)] bg-[var(--bg)]/95 pb-[0.3rem] backdrop-blur">
          {ticks.slice(0, -1).map((t) => (
            <div
              key={t}
              className="text-[0.95rem] font-semibold text-[var(--text-medium)]"
              style={{ width: `${(30 * 60_000) / span * 100}%` }}
            >
              {hhmm(t)}
            </div>
          ))}
        </div>

        {/* Rows (the present is marked by the highlighted live programme). */}
        <div className="relative">
          {rows.map((row) => (
            <div key={row.id} className="flex items-stretch gap-0 border-b border-[var(--hairline)]/60">
              {/* Channel label */}
              <Link
                href={`/watch?c=${encodeURIComponent(row.id)}`}
                data-focusable
                className="focusable sticky left-0 z-[6] flex w-[13rem] shrink-0 items-center gap-[0.5rem] bg-[var(--surface-1)] px-[0.6rem] py-[0.5rem]"
              >
                <span className="w-[1.8rem] shrink-0 text-right text-[0.85rem] font-bold tabular-nums text-[var(--text-disabled)]">
                  {row.number}
                </span>
                <ChannelLogo src={row.logo} name={row.name} size="2.2rem" />
                <span className="min-w-0 flex-1 truncate text-[1rem] font-semibold text-[var(--text-high)]">
                  {row.name}
                </span>
              </Link>

              {/* Programme track */}
              <div className="relative h-[3.4rem] flex-1">
                {row.programmes.length === 0 ? (
                  <div className="flex h-full items-center px-[0.6rem] text-[0.9rem] text-[var(--text-disabled)]">
                    Aucune information
                  </div>
                ) : (
                  row.programmes.map((p, i) => {
                    const left = pct(p.start);
                    const width = Math.max(pct(p.stop) - left, 2);
                    const live = now >= p.start && now < p.stop;
                    return (
                      <Link
                        key={i}
                        href={`/watch?c=${encodeURIComponent(row.id)}`}
                        data-focusable
                        className="focusable absolute inset-y-[0.2rem] overflow-hidden rounded-[0.4rem] px-[0.5rem] py-[0.35rem]"
                        style={{
                          left: `${left}%`,
                          width: `${width}%`,
                          background: live ? "rgba(61,169,252,0.18)" : "var(--surface-2)",
                        }}
                      >
                        <span className="block truncate text-[0.95rem] font-semibold text-[var(--text-high)]">
                          {p.title}
                        </span>
                        <span className="block truncate text-[0.78rem] text-[var(--text-medium)]">
                          {hhmm(p.start)}
                        </span>
                      </Link>
                    );
                  })
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
