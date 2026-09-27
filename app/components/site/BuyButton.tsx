import { stripeHref } from "../../lib/plans";

export default function BuyButton({
  envKey,
  label = "Acheter",
}: {
  envKey: string;
  label?: string;
}) {
  const href = stripeHref(envKey);
  if (!href) {
    return (
      <span
        className="inline-flex w-full cursor-not-allowed items-center justify-center rounded-xl border border-white/15 bg-white/5 px-4 py-3 text-sm font-semibold text-white/45"
        title="Configurez le Payment Link Stripe dans les variables d'environnement"
      >
        Paiement bientôt
      </span>
    );
  }
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="zuno-cta inline-flex w-full items-center justify-center rounded-xl bg-gradient-to-r from-[#3b82f6] to-[#1d4ed8] px-4 py-3 text-sm font-semibold text-white shadow-[0_0_24px_rgba(59,130,246,0.35)] transition hover:brightness-110"
    >
      {label}
    </a>
  );
}
