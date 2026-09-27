import type { Metadata } from "next";
import Row from "../../components/Row";
import { filmsRows } from "../../lib/data";
import { localizeRow } from "../../i18n/localize";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: PageProps<"/[lang]/films">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return { title: m.meta.filmsTitle, description: m.meta.filmsDescription };
}

export default async function FilmsPage({ params }: PageProps<"/[lang]/films">) {
  const { m } = await pageI18n(params);
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        {m.films.title}
      </h1>
      <p className="mb-[1.5rem] pr-[var(--safe-x)] text-[1.3rem] text-[var(--text-medium)]">
        {m.films.intro}
      </p>
      {filmsRows.map((row) => (
        <Row key={row.id} row={localizeRow(row, m)} />
      ))}
    </div>
  );
}
