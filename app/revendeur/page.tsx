"use client";

import Link from "next/link";
import { zunoWaUrl } from "../lib/wa";

const PERKS = [
  { title: "Revendre les forfaits", body: "Proposez Annuel 9,99 € et À vie 15 € à vos clients." },
  { title: "Activation rapide", body: "Activez les appareils de vos clients via MAC + code." },
  { title: "Suivi", body: "Tableau de stats (aperçu) — volume, activations, statut." },
];

export default function RevendeurPage() {
  return (
    <div className="zuno-page mx-auto max-w-4xl px-4 py-14 sm:px-6">
      <div className="text-center">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-[#93c5fd]">Partenaires</p>
        <h1 className="mt-2 text-3xl font-bold text-white sm:text-4xl">Devenir revendeur</h1>
        <p className="mx-auto mt-3 max-w-xl text-white/50">
          Accès revendeur Zuno : revendez les forfaits, activez les appareils, suivez votre activité.
        </p>
      </div>

      <div className="mt-10 grid gap-4 md:grid-cols-3">
        {PERKS.map((p) => (
          <div key={p.title} className="rounded-2xl border border-white/10 bg-white/[0.03] p-5">
            <h2 className="font-semibold text-white">{p.title}</h2>
            <p className="mt-2 text-sm text-white/50">{p.body}</p>
          </div>
        ))}
      </div>

      <div className="zuno-card mt-10 rounded-2xl border border-[#3b82f6]/25 bg-gradient-to-b from-[#1e3a8a]/20 to-transparent p-6">
        <h2 className="text-lg font-semibold text-white">Aperçu stats (stub)</h2>
        <div className="mt-4 grid grid-cols-3 gap-3 text-center">
          {[
            ["—", "Ventes"],
            ["—", "Activations"],
            ["—", "Clients"],
          ].map(([v, l]) => (
            <div key={l} className="rounded-xl border border-white/10 bg-black/30 py-4">
              <p className="text-2xl font-bold text-white/80">{v}</p>
              <p className="text-xs text-white/40">{l}</p>
            </div>
          ))}
        </div>
        <p className="mt-3 text-xs text-white/35">
          Interface premium préparée — les chiffres réels seront branchés après onboarding revendeur.
        </p>
      </div>

      <div className="mt-8 flex flex-col items-center gap-3">
        <a
          href={zunoWaUrl("revendeur")}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center justify-center rounded-xl bg-[#25D366] px-6 py-3.5 text-sm font-semibold text-white shadow-[0_0_28px_rgba(37,211,102,0.35)]"
        >
          Continuer sur WhatsApp
        </a>
        <Link href="/forfaits" className="text-sm text-white/45 hover:text-white/70">
          Voir les forfaits clients
        </Link>
      </div>
    </div>
  );
}
