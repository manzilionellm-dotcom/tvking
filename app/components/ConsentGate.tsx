"use client";

import { useState, useSyncExternalStore } from "react";
import { accept, isAccepted, loadConsent, saveConsent } from "../lib/consent";

/*
 * Conditions d'utilisation — shown full-screen at first launch (and again if
 * the terms version is bumped). Nothing behind the gate is usable until the
 * user explicitly accepts: TV King is a player, it ships no content, and the
 * links / playlists belong to the user, who must hold the rights to them.
 */

const TERMS: { title: string; body: string }[] = [
  {
    title: "TV King ne fournit aucun contenu",
    body: "L'application est un lecteur multimédia. Elle n'héberge, ne diffuse et ne vend aucune chaîne, aucun film, aucun flux. Aucun contenu n'est inclus à l'installation.",
  },
  {
    title: "Vos liens, votre responsabilité",
    body: "Les playlists (M3U) et les liens que vous ajoutez proviennent de vous. Vous déclarez détenir les droits ou autorisations nécessaires pour les contenus auxquels ils mènent, conformément aux lois de votre pays.",
  },
  {
    title: "Chaque lien est vérifié avant lecture",
    body: "Pour une expérience sans souci, chaque lien ajouté est contrôlé (format et disponibilité) avant d'être proposé à la lecture. Un lien invalide est signalé clairement — jamais d'attente sans fin.",
  },
  {
    title: "Lecture instantanée, jamais de roue qui tourne",
    body: "Les films disponibles se préchargent sur l'appareil pour démarrer immédiatement. Si un contenu ne peut pas être lu, l'application l'annonce tout de suite au lieu de faire patienter.",
  },
];

/* The consent store only changes through this gate, never underneath it. */
const noSubscription = () => () => {};

export default function ConsentGate() {
  // Hydration-safe read: the server snapshot says "accepted" so the static
  // HTML never flashes the gate; the client corrects right after mount.
  const stored = useSyncExternalStore(
    noSubscription,
    () => isAccepted(loadConsent()),
    () => true
  );
  const [justAccepted, setJustAccepted] = useState(false);
  const [refused, setRefused] = useState(false);

  if (stored || justAccepted) return null;

  const doAccept = () => {
    saveConsent(accept(Date.now()));
    setJustAccepted(true);
  };

  return (
    <div
      data-focus-scope
      role="dialog"
      aria-modal="true"
      aria-label="Conditions d'utilisation"
      className="fixed inset-0 z-[100] flex items-center justify-center overflow-y-auto bg-[var(--bg)]/97 p-[1.5rem] backdrop-blur-sm"
    >
      <div className="w-full max-w-[46rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[2rem] shadow-2xl ring-1 ring-[var(--hairline)]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.25em] text-[var(--gold)]">
          Bienvenue sur
        </p>
        <h1 className="font-display text-gold-grad mb-[0.4rem] text-[2.6rem] font-extrabold tracking-tight">
          TV King
        </h1>
        <p className="mb-[1.4rem] text-[1.25rem] text-[var(--text-medium)]">
          Avant d&apos;entrer, merci de lire et d&apos;accepter les conditions d&apos;utilisation.
        </p>

        <ol className="mb-[1.6rem] flex flex-col gap-[1rem]">
          {TERMS.map((t, i) => (
            <li key={t.title} className="flex gap-[1rem] rounded-[var(--radius)] bg-[var(--surface-2)] p-[1rem]">
              <span className="text-[1.3rem] font-bold tabular-nums text-[var(--gold)]">
                {String(i + 1).padStart(2, "0")}
              </span>
              <span>
                <span className="block text-[1.2rem] font-bold text-[var(--text-high)]">{t.title}</span>
                <span className="block text-[1.05rem] leading-snug text-[var(--text-medium)]">{t.body}</span>
              </span>
            </li>
          ))}
        </ol>

        {refused && (
          <p className="mb-[1rem] rounded-[var(--radius)] bg-[var(--live)]/15 px-[1rem] py-[0.7rem] text-[1.1rem] font-semibold text-[var(--live)]">
            Sans acceptation des conditions, TV King ne peut pas être utilisé.
          </p>
        )}

        <div className="flex flex-wrap gap-[0.9rem]">
          <button
            data-focusable
            data-focus-default
            onClick={doAccept}
            className="focusable flex-1 rounded-[var(--radius)] px-[1.6rem] py-[0.9rem] text-[1.25rem] font-bold text-black shadow-[0_0.6rem_1.6rem_rgba(227,185,107,0.35)]"
            style={{ background: "var(--gold-grad)" }}
          >
            J&apos;accepte les conditions
          </button>
          <button
            data-focusable
            onClick={() => setRefused(true)}
            className="focusable rounded-[var(--radius)] bg-white/10 px-[1.4rem] py-[0.9rem] text-[1.2rem] font-semibold text-[var(--text-medium)]"
          >
            Refuser
          </button>
        </div>
      </div>
    </div>
  );
}
