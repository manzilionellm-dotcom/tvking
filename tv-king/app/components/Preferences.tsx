"use client";

// =========================================================
//  Preferences.tsx — Écran Réglages (accessibilité + modes)
// =========================================================
//  Profils + tous les réglages d'accessibilité et les modes (repos des
//  yeux, VIP). Contrôles 100 % télécommande : interrupteurs (OK bascule)
//  et incréments − / + (pas de slider, difficile au D-pad). Chaque
//  contrôle est focusable, explicite, et narré.
// =========================================================

import { narration } from "../lib/narration";
import { usePreferences, type ProfileId } from "../lib/preferences";

const PROFILES: { id: ProfileId; icon: string; label: string }[] = [
  { id: "senior", icon: "👓", label: "Confort" },
  { id: "enfants", icon: "🧸", label: "Enfants" },
  { id: "standard", icon: "✨", label: "Standard" },
];

export function Preferences() {
  const { prefs, setProfile, update } = usePreferences();

  return (
    <div style={{ maxWidth: "52rem" }}>
      <h1 className="font-serif" style={{ fontSize: "3rem", margin: "0 0 1.4rem" }}>
        ⚙️ Réglages
      </h1>

      {/* ----- Profil ----- */}
      <Section title="Profil">
        <div style={{ display: "flex", gap: "0.8rem", flexWrap: "wrap" }}>
          {PROFILES.map((p) => (
            <button
              key={p.id}
              type="button"
              className="focusable"
              data-focusable
              data-nav-id={`set-profile-${p.id}`}
              aria-pressed={prefs.profile === p.id}
              aria-label={`Profil ${p.label}`}
              onClick={() => {
                setProfile(p.id);
                narration.confirm(`Profil ${p.label}`);
              }}
              style={{
                cursor: "pointer",
                display: "flex",
                alignItems: "center",
                gap: "0.6rem",
                padding: "0.9rem 1.3rem",
                borderRadius: "999px",
                fontSize: "1.2rem",
                fontWeight: 700,
                color: "var(--text-high)",
                background:
                  prefs.profile === p.id
                    ? "rgba(227,185,107,0.18)"
                    : "var(--surface-2)",
                border:
                  prefs.profile === p.id
                    ? "1px solid var(--gold)"
                    : "1px solid rgba(255,255,255,0.12)",
              }}
            >
              <span aria-hidden style={{ fontSize: "1.5rem" }}>
                {p.icon}
              </span>
              {p.label}
            </button>
          ))}
        </div>
      </Section>

      {/* ----- Taille & zone de sécurité (incréments) ----- */}
      <Section title="Affichage">
        <Stepper
          label="Taille de l'interface"
          value={prefs.uiScale}
          min={0.9}
          max={1.6}
          step={0.05}
          format={(v) => `${Math.round(v * 100)} %`}
          onChange={(v) => update({ uiScale: v })}
          navId="set-uiscale"
        />
        <Stepper
          label="Zone de sécurité (bords de l'écran)"
          value={prefs.safeScale}
          min={0.8}
          max={1.4}
          step={0.05}
          format={(v) => `${Math.round(v * 100)} %`}
          onChange={(v) => update({ safeScale: v })}
          navId="set-safescale"
        />
        <SafeAreaPreview />
      </Section>

      {/* ----- Confort & accessibilité ----- */}
      <Section title="Confort & accessibilité">
        <Toggle
          label="Contraste élevé"
          hint="Texte plus net (objectif AAA)"
          value={prefs.highContrast}
          onChange={(v) => update({ highContrast: v })}
          navId="set-contrast"
        />
        <Toggle
          label="Réduire les animations"
          hint="Moins de mouvement, plus reposant"
          value={prefs.reducedMotion}
          onChange={(v) => update({ reducedMotion: v })}
          navId="set-motion"
        />
        <Toggle
          label="Narration vocale"
          hint="L'app lit à voix haute l'élément sélectionné"
          value={prefs.narration}
          onChange={(v) => {
            update({ narration: v });
            // Active la synthèse immédiatement pour confirmer de vive voix.
            narration.setEnabled(v);
            if (v) narration.confirm("Narration activée");
          }}
          navId="set-narration"
        />
        <Toggle
          label="Repos des yeux"
          hint="Tons plus chauds, luminance plus douce (le soir)"
          value={prefs.eyeRest}
          onChange={(v) => update({ eyeRest: v })}
          navId="set-eyerest"
        />
      </Section>

      {/* ----- Édition VIP ----- */}
      <Section title="Édition VIP">
        <Toggle
          label="Mode VIP / Premium"
          hint="Or plus riche, profondeur accrue, finitions soignées"
          value={prefs.vip}
          onChange={(v) => {
            update({ vip: v });
            narration.confirm(v ? "Mode VIP activé" : "Mode VIP désactivé");
          }}
          navId="set-vip"
        />
      </Section>
    </div>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section style={{ marginBottom: "2rem" }}>
      <h2
        style={{
          fontSize: "1.3rem",
          fontWeight: 800,
          color: "var(--text-medium)",
          margin: "0 0 0.9rem",
          textTransform: "uppercase",
          letterSpacing: "0.06em",
        }}
      >
        {title}
      </h2>
      <div style={{ display: "flex", flexDirection: "column", gap: "0.8rem" }}>
        {children}
      </div>
    </section>
  );
}

const rowStyle = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "1rem",
  padding: "1rem 1.2rem",
  borderRadius: "var(--radius)",
  background: "var(--surface-1)",
  border: "1px solid rgba(255,255,255,0.08)",
} as const;

function Toggle({
  label,
  hint,
  value,
  onChange,
  navId,
}: {
  label: string;
  hint?: string;
  value: boolean;
  onChange: (v: boolean) => void;
  navId: string;
}) {
  return (
    <button
      type="button"
      className="focusable"
      data-focusable
      data-nav-id={navId}
      role="switch"
      aria-checked={value}
      aria-label={`${label}. ${value ? "Activé" : "Désactivé"}`}
      onClick={() => onChange(!value)}
      style={{ ...rowStyle, cursor: "pointer", textAlign: "left" }}
    >
      <span>
        <span style={{ fontSize: "1.25rem", fontWeight: 700 }}>{label}</span>
        {hint && (
          <span
            style={{
              display: "block",
              fontSize: "1rem",
              color: "var(--text-medium)",
            }}
          >
            {hint}
          </span>
        )}
      </span>
      {/* Interrupteur visuel. */}
      <span
        aria-hidden
        style={{
          flex: "none",
          width: "3.4rem",
          height: "1.9rem",
          borderRadius: "999px",
          background: value ? "var(--gold-grad)" : "rgba(255,255,255,0.18)",
          position: "relative",
          transition: "background var(--t-fast) ease",
        }}
      >
        <span
          style={{
            position: "absolute",
            top: "0.2rem",
            left: value ? "1.7rem" : "0.2rem",
            width: "1.5rem",
            height: "1.5rem",
            borderRadius: "999px",
            background: "#fff",
            transition: "left var(--t-fast) ease",
          }}
        />
      </span>
    </button>
  );
}

function Stepper({
  label,
  value,
  min,
  max,
  step,
  format,
  onChange,
  navId,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  format: (v: number) => string;
  onChange: (v: number) => void;
  navId: string;
}) {
  const round = (v: number) => Math.round(v * 100) / 100;
  const dec = () => onChange(round(Math.max(min, value - step)));
  const inc = () => onChange(round(Math.min(max, value + step)));
  const btn = {
    cursor: "pointer",
    width: "3rem",
    height: "3rem",
    borderRadius: "999px",
    border: "1px solid rgba(255,255,255,0.2)",
    background: "var(--surface-3)",
    color: "var(--text-high)",
    fontSize: "1.6rem",
    fontWeight: 800,
  } as const;

  return (
    <div style={rowStyle}>
      <span style={{ fontSize: "1.25rem", fontWeight: 700 }}>{label}</span>
      <span style={{ display: "flex", alignItems: "center", gap: "0.8rem" }}>
        <button
          type="button"
          className="focusable"
          data-focusable
          data-nav-id={`${navId}-dec`}
          aria-label={`${label} : diminuer`}
          onClick={dec}
          style={btn}
        >
          −
        </button>
        <span
          aria-hidden
          style={{
            minWidth: "4rem",
            textAlign: "center",
            fontSize: "1.3rem",
            fontWeight: 800,
            color: "var(--gold)",
          }}
        >
          {format(value)}
        </span>
        <button
          type="button"
          className="focusable"
          data-focusable
          data-nav-id={`${navId}-inc`}
          aria-label={`${label} : augmenter`}
          onClick={inc}
          style={btn}
        >
          +
        </button>
      </span>
    </div>
  );
}

/// Aperçu de la zone de sécurité : un cadre qui matérialise l'overscan
/// courant (utile pour régler sur une TV qui « rogne » les bords).
function SafeAreaPreview() {
  return (
    <div
      aria-label="Aperçu de la zone de sécurité"
      style={{
        position: "relative",
        height: "9rem",
        borderRadius: "var(--radius)",
        background: "var(--surface-2)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          margin: "calc(var(--safe-y) / 2) calc(var(--safe-x) / 2)",
          border: "2px dashed var(--gold)",
          borderRadius: "0.5rem",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "var(--text-medium)",
          fontSize: "1rem",
        }}
      >
        Zone visible à l'écran
      </div>
    </div>
  );
}
