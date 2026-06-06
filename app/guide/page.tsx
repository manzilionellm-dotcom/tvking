import Link from "next/link";
import GuideGrid from "../components/GuideGrid";
import { getGuideView } from "../lib/server-views";

export const dynamic = "force-dynamic";

export default async function GuidePage() {
  const { rows, windowStart, windowEnd, now, hasEpg, total } = await getGuideView();

  return (
    <div className="min-h-screen pl-[6.5rem] pr-[var(--safe-x)] py-[var(--safe-y)]">
      <div className="mb-[1.2rem] flex items-baseline gap-[0.9rem]">
        <h1 className="font-display text-[2.4rem] font-extrabold text-[var(--text-high)]">Guide TV</h1>
        <span className="text-[1rem] text-[var(--text-medium)]">{total} chaînes</span>
      </div>

      {total === 0 ? (
        <p className="text-[1.1rem] text-[var(--text-medium)]">
          Aucune chaîne. Configurez votre source dans{" "}
          <Link href="/settings" className="text-[var(--accent)] underline">Réglages</Link>.
        </p>
      ) : !hasEpg ? (
        <div className="max-w-[44rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.4rem]">
          <p className="text-[1.15rem] text-[var(--text-high)]">Pas de guide (EPG) chargé.</p>
          <p className="mt-[0.5rem] text-[1.05rem] text-[var(--text-medium)]">
            Ajoutez l’URL XMLTV de votre fournisseur dans{" "}
            <Link href="/settings" className="text-[var(--accent)] underline">Réglages</Link>{" "}
            pour afficher les programmes en cours et à venir.
          </p>
        </div>
      ) : (
        <GuideGrid rows={rows} windowStart={windowStart} windowEnd={windowEnd} now={now} />
      )}
    </div>
  );
}
