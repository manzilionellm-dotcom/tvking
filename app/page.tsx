import Link from "next/link";
import ChannelBrowser from "./components/ChannelBrowser";
import { getBrowseView } from "./lib/server-views";

// Live data depends on the user's configured source, so render per request.
export const dynamic = "force-dynamic";

export default async function Home() {
  const { groups, nowNext, total, error } = await getBrowseView();

  if (total === 0) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-[1.2rem] pl-[6.5rem] pr-[var(--safe-x)] text-center">
        <h1 className="font-display text-[2.6rem] font-extrabold">
          <span className="text-accent-grad">NOVA</span>
          <span className="text-[var(--accent)]">+</span>
        </h1>
        <p className="max-w-[40rem] text-[1.2rem] text-[var(--text-medium)]">
          Aucune chaîne chargée. Ajoutez l’URL de votre playlist (M3U ou Xtream) et,
          si vous en avez une, votre guide XMLTV.
        </p>
        {error && (
          <p className="text-[1rem] text-[var(--live)]">Erreur de chargement : {error}</p>
        )}
        <Link
          href="/settings"
          data-focusable
          className="focusable rounded-[var(--radius)] px-[1.6rem] py-[0.9rem] text-[1.15rem] font-bold text-black"
          style={{ background: "var(--accent-grad)" }}
        >
          Configurer ma source
        </Link>
      </div>
    );
  }

  return <ChannelBrowser groups={groups} nowNext={nowNext} />;
}
