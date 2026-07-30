"use client";

import { useState } from "react";
import { SLOT_ID_PATTERN } from "../lib/zk";

/*
 * Panel maître — vue AVEUGLE, par conception.
 *
 * L'interface n'affiche que des états binaires présence/absence renvoyés par
 * /api/panel/status : pas de comptes, pas de tailles, pas de dates, pas de
 * liste. Le maître ne peut interroger que des identifiants aveuglés qu'il
 * possède déjà (communiqués hors bande par l'appareil, cf. Réglages).
 */

type Presence = "present" | "absent";

interface PanelState {
  vault: Presence;
  slots: Record<string, Presence>;
  streams: Record<string, Presence>;
}

function PresenceBadge({ state }: { state: Presence }) {
  const present = state === "present";
  return (
    <span
      className="rounded-full px-[0.9rem] py-[0.25rem] text-[1rem] font-bold uppercase tracking-wider"
      style={{
        background: present ? "rgba(46,160,67,0.2)" : "rgba(248,81,73,0.15)",
        color: present ? "#3fb950" : "#f85149",
      }}
    >
      {present ? "Présence" : "Absence"}
    </span>
  );
}

export default function PanelPage() {
  const [secret, setSecret] = useState("");
  const [slotInput, setSlotInput] = useState("");
  const [result, setResult] = useState<PanelState | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function query() {
    setBusy(true);
    setError("");
    setResult(null);
    const slotIds = slotInput
      .split(/\s+/)
      .map((s) => s.trim().toLowerCase())
      .filter((s) => SLOT_ID_PATTERN.test(s));
    try {
      const res = await fetch("/api/panel/status", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${secret}`,
        },
        body: JSON.stringify({ slotIds }),
      });
      if (res.status === 401) {
        setError("Accès refusé.");
      } else if (res.status === 503) {
        setError("Panel non configuré (ADMIN_SECRET absent).");
      } else if (!res.ok) {
        setError("Erreur serveur.");
      } else {
        setResult((await res.json()) as PanelState);
      }
    } catch {
      setError("Réseau indisponible.");
    }
    setBusy(false);
  }

  return (
    <div className="pb-[var(--safe-y)] pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[0.4rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Panel maître
      </h1>
      <p className="mb-[2rem] max-w-[62rem] text-[1.3rem] text-[var(--text-medium)]">
        Vue aveugle (Zero-Knowledge) : le serveur ne détient que des blocs chiffrés opaques de
        taille fixe, sous identifiants aveuglés. Ce panel ne peut afficher qu&apos;un état binaire
        — présence ou absence — jamais un contenu, un compte ou une métrique.
      </p>

      <section className="mb-[1.6rem] max-w-[62rem]">
        <label className="mb-[0.4rem] block text-[1.2rem] font-bold text-[var(--text-high)]" htmlFor="panel-secret">
          Mot de passe maître
        </label>
        <input
          id="panel-secret"
          data-focusable
          type="password"
          value={secret}
          onChange={(e) => setSecret(e.target.value)}
          className="focusable w-full rounded-[var(--radius)] bg-[var(--surface-2)] px-[1rem] py-[0.8rem] text-[1.2rem] text-[var(--text-high)] outline-none"
          autoComplete="off"
        />
      </section>

      <section className="mb-[1.6rem] max-w-[62rem]">
        <label className="mb-[0.4rem] block text-[1.2rem] font-bold text-[var(--text-high)]" htmlFor="panel-slots">
          Identifiants aveuglés à vérifier (un par ligne, optionnel)
        </label>
        <textarea
          id="panel-slots"
          data-focusable
          rows={3}
          value={slotInput}
          onChange={(e) => setSlotInput(e.target.value)}
          placeholder="64 caractères hexadécimaux…"
          className="focusable w-full rounded-[var(--radius)] bg-[var(--surface-2)] px-[1rem] py-[0.8rem] font-mono text-[1rem] text-[var(--text-high)] outline-none"
        />
      </section>

      <button
        data-focusable
        data-focus-default
        disabled={busy || !secret}
        onClick={query}
        className="focusable rounded-[var(--radius)] px-[1.6rem] py-[0.9rem] text-[1.25rem] font-bold text-black disabled:opacity-60"
        style={{ background: "var(--gold-grad)" }}
      >
        Interroger
      </button>

      {error && <p className="mt-[1.2rem] text-[1.2rem] text-[#f85149]">{error}</p>}

      {result && (
        <section className="mt-[2rem] max-w-[62rem]">
          <div className="mb-[1rem] flex items-center gap-[1rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
            <span className="text-[1.3rem] font-bold text-[var(--text-high)]">Coffre (global)</span>
            <PresenceBadge state={result.vault} />
          </div>
          {Object.keys(result.slots).map((id) => (
            <div
              key={id}
              className="mb-[0.6rem] flex items-center gap-[1rem] rounded-[var(--radius)] bg-[var(--surface-1)] px-[1.2rem] py-[0.8rem]"
            >
              <span className="min-w-0 flex-1 truncate font-mono text-[0.95rem] text-[var(--text-medium)]">{id}</span>
              <span className="flex gap-[0.5rem]">
                <span className="flex items-center gap-[0.4rem]">
                  <span className="text-[0.85rem] uppercase tracking-wider text-[var(--text-medium)]">Sauvegarde</span>
                  <PresenceBadge state={result.slots[id]} />
                </span>
                <span className="flex items-center gap-[0.4rem]">
                  <span className="text-[0.85rem] uppercase tracking-wider text-[var(--text-medium)]">Flux</span>
                  <PresenceBadge state={result.streams[id] ?? "absent"} />
                </span>
              </span>
            </div>
          ))}
          <p className="mt-[1rem] text-[1.05rem] italic text-[var(--text-medium)]">
            Aucune quantité n&apos;est disponible : c&apos;est une garantie d&apos;architecture, pas
            une permission manquante.
          </p>
        </section>
      )}
    </div>
  );
}
