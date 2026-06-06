import FavoritesList from "../components/FavoritesList";

export const dynamic = "force-dynamic";

export default function FavoritesPage() {
  return (
    <div className="min-h-screen pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <h1 className="mb-[1.2rem] font-display text-[2.4rem] font-extrabold text-[var(--text-high)]">
        Favoris
      </h1>
      <FavoritesList />
    </div>
  );
}
