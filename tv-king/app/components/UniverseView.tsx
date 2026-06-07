// =========================================================
//  UniverseView.tsx — Gabarit générique d'un univers
// =========================================================
//  En-tête (icône + titre serif + phrase explicite, dans la couleur de
//  l'univers) puis des rangées GROUPÉES par état : En direct → À venir →
//  Rediffusions / Catalogue. Utilisé par Sports, Chaînes, Divertissement
//  et Journal. Les Enfants ont leur propre vue ultra-simplifiée.
// =========================================================

import {
  getByUniverse,
  getUniverseMeta,
  type MediaItem,
  type Universe,
} from "../lib/data";
import { Row } from "./Row";

export function UniverseHeader({ universe }: { universe: Universe }) {
  const meta = getUniverseMeta(universe);
  return (
    <header style={{ margin: "0.5rem 0 1.8rem" }}>
      <h1
        className="font-serif"
        style={{
          fontSize: "3.2rem",
          margin: 0,
          display: "flex",
          alignItems: "center",
          gap: "0.8rem",
        }}
      >
        <span aria-hidden>{meta.icon}</span>
        <span>{meta.label}</span>
      </h1>
      <p
        style={{
          fontSize: "1.4rem",
          color: "var(--text-medium)",
          margin: "0.4rem 0 0",
        }}
      >
        {meta.hint}
      </p>
      <div
        aria-hidden
        style={{
          height: "0.28rem",
          width: "8rem",
          marginTop: "1rem",
          borderRadius: "999px",
          background: meta.accentVar,
        }}
      />
    </header>
  );
}

export function UniverseView({ universe }: { universe: Universe }) {
  const meta = getUniverseMeta(universe);
  const items = getByUniverse(universe);

  const live = items.filter((m) => m.live || m.badge === "live");
  const upcoming = items.filter((m) => m.badge === "upcoming");
  const rest = items.filter(
    (m: MediaItem) => !m.live && m.badge !== "live" && m.badge !== "upcoming",
  );

  return (
    <div>
      <UniverseHeader universe={universe} />
      <Row title="En direct" items={live} accentVar="var(--live)" />
      <Row title="À venir" items={upcoming} accentVar={meta.accentVar} />
      <Row
        title={universe === "chaines" ? "Toutes les chaînes" : "Catalogue"}
        items={rest}
        accentVar={meta.accentVar}
      />
    </div>
  );
}
