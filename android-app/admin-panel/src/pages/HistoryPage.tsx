import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  Alert, EmptyState, LoadingRows, Pager, SearchField, SortTh, TableFrame, useClientTable,
} from '@/components/ui';
import { auditApi, type AuditLog, ApiError } from '@/lib/api';

// =========================================================
//  HistoryPage — historique des modifications (audit log)
// =========================================================
//  Lecture seule : qui a fait quoi et quand (théme, revendeurs, licences,
//  annonces…). Complète l'« Admin Experience ». Owner uniquement.
// =========================================================

/// Libellés FR lisibles pour les codes d'action techniques.
const ACTION_LABELS: Record<string, string> = {
  'theme.save': 'Thème modifié',
  'theme.automations.save': 'Automatisation du thème',
  'reseller.update': 'Revendeur modifié',
  'reseller.create': 'Revendeur créé',
  'license.update': 'Licence modifiée',
  'license.renew': 'Licence renouvelée',
  'plan_costs.update': 'Tarifs modifiés',
  'password.change_self': 'Mot de passe changé',
};

function fmtDate(ms: number): string {
  try { return new Date(ms).toLocaleString('fr-FR'); } catch { return String(ms); }
}

export function HistoryPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    auditApi.list()
      .then((r) => setItems(r.items || []))
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  const table = useClientTable(items, {
    textOf: (it) => [ACTION_LABELS[it.action] || it.action, it.actor_type, it.target_type, it.target_id].filter(Boolean).join(' '),
    valueOf: (it, key) => {
      if (key === 'when') return it.created_at || 0;
      if (key === 'action') return ACTION_LABELS[it.action] || it.action;
      if (key === 'who') return it.actor_type || '';
      if (key === 'target') return `${it.target_type || ''} ${it.target_id || ''}`;
      return '';
    },
  });

  return (
    <AppLayout
      title="Historique"
      subtitle="Qui a fait quoi, et quand"
      onLogout={onLogout}
    >
      {err && <Alert>{err}</Alert>}

      <SearchField
        label="Rechercher dans l’historique"
        value={table.query}
        onChange={table.setQuery}
        placeholder="Action, personne, cible…"
      />

      <TableFrame label="Historique des modifications" busy={loading}>
          <thead className="bg-midnight text-left">
            <tr>
              <SortTh label="Quand" column="when" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Action" column="action" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Par" column="who" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
              <SortTh label="Cible" column="target" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && <LoadingRows cols={4} />}
            {!loading && table.total === 0 && (
              <tr><td colSpan={4}>
                <EmptyState
                  title={table.query ? `Aucun résultat pour « ${table.query} ».` : 'Aucune modification enregistrée.'}
                  hint={table.query ? 'Essaie un autre mot.' : 'Les changements faits dans le panneau apparaîtront ici.'}
                />
              </td></tr>
            )}
            {!loading && table.rows.map((it) => (
              <tr key={it.id} className="hover:bg-midnight">
                <td className="px-4 py-3 text-ink-secondary">{fmtDate(it.created_at)}</td>
                <td className="px-4 py-3 font-medium">
                  {ACTION_LABELS[it.action] || it.action}
                </td>
                <td className="px-4 py-3 text-ink-secondary">
                  {it.actor_type === 'admin' ? 'Admin' : 'Revendeur'}
                </td>
                <td className="px-4 py-3 text-xs text-ink-secondary">
                  {it.target_type || '—'}{it.target_id ? ` · ${it.target_id}` : ''}
                </td>
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
