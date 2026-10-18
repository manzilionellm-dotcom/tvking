import type { Metadata } from "next";
import Row from "../components/Row";
import { filmsRows } from "../lib/data";
import PageJsonLd from "../components/site/PageJsonLd";
import { canonicalFor } from "../lib/seo";

export const metadata: Metadata = {
  title: "Films",
  description: "Films téléchargés sur l'appareil. Lecture instantanée, sans spinner.",
  ...canonicalFor("/films"),
};

export default function FilmsPage() {
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <PageJsonLd crumbs={[{ name: "Films", path: "/films" }]} />
      <h1 className="font-display mb-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Films
      </h1>
      <p className="mb-[1.5rem] pr-[var(--safe-x)] text-[1.3rem] text-[var(--text-medium)]">
        Chaque film se télécharge sur l&apos;appareil avant lecture : démarrage
        immédiat, zéro mise en mémoire tampon.
      </p>
      {filmsRows.map((row) => (
        <Row key={row.id} row={row} />
      ))}
    </div>
  );
}
