"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV, NavIcon } from "./Sidebar";

/*
 * The pocket shell (< md): a fixed translucent header with the royal brand and
 * a glass bottom tab bar — the native-app conventions (iOS tab bar / Material
 * navigation bar). Thumb-sized targets, notch/home-bar safe areas, gold active
 * state. Hidden at md+ where the TV rail (Sidebar) takes over.
 */

/* Five thumb tabs, Accueil in first position; Réglages lives in the header. */
const TAB_ORDER = ["/", "/sport", "/formation", "/search", "/list"] as const;
const TABS = TAB_ORDER.map((href) => NAV.find((n) => n.href === href)!);

export default function MobileNav() {
  const pathname = usePathname();

  return (
    <div className="md:hidden">
      {/* Top brand bar — a scrim, not a slab, so heroes bleed behind it. */}
      <header
        className="fixed inset-x-0 top-0 z-40 px-[var(--safe-x)]"
        style={{
          paddingTop: "env(safe-area-inset-top, 0px)",
          background:
            "linear-gradient(to bottom, rgba(10,10,12,0.88), rgba(10,10,12,0.45) 62%, transparent)",
        }}
      >
        <div className="flex h-[3.3rem] items-center justify-between">
          <Link href="/" className="flex items-center gap-[0.55rem]" aria-label="Accueil TV King">
            <span
              className="flex h-[1.9rem] w-[1.9rem] items-center justify-center rounded-[0.55rem] text-[1.05rem] shadow-[0_0_0.9rem_rgba(227,185,107,0.45)]"
              style={{ background: "var(--gold-grad)" }}
            >
              👑
            </span>
            <span className="font-display text-gold-grad text-[1.3rem] font-extrabold leading-none">
              TV King
            </span>
          </Link>
          <Link
            href="/reglages"
            aria-label="Réglages"
            className={`focusable flex h-[2.5rem] w-[2.5rem] items-center justify-center rounded-full bg-white/10 ${
              pathname === "/reglages" ? "text-[var(--gold-strong)]" : "text-[var(--text-high)]"
            }`}
          >
            <span className="[&>svg]:h-[1.25rem] [&>svg]:w-[1.25rem]">
              <NavIcon name="settings" />
            </span>
          </Link>
        </div>
      </header>

      {/* Bottom tab bar — frosted glass over the content, gold active pill. */}
      <nav
        aria-label="Navigation principale"
        className="fixed inset-x-0 bottom-0 z-40 border-t border-[var(--hairline)] bg-[rgba(16,16,18,0.88)] backdrop-blur-xl"
        style={{ paddingBottom: "max(0.55rem, env(safe-area-inset-bottom, 0px))" }}
      >
        <div className="grid grid-cols-5">
          {TABS.map((tab) => {
            const active =
              tab.href === "/" ? pathname === "/" : pathname.startsWith(tab.href);
            return (
              <Link
                key={tab.href}
                href={tab.href}
                aria-current={active ? "page" : undefined}
                className="focusable flex flex-col items-center gap-[0.22rem] pb-[0.1rem] pt-[0.5rem]"
              >
                <span
                  className={`flex h-[1.85rem] w-[3.2rem] items-center justify-center rounded-full transition-colors duration-200 ${
                    active ? "text-black" : "text-[var(--text-medium)]"
                  }`}
                  style={active ? { background: "var(--gold-grad)" } : undefined}
                >
                  <span className="[&>svg]:h-[1.2rem] [&>svg]:w-[1.2rem]">
                    <NavIcon name={tab.icon} />
                  </span>
                </span>
                <span
                  className={`text-[0.68rem] font-semibold tracking-wide ${
                    active ? "text-[var(--gold-strong)]" : "text-[var(--text-medium)]"
                  }`}
                >
                  {tab.label}
                </span>
              </Link>
            );
          })}
        </div>
      </nav>
    </div>
  );
}
