"use client";

import { useSyncExternalStore } from "react";
import { getItem, type MediaItem, type Row as RowData } from "../lib/data";
import { loadResume, type ResumeStore } from "../lib/resume";
import Row from "./Row";

/*
 * "Reprendre" driven by the real, persisted playhead (lib/resume.ts) instead of
 * a hard-coded progress hint. The store already existed and the player already
 * wrote to it — nothing read it back on the home page, so a programme watched
 * to 12:30 still showed the mock 45 %.
 *
 * Ranking = most recently watched first, which is the documented behaviour of a
 * Continue Watching rail (research §4). The seeded row remains as the fallback
 * while the store is empty (a fresh box has nothing to resume).
 */

const noSubscription = () => () => {};

function fromStore(store: ResumeStore): MediaItem[] {
  return Object.entries(store.entries)
    .sort((a, b) => b[1].at - a[1].at)
    .map(([id, entry]): MediaItem | null => {
      const item = getItem(id);
      if (!item) return null;
      return entry.dur > 0
        ? { ...item, progress: Math.min(1, entry.pos / entry.dur) }
        : item;
    })
    .filter((it): it is MediaItem => it !== null);
}

export default function ContinueRow({ fallback }: { fallback: RowData }) {
  // Server snapshot is null → the seeded row renders on the server and during
  // hydration; the persisted one takes over on the client.
  const store = useSyncExternalStore(noSubscription, loadResume, () => null);
  const resumed = store ? fromStore(store) : [];
  const items = resumed.length > 0 ? resumed : fallback.items;
  return <Row row={{ ...fallback, items }} />;
}
