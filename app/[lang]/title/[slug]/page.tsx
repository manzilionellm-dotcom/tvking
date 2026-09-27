import Link from "next/link";
import { notFound } from "next/navigation";
import Row from "../../../components/Row";
import FilmActions from "../../../components/FilmActions";
import { LevelBadge, LiveBadge } from "../../../components/Badge";
import { allItems, getItem, kindOf, relatedTo, type MediaItem } from "../../../lib/data";
import { localeHref } from "../../../i18n/config";
import { fmt, type Messages } from "../../../i18n/messages";
import { localizeItem } from "../../../i18n/localize";
import { pageI18n } from "../../../i18n/server";

/* Pre-render a detail page for every known item. */
export function generateStaticParams() {
  return allItems.map((it) => ({ slug: it.id }));
}

function synopsis(item: MediaItem, m: Messages) {
  if (item.description) return item.description;
  const vars = { title: item.title };
  if (kindOf(item) === "sport") {
    if (item.live === "live") return fmt(m.synopsis.live, vars);
    if (item.live === "upcoming") return fmt(m.synopsis.upcoming, vars);
    return fmt(m.synopsis.replay, vars);
  }
  return fmt(m.synopsis.course, vars);
}

export default async function TitlePage({ params }: PageProps<"/[lang]/title/[slug]">) {
  const { slug } = await params;
  const { lang, m } = await pageI18n(params);
  const raw = getItem(slug);
  if (!raw) notFound();
  const item = localizeItem(raw, m);
  const h = (p: string) => localeHref(lang, p);

  const kind = kindOf(item);
  const related = relatedTo(raw).map((it) => localizeItem(it, m));
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
            {item.genre && (
              <span className="text-[1.05rem] font-semibold text-[var(--text-medium)]">{item.genre}</span>
            )}
            {item.year && (
              <span className="text-[1.05rem] text-[var(--text-medium)]">{item.year}</span>
            )}
            {item.league && (
              <span className="text-[1.05rem] font-semibold text-[var(--text-medium)]">{item.league}</span>
            )}
            {item.duration && (
              <span className="text-[1.05rem] text-[var(--text-medium)]">{item.duration}</span>
            )}
            {lessonCount > 0 && (
              <span className="text-[1.05rem] text-[var(--text-medium)]">{fmt(m.common.lessons, { n: lessonCount })}</span>
            )}
            {item.instructor && (
              <span className="text-[1.05rem] text-[var(--text-medium)]">{fmt(m.common.with, { name: item.instructor })}</span>
            )}
          </div>

          <h1 className="font-display max-w-[34ch] text-[3.8rem] font-extrabold leading-[1.04] tracking-tight text-[var(--text-high)] [text-shadow:0_0.2rem_1.5rem_rgba(0,0,0,0.5)]">
            {item.title}
          </h1>

          {(item.score || item.clock || item.startsIn) && (
            <div className="flex items-center gap-[1rem] text-[1.4rem]">
              {item.score && <span className="font-bold tabular-nums text-white">{item.score}</span>}
              {item.clock && <span className="font-semibold text-[var(--live)]">{item.clock}</span>}
              {item.startsIn && <span className="text-[var(--text-medium)]">{item.startsIn}</span>}
            </div>
          )}

          <p className="max-w-[60ch] text-[1.35rem] text-[var(--text-medium)]">{synopsis(item, m)}</p>

          <div className="mt-[0.6rem] flex flex-wrap items-center gap-[1rem]">
            {kind === "film" ? (
              /* Films: auto-download with a determinate bar, then instant play —
                 never a buffering spinner. */
              <FilmActions item={item} />
            ) : item.live === "upcoming" ? (
              <button
                data-focusable
                data-focus-default
                className="focusable rounded-[var(--radius)] px-[1.6rem] py-[0.8rem] text-[1.25rem] font-bold text-black shadow-[0_0.6rem_1.6rem_rgba(227,185,107,0.35)]"
                style={{ background: "var(--gold-grad)" }}
              >
                {m.common.remindMe}
              </button>
            ) : (
              <Link
                href={h(`/watch/${item.id}`)}
                data-focusable
                data-focus-default
                className="focusable flex items-center gap-[0.6rem] rounded-[var(--radius)] px-[1.6rem] py-[0.8rem] text-[1.25rem] font-bold text-black shadow-[0_0.6rem_1.6rem_rgba(227,185,107,0.35)]"
                style={{ background: "var(--gold-grad)" }}
              >
                <svg className="h-[1.3rem] w-[1.3rem]" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M8 5v14l11-7z" />
                </svg>
                {item.live === "live" ? m.common.watchLive : item.progress ? m.common.resume : m.common.play}
              </Link>
            )}
            <button
              data-focusable
              className="focusable rounded-[var(--radius)] bg-white/15 px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold text-[var(--text-high)]"
            >
              {m.common.addToList}
            </button>
            <Link
              href={h(kind === "sport" ? "/sport" : kind === "film" ? "/films" : "/formation")}
              data-focusable
              className="focusable rounded-[var(--radius)] bg-white/10 px-[1.4rem] py-[0.8rem] text-[1.25rem] font-semibold text-[var(--text-medium)]"
            >
              {m.common.back}
            </Link>
          </div>
        </div>
      </header>

      <div className="px-[var(--safe-x)] pt-[1.5rem]">
        {/* Lesson list for courses. */}
        {kind === "formation" && lessonCount > 0 && (
          <section className="mb-[2.4rem]">
            <h2 className="mb-[0.9rem] text-[1.5rem] font-bold text-[var(--text-high)]">{m.common.program}</h2>
            <ol className="flex flex-col gap-[0.6rem]">
              {Array.from({ length: Math.min(lessonCount, 8) }).map((_, idx) => (
                <li key={idx}>
                  <Link
                    href={h(`/watch/${item.id}`)}
                    data-focusable
                    className="focusable flex items-center gap-[1.2rem] rounded-[var(--radius)] bg-[var(--surface-1)] px-[1.2rem] py-[0.9rem]"
                  >
                    <span className="text-[1.3rem] font-bold tabular-nums text-[var(--gold)]">
                      {String(idx + 1).padStart(2, "0")}
                    </span>
                    <span className="flex-1 text-[1.2rem] font-semibold text-[var(--text-high)]">
                      {fmt(m.common.lesson, { n: idx + 1 })}
                    </span>
                    <span className="text-[1.05rem] text-[var(--text-medium)]">
                      {fmt(m.common.minutes, { n: 8 + ((idx * 3) % 9) })}
                    </span>
                  </Link>
                </li>
              ))}
            </ol>
          </section>
        )}

        {related.length > 0 && (
          <Row row={{ id: "related", title: kind === "sport" ? m.common.sameCategory : m.common.moreLikeThis, items: related }} />
        )}
      </div>
    </div>
  );
}
