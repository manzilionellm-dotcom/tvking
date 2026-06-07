"use client";

// =========================================================
//  TrialBadge.tsx — Indicateur discret d'essai en cours
// =========================================================
//  Pendant l'essai (ni payé, ni bloqué), un petit repère en haut à droite
//  rappelle les jours restants. Non focusable (simple information).
// =========================================================

import { isOnTrial } from "../lib/license";
import { useLicense } from "./LicenseProvider";

export function TrialBadge() {
  const { status } = useLicense();
  if (!isOnTrial(status)) return null;

  const d = status.daysLeft;
  const label = d <= 1 ? "Dernier jour d'essai" : `Essai : ${d} jours`;

  return (
    <div
      role="note"
      aria-label={label}
      style={{
        position: "fixed",
        top: "calc(var(--safe-y) / 2)",
        right: "calc(var(--safe-x) / 2)",
        zIndex: 28,
        padding: "0.4rem 0.9rem",
        borderRadius: "999px",
        fontSize: "0.95rem",
        fontWeight: 700,
        color: "#1a1300",
        background: "var(--gold-grad)",
        boxShadow: "0 0.4rem 1rem rgba(0,0,0,0.4)",
        pointerEvents: "none",
      }}
    >
      ⏳ {label}
    </div>
  );
}
