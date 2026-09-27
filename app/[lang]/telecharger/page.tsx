import type { Metadata } from "next";
import { APP_DOWNLOADS, SITE_HOST } from "../../lib/app-downloads";
import { fmt } from "../../i18n/messages";
import { pageI18n } from "../../i18n/server";

export async function generateMetadata({ params }: PageProps<"/[lang]/telecharger">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return {
    title: m.meta.downloadTitle,
    description: m.meta.downloadDescription,
    alternates: { canonical: `https://${SITE_HOST}/telecharger` },
  };
}

/*
 * Page « Télécharger » : une carte par appareil, un bouton principal par
 * carte, les étapes d'installation en dessous. Liens stables → toujours la
 * dernière version publiée (cf. app/lib/app-downloads.ts).
 */

type Card = {
  id: string;
  kicker: string;
  title: string;
  body: string;
  primary?: { label: string; href: string };
  secondary?: { label: string; href: string };
  steps: string[];
  note?: string;
};


export default async function DownloadPage({ params }: PageProps<"/[lang]/telecharger">) {
  const { m } = await pageI18n(params);
  const d = m.download;
  const CARDS: Card[] = [
    {
      id: "tv",
      kicker: d.tvKicker,
      title: d.tvTitle,
      body: d.tvBody,
      primary: { label: d.tvButton, href: APP_DOWNLOADS.tvApk },
      steps: [d.tvStep1, fmt(d.tvStep2, { url: `${SITE_HOST}/apk` }), d.tvStep3],
      note: d.tvNote,
    },
    {
      id: "pc",
      kicker: d.pcKicker,
      title: d.pcTitle,
      body: d.pcBody,
      primary: { label: d.pcButton, href: APP_DOWNLOADS.pcSetup },
      secondary: { label: d.pcZip, href: APP_DOWNLOADS.pcZip },
      steps: [d.pcStep1, d.pcStep2, d.pcStep3],
    },
    { id: "play", kicker: d.playKicker, title: d.playTitle, body: d.playBody, steps: [] },
  ];
  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <p className="text-[0.8rem] font-semibold uppercase tracking-[0.3em] text-[var(--text-medium)]">
        {d.kicker}
      </p>
      <h1 className="font-display mt-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        {d.title}
      </h1>
      <p className="mb-[2rem] mt-[0.4rem] max-w-[46rem] text-[1.3rem] text-[var(--text-medium)]">
        {d.intro}
      </p>

      <div className="grid max-w-[80rem] gap-[var(--gap)] md:grid-cols-3">
        {CARDS.map((c) => (
          <section
            key={c.id}
            aria-labelledby={`dl-${c.id}`}
            className="flex flex-col rounded-[var(--radius-lg)] border border-[var(--hairline)] bg-white/[0.03] p-[1.5rem]"
          >
            <span className="mb-[1rem] block h-[2px] w-[1.75rem] rounded-full bg-[var(--gold)]" />
            <p className="text-[0.75rem] font-semibold uppercase tracking-[0.18em] text-[var(--text-medium)]">
              {c.kicker}
            </p>
            <h2 id={`dl-${c.id}`} className="font-display mt-[0.3rem] text-[1.8rem] font-bold text-[var(--text-high)]">
              {c.title}
            </h2>
            <p className="mt-[0.5rem] text-[1rem] leading-relaxed text-[var(--text-medium)]">{c.body}</p>

            {c.primary && (
              <a
                href={c.primary.href}
                data-focusable
                data-cta={`download-${c.id}`}
                className="mt-[1.25rem] inline-flex items-center justify-center rounded-full px-[1.4rem] py-[0.8rem] text-[1rem] font-semibold text-black outline-none focus-visible:ring-4 focus-visible:ring-[var(--focus)]"
                style={{ background: "var(--gold-grad)" }}
              >
                {c.primary.label}
              </a>
            )}
            {c.secondary && (
              <a
                href={c.secondary.href}
                data-focusable
                className="mt-[0.6rem] inline-flex items-center justify-center rounded-full border border-[var(--hairline)] px-[1.4rem] py-[0.7rem] text-[0.95rem] font-semibold text-[var(--text-high)] outline-none focus-visible:ring-4 focus-visible:ring-[var(--focus)]"
              >
                {c.secondary.label}
              </a>
            )}

            {c.steps.length > 0 && (
              <ol className="mt-[1.25rem] list-decimal space-y-[0.4rem] pl-[1.2rem] text-[0.95rem] text-[var(--text-medium)]">
                {c.steps.map((s) => (
                  <li key={s}>{s}</li>
                ))}
              </ol>
            )}
            {c.note && <p className="mt-[0.9rem] text-[0.85rem] text-[var(--text-disabled)]">{c.note}</p>}
          </section>
        ))}
      </div>
    </div>
  );
}
