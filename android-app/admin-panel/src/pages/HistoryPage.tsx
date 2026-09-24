import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
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

  return (
    <AppLayout
      title="Historique"
      subtitle="Qui a fait quoi, et quand"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-hidden rounded-xl border border-white/5">
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
                <td className="px-4 py-3 text-ink-secondary">{fmtDate(it.created_at)}</td>
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
    </AppLayout>
  );
}
