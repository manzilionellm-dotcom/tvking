import MediaCard from "../components/MediaCard";
import Row from "../components/Row";
import { homeRows } from "../lib/data";

/* "Ma liste" — investment surface (Hooked model): saved items the user has
   chosen, which personalises future recommendations. A rail on TV; a poster
   grid in the pocket UI (the native "library" convention). */
export default function ListPage() {
  const saved = { id: "saved", title: "Ma liste", items: homeRows.flatMap((r) => r.items).slice(0, 8) };
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--page-top)]">
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)] max-md:mb-[0.3rem] max-md:text-[1.8rem]">
        Ma liste
      </h1>
      <p className="mb-[1.1rem] text-[0.95rem] text-[var(--text-medium)] md:hidden">
        {saved.items.length} titres enregistrés
      </p>

      <div className="grid grid-cols-2 gap-x-[0.85rem] gap-y-[1.2rem] pr-[var(--safe-x)] md:hidden">
        {saved.items.map((item) => (
          <MediaCard key={item.id} item={item} fluid />
        ))}
      </div>

      <div className="max-md:hidden">
        <Row row={saved} />
      </div>
    </div>
  );
}
