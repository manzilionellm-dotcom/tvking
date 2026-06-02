// =========================================================
//  page.tsx — Accueil
// =========================================================
//  Hero « à la une » + rangée « Reprendre » + « En direct maintenant »
//  + un aperçu de chaque univers (accès direct depuis l'accueil). La
//  sélection de profil au 1er lancement est gérée en amont par AppFrame.
// =========================================================

import { Hero } from "./components/Hero";
import { Row } from "./components/Row";
import {
  getByUniverse,
  getContinueWatching,
  getHeroItems,
  getLiveNow,
  getUniverseMeta,
  UNIVERSES,
} from "./lib/data";

export default function HomePage() {
  const hero = getHeroItems();
  const resume = getContinueWatching();
  const live = getLiveNow();

  return (
    <div>
      <Hero items={hero} />

      {resume.length > 0 && (
        <Row title="Reprendre" items={resume} accentVar="var(--gold)" />
      )}

      <Row
        title="En direct maintenant"
        items={live}
        accentVar="var(--live)"
      />

      {/* Aperçu de chaque univers (3-7 éléments), accès direct. */}
      {UNIVERSES.map((u) => {
        const meta = getUniverseMeta(u.id);
        return (
          <Row
            key={u.id}
            title={`${meta.icon} ${meta.label}`}
            items={getByUniverse(u.id)}
            accentVar={meta.accentVar}
          />
        );
      })}
    </div>
  );
}
