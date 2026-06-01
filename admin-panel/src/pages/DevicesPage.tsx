import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { devicesApi, type Device, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

export function DevicesPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Device[]>([]);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    devicesApi.list(q)
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
      title="Devices"
      subtitle={`${items.length} appareils enregistrés`}
      onLogout={onLogout}
    >
      <input
        type="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Recherche par MAC, label, client…"
        className="mb-4 w-full max-w-md rounded-md border border-white/5 bg-midnight px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
      />

      {err && (
        <div className="rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-hidden rounded-xl border border-white/5">
        <table className="w-full text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">MAC</th>
              <th className="px-4 py-3">Client</th>
              <th className="px-4 py-3">Label</th>
              <th className="px-4 py-3">Première vue</th>
              <th className="px-4 py-3">Dernière vue</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && Array.from({ length: 5 }).map((_, i) => (
              <tr key={i} className="bg-obsidian">
                <td className="px-4 py-3" colSpan={5}>
                  <div className="h-4 w-full animate-pulse rounded bg-white/5" />
                </td>
              </tr>
            ))}
            {!loading && items.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-8 text-center text-sm text-ink-tertiary">
                Aucun device. La migration KV → D1 ajoutera tes devices existants.
              </td></tr>
            )}
            {items.map((d) => (
              <tr key={d.id} className="bg-obsidian hover:bg-midnight">
                <td className="px-4 py-3 font-mono text-xs text-accent">{d.mac}</td>
                <td className="px-4 py-3">{d.customer_name || d.customer_email || '—'}</td>
                <td className="px-4 py-3 text-ink-secondary">{d.label || '—'}</td>
                <td className="px-4 py-3 text-ink-tertiary">{formatDateTime(d.first_seen_at)}</td>
                <td className="px-4 py-3 text-ink-tertiary">{formatDateTime(d.last_seen_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </AppLayout>
  );
}
