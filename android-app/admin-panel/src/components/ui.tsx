import { useId, useState, type ReactNode } from 'react';
import { cn } from '@/lib/utils';
import {
  filterRows, pageWindow, sortRows, type SortDir,
} from '@/lib/tableView';

// Pastilles d'état. Le code technique (active, expired…) reste en données ;
// seul le libellé affiché est en français.

const TONE_CLASS: Record<string, string> = {
  ok: 'bg-success/15 text-success',
  online: 'bg-success/15 text-success',
  offline: 'bg-white/[0.06] text-ink-secondary',
  expired: 'bg-warning/15 text-warning',
  warn: 'bg-warning/15 text-warning',
  danger: 'bg-accent/20 text-accent-bright',
  neutral: 'bg-white/[0.06] text-ink-secondary',
};

const STATUS_FR: Record<string, { label: string; tone: string }> = {
  active: { label: 'Actif', tone: 'ok' },
  online: { label: 'En ligne', tone: 'online' },
  offline: { label: 'Hors ligne', tone: 'offline' },
  expired: { label: 'Expiré', tone: 'expired' },
  frozen: { label: 'Gelé', tone: 'warn' },
  banned: { label: 'Banni', tone: 'danger' },
  pending: { label: 'En attente', tone: 'warn' },
  suspended: { label: 'Suspendu', tone: 'warn' },
};

function dotClass(status: string): string {
  if (status === 'online' || status === 'active') return 'bg-success';
  if (status === 'expired' || status === 'frozen' || status === 'pending' || status === 'suspended') {
    return 'bg-warning';
  }
  if (status === 'banned') return 'bg-accent-bright';
  return 'bg-ink-tertiary';
}

export function StatusBadge({ status, label }: { status: string; label?: string }) {
  const known = STATUS_FR[status] || { label: label || status, tone: 'neutral' };
  const text = label || known.label;
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-semibold',
        TONE_CLASS[known.tone] || TONE_CLASS.neutral,
      )}
    >
      <span aria-hidden="true" className={cn('h-1.5 w-1.5 shrink-0 rounded-full', dotClass(status))} />
      {text}
    </span>
  );
}

export function Alert({
  children,
  tone = 'error',
}: {
  children: ReactNode;
  tone?: 'error' | 'ok';
}) {
  const ok = tone === 'ok';
  return (
    <div
      role={ok ? 'status' : 'alert'}
      className={cn(
        'mb-4 rounded-lg border px-4 py-3 text-sm leading-relaxed',
        ok
          ? 'border-success/30 bg-success/10 text-success'
          : 'border-accent/40 bg-accent/10 text-accent-bright',
      )}
    >
      {children}
    </div>
  );
}

export function EmptyState({
  title,
  hint,
  action,
}: {
  title: string;
  hint?: string;
  action?: ReactNode;
}) {
  return (
    <div className="px-4 py-12 text-center">
      <p className="text-sm font-medium text-ink-primary">{title}</p>
      {hint && (
        <p className="mx-auto mt-1 max-w-md text-sm leading-relaxed text-ink-secondary">{hint}</p>
      )}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function LoadingRows({ cols }: { cols: number }) {
  return (
    <>
      {Array.from({ length: 5 }).map((_, i) => (
        <tr key={i}>
          <td colSpan={cols} className="px-4 py-3">
            <div className="h-4 animate-pulse rounded bg-white/5" />
            <span className="sr-only">Chargement…</span>
          </td>
        </tr>
      ))}
    </>
  );
}

export function SearchField({
  value,
  onChange,
  label,
  placeholder,
}: {
  value: string;
  onChange: (value: string) => void;
  label: string;
  placeholder?: string;
}) {
  const id = useId();
  return (
    <div className="mb-4 w-full max-w-md">
      <label htmlFor={id} className="mb-1.5 block text-xs font-medium text-ink-secondary">
        {label}
      </label>
      <input
        id={id}
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-md border border-white/10 bg-midnight px-3 py-2.5 text-sm text-ink-primary outline-none placeholder:text-ink-tertiary focus:border-accent/60 focus:ring-2 focus:ring-accent/40"
      />
    </div>
  );
}

export function TableFrame({
  children,
  busy,
  label,
}: {
  children: ReactNode;
  busy?: boolean;
  label: string;
}) {
  return (
    <div className="overflow-x-auto rounded-xl border border-white/10 bg-obsidian">
      <table
        aria-label={label}
        aria-busy={busy || undefined}
        className="w-full min-w-[640px] text-sm"
      >
        {children}
      </table>
    </div>
  );
}

export function SortTh({
  label,
  column,
  sortKey,
  dir,
  onSort,
  align,
}: {
  label: string;
  column: string;
  sortKey: string;
  dir: SortDir;
  onSort: (column: string) => void;
  align?: 'right';
}) {
  const active = sortKey === column;
  return (
    <th
      scope="col"
      aria-sort={active ? (dir === 'asc' ? 'ascending' : 'descending') : 'none'}
      className={cn('px-4 py-3', align === 'right' && 'text-right')}
    >
      <button
        type="button"
        onClick={() => onSort(column)}
        className={cn(
          'inline-flex items-center gap-1 text-[10px] font-semibold uppercase tracking-widest text-ink-secondary hover:text-ink-primary',
          align === 'right' && 'flex-row-reverse',
        )}
      >
        {label}
        <span aria-hidden="true" className={active ? 'text-accent-bright' : 'opacity-40'}>
          {active ? (dir === 'asc' ? '↑' : '↓') : '↕'}
        </span>
      </button>
    </th>
  );
}

export function Pager({
  page,
  pages,
  start,
  end,
  total,
  onPage,
}: {
  page: number;
  pages: number;
  start: number;
  end: number;
  total: number;
  onPage: (page: number) => void;
}) {
  if (total === 0) return null;
  const from = start + 1;
  return (
    <div className="mt-3 flex flex-wrap items-center justify-between gap-3 text-sm text-ink-secondary">
      <p>
        {from}–{end} sur {total}
      </p>
      {pages > 1 && (
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => onPage(page - 1)}
            disabled={page <= 1}
            className="rounded-md border border-white/10 px-3 py-1.5 text-xs font-medium text-ink-primary hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Précédent
          </button>
          <span className="text-xs">
            Page {page} sur {pages}
          </span>
          <button
            type="button"
            onClick={() => onPage(page + 1)}
            disabled={page >= pages}
            className="rounded-md border border-white/10 px-3 py-1.5 text-xs font-medium text-ink-primary hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-40"
          >
            Suivant
          </button>
        </div>
      )}
    </div>
  );
}

export function useClientTable<T>(
  rows: readonly T[],
  opts: {
    pageSize?: number;
    valueOf: (row: T, key: string) => unknown;
    textOf?: (row: T) => string;
    query?: string;
  },
) {
  const pageSize = opts.pageSize ?? 20;
  const [sortKey, setSortKey] = useState('');
  const [dir, setDir] = useState<SortDir>('asc');
  const [page, setPage] = useState(1);
  const [innerQuery, setInnerQuery] = useState('');
  const query = opts.query !== undefined ? opts.query : innerQuery;
  const signature = `${rows.length}:${query}`;
  const [seen, setSeen] = useState(signature);
  if (signature !== seen) {
    setSeen(signature);
    setPage(1);
  }

  const filtered = opts.textOf ? filterRows(rows, query, opts.textOf) : rows.slice();
  const sorted = sortKey ? sortRows(filtered, sortKey, dir, opts.valueOf) : filtered;
  const win = pageWindow(sorted.length, page, pageSize);
  const view = sorted.slice(win.start, win.end);

  function toggleSort(column: string) {
    setPage(1);
    if (sortKey === column) {
      setDir((current) => (current === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(column);
      setDir('asc');
    }
  }

  return {
    rows: view,
    total: sorted.length,
    page: win.page,
    pages: win.pages,
    start: win.start,
    end: win.end,
    sortKey,
    dir,
    toggleSort,
    setPage,
    query,
    setQuery: setInnerQuery,
  };
}
