import { notFound } from "next/navigation";
import FacetNav from "../../components/FacetNav";
import Row from "../../components/Row";
import { formationFacets, getFacet, itemsInFacet, type MediaItem } from "../../lib/data";

export function generateStaticParams() {
  return formationFacets.map((f) => ({ theme: f.key }));
}

/* Inside a theme, LEVEL is the documented first-class facet for learning
   content (Coursera / Peloton / MasterClass all lead with it). */
const LEVELS = ["Débutant", "Intermédiaire", "Avancé"] as const;

function group(items: MediaItem[]) {
  const rows: { id: string; title: string; items: MediaItem[] }[] = LEVELS.map((level) => ({
    id: level,
    title: level,
    items: items.filter((i) => i.level === level),
  }));
  rows.push({ id: "autres", title: "Autres contenus", items: items.filter((i) => !i.level) });
  return rows.filter((r) => r.items.length > 0);
}

export default async function ThemePage({ params }: PageProps<"/formation/[theme]">) {
  const { theme } = await params;
  const facet = getFacet("formation", theme);
  if (!facet) notFound();

  const rows = group(itemsInFacet(facet));

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <header className="mb-[1.4rem]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.2em] text-[var(--learn)]">
          Formation
        </p>
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
          {facet.label}
        </h1>
      </header>

      <FacetNav
        facets={formationFacets}
        current={facet.key}
        allHref="/formation"
        allLabel="Toute la formation"
      />

      {rows.length > 0 ? (
        rows.map((row) => <Row key={row.id} row={row} />)
      ) : (
        <p className="text-[1.3rem] text-[var(--text-medium)]">
          Aucun programme dans ce thème pour l&apos;instant.
        </p>
      )}
    </div>
  );
}
