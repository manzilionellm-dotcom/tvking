"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useT } from "../lib/i18n";

/*
 * Left vertical navigation — the convergent TV shell. Collapsed to an icon rail;
 * expands to show labels when any item is focused (D-pad) or hovered, keeping
 * information density low (10-foot UI). NOVA+ identity: cool desaturated accent.
 */

const NAV = [
  { href: "/search", key: "nav_search", icon: "search" },
  { href: "/", key: "nav_home", icon: "home" },
  { href: "/guide", key: "nav_guide", icon: "guide" },
  { href: "/favorites", key: "nav_favorites", icon: "star" },
  { href: "/settings", key: "nav_settings", icon: "settings" },
] as const;

function Icon({ name }: { name: string }) {
  const common = "h-[1.6rem] w-[1.6rem]";
  switch (name) {
    case "search":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="11" cy="11" r="7" /><path d="m20 20-3-3" strokeLinecap="round" />
        </svg>
      );
    case "home":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M3 11 12 3l9 8" strokeLinecap="round" strokeLinejoin="round" /><path d="M5 10v10h14V10" strokeLinejoin="round" />
        </svg>
      );
    case "guide":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <rect x="3" y="4" width="18" height="16" rx="2" /><path d="M3 9h18M9 9v11M15 9v11" />
        </svg>
      );
    case "star":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="m12 3 2.6 5.6L21 9.3l-4.5 4.2 1.1 6.1L12 16.9 6.4 19.6l1.1-6.1L3 9.3l6.4-.7Z" strokeLinejoin="round" />
        </svg>
      );
    case "settings":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1Z" strokeLinejoin="round" />
        </svg>
      );
    default:
      return null;
  }
}

export default function Sidebar() {
  const pathname = usePathname();
  const t = useT();
  // The full-screen player owns the whole screen; hide the rail there.
  if (pathname.startsWith("/watch")) return null;

  return (
    <nav className="group/nav fixed inset-y-0 left-0 z-50 flex w-[5.5rem] flex-col gap-[0.4rem] bg-gradient-to-r from-black/95 to-black/0 py-[var(--safe-y)] pl-[1.2rem] transition-all duration-200 hover:w-[15rem] hover:bg-[var(--bg)]/95 focus-within:w-[15rem] focus-within:bg-[var(--bg)]/95">
      <div className="mb-[1.6rem] flex items-center gap-[0.7rem] pl-[0.2rem]">
        <span
          className="flex h-[2.6rem] w-[2.6rem] shrink-0 items-center justify-center rounded-[var(--radius)] text-[1.3rem] font-black text-black shadow-[0_0_1.2rem_rgba(61,169,252,0.45)]"
          style={{ background: "var(--accent-grad)" }}
        >
          N
        </span>
        <span className="flex flex-col whitespace-nowrap opacity-0 transition-opacity group-hover/nav:opacity-100 group-focus-within/nav:opacity-100">
          <span className="font-display text-[1.55rem] font-extrabold leading-none">
            <span className="text-accent-grad">NOVA</span>
            <span className="text-[var(--accent)]">+</span>
          </span>
          <span className="text-[0.7rem] font-semibold uppercase tracking-[0.35em] text-[var(--text-medium)]">
            {t("tagline")}
          </span>
        </span>
      </div>

      {NAV.map((item) => {
        const active = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            data-focusable
            className={`focusable relative flex items-center gap-[1rem] rounded-[var(--radius)] px-[0.7rem] py-[0.7rem] ${
              active ? "text-[var(--accent-strong)]" : "text-[var(--text-medium)]"
            }`}
            style={active ? { background: "rgba(61,169,252,0.12)" } : undefined}
          >
            {active && (
              <span
                className="absolute left-0 top-1/2 h-[1.4rem] w-[0.28rem] -translate-y-1/2 rounded-full"
                style={{ background: "var(--accent-grad)" }}
              />
            )}
            <span className="shrink-0"><Icon name={item.icon} /></span>
            <span className="whitespace-nowrap text-[1.15rem] font-semibold opacity-0 transition-opacity group-hover/nav:opacity-100 group-focus-within/nav:opacity-100">
              {t(item.key)}
            </span>
          </Link>
        );
      })}
    </nav>
  );
}
