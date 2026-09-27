import Hero from "../components/Hero";
import Row from "../components/Row";
import { heroSlides, homeRows } from "../lib/data";
import { localizeItem, localizeRow } from "../i18n/localize";
import { pageI18n } from "../i18n/server";

export default async function Home({ params }: PageProps<"/[lang]">) {
  const { m } = await pageI18n(params);
  return (
    <div className="pb-[var(--safe-y)]">
      <Hero slides={heroSlides.map((s) => localizeItem(s, m))} />
      <div className="pl-[var(--safe-x)]">
        {homeRows.map((row) => (
          <Row key={row.id} row={localizeRow(row, m)} />
        ))}
      </div>
    </div>
  );
}
