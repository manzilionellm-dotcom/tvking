"use client";

/*
 * Bandeau d'essai — transparence "premium". Affiché discrètement pendant la
 * période d'essai (jamais quand l'appareil est payé/activé, ni sur le lecteur
 * plein écran). Rappelle le nombre de jours restants et où trouver le code.
 */

import { useState } from "react";
import { usePathname } from "next/navigation";
import { useActivation } from "../lib/activation";
import { useT } from "../lib/i18n";

export default function TrialBanner() {
  const { activation } = useActivation();
  const pathname = usePathname();
  const t = useT();
  const [dismissed, setDismissed] = useState(false);

  // Discret : seulement en essai réel (non payé, jours restants connus),
  // hors lecteur plein écran, et tant qu'on ne l'a pas fermé.
  if (
    dismissed ||
    !activation ||
    activation.paid ||
    activation.state !== "trial" ||
    activation.daysLeft <= 0 ||
    pathname?.startsWith("/watch")
  ) {
    return null;
  }

  const d = activation.daysLeft;
  return (
    <div className="pointer-events-none fixed inset-x-0 top-0 z-[40] flex justify-center px-[var(--safe-x)] pt-[calc(var(--safe-y)*0.5)]">
      <div className="pointer-events-auto flex items-center gap-[0.8rem] rounded-full border border-[var(--hairline)] bg-[var(--surface-2)]/92 px-[1.1rem] py-[0.45rem] backdrop-blur">
        <span className="h-[0.55rem] w-[0.55rem] rounded-full" style={{ background: "var(--accent)" }} />
        <span className="text-[0.95rem] font-semibold text-[var(--text-high)]">{t("trial_banner", { n: d })}</span>
        <span className="text-[0.9rem] text-[var(--text-medium)]">· {t("trial_activate_hint")}</span>
        <button
          data-focusable
          onClick={() => setDismissed(true)}
          aria-label="✕"
          className="focusable ml-[0.3rem] rounded-full px-[0.6rem] py-[0.15rem] text-[1rem] font-bold text-[var(--text-medium)]"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
