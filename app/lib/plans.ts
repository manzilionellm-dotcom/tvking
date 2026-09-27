/** Confirmed Zuno commerce prices — do not invent other tiers. */
export const PLANS = {
  annual: {
    id: "annual",
    name: "Annuel",
    priceLabel: "9,99 €",
    period: "/ an",
    blurb: "Accès Zuno pendant 12 mois. Renouvellement manuel.",
    envKey: "NEXT_PUBLIC_STRIPE_PAYMENT_LINK_ANNUAL",
  },
  lifetime: {
    id: "lifetime",
    name: "À vie",
    priceLabel: "15 €",
    period: "paiement unique",
    blurb: "Accès Zuno à vie. Un seul paiement, sans abonnement.",
    envKey: "NEXT_PUBLIC_STRIPE_PAYMENT_LINK_LIFETIME",
    featured: true,
  },
} as const;

export type PlanId = keyof typeof PLANS;

export function stripeHref(envKey: string): string | null {
  const v =
    typeof process !== "undefined"
      ? process.env[envKey] || process.env[envKey.replace("NEXT_PUBLIC_", "")]
      : undefined;
  if (!v || v === "#" || v.trim() === "") return null;
  return v;
}
