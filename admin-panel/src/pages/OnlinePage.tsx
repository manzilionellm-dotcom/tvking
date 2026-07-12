import { MacLink } from '@/components/MacLink';
import { useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { onlineApi, type OnlineSnapshot, flagEmoji, ApiError } from '@/lib/api';
import { useLiveDevices } from '@/lib/realtime';

/// Page « En ligne » (owner) — qui utilise l'app en ce moment, depuis où.
///
/// UNE seule table : union par MAC des appareils du hub temps réel (WS)
/// et de la présence heartbeat /api/v1/online. Le WS gagne pour la chaîne
/// et le « vu » quand il connaît l'appareil ; l'IP vient de /online.
/// Le polling 30 s tourne TOUJOURS, même WS connecté : il est la seule
/// source de « Actifs aujourd'hui », des IP, et couvre les vieux APK qui
/// heartbeatent sans ouvrir de WebSocket.

function ago(ts: number): string {
  if (!ts) return '—';
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return `il y a ${s}s`;
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  return `il y a ${Math.floor(s / 3600)} h`;
}

/// Ligne fusionnée du tableau (WS ∪ /online, par MAC).
type OnlineRow = {
  mac: string;
  country: string;
  channel: string;
  lastSeen: number;
  ip?: string;
  platform?: string;
  model?: string;
  live: boolean;      // connecté au hub temps réel en ce moment
};

/// Libellé plateforme (connue seulement via le WS).
function platformLabel(p?: string): string {
  if (p === 'tv') return '📺 TV';
  if (p === 'mobile') return '📱 Mobile';
  if (p === 'windows') return '💻 Windows';
  return '—';
}

export function OnlinePage({ onLogout }: { onLogout: () => void }) {
  const [data, setData] = useState<OnlineSnapshot | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const { devices: live, connected } = useLiveDevices();

  function load() {
    onlineApi.get()
      .then((d) => { setData(d); setErr(null); })
      .catch((e: any) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => setLoading(false));
  }

  // Le polling 30 s tourne TOUJOURS (même WS connecté) : seule source de
  // « Actifs aujourd'hui », des IP, et des vieux APK sans WebSocket.
  useEffect(() => {
    load();
    const t = setInterval(load, 30000);
    return () => clearInterval(t);
    /* eslint-disable-next-line */
  }, []);

  // Union par MAC : /online d'abord, puis le WS écrase chaîne / vu /
  // plateforme quand il connaît l'appareil (l'IP reste celle de /online).
  const rows = useMemo<OnlineRow[]>(() => {
    const map = new Map<string, OnlineRow>();
    for (const d of data?.items ?? []) {
      map.set(d.mac, {
        mac: d.mac,
        country: d.country || '',
        channel: d.channel ?? '',
        lastSeen: d.lastSeen,
        ip: d.ip || undefined,
        live: false,
      });
    }
    for (const d of live) {
      const prev = map.get(d.mac);
      map.set(d.mac, {
        mac: d.mac,
        country: d.country || prev?.country || '',
        channel: d.channel ?? '',
        lastSeen: d.lastSeen ?? d.connectedAt ?? prev?.lastSeen ?? 0,
        ip: prev?.ip,
        platform: d.platform,
        model: d.model,
        live: true,
      });
    }
    return Array.from(map.values()).sort((a, b) => b.lastSeen - a.lastSeen);
  }, [data, live]);

  // Compteur = taille de l'UNION (pas live.length : les vieux APK qui
  // heartbeatent sans WS doivent compter aussi).
  const onlineCount = rows.length;
  const byCountry = useMemo(() => {
    const acc: Record<string, number> = {};
    for (const r of rows) {
      const c = r.country || '??';
      acc[c] = (acc[c] || 0) + 1;
    }
    return Object.entries(acc).sort((a, b) => b[1] - a[1]);
  }, [rows]);

  return (
    <AppLayout
      title="En ligne"
      subtitle={connected
        ? "Qui utilise l'app en ce moment — flux temps réel (WebSocket)"
        : "Qui utilise l'app en ce moment, et depuis quel pays (mise à jour auto)"}
      onLogout={onLogout}
      actions={connected ? (
        <span className="inline-flex items-center gap-1.5 rounded-full border border-success/30 bg-success/10 px-3 py-1 text-xs font-semibold text-success">
          Direct <span className="animate-pulse">●</span>
        </span>
      ) : undefined}
    >
      {err && (
        <div className="mb-4 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}

      {loading && !data && !connected ? (
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
                {onlineCount}
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

          {/* Liste des appareils en ligne — UNE table (union WS ∪ /online) */}
          <div className="overflow-hidden rounded-xl border border-white/5">
            <table className="w-full text-left text-sm">
              <thead className="bg-midnight text-[10px] uppercase tracking-widest text-ink-tertiary">
                <tr>
                  <th className="px-4 py-2.5">Pays</th>
                  <th className="px-4 py-2.5">Plateforme</th>
                  <th className="px-4 py-2.5">IP</th>
                  <th className="px-4 py-2.5">MAC</th>
                  <th className="px-4 py-2.5">Regarde</th>
                  <th className="px-4 py-2.5">Vu</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.mac} className="border-t border-white/5">
                    <td className="px-4 py-2.5">
                      {/* Pastille verte pulsante = connecté au hub temps réel. */}
                      {r.live && (
                        <span className="mr-1.5 inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-success align-middle" />
                      )}
                      <span className="mr-1.5">{flagEmoji(r.country)}</span>
                      {r.country || '—'}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-ink-secondary">
                      {platformLabel(r.platform)}
                      {r.model ? <span className="ml-1.5 text-ink-tertiary">{r.model}</span> : null}
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs text-ink-secondary">{r.ip || '—'}</td>
                    <td className="px-4 py-2.5 text-xs"><MacLink mac={r.mac} /></td>
                    <td className="px-4 py-2.5 text-xs">
                      {r.channel
                        ? <span className="inline-flex items-center gap-1 text-accent-bright">▶ {r.channel}</span>
                        : <span className="text-ink-tertiary">—</span>}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-ink-tertiary">{ago(r.lastSeen)}</td>
                  </tr>
                ))}
                {rows.length === 0 && (
                  <tr>
                    <td colSpan={6} className="px-4 py-6 text-center text-xs text-ink-tertiary">
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
