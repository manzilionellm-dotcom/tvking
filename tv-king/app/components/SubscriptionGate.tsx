"use client";

// =========================================================
//  SubscriptionGate.tsx — Écran bloquant (essai fini / gelé / banni)
// =========================================================
//  Affiché quand l'accès est bloqué. Montre le MAC de l'appareil (à
//  communiquer pour l'activation), un message clair selon la raison, et
//  un bouton « J'ai payé — rafraîchir » qui re-interroge le serveur.
//  C'est l'écran d'ACCÈS/licence — il ne distribue aucun contenu.
// =========================================================

import { useState } from "react";
import { narration } from "../lib/narration";
import { gateReason, type LicenseStatus } from "../lib/license";
import { useLicense } from "./LicenseProvider";

const SUPPORT_HINT =
  "Contactez votre revendeur pour activer cet appareil. Donnez-lui le code ci-dessous.";

export function SubscriptionGate({ status }: { status: LicenseStatus }) {
  const { mac, refresh } = useLicense();
  const [busy, setBusy] = useState(false);
  const reason = gateReason(status);

  const title =
    reason === "banned"
      ? "Appareil suspendu"
      : reason === "frozen"
        ? "Appareil en pause"
        : "Essai terminé";

  const message =
    reason === "banned"
      ? "Cet appareil a été suspendu. Si c'est une erreur, contactez votre revendeur."
      : reason === "frozen"
        ? "L'accès est temporairement en pause. Contactez votre revendeur pour le réactiver."
        : "Votre essai gratuit est terminé. Activez l'accès pour continuer à profiter de NOVA+.";

  async function onRefresh() {
    setBusy(true);
    narration.confirm("Vérification de l'activation");
    await refresh();
    setBusy(false);
  }

  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "1.6rem",
        padding: "var(--safe-y) var(--safe-x)",
        textAlign: "center",
        position: "relative",
        zIndex: 1,
      }}
    >
      <div className="font-serif" style={{ fontSize: "2.6rem", color: "var(--gold)" }}>
        ✦ NOVA+
      </div>

      <div
        style={{
          width: "5.5rem",
          height: "5.5rem",
          borderRadius: "999px",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: "2.6rem",
          background: "rgba(227,185,107,0.12)",
          border: "1px solid rgba(227,185,107,0.4)",
        }}
        aria-hidden
      >
        {reason === "banned" ? "⛔" : reason === "frozen" ? "⏸" : "⏳"}
      </div>

      <h1 style={{ fontSize: "2.4rem", margin: 0 }}>{title}</h1>
      <p
        style={{
          fontSize: "1.4rem",
          color: "var(--text-medium)",
          maxWidth: "40rem",
          lineHeight: 1.5,
          margin: 0,
        }}
      >
        {message}
      </p>

      <p style={{ fontSize: "1.15rem", color: "var(--text-medium)", margin: 0 }}>
        {SUPPORT_HINT}
      </p>

      {/* Code d'appareil (MAC) — à communiquer pour l'activation. */}
      <div
        aria-label={`Code de cet appareil : ${mac}`}
        style={{
          padding: "1rem 1.6rem",
          borderRadius: "var(--radius)",
          background: "var(--surface-2)",
          border: "1px solid rgba(255,255,255,0.12)",
          fontFamily: "monospace",
          fontSize: "1.8rem",
          letterSpacing: "0.08em",
          color: "var(--gold-strong)",
        }}
      >
        {mac}
      </div>

      <button
        type="button"
        className="focusable"
        data-focusable
        data-nav-id="gate-refresh"
        aria-label="J'ai payé, vérifier l'activation"
        onClick={onRefresh}
        disabled={busy}
        style={{
          cursor: "pointer",
          marginTop: "0.4rem",
          padding: "1rem 2rem",
          borderRadius: "999px",
          background: "var(--gold-grad)",
          color: "#1a1300",
          fontWeight: 800,
          fontSize: "1.3rem",
          border: "none",
          opacity: busy ? 0.6 : 1,
        }}
      >
        {busy ? "Vérification…" : "J'ai payé — Rafraîchir"}
      </button>
    </main>
  );
}
