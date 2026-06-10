import { ReactNode, useCallback, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { devicesApi, activateApi, type Device, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

export function DevicesPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Device[]>([]);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [activateFor, setActivateFor] = useState<Device | null>(null);

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
              <th className="px-4 py-3">Appareil</th>
              <th className="px-4 py-3">Statut</th>
              <th className="px-4 py-3">Dernière vue</th>
              <th className="px-4 py-3 text-right">Actions</th>
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
                  <td className="px-4 py-3">
                    {d.device_model ? (
                      <div>
                        <div className="text-xs text-ink-secondary">{d.device_model}</div>
                        <div className="text-[10px] text-ink-tertiary">
                          {d.android_release ? `Android ${d.android_release}` : ''}
                          {d.android_build ? ` · ${d.android_build}` : ''}
                        </div>
                      </div>
                    ) : (
                      <span className="text-ink-tertiary">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3"><DeviceStatus status={st} /></td>
                  <td className="px-4 py-3 text-ink-tertiary">{formatDateTime(d.last_seen_at)}</td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap justify-end gap-1.5">
                      <ActionBtn busy={busy} primary onClick={() => setActivateFor(d)} title="Activer / prolonger (le client a payé)">Activer</ActionBtn>
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

      {activateFor && (
        <ActivatePlanModal
          device={activateFor}
          onClose={() => setActivateFor(null)}
          onDone={() => { setActivateFor(null); load(); }}
        />
      )}
    </AppLayout>
  );
}

function ActivatePlanModal({
  device, onClose, onDone,
}: { device: Device; onClose: () => void; onDone: () => void }) {
  const [plan, setPlan] = useState('yearly');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const PLANS = [
    { id: 'monthly', label: '1 mois' },
    { id: 'quarterly', label: '3 mois' },
    { id: 'biannual', label: '6 mois' },
    { id: 'yearly', label: '1 an' },
    { id: 'lifetime', label: 'À vie' },
  ];

  async function go() {
    setBusy(true); setErr(null);
    try {
      await activateApi.activate({ mac: device.mac, plan });
      setDone(true);
      setTimeout(onDone, 900);
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h2 className="mb-1 text-lg font-semibold tracking-tight">Activer / prolonger</h2>
        <p className="mb-4 font-mono text-xs text-accent">{device.mac}</p>
        <p className="mb-3 text-sm text-ink-tertiary">
          Le client a payé ? Choisis la durée — elle s'ajoute au temps restant
          et débloque l'app immédiatement.
        </p>
        <div className="grid grid-cols-2 gap-2">
          {PLANS.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => setPlan(p.id)}
              className={
                'rounded-md border px-3 py-2 text-sm transition ' +
                (plan === p.id
                  ? 'border-accent bg-accent/10 text-ink-primary'
                  : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
              }
            >
              {p.label}
            </button>
          ))}
        </div>
        {err && <div className="mt-3 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
        {done && <div className="mt-3 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">Activé ✔</div>}
        <div className="flex justify-end gap-2 pt-4">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Annuler</button>
          <button disabled={busy || done} onClick={go} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
            {busy ? 'Activation…' : 'Activer'}
          </button>
        </div>
      </div>
    </div>
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
  children, onClick, busy, danger, primary, title,
}: { children: ReactNode; onClick: () => void; busy?: boolean; danger?: boolean; primary?: boolean; title?: string }) {
  const cls = primary
    ? 'bg-accent text-black hover:bg-accent-bright border border-transparent'
    : danger
      ? 'border border-white/10 text-ink-secondary hover:border-accent hover:text-accent-bright'
      : 'border border-white/10 hover:border-white/30';
  return (
    <button
      onClick={onClick}
      disabled={busy}
      title={title}
      className={'rounded-md px-2.5 py-1 text-xs font-medium disabled:opacity-50 ' + cls}
    >
      {children}
    </button>
  );
}
