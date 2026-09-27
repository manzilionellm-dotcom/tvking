import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Télécharger",
  description: "Télécharger Zuno pour Android TV, Fire TV, Google TV et Windows.",
  alternates: { canonical: "https://zuno.7themotion.com/telecharger" },
};

const APK =
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/zuno-tv.apk";
const WIN_SETUP =
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-windows/Zuno-Setup.exe";
const WIN_ZIP =
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-windows/zuno-windows.zip";

const CARDS = [
  {
    title: "Box Android TV · Fire TV · Google TV",
    body: "Installez l'APK, ouvrez Zuno, notez l'adresse MAC affichée, puis activez.",
    primary: { label: "Télécharger pour la box (APK)", href: APK },
    note: "Astuce box : zuno.7themotion.com/apk",
  },
  {
    title: "Windows 10 / 11 · 64 bits",
    body: "Lancez Zuno-Setup.exe. Si Windows affiche « Éditeur inconnu » : Informations complémentaires → Exécuter quand même.",
    primary: { label: "Télécharger pour Windows", href: WIN_SETUP },
    secondary: { label: "Archive ZIP", href: WIN_ZIP },
  },
  {
    title: "Google Play · Android TV",
    body: "Publication Play Store en cours.",
    primary: null,
    soon: true,
  },
];

export default function TelechargerPage() {
  return (
    <div className="zuno-page mx-auto max-w-4xl px-4 py-14 sm:px-6">
      <h1 className="text-3xl font-bold text-white sm:text-4xl">Télécharger</h1>
      <p className="mt-3 text-white/50">Application Zuno — toujours la dernière version.</p>
      <div className="mt-10 grid gap-5">
        {CARDS.map((c) => (
          <div key={c.title} className="rounded-2xl border border-white/10 bg-white/[0.03] p-6">
            <h2 className="text-lg font-semibold text-white">{c.title}</h2>
            <p className="mt-2 text-sm text-white/50">{c.body}</p>
            <div className="mt-4 flex flex-wrap gap-3">
              {c.soon ? (
                <span className="rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-white/40">
                  Google Play · bientôt
                </span>
              ) : (
                c.primary && (
                  <a
                    href={c.primary.href}
                    className="rounded-xl bg-[#2563eb] px-4 py-2.5 text-sm font-semibold text-white"
                  >
                    {c.primary.label}
                  </a>
                )
              )}
              {"secondary" in c && c.secondary && (
                <a
                  href={c.secondary.href}
                  className="rounded-xl border border-white/15 px-4 py-2.5 text-sm text-white/70"
                >
                  {c.secondary.label}
                </a>
              )}
            </div>
            {"note" in c && c.note && (
              <p className="mt-3 text-xs text-white/35">{c.note}</p>
            )}
          </div>
        ))}
      </div>
      <p className="mt-8 text-sm text-white/40">
        Pas encore activé ?{" "}
        <Link href="/activer" className="text-[#60a5fa] hover:underline">
          Activer mon appareil
        </Link>
      </p>
    </div>
  );
}
