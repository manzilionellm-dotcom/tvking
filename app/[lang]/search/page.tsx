import { pageI18n } from "../../i18n/server";

/*
 * Search is intentionally browse-first and minimal: text entry on a remote is
 * high-friction, so we surface quick category chips rather than a keyboard.
 */
export default async function SearchPage({ params }: PageProps<"/[lang]/search">) {
  const { m } = await pageI18n(params);
  return (
    <div className="pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="font-display mb-[1.5rem] text-[3rem] font-extrabold tracking-tight text-[var(--text-high)]">
        {m.search.title}
      </h1>
      <div
        data-focusable
        className="focusable mb-[2rem] flex max-w-[40rem] items-center gap-[0.8rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[1rem] text-[1.3rem] text-[var(--text-medium)]"
      >
        <svg className="h-[1.5rem] w-[1.5rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="11" cy="11" r="7" /><path d="m20 20-3-3" strokeLinecap="round" />
        </svg>
        {m.search.placeholder}
      </div>
      <p className="mb-[1rem] text-[1.3rem] font-semibold text-[var(--text-high)]">{m.search.suggestions}</p>
      <div className="flex flex-wrap gap-[0.8rem]">
        {m.data.suggestions.map((s) => (
          <button
            key={s}
            data-focusable
            className="focusable rounded-full bg-[var(--surface-2)] px-[1.4rem] py-[0.7rem] text-[1.15rem] font-semibold text-[var(--text-high)]"
          >
            {s}
          </button>
        ))}
      </div>
    </div>
  );
}
