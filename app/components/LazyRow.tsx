"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

/*
 * Montage paresseux d'une rangée (rails « catégories »). Sur une box bas de
 * gamme, monter des dizaines de rails d'un coup sature le DOM. On ne monte le
 * contenu que lorsqu'il approche du viewport (rootMargin large pour qu'il soit
 * prêt AVANT que le focus D-pad n'y arrive), et on réserve sa hauteur pour ne
 * créer aucune secousse de layout. Repli : si IntersectionObserver manque
 * (très vieux WebView), on monte directement.
 */
export default function LazyRow({ minHeight, children }: { minHeight: string; children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (show) return;
    const el = ref.current;
    // Repli (très vieux WebView sans IntersectionObserver) : on monte au
    // prochain frame — différé pour ne pas déclencher un setState synchrone.
    if (typeof IntersectionObserver === "undefined" || !el) {
      const id = requestAnimationFrame(() => setShow(true));
      return () => cancelAnimationFrame(id);
    }
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setShow(true);
          io.disconnect();
        }
      },
      { rootMargin: "1200px 0px" },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [show]);

  return (
    <div ref={ref} style={show ? undefined : { minHeight }}>
      {show ? children : null}
    </div>
  );
}
