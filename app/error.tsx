"use client"; // Error boundaries must be Client Components (Next.js)

import { useEffect } from "react";
import Link from "next/link";
import { logError } from "./lib/telemetry";

/*
 * Route-level error boundary (app/error.tsx). Catches uncaught render errors in
 * any page below the root layout and shows a calm, 10-foot fallback instead of
 * a blank screen — the app must never dead-end (S4 spirit). The error is sent to
 * privacy-first telemetry (no PII), and both actions are D-pad focusable.
 */
export default function AppError({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  useEffect(() => {
    logError(error, { where: "route" });
  }, [error]);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-[1.5rem] px-[var(--safe-x)] text-center">
      <span className="text-[3rem]" aria-hidden>
        👑
      </span>
      <h1 className="font-display text-[2.6rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Un instant, une erreur est survenue
      </h1>
      <p className="max-w-[48ch] text-[1.3rem] text-[var(--text-medium)]">
        Le contenu n&apos;a pas pu s&apos;afficher. Vous pouvez réessayer ou revenir à
        l&apos;accueil — rien n&apos;est perdu.
      </p>
      <div className="mt-[0.6rem] flex items-center gap-[1rem]">
        <button
          data-focusable
          onClick={() => unstable_retry()}
          className="focusable rounded-[var(--radius)] px-[1.6rem] py-[0.8rem] text-[1.25rem] font-bold text-black"
          style={{ background: "var(--gold-grad)" }}
        >
          Réessayer
        </button>
        <Link
          href="/"
          data-focusable
          className="focusable rounded-[var(--radius)] bg-white/15 px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold text-[var(--text-high)]"
        >
          Accueil
        </Link>
      </div>
    </div>
  );
}
