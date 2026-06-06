"use client";

/*
 * Carte « Mon appareil » (Réglages). Montre le code d'activation (MAC virtuel)
 * et l'état courant, et permet de re-vérifier ou de régénérer le code.
 */

import { useState } from "react";
import { useActivation, refreshActivation, activationEnabled, type ActivationState } from "../lib/activation";
import { getDeviceMac, regenerateDeviceMac } from "../lib/device";

const STATE_LABEL: Record<ActivationState, string> = {
  active: "Activé",
  trial: "Essai en cours",
  expired: "Essai terminé",
  frozen: "Compte suspendu",
  banned: "Appareil bloqué",
  unknown: "Non vérifié",
};

function stateColor(s: ActivationState): string {
  if (s === "active" || s === "trial") return "var(--ok)";
  if (s === "unknown") return "var(--accent)";
  return "var(--live)";
}

export default function DeviceCard() {
  const { activation } = useActivation();
  // MAC affiché même avant la 1re réponse serveur (lecture directe locale).
  const [mac, setMac] = useState<string>(() => (typeof window !== "undefined" ? getDeviceMac() : ""));

  const state = activation?.state ?? "unknown";
  const enabled = activationEnabled();

  function onRegenerate() {
    if (
      !window.confirm(
        "Régénérer le code créera un NOUVEL appareil : l’activation actuelle sera perdue et il faudra réactiver ce nouveau code. Continuer ?",
      )
    )
      return;
    setMac(regenerateDeviceMac());
    void refreshActivation();
  }

  return (
    <div className="mt-[2rem] max-w-[52rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
      <h2 className="mb-[0.4rem] text-[1.3rem] font-bold text-[var(--text-high)]">Mon appareil</h2>
      <p className="mb-[1rem] text-[1rem] text-[var(--text-medium)]">
        Communiquez ce code à votre support pour activer NOVA+ à distance.
      </p>

      <div className="flex flex-col gap-[0.3rem]">
        <span className="text-[0.9rem] font-semibold uppercase tracking-[0.16em] text-[var(--text-disabled)]">
          Code d’activation
        </span>
        <span className="font-mono text-[1.7rem] font-bold tracking-[0.12em] text-accent-grad">{mac || "—"}</span>
      </div>

      <div className="mt-[0.9rem] flex items-center gap-[0.7rem]">
        <span className="h-[0.7rem] w-[0.7rem] rounded-full" style={{ background: stateColor(state) }} />
        <span className="text-[1.1rem] font-bold text-[var(--text-high)]">{STATE_LABEL[state]}</span>
        {(state === "trial" || state === "active") && activation && activation.daysLeft > 0 && !activation.paid && (
          <span className="text-[1rem] text-[var(--text-medium)]">· {activation.daysLeft} j restants</span>
        )}
        {activation?.offline && <span className="text-[0.95rem] text-[var(--text-disabled)]">· hors-ligne</span>}
      </div>

      {!enabled && (
        <p className="mt-[0.6rem] text-[0.9rem] text-[var(--text-disabled)]">
          Activation désactivée pour ce build.
        </p>
      )}

      <div className="mt-[1.1rem] flex flex-wrap gap-[0.8rem]">
        <button
          data-focusable
          onClick={() => void refreshActivation()}
          className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.3rem] py-[0.7rem] text-[1.05rem] font-semibold text-[var(--text-high)]"
        >
          Vérifier maintenant
        </button>
        <button
          data-focusable
          onClick={onRegenerate}
          className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.3rem] py-[0.7rem] text-[1.05rem] font-semibold text-[var(--text-medium)]"
        >
          Régénérer le code
        </button>
      </div>
    </div>
  );
}
