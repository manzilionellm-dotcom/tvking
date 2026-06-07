"use client";

import Link from "next/link";
import { useMemo } from "react";
import ChannelBrowser from "./components/ChannelBrowser";
import { useSource, nowNextMap } from "./lib/client-source";
import { useT } from "./lib/i18n";

export default function Home() {
  const { status, playlist, error } = useSource();
  const t = useT();
  // now/next pour toute la grille : recalculé seulement quand la source change.
  const nowNext = useMemo(() => {
    void playlist; // recompute quand la playlist/EPG change (lecture via le store)
    return nowNextMap();
  }, [playlist]);

  if (status === "loading" || status === "idle") {
    return <Center>{t("loading_channels")}</Center>;
  }

  if (playlist.total === 0) {
    return (
      <Center>
        <h1 className="font-display text-[2.6rem] font-extrabold">
          <span className="text-accent-grad">NOVA</span>
          <span className="text-[var(--accent)]">+</span>
        </h1>
        <p className="max-w-[40rem] text-[1.2rem] text-[var(--text-medium)]">{t("home_empty")}</p>
        {error && (
          <p className="text-[1rem] text-[var(--live)]">
            {t("error")} : {error}
          </p>
        )}
        <Link
          href="/settings"
          data-focusable
          className="focusable rounded-[var(--radius)] px-[1.6rem] py-[0.9rem] text-[1.15rem] font-bold text-black"
          style={{ background: "var(--accent-grad)" }}
        >
          {t("configure_source")}
        </Link>
      </Center>
    );
  }

  return <ChannelBrowser groups={playlist.groups} nowNext={nowNext} />;
}

function Center({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-[1.2rem] pl-[6.5rem] pr-[var(--safe-x)] text-center">
      {children}
    </div>
  );
}
