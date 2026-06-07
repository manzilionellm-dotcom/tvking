"use client";

import ChannelSearch from "../components/ChannelSearch";
import { useT } from "../lib/i18n";

export default function SearchPage() {
  const t = useT();
  return (
    /* Champ de saisie présent : on dégage la largeur du menu déployé (15rem)
       pour qu'il ne recouvre pas la recherche au focus. */
    <div className="min-h-screen pl-[16rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <h1 className="mb-[1.4rem] font-display text-[2.4rem] font-extrabold tracking-tight text-[var(--text-high)]">
        {t("search_title")}
      </h1>
      <ChannelSearch />
    </div>
  );
}
