import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { appsApi, type App, ApiError } from '@/lib/api';

export function AppsPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<App[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    appsApi.list()
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
      title="Apps"
      subtitle="Ajoute une app sans toucher au code. Chaque app a son propre flavor, branding et serveur Xtream."
      onLogout={onLogout}
      actions={
        <button className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black opacity-50 cursor-not-allowed">
          + Nouvelle app (1.B)
        </button>
      }
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      {loading && (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {[0, 1].map((i) => (
            <div key={i} className="h-32 animate-pulse rounded-xl border border-white/5 bg-midnight" />
          ))}
        </div>
      )}

      {!loading && (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {items.map((a) => (
            <div key={a.id} className="rounded-xl border border-white/5 bg-midnight p-5">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-base font-semibold tracking-tight">{a.name}</p>
                  <p className="mt-1 font-mono text-[11px] text-ink-tertiary">{a.package_name}</p>
                </div>
                <span
                  className={`rounded-sm px-2 py-0.5 text-[9px] uppercase tracking-widest ${
                    a.is_active
                      ? 'bg-accent/20 text-accent'
                      : 'bg-white/5 text-ink-tertiary'
                  }`}
                >
                  {a.is_active ? 'Active' : 'Inactive'}
                </span>
              </div>
              {a.tagline && (
                <p className="mt-3 text-xs text-ink-secondary">{a.tagline}</p>
              )}
              {a.default_iptv_server && (
                <p className="mt-3 truncate text-[11px] text-ink-tertiary">
                  Serveur IPTV : <span className="text-ink-secondary">{a.default_iptv_server}</span>
                </p>
              )}
            </div>
          ))}
          {items.length === 0 && (
            <div className="col-span-full rounded-xl border border-dashed border-white/10 p-8 text-center text-sm text-ink-tertiary">
              Aucune app enregistrée. Lance la migration KV → D1 ou crée manuellement.
            </div>
          )}
        </div>
      )}
    </AppLayout>
  );
}
