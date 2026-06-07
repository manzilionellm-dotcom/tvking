"use client";

/*
 * Porte d'activation. Enveloppe toute l'app : tant que l'appareil n'est pas
 * activé (essai terminé, gelé ou banni), on n'affiche QUE l'écran de blocage —
 * les écrans chaînes / lecteur ne sont même pas montés. Voir activation.ts pour
 * la logique et device.ts pour le code (MAC virtuel).
 */

import { useEffect, useRef } from "react";
import { useActivation, refreshActivation, type ActivationState } from "../lib/activation";
import { useT } from "../lib/i18n";
import QrCode from "./QrCode";

// Titre/corps de l'écran de blocage selon l'état (clés i18n).
const LOCK_KEYS: Partial<Record<ActivationState, { title: string; body: string }>> = {
  expired: { title: "gate_expired_title", body: "gate_expired_body" },
  frozen: { title: "gate_frozen_title", body: "gate_frozen_body" },
  banned: { title: "gate_banned_title", body: "gate_banned_body" },
};

function Wordmark() {
  return (
    <div className="font-display text-[3rem] font-extrabold leading-none">
      <span className="text-[var(--text-high)]">NOVA</span>
      <span className="text-accent-grad">+</span>
    </div>
  );
}

/** Plein écran de chargement (le temps de la 1re vérification serveur). */
function Splash({ sub }: { sub: string }) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-[1.2rem] px-[var(--safe-x)] text-center">
      <Wordmark />
      <p className="text-[1.15rem] text-[var(--text-medium)]">{sub}</p>
    </div>
  );
}

function LockScreen({
  mac,
  state,
  offline,
}: {
  mac: string;
  state: ActivationState;
  offline: boolean;
}) {
  const t = useT();
  const keys = LOCK_KEYS[state] ?? LOCK_KEYS.expired!;
  const btnRef = useRef<HTMLButtonElement>(null);

  // La télécommande a besoin d'un point de départ : on focalise « Réessayer ».
  useEffect(() => {
    btnRef.current?.focus();
  }, []);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-[1.6rem] px-[var(--safe-x)] py-[var(--safe-y)] text-center">
      <Wordmark />

      <div className="max-w-[44rem]">
        <h1 className="mb-[0.6rem] font-display text-[2.4rem] font-extrabold text-[var(--text-high)]">
          {t(keys.title)}
        </h1>
        <p className="text-[1.2rem] leading-relaxed text-[var(--text-medium)]">{t(keys.body)}</p>
      </div>

      {/* Code d'activation de cet appareil — grand et lisible à 3 mètres,
          + QR pour le scanner au téléphone. */}
      <div className="flex flex-wrap items-center justify-center gap-[1.4rem]">
        <div className="rounded-[var(--radius-lg)] border border-[var(--hairline)] bg-[var(--surface-1)] px-[2rem] py-[1.3rem]">
          <p className="mb-[0.5rem] text-[0.95rem] font-semibold uppercase tracking-[0.18em] text-[var(--text-disabled)]">
            {t("gate_code_label")}
          </p>
          <p className="font-mono text-[2.4rem] font-bold tracking-[0.15em] text-accent-grad">{mac || "—"}</p>
        </div>
        {mac && <QrCode text={mac} size="11rem" />}
      </div>

      <button
        ref={btnRef}
        data-focusable
        onClick={() => void refreshActivation()}
        className="focusable rounded-[var(--radius)] px-[1.8rem] py-[0.9rem] text-[1.15rem] font-bold text-black"
        style={{ background: "var(--accent-grad)" }}
      >
        {t("gate_retry")}
      </button>

      <p className="max-w-[40rem] text-[0.95rem] text-[var(--text-disabled)]">
        {offline ? t("gate_offline_hint") : t("gate_auto_unlock")}
      </p>
    </div>
  );
}

function GateSplash() {
  const t = useT();
  return <Splash sub={t("gate_checking")} />;
}

export default function ActivationGate({ children }: { children: React.ReactNode }) {
  const { phase, activation } = useActivation();

  if (phase === "unlocked") return <>{children}</>;
  if (phase === "checking") return <GateSplash />;

  return (
    <LockScreen
      mac={activation?.mac ?? ""}
      state={activation?.state ?? "expired"}
      offline={activation?.offline ?? false}
    />
  );
}
