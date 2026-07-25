"use client";

import Link from "next/link";
import { useSyncExternalStore } from "react";
import {
  MYLIST_KEY,
  REMINDERS_KEY,
  loadSet,
  subscribeCollections,
} from "../lib/collections";
import { getItem, type MediaItem } from "../lib/data";
import Row from "./Row";

/*
 * "Ma liste" — the real saved collection, replacing the placeholder that showed
 * the first items of the home page whether or not the viewer had saved anything.
 *
 * Order is most-recently-saved first (the store keeps insertion order). Ids that
 * no longer exist in the catalogue are skipped rather than crashing — content
 * comes and goes, a saved list must survive it.
 */

const EMPTY: string[] = [];

function useIds(key: string): string[] {
  return useSyncExternalStore(
    subscribeCollections,
    () => loadSet(key).ids,
    () => EMPTY
  );
}

function resolve(ids: string[]): MediaItem[] {
  return ids.map(getItem).filter((it): it is MediaItem => Boolean(it));
}

function Empty({ title, body, cta }: { title: string; body: string; cta: { href: string; label: string } }) {
  return (
    <div className="mb-[2.4rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] px-[2rem] py-[2rem]">
      <h2 className="mb-[0.4rem] text-[1.6rem] font-bold text-[var(--text-high)]">{title}</h2>
      <p className="mb-[1.2rem] max-w-[52ch] text-[1.25rem] text-[var(--text-medium)]">{body}</p>
      <Link
        href={cta.href}
        data-focusable
        className="focusable inline-block rounded-[var(--radius)] px-[1.4rem] py-[0.7rem] text-[1.15rem] font-bold text-black"
        style={{ background: "var(--gold-grad)" }}
      >
        {cta.label}
      </Link>
    </div>
  );
}

export default function CollectionsView() {
  const saved = resolve(useIds(MYLIST_KEY));
  const reminders = resolve(useIds(REMINDERS_KEY));

  return (
    <>
      {saved.length > 0 ? (
        <Row row={{ id: "saved", title: "Ma liste", items: saved }} />
      ) : (
        <Empty
          title="Votre liste est vide"
          body="Ajoutez un match ou un cours avec « + Ma liste » depuis sa fiche : vous le retrouverez ici, sur toutes vos sessions."
          cta={{ href: "/", label: "Parcourir l'accueil" }}
        />
      )}

      {reminders.length > 0 && (
        <Row row={{ id: "reminders", title: "Mes rappels", items: reminders }} />
      )}
    </>
  );
}
