import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { ListPager } from '@/components/ListPager';
import { customersApi, type Customer, ApiError, isAbortError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { LIST_PAGE_SIZE, createAbortBag, createGeneration, readListPage } from '@/lib/robust';

export function CustomersPage({ onLogout }: { onLogout: () => void }) {
  const navigate = useNavigate();
  const [items, setItems] = useState<Customer[]>([]);
  const [q, setQ] = useState('');
  const [offset, setOffset] = useState(0);
  const [total, setTotal] = useState(0);
  const [truncated, setTruncated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const gen = useRef(createGeneration());
  const aborts = useRef(createAbortBag());

  const load = useCallback(() => {
    const id = gen.current.next();
    const signal = aborts.current.next();
    setLoading(true);
    customersApi.list(q, { limit: LIST_PAGE_SIZE, offset }, signal)
      .then((r) => {
        if (!gen.current.isCurrent(id)) return;
        const page = readListPage<Customer>(r);
        setItems(page.items);
        setTotal(page.total);
        setTruncated(page.truncated);
        setErr(null);
      })
      .catch((e) => {
        if (isAbortError(e) || !gen.current.isCurrent(id)) return;
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => { if (gen.current.isCurrent(id)) setLoading(false); });
  }, [q, offset, onLogout]);

  // Debounce : chaque lettre ne doit pas frapper l'API.
  useEffect(() => {
    const t = setTimeout(load, 200);
    return () => { clearTimeout(t); aborts.current.abort(); };
  }, [load]);

  return (
    <AppLayout
      title="Clients"
      subtitle={`${total} client${total !== 1 ? 's' : ''}${q ? ` correspondant à « ${q} »` : ''}`}
      onLogout={onLogout}
      actions={
        <button
          onClick={() => navigate('/activate')}
          className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black transition duration-150 hover:bg-accent-bright"
        >
          + Activer un client
        </button>
      }
    >
      <input
        type="search"
        value={q}
        onChange={(e) => { setQ(e.target.value); setOffset(0); }}
        placeholder="Recherche par nom, email, téléphone…"
        className="mb-4 w-full max-w-md rounded-md border border-white/5 bg-midnight px-3 py-2 text-sm outline-none transition duration-150 focus:ring-1 focus:ring-accent"
      />

      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-x-auto rounded-xl border border-white/5">
        <table className="w-full text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">Nom</th>
              <th className="px-4 py-3">Email</th>
              <th className="px-4 py-3">Téléphone</th>
              <th className="px-4 py-3">Créé le</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && Array.from({ length: 5 }).map((_, i) => (
              <tr key={i} className="bg-obsidian">
                <td className="px-4 py-3" colSpan={4}>
                  <div className="h-4 w-full animate-pulse rounded bg-white/5" />
                </td>
              </tr>
            ))}
            {!loading && items.length === 0 && (
              <tr>
                <td colSpan={4} className="px-4 py-10 text-center">
                  <p className="text-sm text-ink-secondary">
                    {q
                      ? `Aucun client trouvé pour « ${q} ».`
                      : 'Aucun client pour l\'instant.'}
                  </p>
                  {!q && (
                    <Link
                      to="/activate"
                      className="mt-3 inline-flex rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black transition duration-150 hover:bg-accent-bright"
                    >
                      Activer un client
                    </Link>
                  )}
                </td>
              </tr>
            )}
            {items.map((c) => (
              <tr key={c.id} className="bg-obsidian transition duration-150 hover:bg-midnight">
                <td className="px-4 py-3 font-medium">{c.name || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{c.email || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{c.phone || '—'}</td>
                <td className="px-4 py-3 text-ink-tertiary">{formatDateTime(c.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ListPager
        total={total}
        offset={offset}
        count={items.length}
        limit={LIST_PAGE_SIZE}
        truncated={truncated}
        onOffset={setOffset}
      />
    </AppLayout>
  );
}
