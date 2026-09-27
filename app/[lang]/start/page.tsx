import type { Metadata } from "next";
import { SITE_URL } from "../../lib/app-downloads";
import { fmt } from "../../i18n/messages";
import { pageI18n } from "../../i18n/server";

const NUMBER =
  process.env.NEXT_PUBLIC_WHATSAPP_TVKING ||
  process.env.NEXT_PUBLIC_WHATSAPP_PHONE ||
  "447307410512";

export async function generateMetadata({ params }: PageProps<"/[lang]/start">): Promise<Metadata> {
  const { m } = await pageI18n(params);
  return {
    title: m.meta.startTitle,
    description: m.meta.startDescription,
    alternates: { canonical: `${SITE_URL}/start` },
  };
}

export default async function StartPage({ params }: PageProps<"/[lang]/start">) {
  const { m } = await pageI18n(params);
  const prefill = m.whatsapp.prefill;
  const href = `https://wa.me/${NUMBER}?text=${encodeURIComponent(prefill)}`;
  return (
    <div className="mx-auto max-w-xl px-5 py-16 text-[var(--fg,#f5f5f5)]">
      <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[#888]">TV King</p>
      <h1 className="mt-3 font-[var(--font-display)] text-4xl font-bold">{m.start.title}</h1>
      <p className="mt-4 text-lg text-[#bbb]">{m.start.body}</p>
      <a
        href={href}
        target="_blank"
        rel="noopener noreferrer"
        data-cta="start"
        className="mt-8 inline-flex rounded-full bg-[#25D366] px-6 py-3 text-sm font-semibold text-white"
      >
        {m.start.cta}
      </a>
      <ul className="mt-10 space-y-2 text-sm text-[#bbb]">
        <li>{fmt(m.start.prefillLabel, { text: prefill })}</li>
        <li>{m.start.note}</li>
      </ul>
    </div>
  );
}
