// =========================================================
//  ListPager — « 1–100 sur 3 500 » + précédent / suivant
// =========================================================
//  Sans ça, le panel affichait « 200 appareils » alors que la base
//  en contenait des milliers (LIMIT muet côté Worker).
// =========================================================

export function ListPager({
  total,
  offset,
  count,
  limit,
  truncated,
  onOffset,
}: {
  total: number;
  offset: number;
  count: number;
  limit: number;
  truncated: boolean;
  onOffset: (next: number) => void;
}) {
  if (total <= count && offset === 0 && !truncated) return null;
  const from = total === 0 ? 0 : offset + 1;
  const to = offset + count;
  const step = limit > 0 ? limit : count || 100;
  return (
    <div className="mt-3 flex flex-wrap items-center justify-between gap-3 text-xs text-ink-tertiary">
      <span>{from}–{to} sur {total}</span>
      <div className="flex gap-2">
        <button
          type="button"
          disabled={offset <= 0}
          onClick={() => onOffset(Math.max(0, offset - step))}
          className="rounded-md border border-white/10 px-3 py-1.5 text-ink-secondary transition hover:border-white/30 disabled:opacity-40"
        >
          Précédent
        </button>
        <button
          type="button"
          disabled={!truncated}
          onClick={() => onOffset(offset + step)}
          className="rounded-md border border-white/10 px-3 py-1.5 text-ink-secondary transition hover:border-white/30 disabled:opacity-40"
        >
          Suivant
        </button>
      </div>
    </div>
  );
}
