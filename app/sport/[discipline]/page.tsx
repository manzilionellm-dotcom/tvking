import { notFound } from "next/navigation";
import FacetNav from "../../components/FacetNav";
import Row from "../../components/Row";
import { getFacet, itemsInFacet, sportFacets, type MediaItem } from "../../lib/data";

/* One static page per discipline — the facet tiles of "Par discipline" now lead
   somewhere real instead of opening a detail page for a logo. */
export function generateStaticParams() {
  return sportFacets.map((f) => ({ discipline: f.key }));
}

/** Inside a discipline, the tri-state model is the useful ordering. */
function group(items: MediaItem[]) {
  return [
    { id: "live", title: "En direct", items: items.filter((i) => i.live === "live") },
    { id: "upcoming", title: "À venir", items: items.filter((i) => i.live === "upcoming") },
    { id: "replay", title: "Replays & temps forts", items: items.filter((i) => i.live === "replay") },
    {
      id: "around",
      title: "Analyses & autour du sport",
      items: items.filter((i) => !i.live),
    },
  ].filter((r) => r.items.length > 0);
}

export default async function DisciplinePage({ params }: PageProps<"/sport/[discipline]">) {
  const { discipline } = await params;
  const facet = getFacet("sport", discipline);
  if (!facet) notFound();

  const rows = group(itemsInFacet(facet));

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <header className="mb-[1.4rem]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.2em] text-[var(--sport)]">
          Sport
        </p>
        <h1 className="font-display text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
          {facet.label}
        </h1>
      </header>

      <FacetNav facets={sportFacets} current={facet.key} allHref="/sport" allLabel="Tout le sport" />

      {rows.length > 0 ? (
        rows.map((row) => <Row key={row.id} row={row} />)
      ) : (
        <p className="text-[1.3rem] text-[var(--text-medium)]">
          Rien de programmé pour le moment dans cette discipline.
        </p>
      )}
    </div>
  );
}
