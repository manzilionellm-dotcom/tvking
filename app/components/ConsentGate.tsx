"use client";

import { useState, useSyncExternalStore } from "react";
import { accept, isAccepted, loadConsent, saveConsent } from "../lib/consent";
import { useI18n } from "../i18n/provider";

/*
 * Conditions d'utilisation — shown full-screen at first launch (and again if
 * the terms version is bumped). Nothing behind the gate is usable until the
 * user explicitly accepts: TV King is a player, it ships no content, and the
 * links / playlists belong to the user, who must hold the rights to them.
 */


/* The consent store only changes through this gate, never underneath it. */
const noSubscription = () => () => {};

export default function ConsentGate() {
  const { m } = useI18n();
  const TERMS = [
    { title: m.consent.t1, body: m.consent.b1 },
    { title: m.consent.t2, body: m.consent.b2 },
    { title: m.consent.t3, body: m.consent.b3 },
    { title: m.consent.t4, body: m.consent.b4 },
  ];
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
      aria-label={m.consent.dialog}
      className="fixed inset-0 z-[100] flex items-center justify-center overflow-y-auto bg-[var(--bg)]/97 p-[1.5rem] backdrop-blur-sm"
    >
      <div className="w-full max-w-[46rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[2rem] shadow-2xl ring-1 ring-[var(--hairline)]">
        <p className="text-[1rem] font-semibold uppercase tracking-[0.25em] text-[var(--gold)]">
          {m.consent.welcome}
        </p>
        <h1 className="font-display text-gold-grad mb-[0.4rem] text-[2.6rem] font-extrabold tracking-tight">
          TV King
        </h1>
        <p className="mb-[1.4rem] text-[1.25rem] text-[var(--text-medium)]">
          {m.consent.intro}
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
            {m.consent.refused}
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
            {m.consent.accept}
          </button>
          <button
            data-focusable
            onClick={() => setRefused(true)}
            className="focusable rounded-[var(--radius)] bg-white/10 px-[1.4rem] py-[0.9rem] text-[1.2rem] font-semibold text-[var(--text-medium)]"
          >
            {m.consent.refuse}
          </button>
        </div>
      </div>
    </div>
  );
}
