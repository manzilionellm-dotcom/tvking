import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { ListPager } from '@/components/ListPager';
import { licensesApi, type License, ApiError, isAbortError } from '@/lib/api';
import { LIST_PAGE_SIZE, createAbortBag, createGeneration, expiryPhrase, readListPage } from '@/lib/robust';

export function ActivationsPage({ onLogout }: { onLogout: () => void }) {
  const navigate = useNavigate();
  const [items, setItems] = useState<License[]>([]);
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
    licensesApi.list({ limit: LIST_PAGE_SIZE, offset }, signal)
      .then((r) => {
        if (!gen.current.isCurrent(id)) return;
        const page = readListPage<License>(r);
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
  }, [offset, onLogout]);

  useEffect(() => { load(); }, [load]);

  return (
    <AppLayout
      title="Activations"
      subtitle={`${total} licence(s) — statut recalculé à la date du jour (heure de Paris).`}
      onLogout={onLogout}
      actions={
        <button
          onClick={() => navigate('/activate')}
          className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black transition duration-150 hover:bg-accent-bright"
        >
          + Activer un MAC
        </button>
      }
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-hidden rounded-xl border border-white/5">
        <table className="w-full text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">Client</th>
              <th className="px-4 py-3">App</th>
              <th className="px-4 py-3">Device MAC</th>
              <th className="px-4 py-3">Plan</th>
              <th className="px-4 py-3">Statut</th>
              <th className="px-4 py-3">Expire le</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && Array.from({ length: 5 }).map((_, i) => (
              <tr key={i} className="bg-obsidian">
                <td className="px-4 py-3" colSpan={6}>
                  <div className="h-4 w-full animate-pulse rounded bg-white/5" />
                </td>
              </tr>
            ))}
            {!loading && items.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-10 text-center">
                  <p className="text-sm text-ink-secondary">Aucune activation — Activer un appareil</p>
                  <Link
                    to="/activate"
                    className="mt-3 inline-flex rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black transition duration-150 hover:bg-accent-bright"
                  >
                    Activer un appareil
                  </Link>
                </td>
              </tr>
            )}
            {items.map((l) => (
              <tr key={l.id} className="bg-obsidian transition duration-150 hover:bg-midnight">
                <td className="px-4 py-3 font-medium">{l.customer_name || l.customer_email || '—'}</td>
                <td className="px-4 py-3">{l.app_name || '—'}</td>
                <td className="px-4 py-3 font-mono text-xs text-accent">{l.device_mac}</td>
                <td className="px-4 py-3 text-ink-secondary uppercase tracking-wider text-[10px]">{l.plan}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-sm px-2 py-0.5 text-[9px] uppercase tracking-widest ${statusClass(l.status)}`}>
                    {l.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-ink-tertiary">{expiryPhrase(l.expires_at)}</td>
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

function statusClass(s: string): string {
  switch (s) {
    case 'active':  return 'bg-accent/20 text-accent';
    case 'expired': return 'bg-white/5 text-ink-tertiary';
    case 'frozen':  return 'bg-champagne/15 text-champagne';
    case 'banned':  return 'bg-accent/30 text-accent-bright';
    case 'pending': return 'bg-white/10 text-ink-secondary';
    default:        return 'bg-white/5 text-ink-tertiary';
  }
}
