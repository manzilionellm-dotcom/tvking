"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { zunoWaUrl, type WaBranch } from "../../lib/wa";

type Step = "closed" | "greet" | "activate" | "done";

export default function SupportChat() {
  const [step, setStep] = useState<Step>("closed");
  const [mac, setMac] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [stub, setStub] = useState(false);

  useEffect(() => {
    if (step === "closed") {
      setMsg(null);
      setStub(false);
    }
  }, [step]);

  async function submitActivate() {
    setBusy(true);
    setMsg(null);
    try {
      const res = await fetch("/api/activate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mac, code }),
      });
      const data = await res.json();
      setStub(Boolean(data.stub));
      if (!res.ok) {
        setMsg(data.message || "Activation impossible.");
        return;
      }
      setMsg(data.message || "Demande envoyée.");
      setStep("done");
    } catch {
      setMsg("Erreur réseau. Réessayez ou contactez le support.");
    } finally {
      setBusy(false);
    }
  }

  function openWa(branch: WaBranch) {
    window.open(zunoWaUrl(branch), "_blank", "noopener,noreferrer");
  }

  return (
    <>
      <button
        type="button"
        aria-label="Assistance Zuno"
        onClick={() => setStep((s) => (s === "closed" ? "greet" : "closed"))}
        className="zuno-wa-fab fixed bottom-5 right-5 z-[60] flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-[#25D366] to-[#128C7E] text-white shadow-[0_8px_32px_rgba(37,211,102,0.45)] transition hover:scale-105 hover:shadow-[0_12px_40px_rgba(37,211,102,0.55)] focus:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
      >
        {step === "closed" ? (
          <svg className="h-7 w-7" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
            <path d="M12.04 2C6.58 2 2.13 6.45 2.13 11.91c0 1.75.46 3.45 1.34 4.95L2 22l5.25-1.38c1.45.79 3.08 1.21 4.79 1.21 5.46 0 9.91-4.45 9.91-9.91S17.5 2 12.04 2zm5.79 14.12c-.24.68-1.4 1.25-1.93 1.33-.49.07-1.12.1-1.81-.11-.42-.13-.95-.31-1.64-.61-2.89-1.25-4.77-4.16-4.92-4.35-.14-.19-1.18-1.57-1.18-3 0-1.42.75-2.12 1.01-2.41.27-.29.58-.36.78-.36h.56c.18 0 .42-.07.66.5.24.58.82 2 .89 2.15.07.14.12.31.02.5-.1.19-.14.31-.29.48-.14.17-.31.38-.44.51-.14.14-.29.29-.12.56.17.28.75 1.23 1.61 2 .1.9 2.03 1.66 2.34 1.85.31.19.49.16.67-.1.18-.25.77-.9.98-1.21.21-.31.42-.26.7-.16.29.1 1.82.86 2.13 1.01.31.16.52.23.6.36.07.13.07.75-.17 1.43z" />
          </svg>
        ) : (
          <svg className="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
            <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
          </svg>
        )}
      </button>

      {step !== "closed" && (
        <div className="zuno-chat-panel fixed bottom-[5.5rem] right-5 z-[60] flex w-[min(100vw-2rem,22rem)] flex-col overflow-hidden rounded-2xl border border-white/10 bg-[#0f1117]/95 shadow-[0_24px_64px_rgba(0,0,0,0.65)] backdrop-blur-xl">
          <div className="border-b border-white/8 bg-gradient-to-r from-[#1e293b] to-[#0f172a] px-4 py-3">
            <p className="text-sm font-semibold text-white">Zuno Concierge</p>
            <p className="text-xs text-white/45">Réponse rapide · VIP</p>
          </div>

          <div className="flex max-h-[70vh] flex-col gap-3 overflow-y-auto p-4">
            {step === "greet" && (
              <>
                <div className="zuno-fade-in rounded-2xl rounded-tl-sm bg-white/8 px-3.5 py-2.5 text-sm text-white/90">
                  Dis-moi ce que tu veux
                </div>
                <div className="flex flex-col gap-2">
                  <button
                    type="button"
                    onClick={() => setStep("activate")}
                    className="rounded-xl border border-[#3b82f6]/35 bg-[#3b82f6]/15 px-3 py-2.5 text-left text-sm font-medium text-white transition hover:bg-[#3b82f6]/25"
                  >
                    Activer
                  </button>
                  <Link
                    href="/revendeur"
                    onClick={() => {
                      setStep("closed");
                    }}
                    className="rounded-xl border border-white/10 bg-white/5 px-3 py-2.5 text-sm font-medium text-white/90 transition hover:bg-white/10"
                  >
                    Devenir revendeur
                  </Link>
                  <button
                    type="button"
                    onClick={() => openWa("support")}
                    className="rounded-xl border border-white/10 bg-white/5 px-3 py-2.5 text-left text-sm font-medium text-white/90 transition hover:bg-white/10"
                  >
                    Support
                  </button>
                </div>
              </>
            )}

            {step === "activate" && (
              <div className="zuno-fade-in flex flex-col gap-3">
                <p className="text-sm text-white/70">
                  Entrez l'adresse MAC et votre code d'activation.
                </p>
                <label className="block text-xs font-medium text-white/50">
                  Adresse MAC
                  <input
                    value={mac}
                    onChange={(e) => setMac(e.target.value)}
                    placeholder="AA:BB:CC:DD:EE:FF"
                    className="mt-1 w-full rounded-xl border border-white/10 bg-black/40 px-3 py-2.5 text-sm text-white outline-none focus:border-[#3b82f6]/60"
                  />
                </label>
                <label className="block text-xs font-medium text-white/50">
                  Code d'activation
                  <input
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    placeholder="Votre code"
                    className="mt-1 w-full rounded-xl border border-white/10 bg-black/40 px-3 py-2.5 text-sm text-white outline-none focus:border-[#3b82f6]/60"
                  />
                </label>
                {msg && <p className="text-xs text-amber-300/90">{msg}</p>}
                <button
                  type="button"
                  disabled={busy}
                  onClick={submitActivate}
                  className="rounded-xl bg-[#2563eb] px-3 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
                >
                  {busy ? "Activation…" : "Activer maintenant"}
                </button>
                <button
                  type="button"
                  onClick={() => openWa("activation")}
                  className="text-xs text-white/45 underline-offset-2 hover:text-white/70 hover:underline"
                >
                  Continuer sur WhatsApp
                </button>
              </div>
            )}

            {step === "done" && (
              <div className="zuno-fade-in flex flex-col gap-3">
                <p className="text-sm text-white/85">{msg}</p>
                {stub && (
                  <p className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-2.5 py-2 text-xs text-amber-200/90">
                    Mode stub : l'API d'activation n'est pas encore configurée
                    (ACTIVATION_API_URL). Finalisez via WhatsApp.
                  </p>
                )}
                <button
                  type="button"
                  onClick={() => openWa("activation")}
                  className="rounded-xl bg-[#25D366] px-3 py-2.5 text-sm font-semibold text-white"
                >
                  Ouvrir WhatsApp
                </button>
                <Link href="/telecharger" className="text-center text-xs text-[#60a5fa]">
                  Télécharger l'app →
                </Link>
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}
