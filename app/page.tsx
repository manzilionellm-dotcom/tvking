import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Zuno — TV, films & multi-appareils",
  description:
    "Zuno : TV en direct, films et séries, sur box Android TV, Fire TV, Google TV et Windows. Forfaits simples.",
};

const BENEFITS = [
  {
    title: "TV en direct",
    body: "Retrouvez vos chaînes sur grand écran, avec une interface pensée pour la télécommande.",
    icon: "📺",
  },
  {
    title: "Films & séries",
    body: "Parcourez et lancez vos contenus VOD dans une expérience sombre, fluide et premium.",
    icon: "🎬",
  },
  {
    title: "Multi-appareils",
    body: "Box Android TV, Fire TV, Google TV et PC Windows — une app, plusieurs écrans.",
    icon: "📱",
  },
];

export default function HomePage() {
  return (
    <div className="zuno-page">
      <section className="relative overflow-hidden px-4 pb-20 pt-16 sm:px-6 sm:pt-24">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,_rgba(59,130,246,0.18),_transparent_55%)]" />
        <div className="pointer-events-none absolute -right-24 top-10 h-72 w-72 rounded-full bg-[#3b82f6]/10 blur-3xl" />
        <div className="relative mx-auto max-w-4xl text-center">
          <p className="zuno-fade-in mb-4 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-[#93c5fd]">
            Zuno
          </p>
          <h1 className="zuno-slide-up text-4xl font-bold tracking-tight text-white sm:text-5xl md:text-6xl">
            Votre TV,{" "}
            <span className="bg-gradient-to-r from-[#93c5fd] to-[#3b82f6] bg-clip-text text-transparent">
              simplement
            </span>
          </h1>
          <p className="zuno-slide-up mx-auto mt-5 max-w-2xl text-base text-white/60 sm:text-lg" style={{ animationDelay: "80ms" }}>
            Lecteur premium pour box et PC. Choisissez un forfait, activez votre
            appareil, téléchargez l&apos;application.
          </p>
          <div className="zuno-slide-up mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row" style={{ animationDelay: "140ms" }}>
            <Link
              href="/forfaits"
              className="zuno-cta inline-flex min-w-[12rem] items-center justify-center rounded-xl bg-gradient-to-r from-[#3b82f6] to-[#1d4ed8] px-6 py-3.5 text-sm font-semibold text-white shadow-[0_0_32px_rgba(59,130,246,0.4)]"
            >
              Voir les forfaits
            </Link>
            <Link
              href="/telecharger"
              className="inline-flex min-w-[12rem] items-center justify-center rounded-xl border border-white/15 bg-white/5 px-6 py-3.5 text-sm font-semibold text-white/90 transition hover:bg-white/10"
            >
              Télécharger
            </Link>
          </div>
          <p className="mt-6 text-xs text-white/35">
            Tunnel : Accueil → Forfaits → Paiement → Activer → Télécharger
          </p>
        </div>
      </section>

      <section className="mx-auto grid max-w-6xl gap-4 px-4 pb-20 sm:px-6 md:grid-cols-3">
        {BENEFITS.map((b, i) => (
          <div
            key={b.title}
            className="zuno-card rounded-2xl border border-white/10 bg-white/[0.03] p-6 transition hover:border-[#3b82f6]/30 hover:bg-white/[0.05]"
            style={{ animationDelay: `${i * 60}ms` }}
          >
            <div className="mb-3 text-2xl">{b.icon}</div>
            <h2 className="text-lg font-semibold text-white">{b.title}</h2>
            <p className="mt-2 text-sm leading-relaxed text-white/50">{b.body}</p>
          </div>
        ))}
      </section>

      <section className="border-t border-white/5 bg-[#070709] px-4 py-16 sm:px-6">
        <div className="mx-auto flex max-w-4xl flex-col items-center gap-4 text-center">
          <h2 className="text-2xl font-bold text-white">Prêt à commencer ?</h2>
          <p className="text-sm text-white/50">
            Annuel <strong className="text-white/80">9,99 € / an</strong> · À vie{" "}
            <strong className="text-white/80">15 €</strong>
          </p>
          <div className="flex flex-wrap justify-center gap-3">
            <Link href="/forfaits" className="rounded-xl bg-[#2563eb] px-5 py-3 text-sm font-semibold text-white">
              Choisir un forfait
            </Link>
            <Link href="/activer" className="rounded-xl border border-white/15 px-5 py-3 text-sm font-medium text-white/80">
              Activer mon appareil
            </Link>
          </div>
        </div>
      </section>
    </div>
  );
}
