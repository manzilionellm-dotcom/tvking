import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { ListPager } from '@/components/ListPager';
import {
  Alert, EmptyState, LoadingRows, SearchField, SortTh, StatusBadge,
  TableFrame, useClientTable,
} from '@/components/ui';
import { licensesApi, type License, ApiError, isAbortError } from '@/lib/api';
import { LIST_PAGE_SIZE, createAbortBag, createGeneration, expiryPhrase, readListPage } from '@/lib/robust';

const PLAN_FR: Record<string, string> = {
  monthly: '1 mois', quarterly: '3 mois', biannual: '6 mois',
  yearly: '1 an', lifetime: 'À vie',
};

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

  const table = useClientTable(items, {
    textOf: (l) => [l.customer_name, l.customer_email, l.app_name, l.device_mac, l.plan, l.status].filter(Boolean).join(' '),
    valueOf: (l, key) => {
      if (key === 'client') return l.customer_name || l.customer_email || '';
      if (key === 'app') return l.app_name || '';
      if (key === 'mac') return l.device_mac || '';
      if (key === 'plan') return l.plan || '';
      if (key === 'status') return l.status || '';
      if (key === 'expires') return l.expires_at ?? Number.MAX_SAFE_INTEGER;
      return '';
    },
  });

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
          + Activer une MAC
        </button>
      }
    >
      {err && <Alert>{err}</Alert>}

      <SearchField
        label="Filtrer les activations"
        value={table.query}
        onChange={table.setQuery}
        placeholder="Client, application, MAC…"
      />

      <TableFrame label="Liste des activations" busy={loading}>
          <thead className="bg-midnight text-left">
            <tr>
              <SortTh label="Client" column="client" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Application" column="app" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="MAC" column="mac" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Durée" column="plan" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Statut" column="status" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Expire le" column="expires" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && <LoadingRows cols={6} />}
            {!loading && table.total === 0 && (
              <tr>
                <td colSpan={6}>
                  <EmptyState
                    title={table.query ? `Aucune activation pour « ${table.query} ».` : 'Aucune activation pour l’instant.'}
                    hint={table.query ? 'Essaie un autre nom ou une autre MAC.' : 'Active un appareil pour le voir apparaître ici.'}
                    action={!table.query ? (
                      <Link
                        to="/activate"
                        className="inline-flex rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-obsidian hover:bg-accent-bright"
                      >
                        Activer un appareil
                      </Link>
                    ) : undefined}
                  />
                </td>
              </tr>
            )}
            {!loading && table.rows.map((l) => (
              <tr key={l.id} className="transition duration-150 hover:bg-midnight">
                <td className="px-4 py-3 font-medium">{l.customer_name || l.customer_email || '—'}</td>
                <td className="px-4 py-3">{l.app_name || '—'}</td>
                <td className="px-4 py-3 font-mono text-xs text-accent">{l.device_mac}</td>
                <td className="px-4 py-3 text-ink-secondary">{PLAN_FR[l.plan] || l.plan}</td>
                <td className="px-4 py-3"><StatusBadge status={l.status} /></td>
                <td className="px-4 py-3 text-ink-secondary">{expiryPhrase(l.expires_at)}</td>
              </tr>
            ))}
          </tbody>
      </TableFrame>
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
