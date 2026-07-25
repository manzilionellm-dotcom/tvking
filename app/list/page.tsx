import CollectionsView from "../components/CollectionsView";

/* "Ma liste" — investment surface (Hooked model): the items the viewer chose to
   keep, plus the upcoming events they asked to be reminded of. Both come from
   the persisted collections, so the page shows reality (or says it is empty)
   instead of borrowing the first cards of the home page. */
export default function ListPage() {
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Ma liste
      </h1>
      <CollectionsView />
    </div>
  );
}
