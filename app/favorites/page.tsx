"use client";

import FavoritesList from "../components/FavoritesList";
import { useT } from "../lib/i18n";

export default function FavoritesPage() {
  const t = useT();
  return (
    <div className="min-h-screen pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <h1 className="mb-[1.2rem] font-display text-[2.4rem] font-extrabold text-[var(--text-high)]">
        {t("nav_favorites")}
      </h1>
      <FavoritesList />
    </div>
  );
}
