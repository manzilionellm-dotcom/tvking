import ChannelSearch from "../components/ChannelSearch";

export default function SearchPage() {
  return (
    <div className="min-h-screen pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <h1 className="mb-[1.4rem] font-display text-[2.4rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Rechercher une chaîne
      </h1>
      <ChannelSearch />
    </div>
  );
}
