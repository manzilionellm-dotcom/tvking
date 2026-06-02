import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { licensesApi, type License, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

export function ActivationsPage({ onLogout }: { onLogout: () => void }) {
  const navigate = useNavigate();
  const [items, setItems] = useState<License[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    licensesApi.list()
      .then((r) => { if (active) { setItems(r.items); setErr(null); } })
      .catch((e) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [onLogout]);

  return (
    <AppLayout
      title="Activations"
      subtitle="Licences actives, expirées et gelées sur toutes les apps."
      onLogout={onLogout}
      actions={
        <button
          onClick={() => navigate('/activate')}
          className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black hover:bg-accent-bright"
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
              <tr><td colSpan={6} className="px-4 py-8 text-center text-sm text-ink-tertiary">
                Aucune activation. Phase 1.B ajoutera l'action « + Activer un MAC ».
              </td></tr>
            )}
            {items.map((l) => (
              <tr key={l.id} className="bg-obsidian hover:bg-midnight">
                <td className="px-4 py-3 font-medium">{l.customer_name || l.customer_email || '—'}</td>
                <td className="px-4 py-3">{l.app_name || '—'}</td>
                <td className="px-4 py-3 font-mono text-xs text-accent">{l.device_mac}</td>
                <td className="px-4 py-3 text-ink-secondary uppercase tracking-wider text-[10px]">{l.plan}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-sm px-2 py-0.5 text-[9px] uppercase tracking-widest ${statusClass(l.status)}`}>
                    {l.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-ink-tertiary">{formatDateTime(l.expires_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
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
