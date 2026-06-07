import Link from "next/link";
import { UniverseView } from "../components/UniverseView";

// Univers SPORTS : directs, à venir, rediffusions + accès Multi-écran.
export default function SportsPage() {
  return (
    <div>
      <div style={{ display: "flex", justifyContent: "flex-end" }}>
        <Link
          href="/sports/multiview"
          className="focusable"
          data-focusable
          data-nav-id="sports-multiview"
          aria-label="Ouvrir le multi-écran : plusieurs directs à la fois"
          style={{
            padding: "0.7rem 1.3rem",
            borderRadius: "999px",
            background: "rgba(88,201,163,0.16)",
            color: "var(--text-high)",
            fontWeight: 700,
            fontSize: "1.1rem",
            textDecoration: "none",
            border: "1px solid var(--u-sports)",
          }}
        >
          🔲 Multi-écran
        </Link>
      </div>
      <UniverseView universe="sports" />
    </div>
  );
}
