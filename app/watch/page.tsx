"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense } from "react";
import Player from "../components/Player";
import { useSource, nowNextFor } from "../lib/client-source";

/*
 * Live player route. We use a query param (?c=<id>) rather than a dynamic
 * segment so the app static-exports cleanly into the APK (no per-channel HTML).
 */
export default function WatchPage() {
  return (
    <Suspense fallback={<Splash>Chargement…</Splash>}>
      <WatchInner />
    </Suspense>
  );
}

function WatchInner() {
  const id = useSearchParams().get("c") ?? "";
  const { status, playlist } = useSource();

  if (status === "loading" || status === "idle") return <Splash>Chargement…</Splash>;

  const channel = playlist.channels.find((c) => c.id === id);
  if (!channel) {
    return (
      <Splash>
        <p>Chaîne introuvable.</p>
        <Link
          href="/"
          data-focusable
          className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[0.7rem] text-[var(--text-high)]"
        >
          Retour à l’accueil
        </Link>
      </Splash>
    );
  }

  const group = playlist.groups.find((g) => g.name === channel.group);
  const channels = group?.channels ?? [channel];

  return <Player channels={channels} startId={channel.id} initialNowNext={nowNextFor(channel.id)} />;
}

function Splash({ children }: { children: React.ReactNode }) {
  return (
    <div className="fixed inset-0 z-[60] flex flex-col items-center justify-center gap-[1rem] bg-black text-[var(--text-medium)]">
      {children}
    </div>
  );
}
