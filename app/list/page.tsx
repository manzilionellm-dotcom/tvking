import type { Metadata } from "next";
import Row from "../components/Row";
import { homeRows } from "../lib/data";
import PageJsonLd from "../components/site/PageJsonLd";

export const metadata: Metadata = {
  title: "Ma liste",
  description: "Vos titres sauvegardés dans TV King.",
  alternates: { canonical: "https://zuno.7themotion.com/list" },
};

export default function ListPage() {
  const saved = { id: "saved", title: "Ma liste", items: homeRows.flatMap((r) => r.items).slice(0, 8) };
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <PageJsonLd crumbs={[{ name: "Ma liste", path: "/list" }]} />
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Ma liste
      </h1>
      <Row row={saved} />
    </div>
  );
}
