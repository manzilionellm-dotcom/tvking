import { useCallback, useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { ListPager } from '@/components/ListPager';
import { auditApi, type AuditLog, ApiError, isAbortError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { LIST_PAGE_SIZE, createAbortBag, createGeneration, readListPage } from '@/lib/robust';

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

export function HistoryPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<AuditLog[]>([]);
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
    auditApi.list({ limit: LIST_PAGE_SIZE, offset }, signal)
      .then((r) => {
        if (!gen.current.isCurrent(id)) return;
        const page = readListPage<AuditLog>(r);
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
      title="Historique"
      subtitle="Qui a fait quoi, et quand"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-x-auto rounded-xl border border-white/5">
        <table className="w-full text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">Quand</th>
              <th className="px-4 py-3">Action</th>
              <th className="px-4 py-3">Par</th>
              <th className="px-4 py-3">Cible</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && (
              <tr><td colSpan={4} className="px-4 py-8 text-center text-sm text-ink-tertiary">Chargement…</td></tr>
            )}
            {!loading && items.length === 0 && (
              <tr><td colSpan={4} className="px-4 py-8 text-center text-sm text-ink-tertiary">
                Aucune modification enregistrée pour l'instant.
              </td></tr>
            )}
            {items.map((it) => (
              <tr key={it.id} className="bg-obsidian hover:bg-midnight">
                <td className="px-4 py-3 text-ink-secondary">{formatDateTime(it.created_at)}</td>
                <td className="px-4 py-3 font-medium">
                  {ACTION_LABELS[it.action] || it.action}
                </td>
                <td className="px-4 py-3 text-ink-secondary">
                  {it.actor_type === 'admin' ? '👑 Admin' : '🛒 Revendeur'}
                </td>
                <td className="px-4 py-3 text-[11px] text-ink-tertiary">
                  {it.target_type || '—'}{it.target_id ? ` · ${it.target_id}` : ''}
                </td>
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
