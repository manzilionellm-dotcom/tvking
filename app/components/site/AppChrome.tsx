"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import SiteHeader from "./SiteHeader";
import SiteFooter from "./SiteFooter";
import SupportChat from "./SupportChat";
import Sidebar from "../Sidebar";
import MobileNav from "../MobileNav";
import SpatialNav from "../SpatialNav";
import MiniPlayer from "../MiniPlayer";

const MARKETING = new Set([
  "/",
  "/forfaits",
  "/connexion",
  "/telecharger",
  "/activer",
  "/faq",
  "/legal",
  "/revendeur",
  "/start",
]);

function isMarketing(path: string): boolean {
  if (MARKETING.has(path)) return true;
  // locale prefixes if any
  if (path.startsWith("/fr/") || path === "/fr") {
    const rest = path === "/fr" ? "/" : path.slice(3);
    return MARKETING.has(rest) || rest === "/";
  }
  return false;
}

export default function AppChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname() || "/";
  const marketing = isMarketing(pathname);

  if (marketing) {
    return (
      <div className="zuno-marketing flex min-h-screen flex-col bg-[#0a0a0c] text-[var(--text-high)]">
        <SiteHeader />
        <main className="flex-1">{children}</main>
        <SiteFooter />
        <SupportChat />
      </div>
    );
  }

  return (
    <>
      <Sidebar />
      <MobileNav />
      <SpatialNav />
      <main className="min-h-screen pl-[5.5rem] max-md:pb-[5.5rem] max-md:pl-0">{children}</main>
      <MiniPlayer />
      <SupportChat />
    </>
  );
}
