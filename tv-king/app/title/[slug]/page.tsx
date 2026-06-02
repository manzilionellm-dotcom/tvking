// =========================================================
//  title/[slug]/page.tsx — Fiche détail d'un contenu
// =========================================================
//  Grand visuel + titre serif + métadonnées explicites + actions :
//  Lecture (or plein), Ajouter à ma liste (toggle persistant), Retour.
//  Si le slug est inconnu → 404 propre (notFound()).
// =========================================================

import Link from "next/link";
import { notFound } from "next/navigation";
import { AddToListButton } from "../../components/AddToListButton";
import { LevelBadge, LiveBadge } from "../../components/Badge";
import { getById, getUniverseMeta } from "../../lib/data";

export default async function TitlePage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const item = getById(slug);
  if (!item) notFound();

  const meta = getUniverseMeta(item.universe);

  const facts: string[] = [];
  if (item.duration) facts.push(item.duration);
  if (item.lessons) facts.push(`${item.lessons} leçons`);
  if (item.channel) facts.push(item.channel);
  if (item.league) facts.push(item.league);
  if (item.instructor) facts.push(`avec ${item.instructor}`);
  if (item.startsIn) facts.push(item.startsIn);

  return (
    <article style={{ maxWidth: "70rem" }}>
      {/* Visuel d'en-tête. */}
      <div
        style={{
          position: "relative",
          height: "40vh",
          minHeight: "20rem",
          borderRadius: "var(--radius-lg)",
          overflow: "hidden",
          background: `linear-gradient(125deg, ${item.art.from}, ${item.art.to})`,
          display: "flex",
          alignItems: "flex-end",
        }}
      >
        <div
          aria-hidden
          style={{
            position: "absolute",
            inset: 0,
            background:
              "linear-gradient(to top, rgba(0,0,0,0.72), transparent 60%)",
          }}
        />
        <div style={{ position: "relative", padding: "2rem" }}>
          <span
            style={{
              fontSize: "1rem",
              fontWeight: 800,
              letterSpacing: "0.08em",
              color: meta.accentVar,
            }}
          >
            {meta.icon} {meta.label.toUpperCase()}
          </span>
          <h1
            className="font-serif"
            style={{ fontSize: "3.4rem", margin: "0.3rem 0 0" }}
          >
            {item.title}
          </h1>
        </div>
      </div>

      {/* Méta + actions. */}
      <div style={{ marginTop: "1.4rem" }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "0.8rem",
            flexWrap: "wrap",
          }}
        >
          {item.badge && <LiveBadge kind={item.badge} />}
          {item.level && <LevelBadge level={item.level} />}
          <span style={{ fontSize: "1.2rem", color: "var(--text-medium)" }}>
            {item.subtitle}
          </span>
        </div>

        {facts.length > 0 && (
          <p
            style={{
              marginTop: "0.8rem",
              fontSize: "1.15rem",
              color: "var(--text-medium)",
            }}
          >
            {facts.join("  ·  ")}
          </p>
        )}

        <div
          style={{
            display: "flex",
            gap: "1rem",
            marginTop: "1.6rem",
            flexWrap: "wrap",
          }}
        >
          <Link
            href={`/watch/${item.id}`}
            className="focusable"
            data-focusable
            data-nav-id="detail-play"
            aria-label={`Lecture de ${item.title}`}
            style={{
              padding: "0.9rem 1.8rem",
              borderRadius: "999px",
              background: "var(--gold-grad)",
              color: "#1a1300",
              fontWeight: 800,
              fontSize: "1.25rem",
              textDecoration: "none",
            }}
          >
            ▶ Lecture
          </Link>

          <AddToListButton id={item.id} title={item.title} />

          <Link
            href={`/${item.universe}`}
            className="focusable"
            data-focusable
            data-nav-id="detail-back"
            aria-label={`Retour à ${meta.label}`}
            style={{
              padding: "0.9rem 1.6rem",
              borderRadius: "999px",
              background: "rgba(255,255,255,0.12)",
              color: "var(--text-high)",
              fontWeight: 700,
              fontSize: "1.2rem",
              textDecoration: "none",
              border: "1px solid rgba(255,255,255,0.2)",
            }}
          >
            ⬅ Retour
          </Link>
        </div>
      </div>
    </article>
  );
}
