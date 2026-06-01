"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

/*
 * Left vertical navigation — the convergent TV shell (Netflix/Hulu/Disney+/ESPN).
 * Collapsed to an icon rail; expands to show labels when any item is focused or
 * hovered, keeping information density low (10-foot UI).
 */

const NAV = [
  { href: "/search", label: "Rechercher", icon: "search" },
  { href: "/", label: "Accueil", icon: "home" },
  { href: "/sport", label: "Sport", icon: "sport" },
  { href: "/formation", label: "Formation", icon: "learn" },
  { href: "/list", label: "Ma liste", icon: "list" },
  { href: "/reglages", label: "Réglages", icon: "settings" },
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
    case "sport":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="12" cy="12" r="9" /><path d="M12 3a9 9 0 0 0 0 18M3 12h18M5 6c3 2 11 2 14 0M5 18c3-2 11-2 14 0" />
        </svg>
      );
    case "learn":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M3 7 12 3l9 4-9 4-9-4Z" strokeLinejoin="round" /><path d="M7 9v5c0 1.5 10 1.5 10 0V9" strokeLinejoin="round" />
        </svg>
      );
    case "list":
      return (
        <svg className={common} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <path d="M5 6h14M5 12h14M5 18h9" /><path d="m17 16 2 2 3-3" />
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

  return (
    <nav
      className="group/nav fixed inset-y-0 left-0 z-50 flex w-[5.5rem] flex-col gap-[0.4rem] bg-gradient-to-r from-black/95 to-black/0 py-[var(--safe-y)] pl-[1.2rem] transition-all duration-200 hover:w-[16rem] hover:bg-[var(--bg)]/95 focus-within:w-[16rem] focus-within:bg-[var(--bg)]/95"
    >
      <div className="mb-[1.5rem] flex items-center gap-[0.7rem] pl-[0.4rem]">
        <span className="text-[1.8rem]">👑</span>
        <span className="whitespace-nowrap text-[1.4rem] font-extrabold tracking-tight text-[var(--gold)] opacity-0 transition-opacity group-hover/nav:opacity-100 group-focus-within/nav:opacity-100">
          TV King
        </span>
      </div>

      {NAV.map((item) => {
        const active = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            data-focusable
            className={`focusable flex items-center gap-[1rem] rounded-[var(--radius)] px-[0.7rem] py-[0.7rem] ${
              active ? "bg-white/10 text-[var(--gold)]" : "text-[var(--text-medium)]"
            }`}
          >
            <span className="shrink-0"><Icon name={item.icon} /></span>
            <span className="whitespace-nowrap text-[1.15rem] font-semibold opacity-0 transition-opacity group-hover/nav:opacity-100 group-focus-within/nav:opacity-100">
              {item.label}
            </span>
          </Link>
        );
      })}
    </nav>
  );
}
