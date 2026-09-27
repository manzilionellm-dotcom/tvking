import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { customersApi, type Customer, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

export function CustomersPage({ onLogout }: { onLogout: () => void }) {
  const navigate = useNavigate();
  const [items, setItems] = useState<Customer[]>([]);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    customersApi.list(q)
      .then((r) => { if (active) { setItems(r.items); setErr(null); } })
      .catch((e) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [q, onLogout]);

  return (
    <AppLayout
      title="Clients"
      subtitle={`${items.length} client${items.length !== 1 ? 's' : ''}${q ? ` correspondant à « ${q} »` : ''}`}
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
        onChange={(e) => setQ(e.target.value)}
        placeholder="Recherche par nom, email, téléphone…"
        className="mb-4 w-full max-w-md rounded-md border border-white/5 bg-midnight px-3 py-2 text-sm outline-none transition duration-150 focus:ring-1 focus:ring-accent"
      />

      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-hidden rounded-xl border border-white/5">
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
    </AppLayout>
  );
}
