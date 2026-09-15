import type { Metadata } from "next";
import Row from "../components/Row";
import { formationRows } from "../lib/data";

export const metadata: Metadata = {
  title: "Formation",
  description: "Parcours par niveau, progression et intervenants.",
};

export default function FormationPage() {
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <header className="mb-[1.8rem]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.2em] text-[var(--learn)]">
          Formation
        </p>
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
          Progresser, à votre rythme
        </h1>
      </header>
      {formationRows.map((row) => (
        <Row key={row.id} row={row} />
      ))}
    </div>
  );
}
