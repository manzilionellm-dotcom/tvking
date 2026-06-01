import Row from "../components/Row";
import { homeRows } from "../lib/data";

/* "Ma liste" — investment surface (Hooked model): saved items the user has
   chosen, which personalises future recommendations. */
export default function ListPage() {
  const saved = { id: "saved", title: "Ma liste", items: homeRows.flatMap((r) => r.items).slice(0, 8) };
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Ma liste
      </h1>
      <Row row={saved} />
    </div>
  );
}
