"use client"; // Error boundaries must be Client Components (Next.js)

import { useEffect } from "react";
import "./globals.css";
import { logError } from "./lib/telemetry";

/*
 * Root error boundary (app/global-error.tsx). It replaces the root layout when a
 * render error escapes it, so it must define its own <html> and <body>. Kept
 * self-contained and inline-styled (design tokens from globals.css) so it works
 * even if the layout itself failed to render.
 */
export default function GlobalError({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  useEffect(() => {
    logError(error, { where: "global" });
  }, [error]);

  return (
    <html lang="fr">
      <body style={{ background: "var(--bg)", color: "var(--text-high)" }}>
        <title>TV King — Erreur</title>
        <main
          style={{
            minHeight: "100vh",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: "1.5rem",
            padding: "0 5vw",
            textAlign: "center",
          }}
        >
          <span style={{ fontSize: "3rem" }} aria-hidden>
            👑
          </span>
          <h1
            className="font-display"
            style={{ fontSize: "2.6rem", fontWeight: 800, color: "var(--text-high)" }}
          >
            L&apos;application a rencontré un problème
          </h1>
          <p style={{ maxWidth: "48ch", fontSize: "1.3rem", color: "var(--text-medium)" }}>
            Réessayez pour recharger l&apos;application.
          </p>
          <button
            onClick={() => unstable_retry()}
            style={{
              borderRadius: "var(--radius)",
              padding: "0.8rem 1.6rem",
              fontSize: "1.25rem",
              fontWeight: 700,
              color: "#000",
              background: "var(--gold-grad)",
            }}
          >
            Réessayer
          </button>
        </main>
      </body>
    </html>
  );
}
