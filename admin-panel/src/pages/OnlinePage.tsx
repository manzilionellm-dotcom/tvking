import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { onlineApi, type OnlineSnapshot, flagEmoji, ApiError } from '@/lib/api';

/// Page « En ligne » (owner) — qui utilise l'app en ce moment, depuis où.
/// Données issues de la présence (heartbeat) : IP + pays fournis par
/// Cloudflare. « En ligne » = vu il y a moins de 15 min.

function ago(ts: number): string {
  if (!ts) return '—';
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return `il y a ${s}s`;
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  return `il y a ${Math.floor(s / 3600)} h`;
}

export function OnlinePage({ onLogout }: { onLogout: () => void }) {
  const [data, setData] = useState<OnlineSnapshot | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  function load() {
    onlineApi.get()
      .then(setData)
      .catch((e: any) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => setLoading(false));
  }

  // Rafraîchissement auto toutes les 30 s.
  useEffect(() => {
    load();
    const t = setInterval(load, 30000);
    return () => clearInterval(t);
    /* eslint-disable-next-line */
  }, []);

  const byCountry = data
    ? Object.entries(data.byCountry).sort((a, b) => b[1] - a[1])
    : [];

  return (
    <AppLayout
      title="En ligne"
      subtitle="Qui utilise l'app en ce moment, et depuis quel pays (mise à jour auto)"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}

      {loading && !data ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <>
          {/* Compteurs */}
          <div className="mb-5 grid gap-3 sm:grid-cols-3">
            <div className="rounded-xl border border-success/20 bg-success/[0.06] p-4">
              <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                En ligne maintenant
              </div>
              <div className="mt-1 text-3xl font-bold text-success">
                {data?.onlineCount ?? 0}
              </div>
            </div>
            <div className="rounded-xl border border-white/5 bg-midnight p-4">
              <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                Actifs aujourd'hui
              </div>
              <div className="mt-1 text-3xl font-bold text-ink-primary">
                {data?.todayCount ?? 0}
              </div>
            </div>
            <div className="rounded-xl border border-white/5 bg-midnight p-4">
              <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                Pays en ligne
              </div>
              <div className="mt-1 text-3xl font-bold text-ink-primary">
                {byCountry.length}
              </div>
            </div>
          </div>

          {/* Répartition par pays */}
          {byCountry.length > 0 && (
            <div className="mb-5">
              <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
                Par pays
              </div>
              <div className="flex flex-wrap gap-2">
                {byCountry.map(([code, n]) => (
                  <span
                    key={code}
                    className="flex items-center gap-1.5 rounded-full border border-white/10 bg-midnight px-3 py-1.5 text-sm"
                  >
                    <span className="text-base">{flagEmoji(code)}</span>
                    <span className="text-ink-primary">{code}</span>
                    <span className="font-bold text-accent-bright">{n}</span>
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Liste des appareils en ligne */}
          <div className="overflow-hidden rounded-xl border border-white/5">
            <table className="w-full text-left text-sm">
              <thead className="bg-midnight text-[10px] uppercase tracking-widest text-ink-tertiary">
                <tr>
                  <th className="px-4 py-2.5">Pays</th>
                  <th className="px-4 py-2.5">IP</th>
                  <th className="px-4 py-2.5">MAC</th>
                  <th className="px-4 py-2.5">Vu</th>
                </tr>
              </thead>
              <tbody>
                {(data?.items ?? []).map((d) => (
                  <tr key={d.mac} className="border-t border-white/5">
                    <td className="px-4 py-2.5">
                      <span className="mr-1.5">{flagEmoji(d.country)}</span>
                      {d.country || '—'}
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs text-ink-secondary">{d.ip || '—'}</td>
                    <td className="px-4 py-2.5 font-mono text-xs text-ink-tertiary">{d.mac}</td>
                    <td className="px-4 py-2.5 text-xs text-ink-tertiary">{ago(d.lastSeen)}</td>
                  </tr>
                ))}
                {(data?.items.length ?? 0) === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-xs text-ink-tertiary">
                      Personne en ligne dans les 15 dernières minutes.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
    </AppLayout>
  );
}
