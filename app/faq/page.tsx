import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "FAQ",
  description: "Questions fréquentes Zuno : activation, appareils, paiement, contact.",
};

const FAQS = [
  {
    q: "Comment activer mon appareil ?",
    a: "Après paiement, ouvrez Activer, saisissez l'adresse MAC affichée dans Zuno (Réglages → Mon appareil) et votre code d'activation.",
  },
  {
    q: "Quels appareils sont supportés ?",
    a: "Box Android TV, Amazon Fire TV, Google TV, et PC Windows 10/11 64 bits. Google Play arrive bientôt.",
  },
  {
    q: "Quels sont les forfaits ?",
    a: "Annuel à 9,99 € / an, ou À vie à 15 € (paiement unique). Paiement via Stripe.",
  },
  {
    q: "Le paiement est-il sécurisé ?",
    a: "Oui. Le checkout est géré par Stripe Payment Links. Zuno ne stocke pas vos données de carte.",
  },
  {
    q: "Comment contacter le support ?",
    a: "Utilisez le bouton WhatsApp flottant (Concierge) ou écrivez via wa.me. Choisissez Activer, Revendeur ou Support.",
  },
  {
    q: "Puis-je devenir revendeur ?",
    a: "Oui — voir la page Devenir revendeur, puis finalisez sur WhatsApp.",
  },
];

export default function FaqPage() {
  return (
    <div className="zuno-page mx-auto max-w-3xl px-4 py-14 sm:px-6">
      <h1 className="text-3xl font-bold text-white">FAQ</h1>
      <div className="mt-8 space-y-3">
        {FAQS.map((f) => (
          <details
            key={f.q}
            className="group rounded-2xl border border-white/10 bg-white/[0.03] px-5 py-4 open:border-[#3b82f6]/30"
          >
            <summary className="cursor-pointer list-none text-base font-medium text-white marker:content-none">
              <span className="flex items-center justify-between gap-3">
                {f.q}
                <span className="text-white/30 transition group-open:rotate-45">+</span>
              </span>
            </summary>
            <p className="mt-3 text-sm leading-relaxed text-white/55">{f.a}</p>
          </details>
        ))}
      </div>
      <p className="mt-8 text-sm text-white/40">
        Voir aussi{" "}
        <Link href="/legal" className="text-[#60a5fa]">
          mentions légales
        </Link>
        .
      </p>
    </div>
  );
}
