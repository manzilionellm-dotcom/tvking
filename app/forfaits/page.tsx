import type { Metadata } from "next";
import Link from "next/link";
import { PLANS } from "../lib/plans";
import BuyButton from "../components/site/BuyButton";
import AppOnlyNotice from "../components/site/AppOnlyNotice";

export const metadata: Metadata = {
  title: "Forfaits",
  description: "Licence app Zuno : 9,99 € / an ou 15 € à vie. Nous ne vendons pas de chaînes.",
};

export default function ForfaitsPage() {
  const plans = [PLANS.annual, PLANS.lifetime];
  return (
    <div className="zuno-page mx-auto max-w-5xl px-4 py-14 sm:px-6">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-white sm:text-4xl">Forfaits</h1>
        <p className="mt-3 text-white/50">Licence application uniquement — pas de chaînes ni de M3U. Paiement sécurisé via Stripe.</p>
        <div className="mx-auto mt-5 max-w-xl"><AppOnlyNotice variant="banner" /></div>
      </div>
      <div className="mt-10 grid gap-6 md:grid-cols-2">
        {plans.map((plan) => {
          const featured = "featured" in plan && plan.featured;
          return (
            <div
              key={plan.id}
              className={`relative flex flex-col rounded-2xl border p-6 sm:p-8 ${
                featured
                  ? "border-[#3b82f6]/50 bg-gradient-to-b from-[#1e3a8a]/25 to-white/[0.03] shadow-[0_0_48px_rgba(59,130,246,0.15)]"
                  : "border-white/10 bg-white/[0.03]"
              }`}
            >
              {featured && (
                <span className="absolute -top-3 left-6 rounded-full bg-[#2563eb] px-3 py-0.5 text-xs font-semibold text-white">
                  Recommandé
                </span>
              )}
              <h2 className="text-xl font-semibold text-white">{plan.name}</h2>
              <p className="mt-4 flex items-baseline gap-2">
                <span className="text-4xl font-bold tracking-tight text-white">{plan.priceLabel}</span>
                <span className="text-sm text-white/45">{plan.period}</span>
              </p>
              <p className="mt-3 flex-1 text-sm text-white/50">{plan.blurb}</p>
              <div className="mt-6">
                <BuyButton envKey={plan.envKey} label={`Acheter — ${plan.name}`} />
              </div>
            </div>
          );
        })}
      </div>
      <p className="mt-8 text-center text-sm text-white/40">
        Après paiement :{" "}
        <Link href="/activer" className="text-[#60a5fa] hover:underline">
          activez votre appareil
        </Link>{" "}
        puis{" "}
        <Link href="/telecharger" className="text-[#60a5fa] hover:underline">
          téléchargez Zuno
        </Link>
        .
      </p>
    </div>
  );
}
