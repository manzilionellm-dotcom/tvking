"use client";

/*
 * Carte « Mon appareil » (Réglages). Montre le code d'activation (MAC virtuel)
 * et l'état courant, et permet de re-vérifier ou de régénérer le code.
 */

import { useState } from "react";
import {
  useActivation,
  refreshActivation,
  activationEnabled,
  getSourceDiag,
  type ActivationState,
} from "../lib/activation";
import { getDeviceMac, regenerateDeviceMac, hasNativeDeviceId } from "../lib/device";
import { useT } from "../lib/i18n";
import QrCode from "./QrCode";

function stateColor(s: ActivationState): string {
  if (s === "active" || s === "trial") return "var(--ok)";
  if (s === "unknown") return "var(--accent)";
  return "var(--live)";
}

export default function DeviceCard() {
  const { activation } = useActivation();
  const t = useT();
  // MAC affiché même avant la 1re réponse serveur (lecture directe locale).
  const [mac, setMac] = useState<string>(() => (typeof window !== "undefined" ? getDeviceMac() : ""));

  const state = activation?.state ?? "unknown";
  const enabled = activationEnabled();
  // Diagnostic source : recalculé à chaque réponse serveur (via useActivation).
  const diag = getSourceDiag();
  // Identité ancrée au matériel : le code ne change jamais (même après réinstall).
  const hardwareBound = typeof window !== "undefined" && hasNativeDeviceId();

  function onRegenerate() {
    if (!window.confirm(t("regenerate_confirm"))) return;
    setMac(regenerateDeviceMac());
    void refreshActivation();
  }

  return (
    <div className="mt-[2rem] max-w-[52rem] rounded-[var(--radius-lg)] bg-[var(--surface-1)] p-[1.2rem]">
      <h2 className="mb-[0.4rem] text-[1.3rem] font-bold text-[var(--text-high)]">{t("my_device")}</h2>
      <p className="mb-[1rem] text-[1rem] text-[var(--text-medium)]">
        {t("device_intro")}
        {hardwareBound && ` ${t("device_hw_bound")}`}
      </p>

      <div className="flex flex-wrap items-center gap-[1.2rem]">
        <div className="flex flex-col gap-[0.3rem]">
          <span className="text-[0.9rem] font-semibold uppercase tracking-[0.16em] text-[var(--text-disabled)]">
            {t("activation_code")}
          </span>
          <span className="font-mono text-[1.7rem] font-bold tracking-[0.12em] text-accent-grad">{mac || "—"}</span>
        </div>
        {mac && <QrCode text={mac} size="7.5rem" />}
      </div>

      <div className="mt-[0.9rem] flex items-center gap-[0.7rem]">
        <span className="h-[0.7rem] w-[0.7rem] rounded-full" style={{ background: stateColor(state) }} />
        <span className="text-[1.1rem] font-bold text-[var(--text-high)]">{t(`state_${state}`)}</span>
        {(state === "trial" || state === "active") && activation && activation.daysLeft > 0 && !activation.paid && (
          <span className="text-[1rem] text-[var(--text-medium)]">· {t("days_left", { n: activation.daysLeft })}</span>
        )}
        {activation?.offline && <span className="text-[0.95rem] text-[var(--text-disabled)]">· {t("offline")}</span>}
      </div>

      {!enabled && (
        <p className="mt-[0.6rem] text-[0.9rem] text-[var(--text-disabled)]">{t("activation_disabled")}</p>
      )}

      {/* Diagnostic « source poussée par le panel » : la source détectée +, à
          défaut, les clés brutes renvoyées par le serveur (pour confirmer le
          format réel de la source assignée à cet appareil). */}
      {diag.keys.length > 0 && (
        <p className="mt-[0.7rem] break-all text-[0.8rem] text-[var(--text-disabled)]">
          📡 {diag.applied ? diag.applied.replace(/(password=)[^&]*/i, "$1•••") : "—"}
          {"  ·  "}
          {diag.keys.join(", ")}
        </p>
      )}

      <div className="mt-[1.1rem] flex flex-wrap gap-[0.8rem]">
        <button
          data-focusable
          onClick={() => void refreshActivation()}
          className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.3rem] py-[0.7rem] text-[1.05rem] font-semibold text-[var(--text-high)]"
        >
          {t("check_now")}
        </button>
        {/* Régénérer n'a de sens que sur le repli navigateur : sur un appareil
            réel le code est ancré au matériel et reste fixe. */}
        {!hardwareBound && (
          <button
            data-focusable
            onClick={onRegenerate}
            className="focusable rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.3rem] py-[0.7rem] text-[1.05rem] font-semibold text-[var(--text-medium)]"
          >
            {t("regenerate")}
          </button>
        )}
      </div>
    </div>
  );
}
