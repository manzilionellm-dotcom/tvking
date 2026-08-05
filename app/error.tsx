"use client";

import Link from "next/link";
import { useEffect } from "react";

/*
 * Filet de sécurité global : une erreur d'exécution inattendue (WebView ancien,
 * donnée corrompue…) affichait un écran blanc — perçu comme une fermeture de
 * l'app sur un box TV. Ici : message clair + reprise sans quitter.
 */
export default function Error({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string };
  unstable_retry: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-[1rem] px-[var(--safe-x)] py-[var(--safe-y)] text-center">
      <span className="text-[3rem]">📺</span>
      <h1 className="font-display text-[2.4rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Oups, un problème est survenu
      </h1>
      <p className="max-w-[42ch] text-[1.3rem] text-[var(--text-medium)]">
        Rien de grave : l&apos;application est toujours ouverte. Reprenez la
        lecture ou revenez à l&apos;accueil.
      </p>
      <div className="mt-[0.8rem] flex flex-wrap items-center justify-center gap-[1rem]">
        <button
          data-focusable
          data-focus-default
          onClick={() => unstable_retry()}
          className="focusable rounded-[var(--radius)] px-[1.6rem] py-[0.9rem] text-[1.25rem] font-bold text-black"
          style={{ background: "var(--gold-grad)" }}
        >
          Réessayer
        </button>
        <Link
          href="/"
          data-focusable
          className="focusable rounded-[var(--radius)] bg-white/12 px-[1.4rem] py-[0.9rem] text-[1.2rem] font-semibold text-[var(--text-high)]"
        >
          Retour à l&apos;accueil
        </Link>
      </div>
    </div>
  );
}
