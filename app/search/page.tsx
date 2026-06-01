/*
 * Search is intentionally browse-first and minimal: text entry on a remote is
 * high-friction, so we surface quick category chips rather than a keyboard.
 */
const SUGGESTIONS = ["Football", "Basket", "Tennis", "F1", "Leadership", "Yoga", "Nutrition", "HIIT"];

export default function SearchPage() {
  return (
    <div className="pl-[var(--safe-x)] pr-[var(--safe-x)] pt-[var(--safe-y)]">
      <h1 className="mb-[1.5rem] text-[2.6rem] font-extrabold tracking-tight text-[var(--text-high)]">
        Rechercher
      </h1>
      <div
        data-focusable
        className="focusable mb-[2rem] flex max-w-[40rem] items-center gap-[0.8rem] rounded-[var(--radius)] bg-[var(--surface-2)] px-[1.2rem] py-[1rem] text-[1.3rem] text-[var(--text-medium)]"
      >
        <svg className="h-[1.5rem] w-[1.5rem]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="11" cy="11" r="7" /><path d="m20 20-3-3" strokeLinecap="round" />
        </svg>
        Dites un titre, une équipe ou un thème…
      </div>
      <p className="mb-[1rem] text-[1.3rem] font-semibold text-[var(--text-high)]">Suggestions</p>
      <div className="flex flex-wrap gap-[0.8rem]">
        {SUGGESTIONS.map((s) => (
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
