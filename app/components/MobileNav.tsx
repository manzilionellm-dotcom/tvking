"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon, NAV } from "./Sidebar";

/*
 * Bottom tab bar for phones (<768px), where the 10-foot side rail makes no
 * sense (hover-expand needs a pointer, and thumbs live at the bottom of the
 * screen). Same destinations as the rail; horizontally scrollable so nothing
 * is dropped on narrow screens.
 */
export default function MobileNav() {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Navigation principale"
      className="no-scrollbar fixed inset-x-0 bottom-0 z-50 flex overflow-x-auto border-t border-[var(--hairline)] bg-[var(--bg)]/95 px-[0.4rem] pb-[max(0.4rem,env(safe-area-inset-bottom))] pt-[0.5rem] backdrop-blur md:hidden"
    >
      {NAV.map((item) => {
        const active = pathname === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            className="flex min-w-[4.6rem] flex-1 flex-col items-center gap-[0.25rem] rounded-[var(--radius)] px-[0.4rem] py-[0.35rem]"
            style={active ? { color: "var(--gold-strong)" } : { color: "var(--text-medium)" }}
          >
            <Icon name={item.icon} />
            <span className="whitespace-nowrap text-[0.72rem] font-semibold">{item.label}</span>
          </Link>
        );
      })}
    </nav>
  );
}
