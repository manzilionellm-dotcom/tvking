"use client";

// =========================================================
//  Sidebar.tsx — Rail de navigation gauche
// =========================================================
//  Collapsé en icônes (5.5rem), s'élargit au focus/survol pour révéler
//  les libellés. Liste : Accueil, Rechercher, les 5 univers, Ma liste,
//  Réglages. Logo « ✦ NOVA+ » avec halo or. L'item actif porte une
//  barre dorée. Tout est focusable et explicitement libellé.
// =========================================================

import Link from "next/link";
import { usePathname } from "next/navigation";
import { UNIVERSES } from "../lib/data";

interface NavEntry {
  href: string;
  icon: string;
  label: string;
}

const TOP: NavEntry[] = [
  { href: "/", icon: "🏠", label: "Accueil" },
  { href: "/search", icon: "🔎", label: "Rechercher" },
];

const BOTTOM: NavEntry[] = [
  { href: "/list", icon: "⭐", label: "Ma liste" },
  { href: "/reglages", icon: "⚙️", label: "Réglages" },
];

const UNIVERSE_ENTRIES: NavEntry[] = UNIVERSES.map((u) => ({
  href: `/${u.id}`,
  icon: u.icon,
  label: u.label,
}));

function NavItem({ entry, active }: { entry: NavEntry; active: boolean }) {
  return (
    <Link
      href={entry.href}
      className="nav-item focusable"
      data-focusable
      data-nav-id={`nav-${entry.href}`}
      data-active={active}
      aria-label={entry.label}
      aria-current={active ? "page" : undefined}
    >
      <span className="nav-icon" aria-hidden>
        {entry.icon}
      </span>
      <span className="nav-label">{entry.label}</span>
    </Link>
  );
}

export function Sidebar() {
  const pathname = usePathname();
  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname.startsWith(href);

  return (
    <nav className="sidebar" aria-label="Navigation principale">
      <Link
        href="/"
        className="sidebar-logo focusable"
        data-focusable
        data-nav-id="nav-logo"
        aria-label="NOVA+, accueil"
        style={{ color: "var(--text-high)", textDecoration: "none" }}
      >
        <span className="crown" aria-hidden>
          ✦
        </span>
        <span className="nav-label">
          NOVA<span style={{ color: "var(--gold)" }}>+</span>
        </span>
      </Link>

      {TOP.map((e) => (
        <NavItem key={e.href} entry={e} active={isActive(e.href)} />
      ))}

      <div
        aria-hidden
        style={{
          height: 1,
          background: "rgba(255,255,255,0.08)",
          margin: "0.5rem 0.4rem",
        }}
      />

      {UNIVERSE_ENTRIES.map((e) => (
        <NavItem key={e.href} entry={e} active={isActive(e.href)} />
      ))}

      <div style={{ flex: 1 }} />

      {BOTTOM.map((e) => (
        <NavItem key={e.href} entry={e} active={isActive(e.href)} />
      ))}
    </nav>
  );
}
