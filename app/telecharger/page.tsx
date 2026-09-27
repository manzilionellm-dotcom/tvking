import type { Metadata } from "next";
import Link from "next/link";
import AppOnlyNotice from "../components/site/AppOnlyNotice";
import {
  ZUNO_ANDROID_PACKAGE_ID,
  zunoAndroidDownloadUrl,
} from "../lib/downloads-public";

export const metadata: Metadata = {
  title: "Télécharger",
  description:
    "Télécharger l'application Zuno. Nous ne vendons pas de chaînes — licence app uniquement.",
  alternates: { canonical: "https://zuno.7themotion.com/telecharger" },
};

const WIN_SETUP =
  process.env.NEXT_PUBLIC_ZUNO_DOWNLOAD_WINDOWS ||
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-windows/Zuno-Setup.exe";
const WIN_ZIP =
  process.env.NEXT_PUBLIC_ZUNO_DOWNLOAD_WINDOWS_ZIP ||
  "https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-windows/zuno-windows.zip";

export default function TelechargerPage() {
  const android = zunoAndroidDownloadUrl();
  const CARDS = [
    {
      title: "Box Android TV · Fire TV · Google TV",
      body: "Téléchargez le fichier Zuno (.aab), installez-le sur la box, ouvrez Zuno, notez votre M2, puis activez avec votre S code. L'app n'inclut aucune chaîne.",
      primary: { label: "Télécharger Zuno (Android)", href: android },
      note: `Package : ${ZUNO_ANDROID_PACKAGE_ID} · Astuce box : zuno.7themotion.com/apk`,
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
      primary: null as null,
      soon: true,
    },
  ];

  return (
    <div className="zuno-page mx-auto max-w-4xl px-4 py-14 sm:px-6">
      <h1 className="text-3xl font-bold text-white sm:text-4xl">Télécharger</h1>
      <p className="mt-3 text-white/50">
        Application Zuno uniquement — toujours la dernière version.
      </p>
      <div className="mx-auto mt-5 max-w-xl">
        <AppOnlyNotice variant="banner" />
      </div>
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
                <>
                  <a
                    href={c.primary!.href}
                    className="rounded-xl bg-gradient-to-r from-[#3b82f6] to-[#1d4ed8] px-4 py-2.5 text-sm font-semibold text-white"
                  >
                    {c.primary!.label}
                  </a>
                  {"secondary" in c && c.secondary ? (
                    <a
                      href={c.secondary.href}
                      className="rounded-xl border border-white/15 px-4 py-2.5 text-sm font-medium text-white/80"
                    >
                      {c.secondary.label}
                    </a>
                  ) : null}
                </>
              )}
            </div>
            {"note" in c && c.note ? (
              <p className="mt-3 text-xs text-white/35">{c.note}</p>
            ) : null}
          </div>
        ))}
      </div>
      <p className="mt-8 text-center text-sm text-white/40">
        Ensuite :{" "}
        <Link href="/activer" className="text-[#60a5fa]">
          activer (S code + M2)
        </Link>
      </p>
    </div>
  );
}
