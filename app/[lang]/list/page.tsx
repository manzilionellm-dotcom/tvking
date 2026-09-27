import type { Metadata } from "next";
import Row from "../../components/Row";
import { homeRows } from "../../lib/data";
import { localizeItem } from "../../i18n/localize";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: PageProps<"/[lang]/list">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return { title: m.meta.listTitle, description: m.meta.listDescription };
}

export default async function ListPage({ params }: PageProps<"/[lang]/list">) {
  const { m } = await pageI18n(params);
  const saved = {
    id: "saved",
    title: m.list.title,
    items: homeRows.flatMap((r) => r.items).slice(0, 8).map((it) => localizeItem(it, m)),
  };
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        {m.list.title}
      </h1>
      <Row row={saved} />
    </div>
  );
}
