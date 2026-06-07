"use client";

import type { ReactNode } from "react";

/*
 * Un rail horizontal de l'accueil : titre + rangée de cartes défilable au D-pad.
 * La navigation spatiale (SpatialNav) recentre la carte focalisée — comme le
 * « focus mémorisé par rail » côté ressenti : la carte active reste centrée, et
 * remonter/descendre retombe sur la carte alignée. Le parent n'affiche le rail
 * que s'il a du contenu (rails vides masqués).
 */
export default function Rail({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mb-[1.6rem]">
      <h2 className="mb-[0.7rem] text-[1.25rem] font-bold text-[var(--text-high)]">{title}</h2>
      <div className="no-scrollbar flex gap-[0.8rem] overflow-x-auto pb-[0.4rem]">{children}</div>
    </section>
  );
}
