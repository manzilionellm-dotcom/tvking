import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { MacLink } from '@/components/MacLink';
import { adminMonitorApi, ApiError, type AdminSession } from '@/lib/api';

// =========================================================
//  MonitorPage — Admin Monitoring (sessions admin séparées)
// =========================================================
//  Les MAC déclarées « maître/admin » ne comptent JAMAIS dans les stats
//  clients (« En ligne », Tendances, dashboard) : leurs sessions sont
//  détournées côté serveur vers une table à part (admin_presence). Cette page
//  les affiche — un admin peut donc surveiller/ouvrir plusieurs chaînes sans
//  fausser les chiffres clients. Gardé par la permission `admin_monitor`.
// =========================================================

function ago(ts: number, now: number): string {
  const s = Math.floor((now - ts) / 1000);
  if (s < 60) return `il y a ${s}s`;
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  return `il y a ${Math.floor(s / 3600)} h`;
}

export function MonitorPage({ onLogout }: { onLogout: () => void }) {
  const [rows, setRows] = useState<AdminSession[]>([]);
  const [now, setNow] = useState<number>(Date.now());
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  async function load() {
    setBusy(true);
    setErr(null);
    try {
      const r = await adminMonitorApi.list();
      setRows(r.items || []);
      setNow(r.now || Date.now());
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Chargement impossible.');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 15000); // rafraîchit toutes les 15 s
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <AppLayout
      title="Admin Monitoring"
      subtitle="Les sessions des comptes maîtres ET des tests en cours — invisibles dans les stats clients."
      onLogout={onLogout}
      actions={
        <button
          onClick={load}
          className="rounded-md border border-white/10 px-3 py-1.5 text-sm text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright"
        >
          Rafraîchir
        </button>
      }
    >
      <div className="space-y-5">
        <div className="rounded-lg border border-accent/20 bg-accent/5 px-4 py-3 text-[13px] text-ink-secondary">
          Ces sessions n'apparaissent <strong>jamais</strong> dans « En ligne »,
          les Tendances ni le tableau de bord : un admin peut surveiller ou
          ouvrir plusieurs chaînes <strong>sans fausser les statistiques
          clients</strong>. Journal séparé, réservé à la permission
          <span className="font-mono"> admin_monitor</span>.
        </div>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div className="rounded-xl border border-white/5 bg-midnight p-4">
            <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Sessions actives</div>
            <div className="mt-1 text-2xl font-semibold text-accent-bright">{rows.length}</div>
          </div>
          {/* Détail maîtres / testeurs : les tests distribués sont suivis ICI,
              eux aussi hors stats clients (invisibilité totale du flux). */}
          <div className="rounded-xl border border-white/5 bg-midnight p-4">
            <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Maîtres</div>
            <div className="mt-1 text-2xl font-semibold text-ink-primary">
              {rows.filter((r) => r.kind !== 'test').length}
            </div>
          </div>
          <div className="rounded-xl border border-white/5 bg-midnight p-4">
            <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Testeurs (tests en cours)</div>
            <div className="mt-1 text-2xl font-semibold text-ink-primary">
              {rows.filter((r) => r.kind === 'test').length}
            </div>
          </div>
        </div>

        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
        )}

        <div className="overflow-x-auto rounded-xl border border-white/5 bg-midnight">
          <table className="w-full min-w-[640px] text-sm">
            <thead>
              <tr className="border-b border-white/5 text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
                <th className="px-4 py-3 font-medium">MAC</th>
                <th className="px-4 py-3 font-medium">Type</th>
                <th className="px-4 py-3 font-medium">Chaîne surveillée</th>
                <th className="px-4 py-3 font-medium">Pays</th>
                <th className="px-4 py-3 font-medium">IP</th>
                <th className="px-4 py-3 font-medium">Vu</th>
              </tr>
            </thead>
            <tbody>
              {busy && rows.length === 0 && (
                <tr><td colSpan={6} className="px-4 py-8 text-center text-ink-tertiary">Chargement…</td></tr>
              )}
              {!busy && rows.length === 0 && (
                <tr><td colSpan={6} className="px-4 py-8 text-center text-ink-tertiary">Aucune session admin active.</td></tr>
              )}
              {rows.map((r) => (
                <tr key={r.mac} className="border-b border-white/[0.03] last:border-0 hover:bg-white/[0.02]">
                  <td className="px-4 py-3"><MacLink mac={r.mac} /></td>
                  <td className="px-4 py-3">
                    {r.kind === 'test' ? (
                      <span className="rounded bg-sky-500/15 px-2 py-0.5 text-[11px] font-semibold text-sky-300 ring-1 ring-sky-500/30">Testeur</span>
                    ) : (
                      <span className="rounded bg-accent/15 px-2 py-0.5 text-[11px] font-semibold text-accent-bright ring-1 ring-accent/30">Maître</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-ink-secondary">{r.channel || '—'}</td>
                  <td className="px-4 py-3 text-ink-secondary">{r.country || '—'}</td>
                  <td className="px-4 py-3 font-mono text-[12px] text-ink-tertiary">{r.ip || '—'}</td>
                  <td className="px-4 py-3 text-[12px] text-ink-tertiary">{ago(r.last_seen, now)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </AppLayout>
  );
}
