import { ReactNode, useCallback, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { devicesApi, type Device, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

export function DevicesPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Device[]>([]);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    devicesApi.list(q)
      .then((r) => { setItems(r.items); setErr(null); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => setLoading(false));
  }, [q, onLogout]);

  useEffect(() => {
    const id = setTimeout(load, 200); // petit debounce sur la recherche
    return () => clearTimeout(id);
  }, [load]);

  async function setBlock(d: Device, status: 'active' | 'frozen' | 'banned') {
    setBusyId(d.id); setErr(null);
    try { await devicesApi.setBlock(d.id, status); load(); }
    catch (e: any) { setErr(e instanceof ApiError ? e.message : 'Échec.'); }
    finally { setBusyId(null); }
  }

  async function remove(d: Device) {
    if (!window.confirm(`Supprimer définitivement la MAC ${d.mac} ?\n(Si l'app reste installée, elle réapparaîtra avec un nouvel essai. Pour stopper un abuseur, utilise plutôt « Bannir ».)`)) return;
    setBusyId(d.id); setErr(null);
    try { await devicesApi.remove(d.id); load(); }
    catch (e: any) { setErr(e instanceof ApiError ? e.message : 'Échec.'); }
    finally { setBusyId(null); }
  }

  return (
    <AppLayout
      title="Appareils"
      subtitle={`${items.length} appareil(s)`}
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
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-x-auto rounded-xl border border-white/5">
        <table className="w-full min-w-[640px] text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">MAC</th>
              <th className="px-4 py-3">Client</th>
              <th className="px-4 py-3">Statut</th>
              <th className="px-4 py-3">Dernière vue</th>
              <th className="px-4 py-3 text-right">Actions</th>
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
                Aucun appareil pour l'instant. Dès qu'une app contacte le serveur,
                sa MAC apparaît ici automatiquement.
              </td></tr>
            )}
            {items.map((d) => {
              const st = d.block_status || 'active';
              const busy = busyId === d.id;
              return (
                <tr key={d.id} className="bg-obsidian hover:bg-midnight">
                  <td className="px-4 py-3 font-mono text-xs text-accent">{d.mac}</td>
                  <td className="px-4 py-3">{d.customer_name || d.customer_email || '—'}</td>
                  <td className="px-4 py-3"><DeviceStatus status={st} /></td>
                  <td className="px-4 py-3 text-ink-tertiary">{formatDateTime(d.last_seen_at)}</td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap justify-end gap-1.5">
                      {st !== 'frozen' && (
                        <ActionBtn busy={busy} onClick={() => setBlock(d, 'frozen')} title="Geler (rappel de paiement)">Geler</ActionBtn>
                      )}
                      {st !== 'banned' && (
                        <ActionBtn busy={busy} onClick={() => setBlock(d, 'banned')} title="Bannir (abus)">Bannir</ActionBtn>
                      )}
                      {st !== 'active' && (
                        <ActionBtn busy={busy} onClick={() => setBlock(d, 'active')} title="Réactiver">Réactiver</ActionBtn>
                      )}
                      <ActionBtn busy={busy} danger onClick={() => remove(d)} title="Supprimer la MAC">Suppr.</ActionBtn>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </AppLayout>
  );
}

function DeviceStatus({ status }: { status: string }) {
  const map: Record<string, { label: string; cls: string }> = {
    active: { label: 'Actif', cls: 'bg-success/15 text-success' },
    frozen: { label: 'Gelé', cls: 'bg-warning/15 text-warning' },
    banned: { label: 'Banni', cls: 'bg-accent/15 text-accent-bright' },
  };
  const s = map[status] || map.active;
  return <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${s.cls}`}>{s.label}</span>;
}

function ActionBtn({
  children, onClick, busy, danger, title,
}: { children: ReactNode; onClick: () => void; busy?: boolean; danger?: boolean; title?: string }) {
  return (
    <button
      onClick={onClick}
      disabled={busy}
      title={title}
      className={
        'rounded-md border px-2.5 py-1 text-xs disabled:opacity-50 ' +
        (danger
          ? 'border-white/10 text-ink-secondary hover:border-accent hover:text-accent-bright'
          : 'border-white/10 hover:border-white/30')
      }
    >
      {children}
    </button>
  );
}
