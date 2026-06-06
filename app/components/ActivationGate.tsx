"use client";

/*
 * Porte d'activation. Enveloppe toute l'app : tant que l'appareil n'est pas
 * activé (essai terminé, gelé ou banni), on n'affiche QUE l'écran de blocage —
 * les écrans chaînes / lecteur ne sont même pas montés. Voir activation.ts pour
 * la logique et device.ts pour le code (MAC virtuel).
 */

import { useEffect, useRef } from "react";
import { useActivation, refreshActivation, type ActivationState } from "../lib/activation";
import QrCode from "./QrCode";

const LOCK_COPY: Partial<Record<ActivationState, { title: string; body: string }>> = {
  expired: {
    title: "Essai terminé",
    body: "Votre période d’essai NOVA+ est terminée. Communiquez le code ci-dessous à votre support pour activer cet appareil.",
  },
  frozen: {
    title: "Compte suspendu",
    body: "Votre accès NOVA+ est temporairement suspendu. Communiquez le code ci-dessous à votre support pour le réactiver.",
  },
  banned: {
    title: "Appareil bloqué",
    body: "Cet appareil a été bloqué. Contactez votre support en indiquant le code ci-dessous.",
  },
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
  const copy = LOCK_COPY[state] ?? LOCK_COPY.expired!;
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
          {copy.title}
        </h1>
        <p className="text-[1.2rem] leading-relaxed text-[var(--text-medium)]">{copy.body}</p>
      </div>

      {/* Code d'activation de cet appareil — grand et lisible à 3 mètres,
          + QR pour le scanner au téléphone. */}
      <div className="flex flex-wrap items-center justify-center gap-[1.4rem]">
        <div className="rounded-[var(--radius-lg)] border border-[var(--hairline)] bg-[var(--surface-1)] px-[2rem] py-[1.3rem]">
          <p className="mb-[0.5rem] text-[0.95rem] font-semibold uppercase tracking-[0.18em] text-[var(--text-disabled)]">
            Code d’activation de cet appareil
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
        Réessayer
      </button>

      <p className="max-w-[40rem] text-[0.95rem] text-[var(--text-disabled)]">
        {offline
          ? "Connexion au serveur impossible — vérifiez le réseau, puis Réessayer."
          : "Cet écran se déverrouille automatiquement dès que votre appareil est activé."}
      </p>
    </div>
  );
}

export default function ActivationGate({ children }: { children: React.ReactNode }) {
  const { phase, activation } = useActivation();

  if (phase === "unlocked") return <>{children}</>;
  if (phase === "checking") return <Splash sub="Vérification de l’activation…" />;

  return (
    <LockScreen
      mac={activation?.mac ?? ""}
      state={activation?.state ?? "expired"}
      offline={activation?.offline ?? false}
    />
  );
}
