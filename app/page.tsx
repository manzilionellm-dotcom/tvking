import Hero from "./components/Hero";
import Row from "./components/Row";
import { heroSlides, homeRows } from "./lib/data";

export default function Home() {
  return (
    <div className="page-enter pb-[var(--safe-y)]">
      <Hero slides={heroSlides} />
      <div className="pl-[var(--safe-x)]">
        {homeRows.map((row) => (
          <Row key={row.id} row={row} />
        ))}
      </div>
    </div>
  );
}
