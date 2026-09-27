"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

const NAV = [
  { href: "/", label: "Accueil" },
  { href: "/forfaits", label: "Forfaits" },
  { href: "/telecharger", label: "Télécharger" },
  { href: "/activer", label: "Activer" },
  { href: "/faq", label: "FAQ" },
];

export default function SiteHeader() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <header className="zuno-header sticky top-0 z-50 border-b border-white/8 bg-[#0a0a0c]/85 backdrop-blur-xl">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <Link href="/" className="group flex items-center gap-2.5" onClick={() => setOpen(false)}>
          <span className="zuno-logo-mark flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-[#3b82f6] to-[#1d4ed8] text-sm font-black text-white shadow-[0_0_24px_rgba(59,130,246,0.45)]">
            Z
          </span>
          <span className="flex flex-col leading-none">
            <span className="text-[1.15rem] font-bold tracking-tight text-white">Zuno</span>
            <span className="text-[0.65rem] font-medium uppercase tracking-[0.2em] text-white/45">
              VIP
            </span>
          </span>
        </Link>

        <nav className="hidden items-center gap-1 md:flex">
          {NAV.map((item) => {
            const active = pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`rounded-lg px-3 py-2 text-sm font-medium transition ${
                  active
                    ? "bg-white/10 text-white"
                    : "text-white/55 hover:bg-white/5 hover:text-white"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="hidden items-center gap-2 md:flex">
          <Link
            href="/connexion"
            className="rounded-lg px-3 py-2 text-sm font-medium text-white/70 transition hover:text-white"
          >
            Se connecter
          </Link>
          <Link
            href="/forfaits"
            className="zuno-cta rounded-xl bg-gradient-to-r from-[#3b82f6] to-[#2563eb] px-4 py-2 text-sm font-semibold text-white shadow-[0_0_20px_rgba(59,130,246,0.35)] transition hover:brightness-110"
          >
            Voir les forfaits
          </Link>
        </div>

        <button
          type="button"
          aria-label="Menu"
          className="rounded-lg border border-white/10 p-2 text-white md:hidden"
          onClick={() => setOpen((v) => !v)}
        >
          <svg className="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            {open ? (
              <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
            ) : (
              <path d="M4 7h16M4 12h16M4 17h16" strokeLinecap="round" />
            )}
          </svg>
        </button>
      </div>

      {open && (
        <div className="zuno-fade-in border-t border-white/8 bg-[#0a0a0c] px-4 py-4 md:hidden">
          <div className="flex flex-col gap-1">
            {NAV.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setOpen(false)}
                className="rounded-lg px-3 py-3 text-base font-medium text-white/80"
              >
                {item.label}
              </Link>
            ))}
            <Link href="/connexion" onClick={() => setOpen(false)} className="rounded-lg px-3 py-3 text-white/70">
              Se connecter
            </Link>
            <Link
              href="/forfaits"
              onClick={() => setOpen(false)}
              className="mt-2 rounded-xl bg-[#2563eb] px-4 py-3 text-center font-semibold text-white"
            >
              Voir les forfaits
            </Link>
            <Link
              href="/activer"
              onClick={() => setOpen(false)}
              className="rounded-xl border border-white/15 px-4 py-3 text-center font-medium text-white/80"
            >
              Activer mon appareil
            </Link>
          </div>
        </div>
      )}
    </header>
  );
}
