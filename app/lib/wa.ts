const DEFAULT_WA = "https://wa.me/447307410512";

export function zunoWaBase(): string {
  const raw =
    process.env.NEXT_PUBLIC_ZUNO_WA ||
    process.env.NEXT_PUBLIC_WHATSAPP_URL ||
    DEFAULT_WA;
  return raw.replace(/\/$/, "");
}

export type WaBranch = "activation" | "revendeur" | "support";

const PREFILLS: Record<WaBranch, string> = {
  activation:
    "Bonjour Zuno — je souhaite activer mon appareil (MAC / code).",
  revendeur: "Bonjour Zuno — je souhaite devenir revendeur.",
  support: "Bonjour Zuno — j'ai besoin d'assistance.",
};

export function zunoWaUrl(branch: WaBranch, extra?: string): string {
  const text = extra ? `${PREFILLS[branch]} ${extra}` : PREFILLS[branch];
  return `${zunoWaBase()}?text=${encodeURIComponent(text)}`;
}
