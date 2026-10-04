import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { ListPager } from '@/components/ListPager';
import { EntityLink } from '@/components/fiches/EntityLink';
import { useFicheOpener } from '@/components/fiches/fiche-context';
import { usePanelFlag } from '@/components/fiches/usePanelFlag';
import { FLAG_FICHES } from '@/lib/flags';
import { cibleClient } from '@/lib/fiches';
import {
  Alert, EmptyState, LoadingRows, SearchField, SortTh, TableFrame, useClientTable,
} from '@/components/ui';
import { customersApi, type Customer, ApiError, isAbortError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { LIST_PAGE_SIZE, createAbortBag, createGeneration, readListPage } from '@/lib/robust';

export function CustomersPage({ onLogout }: { onLogout: () => void }) {
  const navigate = useNavigate();
  const [fichesOn] = usePanelFlag(FLAG_FICHES);
  const openFiche = useFicheOpener();
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
      <SearchField
        label="Rechercher un client"
        value={q}
        onChange={(value) => { setQ(value); setOffset(0); }}
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
              <tr
                key={c.id}
                className={'transition duration-150 hover:bg-midnight' + (fichesOn ? ' cursor-pointer' : '')}
                onClick={() => {
                  if (!fichesOn) return;
                  const cible = cibleClient(c.id);
                  if (cible) openFiche(cible);
                }}
              >
                <td className="px-4 py-3 font-medium">
                  <EntityLink cible={cibleClient(c.id)}>{c.name || '—'}</EntityLink>
                </td>
                <td className="px-4 py-3 text-ink-secondary">{c.email || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{c.phone || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{formatDateTime(c.created_at)}</td>
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
