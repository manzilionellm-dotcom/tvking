import ContinueRow from "./components/ContinueRow";
import Hero from "./components/Hero";
import Row from "./components/Row";
import { heroSlides, homeRows } from "./lib/data";

export default function Home() {
  return (
    <div className="pb-[var(--safe-y)]">
      <Hero slides={heroSlides} />
      <div className="pl-[var(--safe-x)]">
        {homeRows.map((row) =>
          // "Reprendre" is rendered from the persisted playhead when there is
          // one; the seeded row is only the fallback for a fresh install.
          row.id === "continue" ? (
            <ContinueRow key={row.id} fallback={row} />
          ) : (
            <Row key={row.id} row={row} />
          )
        )}
      </div>
    </div>
  );
}
