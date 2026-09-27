"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { zunoWaUrl } from "../../lib/wa";

export default function ActivationForm() {
  const [sCode, setSCode] = useState("");
  const [m2, setM2] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{
    ok: boolean;
    message: string;
  } | null>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setResult(null);
    try {
      const res = await fetch("/api/activate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ s: sCode, m2 }),
      });
      const data = await res.json();
      setResult({
        ok: res.ok && Boolean(data.ok),
        message:
          data.message ||
          (res.ok ? "Appareil activé." : "Activation impossible."),
      });
    } catch {
      setResult({ ok: false, message: "Erreur réseau." });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form
      onSubmit={onSubmit}
      className="zuno-card mx-auto flex w-full max-w-md flex-col gap-4 rounded-2xl border border-white/10 bg-white/[0.03] p-6 shadow-[0_0_60px_rgba(59,130,246,0.08)]"
    >
      <label className="block text-sm font-medium text-white/70">
        S code
        <input
          required
          value={sCode}
          onChange={(e) => setSCode(e.target.value)}
          placeholder="Code d'activation reçu après paiement"
          autoComplete="off"
          className="mt-1.5 w-full rounded-xl border border-white/10 bg-black/40 px-4 py-3 text-white outline-none transition focus:border-[#3b82f6]/70 focus:shadow-[0_0_0_3px_rgba(59,130,246,0.2)]"
        />
        <span className="mt-1 block text-xs text-white/35">
          Code d'activation (annuel ou à vie) reçu après paiement
        </span>
      </label>
      <label className="block text-sm font-medium text-white/70">
        M2
        <input
          required
          value={m2}
          onChange={(e) => setM2(e.target.value)}
          placeholder="MK:1A:2B:3C:4D:5E"
          autoComplete="off"
          spellCheck={false}
          className="mt-1.5 w-full rounded-xl border border-white/10 bg-black/40 px-4 py-3 font-mono text-white outline-none transition focus:border-[#3b82f6]/70 focus:shadow-[0_0_0_3px_rgba(59,130,246,0.2)]"
        />
        <span className="mt-1 block text-xs text-white/35">
          Identifiant appareil (M2) — Zuno → Réglages → Mon appareil
        </span>
      </label>

      {result && (
        <div
          className={`rounded-xl border px-3 py-2.5 text-sm ${
            result.ok
              ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-200"
              : "border-red-500/30 bg-red-500/10 text-red-200"
          }`}
        >
          {result.message}
        </div>
      )}

      <button
        type="submit"
        disabled={busy}
        className="rounded-xl bg-gradient-to-r from-[#3b82f6] to-[#1d4ed8] px-4 py-3 font-semibold text-white shadow-[0_0_24px_rgba(59,130,246,0.35)] disabled:opacity-50"
      >
        {busy ? "Activation…" : "Activer maintenant"}
      </button>

      <a
        href={zunoWaUrl("activation")}
        target="_blank"
        rel="noopener noreferrer"
        className="text-center text-sm text-white/45 hover:text-[#25D366]"
      >
        Besoin d'aide ? WhatsApp
      </a>

      {result?.ok && (
        <Link
          href="/telecharger"
          className="text-center text-sm font-medium text-[#60a5fa]"
        >
          Ensuite : télécharger l'application →
        </Link>
      )}
    </form>
  );
}
