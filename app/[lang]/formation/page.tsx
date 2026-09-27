import type { Metadata } from "next";
import Row from "../../components/Row";
import { formationRows } from "../../lib/data";
import { localizeRow } from "../../i18n/localize";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: PageProps<"/[lang]/formation">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return { title: m.meta.formationTitle, description: m.meta.formationDescription };
}

export default async function FormationPage({ params }: PageProps<"/[lang]/formation">) {
  const { m } = await pageI18n(params);
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <header className="mb-[1.8rem]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.2em] text-[var(--learn)]">
          {m.formation.kicker}
        </p>
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
          {m.formation.title}
        </h1>
      </header>
      {formationRows.map((row) => (
        <Row key={row.id} row={localizeRow(row, m)} />
      ))}
    </div>
  );
}
