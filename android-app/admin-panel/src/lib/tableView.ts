// Tri, filtre et pagination côté écran.
// Les données viennent déjà de l'API : on ne rappelle pas le serveur.

export type SortDir = 'asc' | 'desc';

export function compareValues(a: unknown, b: unknown): number {
  if (a == null && b == null) return 0;
  if (a == null || a === '') return 1;
  if (b == null || b === '') return -1;
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return String(a).localeCompare(String(b), 'fr', {
    sensitivity: 'base',
    numeric: true,
  });
}

export function sortRows<T>(
  rows: readonly T[],
  key: string,
  dir: SortDir,
  valueOf: (row: T, key: string) => unknown,
): T[] {
  const copy = rows.slice();
  copy.sort((left, right) => {
    const cmp = compareValues(valueOf(left, key), valueOf(right, key));
    return dir === 'asc' ? cmp : -cmp;
  });
  return copy;
}

export function filterRows<T>(
  rows: readonly T[],
  query: string,
  textOf: (row: T) => string,
): T[] {
  const needle = query.trim().toLocaleLowerCase('fr');
  if (!needle) return rows.slice();
  return rows.filter((row) => textOf(row).toLocaleLowerCase('fr').includes(needle));
}

export function pageWindow(total: number, page: number, pageSize: number) {
  const pages = Math.max(1, Math.ceil(total / pageSize) || 1);
  const safe = Math.min(Math.max(1, page), pages);
  const start = total === 0 ? 0 : (safe - 1) * pageSize;
  const end = Math.min(start + pageSize, total);
  return { page: safe, pages, start, end };
}
