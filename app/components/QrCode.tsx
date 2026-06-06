"use client";

/*
 * QR code rendu côté client (aucun appel réseau, aucune fuite du code vers un
 * tiers) via qrcode → SVG net à toute distance. Sert à scanner le code
 * d'activation avec un téléphone. Fond blanc + modules sombres = contraste
 * maximal pour une lecture fiable par les appareils photo.
 */

import { useEffect, useState } from "react";
import QRCode from "qrcode";

export default function QrCode({ text, size = "11rem" }: { text: string; size?: string }) {
  // On mémorise le SVG AVEC le texte d'origine : si le code change, on
  // n'affiche pas l'ancien QR (le rendu attend que le nouveau soit prêt).
  const [data, setData] = useState<{ text: string; svg: string }>({ text: "", svg: "" });

  useEffect(() => {
    let alive = true;
    if (!text) return;
    QRCode.toString(text, {
      type: "svg",
      margin: 1,
      errorCorrectionLevel: "M",
      color: { dark: "#0b0e12", light: "#ffffff" },
    })
      .then((svg) => {
        if (alive) setData({ text, svg });
      })
      .catch(() => {
        if (alive) setData({ text, svg: "" });
      });
    return () => {
      alive = false;
    };
  }, [text]);

  if (!text || data.text !== text || !data.svg) return null;
  return (
    <div
      className="rounded-[var(--radius)] bg-white p-[0.6rem] [&>svg]:block [&>svg]:h-full [&>svg]:w-full"
      style={{ width: size, height: size }}
      dangerouslySetInnerHTML={{ __html: data.svg }}
    />
  );
}
