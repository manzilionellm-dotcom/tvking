import type { Metadata } from "next";

const NUMBER =
  process.env.NEXT_PUBLIC_WHATSAPP_TVKING ||
  process.env.NEXT_PUBLIC_WHATSAPP_PHONE ||
  "447307410512";

const PREFILL = "TV King — 24h trial. City + device";
const HREF = `https://wa.me/${NUMBER}?text=${encodeURIComponent(PREFILL)}`;

export const metadata: Metadata = {
  title: "TV King — start a 24h trial",
  description: "Same WhatsApp number as the other brands. City + device. 24h trial, no card.",
  alternates: { canonical: "https://tvking.vercel.app/start" },
};

export default function StartPage() {
  return (
    <div className="mx-auto max-w-xl px-5 py-16 text-[var(--fg,#f5f5f5)]">
      <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[#888]">TV King</p>
      <h1 className="mt-3 font-[var(--font-display)] text-4xl font-bold">Start on WhatsApp</h1>
      <p className="mt-4 text-lg text-[#bbb]">
        One number for every brand: +44 7307 410512. Tell us city + device. 24h trial, no card.
        Keep this chat on TV King — do not mix a USA or Mzansi login in this thread.
      </p>
      <a
        href={HREF}
        target="_blank"
        rel="noopener noreferrer"
        data-cta="start"
        className="mt-8 inline-flex rounded-full bg-[#25D366] px-6 py-3 text-sm font-semibold text-white"
      >
        Message TV King
      </a>
      <ul className="mt-10 space-y-2 text-sm text-[#bbb]">
        <li>Prefill: {PREFILL}</li>
        <li>Player + playlists stay on the home screen. This page is the checkout door.</li>
        <li>No invented reviews. No official league claims.</li>
      </ul>
    </div>
  );
}
