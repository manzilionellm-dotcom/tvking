import Link from "next/link";
import { notFound } from "next/navigation";
import Row from "../../components/Row";
import { LevelBadge, LiveBadge } from "../../components/Badge";
import { allItems, getItem, kindOf, relatedTo } from "../../lib/data";

/* Pre-render a detail page for every known item. */
export function generateStaticParams() {
  return allItems.map((it) => ({ slug: it.id }));
}

function synopsis(item: ReturnType<typeof getItem>) {
  if (!item) return "";
  if (item.description) return item.description;
  if (kindOf(item) === "sport") {
    if (item.live === "live") return `Suivez ${item.title} en direct, score et temps forts à la minute.`;
    if (item.live === "upcoming") return `${item.title} — programmez un rappel pour ne rien manquer du coup d'envoi.`;
    return `Revivez ${item.title} : intégrale et meilleurs moments à la demande.`;
  }
  return `${item.title} — un programme guidé pour progresser pas à pas, à votre rythme.`;
}

export default async function TitlePage({ params }: PageProps<"/title/[slug]">) {
  const { slug } = await params;
  const item = getItem(slug);
  if (!item) notFound();

  const kind = kindOf(item);
  const related = relatedTo(item);
  const lessonCount = item.lessons ?? (kind === "formation" ? 8 : 0);

  return (
    <div className="pb-[var(--safe-y)]">
      {/* Backdrop */}
      <header className="relative min-h-[62vh] w-full overflow-hidden">
        <div
          className="absolute inset-0"
          style={{ background: `linear-gradient(120deg, ${item.art.from}, ${item.art.to})` }}
        />
        <div className="absolute inset-0 bg-gradient-to-t from-[var(--bg)] via-[var(--bg)]/45 to-transparent" />
        <div className="absolute inset-0 bg-gradient-to-r from-[var(--bg)]/90 via-transparent to-transparent" />

        <div className="relative flex min-h-[62vh] flex-col justify-end gap-[1rem] px-[var(--safe-x)] pb-[2.2rem] pt-[var(--safe-y)]">
          <div className="flex flex-wrap items-center gap-[0.7rem]">
            {item.live && <LiveBadge state={item.live} />}
            {item.level && <LevelBadge level={item.level} />}
            {item.league && (
              <span className="text-[1.05rem] font-semibold text-[var(--text-medium)]">{item.league}</span>
            )}
            {item.duration && (
              <span className="text-[1.05rem] text-[var(--text-medium)]">{item.duration}</span>
            )}
            {lessonCount > 0 && (
              <span className="text-[1.05rem] text-[var(--text-medium)]">{lessonCount} leçons</span>
            )}
            {item.instructor && (
              <span className="text-[1.05rem] text-[var(--text-medium)]">avec {item.instructor}</span>
            )}
          </div>

          <h1 className="max-w-[34ch] text-[3.4rem] font-extrabold leading-[1.05] tracking-tight text-[var(--text-high)]">
            {item.title}
          </h1>

          {(item.score || item.clock || item.startsIn) && (
            <div className="flex items-center gap-[1rem] text-[1.4rem]">
              {item.score && <span className="font-bold tabular-nums text-white">{item.score}</span>}
              {item.clock && <span className="font-semibold text-[var(--live)]">{item.clock}</span>}
              {item.startsIn && <span className="text-[var(--text-medium)]">{item.startsIn}</span>}
            </div>
          )}

          <p className="max-w-[60ch] text-[1.35rem] text-[var(--text-medium)]">{synopsis(item)}</p>

          <div className="mt-[0.6rem] flex flex-wrap items-center gap-[1rem]">
            {item.live === "upcoming" ? (
              <button
                data-focusable
                className="focusable rounded-[var(--radius)] bg-[var(--gold)] px-[1.6rem] py-[0.8rem] text-[1.25rem] font-bold text-black"
              >
                🔔 Me rappeler
              </button>
            ) : (
              <Link
                href={`/watch/${item.id}`}
                data-focusable
                className="focusable flex items-center gap-[0.6rem] rounded-[var(--radius)] bg-[var(--gold)] px-[1.6rem] py-[0.8rem] text-[1.25rem] font-bold text-black"
              >
                <svg className="h-[1.3rem] w-[1.3rem]" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M8 5v14l11-7z" />
                </svg>
                {item.live === "live" ? "Regarder en direct" : item.progress ? "Reprendre" : "Lecture"}
              </Link>
            )}
            <button
              data-focusable
              className="focusable rounded-[var(--radius)] bg-white/15 px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold text-[var(--text-high)]"
            >
              + Ma liste
            </button>
            <Link
              href={kind === "sport" ? "/sport" : "/formation"}
              data-focusable
              className="focusable rounded-[var(--radius)] bg-white/10 px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold text-[var(--text-medium)]"
            >
              ← Retour
            </Link>
          </div>
        </div>
      </header>

      <div className="px-[var(--safe-x)] pt-[1.5rem]">
        {/* Lesson list for courses. */}
        {kind === "formation" && lessonCount > 0 && (
          <section className="mb-[2.4rem]">
            <h2 className="mb-[0.9rem] text-[1.5rem] font-bold text-[var(--text-high)]">Programme</h2>
            <ol className="flex flex-col gap-[0.6rem]">
              {Array.from({ length: Math.min(lessonCount, 8) }).map((_, idx) => (
                <li key={idx}>
                  <Link
                    href={`/watch/${item.id}`}
                    data-focusable
                    className="focusable flex items-center gap-[1.2rem] rounded-[var(--radius)] bg-[var(--surface-1)] px-[1.2rem] py-[0.9rem]"
                  >
                    <span className="text-[1.3rem] font-bold tabular-nums text-[var(--gold)]">
                      {String(idx + 1).padStart(2, "0")}
                    </span>
                    <span className="flex-1 text-[1.2rem] font-semibold text-[var(--text-high)]">
                      Leçon {idx + 1}
                    </span>
                    <span className="text-[1.05rem] text-[var(--text-medium)]">
                      {8 + ((idx * 3) % 9)} min
                    </span>
                  </Link>
                </li>
              ))}
            </ol>
          </section>
        )}

        {related.length > 0 && (
          <Row row={{ id: "related", title: kind === "sport" ? "Dans la même catégorie" : "Plus comme ça", items: related }} />
        )}
      </div>
    </div>
  );
}
