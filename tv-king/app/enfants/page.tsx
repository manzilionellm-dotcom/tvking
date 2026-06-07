// =========================================================
//  enfants/page.tsx — Univers ENFANTS (ultra-simplifié)
// =========================================================
//  Pensé pour un enfant qui NE SAIT PAS LIRE : pas de petits textes, de
//  grandes vignettes en grille (pas de rangées qui défilent à perte de
//  vue), gros pictogrammes, libellés courts. Chaque carte reste un lien
//  focusable narré à voix haute (l'app peut lire le titre à l'enfant).
// =========================================================

import Link from "next/link";
import { getByUniverse } from "../lib/data";

export default function EnfantsPage() {
  const items = getByUniverse("enfants");

  return (
    <div>
      <header style={{ margin: "0.5rem 0 1.8rem", textAlign: "center" }}>
        <h1 className="font-serif" style={{ fontSize: "3.4rem", margin: 0 }}>
          🧸 Pour les enfants
        </h1>
        <p style={{ fontSize: "1.6rem", color: "var(--text-medium)" }}>
          Choisis une image pour regarder un dessin animé
        </p>
      </header>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(20rem, 1fr))",
          gap: "1.6rem",
        }}
      >
        {items.map((item) => (
          <Link
            key={item.id}
            href={`/watch/${item.id}`}
            className="focusable"
            data-focusable
            data-nav-id={item.id}
            aria-label={`Regarder ${item.title}`}
            style={{
              textDecoration: "none",
              color: "var(--text-high)",
              borderRadius: "var(--radius-lg)",
            }}
          >
            <div
              style={{
                position: "relative",
                height: "13rem",
                borderRadius: "var(--radius-lg)",
                overflow: "hidden",
                background: `linear-gradient(150deg, ${item.art.from}, ${item.art.to})`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)",
              }}
            >
              {/* Gros pictogramme pour reconnaître sans lire. */}
              <span style={{ fontSize: "5rem" }} aria-hidden>
                ▶
              </span>
            </div>
            <div
              style={{
                marginTop: "0.6rem",
                fontSize: "1.5rem",
                fontWeight: 800,
                textAlign: "center",
              }}
            >
              {item.title}
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
