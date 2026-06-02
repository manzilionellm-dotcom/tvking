"use client";

// =========================================================
//  ProfileGate.tsx — Choix du profil au 1er lancement
// =========================================================
//  3 grands boutons illustrés : SENIOR, ENFANTS, STANDARD. Chaque choix
//  applique des réglages adaptés (taille, contraste, animations,
//  narration) — modifiables ensuite dans Réglages. Très peu d'éléments,
//  cibles énormes, libellés explicites : « personne n'est perdu ».
// =========================================================

import { narration } from "../lib/narration";
import { usePreferences, type ProfileId } from "../lib/preferences";

interface ProfileChoice {
  id: ProfileId;
  icon: string;
  title: string;
  desc: string;
  accent: string;
}

const CHOICES: ProfileChoice[] = [
  {
    id: "senior",
    icon: "👓",
    title: "Confort",
    desc: "Tout est plus grand, plus contrasté, et l'app parle à voix haute.",
    accent: "var(--gold)",
  },
  {
    id: "enfants",
    icon: "🧸",
    title: "Enfants",
    desc: "Des images et des dessins animés. Simple, sans avoir besoin de lire.",
    accent: "var(--u-enfants)",
  },
  {
    id: "standard",
    icon: "✨",
    title: "Standard",
    desc: "L'expérience complète, avec toutes les options.",
    accent: "var(--u-divertissement)",
  },
];

export function ProfileGate() {
  const { setProfile } = usePreferences();

  function choose(c: ProfileChoice) {
    narration.confirm(`Profil ${c.title} choisi`);
    setProfile(c.id);
  }

  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "2.5rem",
        padding: "var(--safe-y) var(--safe-x)",
        position: "relative",
        zIndex: 1,
        textAlign: "center",
      }}
    >
      <div>
        <h1
          className="font-serif"
          style={{ fontSize: "3.4rem", margin: 0 }}
        >
          <span style={{ color: "var(--gold)" }}>👑 TV King</span>
        </h1>
        <p
          style={{
            fontSize: "1.7rem",
            color: "var(--text-medium)",
            marginTop: "0.6rem",
          }}
        >
          Pour qui est cette télé&nbsp;? Choisissez, c'est modifiable à tout
          moment.
        </p>
      </div>

      <div
        style={{
          display: "flex",
          gap: "1.8rem",
          flexWrap: "wrap",
          justifyContent: "center",
        }}
      >
        {CHOICES.map((c) => (
          <button
            key={c.id}
            type="button"
            className="focusable"
            data-focusable
            data-nav-id={`profile-${c.id}`}
            aria-label={`${c.title}. ${c.desc}`}
            onClick={() => choose(c)}
            style={{
              cursor: "pointer",
              width: "20rem",
              minHeight: "20rem",
              padding: "2rem 1.6rem",
              borderRadius: "var(--radius-lg)",
              border: `2px solid ${c.accent}`,
              background: "var(--surface-1)",
              color: "var(--text-high)",
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              gap: "1rem",
              textAlign: "center",
            }}
          >
            <span style={{ fontSize: "4.5rem", lineHeight: 1 }} aria-hidden>
              {c.icon}
            </span>
            <span style={{ fontSize: "1.9rem", fontWeight: 800 }}>
              {c.title}
            </span>
            <span
              style={{
                fontSize: "1.15rem",
                color: "var(--text-medium)",
                lineHeight: 1.4,
              }}
            >
              {c.desc}
            </span>
          </button>
        ))}
      </div>
    </main>
  );
}
