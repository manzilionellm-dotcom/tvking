import SearchClient from "../components/SearchClient";

/*
 * Search stays browse-first (suggestion chips before typing), but it now
 * actually searches the catalogue — the previous screen only *looked* like a
 * search field.
 */
export default function SearchPage() {
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Rechercher
      </h1>
      <SearchClient />
    </div>
  );
}
