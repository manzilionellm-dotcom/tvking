import type { Metadata } from "next";
import Row from "../../components/Row";
import { sportRows } from "../../lib/data";
import { localizeRow } from "../../i18n/localize";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: PageProps<"/[lang]/sport">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return { title: m.meta.sportTitle, description: m.meta.sportDescription };
}

export default async function SportPage({ params }: PageProps<"/[lang]/sport">) {
  const { m } = await pageI18n(params);
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <header className="mb-[1.8rem]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.2em] text-[var(--sport)]">
          {m.sport.kicker}
        </p>
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
          {m.sport.title}
        </h1>
        <p className="mt-[0.3rem] text-[1.3rem] text-[var(--text-medium)]">{m.sport.intro}</p>
      </header>
      {sportRows.map((row) => (
        <Row key={row.id} row={localizeRow(row, m)} />
      ))}
    </div>
  );
}
