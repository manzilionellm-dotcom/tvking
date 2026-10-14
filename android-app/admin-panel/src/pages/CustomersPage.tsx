import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import {
  Alert, EmptyState, LoadingRows, Pager, SearchField, SortTh, TableFrame, useClientTable,
} from '@/components/ui';
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

  const table = useClientTable(items, {
    query: q,
    valueOf: (c, key) => {
      if (key === 'name') return c.name || '';
      if (key === 'email') return c.email || '';
      if (key === 'phone') return c.phone || '';
      if (key === 'created') return c.created_at || 0;
      return '';
    },
  });

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
      <SearchField
        label="Rechercher un client"
        value={q}
        onChange={setQ}
        placeholder="Nom, e-mail, téléphone…"
      />

      {err && <Alert>{err}</Alert>}

      <TableFrame label="Liste des clients" busy={loading}>
          <thead className="bg-midnight text-left">
            <tr>
              <SortTh label="Nom" column="name" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="E-mail" column="email" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Téléphone" column="phone" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Créé le" column="created" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && <LoadingRows cols={4} />}
            {!loading && table.total === 0 && (
              <tr>
                <td colSpan={4}>
                  <EmptyState
                    title={q ? `Aucun client pour « ${q} ».` : 'Aucun client pour l’instant.'}
                    hint={q ? 'Vérifie l’orthographe ou élargis la recherche.' : 'Un client apparaît ici dès qu’un appareil est activé.'}
                    action={!q ? (
                      <Link
                        to="/activate"
                        className="inline-flex rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-obsidian hover:bg-accent-bright"
                      >
                        Activer un client
                      </Link>
                    ) : undefined}
                  />
                </td>
              </tr>
            )}
            {!loading && table.rows.map((c) => (
              <tr key={c.id} className="transition duration-150 hover:bg-midnight">
                <td className="px-4 py-3 font-medium">{c.name || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{c.email || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{c.phone || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{formatDateTime(c.created_at)}</td>
              </tr>
            ))}
          </tbody>
      </TableFrame>
      <Pager
        page={table.page}
        pages={table.pages}
        start={table.start}
        end={table.end}
        total={table.total}
        onPage={table.setPage}
      />
    </AppLayout>
  );
}
