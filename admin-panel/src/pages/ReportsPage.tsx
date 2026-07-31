import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  ApiError, ReportBucket, ReportsOverview, reportsApi,
} from '@/lib/api';

// =========================================================
//  ReportsPage — Rapports Boîte noire du parc mondial (owner)
// =========================================================
//  Chaque application (téléphone + TV, partout dans le monde) envoie
//  1×/24 h un résumé ANONYME de sa Boîte noire : les échecs de lecture
//  EXACTS vécus par le client (chaîne, code d'erreur stable, cause,
//  verdict). Le pays est déduit côté serveur (Cloudflare). Cette page
//  agrège tout : où ça souffre, sur quoi, avec quelle version — pour
//  rendre l'application meilleure, données réelles à l'appui.
// =========================================================

const DAY_CHOICES = [1, 7, 30, 90];

export function ReportsPage({ onLogout }: { onLogout: () => void }) {
  const [data, setData] = useState<ReportsOverview | null>(null);
  const [days, setDays] = useState(7);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  async function refresh(d: number) {
    setLoading(true);
    setErr(null);
    try {
      setData(await reportsApi.overview(d));
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh(days);
    /* eslint-disable-next-line */
  }, [days]);

  const sortedBuckets = (m: Record<string, ReportBucket>) =>
    Object.entries(m).sort((a, b) => b[1].devices - a[1].devices);

  return (
    <AppLayout
      title="Rapports"
      subtitle="Boîte noire du parc mondial — un rapport anonyme par appareil et par 24 h"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 max-w-5xl rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
      )}

      <div className="mb-4 flex items-center gap-2">
        {DAY_CHOICES.map((d) => (
          <button
            key={d}
            type="button"
            onClick={() => setDays(d)}
            className={
              'rounded-md border px-3 py-1.5 text-xs ' +
              (days === d
                ? 'border-accent bg-accent/10 text-accent-bright'
                : 'border-white/10 hover:bg-white/5')
            }
          >
            {d === 1 ? '24 h' : `${d} jours`}
          </button>
        ))}
        <button
          type="button"
          onClick={() => refresh(days)}
          className="ml-auto rounded-md border border-white/10 px-3 py-1.5 text-xs hover:bg-white/5"
        >
          Actualiser
        </button>
      </div>

      {loading || !data ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <div className="max-w-5xl space-y-6">
          {/* ----- Totaux ----- */}
          <div className="flex flex-wrap items-center gap-4">
            <Stat label="Appareils" value={String(data.totals.devices)} />
            <Stat label="Rapports" value={String(data.totals.reports)} />
            <Stat label="Échecs de lecture" value={String(data.totals.failures)} />
            <Stat label="Pays" value={String(Object.keys(data.byCountry).length)} />
          </div>

          {/* ----- Top des problèmes ----- */}
          <section className="rounded-xl border border-white/5 bg-midnight p-6">
            <div className="mb-3 text-sm font-medium">
              Top des problèmes ({data.days === 1 ? 'dernières 24 h' : `${data.days} derniers jours`})
            </div>
            {data.topProblems.length === 0 ? (
              <div className="text-xs text-ink-tertiary">
                Aucun échec remonté sur la période — rien à réparer pour l'instant.
              </div>
            ) : (
              <table className="w-full text-left text-xs">
                <thead className="text-ink-tertiary">
                  <tr>
                    <th className="py-1 pr-3">Code d'erreur / cause</th>
                    <th className="py-1 pr-3">Occurrences</th>
                    <th className="py-1">Chaînes les plus touchées</th>
                  </tr>
                </thead>
                <tbody>
                  {data.topProblems.map((p) => (
                    <tr key={p.code} className="border-t border-white/5">
                      <td className="py-1.5 pr-3 font-mono">{p.code}</td>
                      <td className="py-1.5 pr-3 tabular-nums">{p.count}</td>
                      <td className="py-1.5 text-ink-tertiary">
                        {p.topChannels.map((c) => `${c.name} (${c.count})`).join(' · ') || '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>

          {/* ----- Répartitions ----- */}
          <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
            <BucketCard title="Par pays" rows={sortedBuckets(data.byCountry)} />
            <BucketCard title="Par application"
              rows={sortedBuckets(data.byApp).map(([k, v]) =>
                [k === 'tv' ? 'DeFew TV (box)' : '7 MOTION (téléphone)', v] as [string, ReportBucket])} />
            <BucketCard title="Par jour"
              rows={Object.entries(data.byDay).sort((a, b) => b[0].localeCompare(a[0]))} />
          </div>

          {/* ----- Derniers rapports ----- */}
          <section className="rounded-xl border border-white/5 bg-midnight p-6">
            <div className="mb-3 text-sm font-medium">Derniers rapports reçus</div>
            {data.recent.length === 0 ? (
              <div className="text-xs text-ink-tertiary">
                Aucun rapport pour l'instant. Les applications commencent à
                envoyer leur Boîte noire dès leur prochaine mise à jour, une
                fois par 24 h.
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  <thead className="text-ink-tertiary">
                    <tr>
                      <th className="py-1 pr-3">Jour</th>
                      <th className="py-1 pr-3">Appareil</th>
                      <th className="py-1 pr-3">App</th>
                      <th className="py-1 pr-3">Version</th>
                      <th className="py-1 pr-3">Pays</th>
                      <th className="py-1 pr-3">Langue</th>
                      <th className="py-1">Échecs</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.recent.map((r) => (
                      <tr key={`${r.device}-${r.day}`} className="border-t border-white/5 align-top">
                        <td className="py-1.5 pr-3 whitespace-nowrap">{r.day}</td>
                        <td className="py-1.5 pr-3 font-mono">{r.device}</td>
                        <td className="py-1.5 pr-3">{r.app === 'tv' ? 'TV' : 'Téléphone'}</td>
                        <td className="py-1.5 pr-3 whitespace-nowrap">{r.version_name}</td>
                        <td className="py-1.5 pr-3">{r.country || '—'}</td>
                        <td className="py-1.5 pr-3">{r.locale || '—'}</td>
                        <td className="py-1.5">
                          {r.failure_count === 0 ? (
                            <span className="text-success">aucun</span>
                          ) : (
                            <details>
                              <summary className="cursor-pointer">{r.failure_count} échec(s)</summary>
                              <ul className="mt-1 space-y-1 text-ink-tertiary">
                                {r.failures.map((f, i) => (
                                  <li key={i}>
                                    <span className="font-mono">{f.code || '—'}</span>
                                    {f.channel ? ` · ${f.channel}` : ''}
                                    {f.verdict ? ` · ${f.verdict}` : ''}
                                  </li>
                                ))}
                              </ul>
                            </details>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </div>
      )}
    </AppLayout>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-white/5 bg-midnight px-4 py-2">
      <div className="text-lg font-semibold tabular-nums">{value}</div>
      <div className="text-xs text-ink-tertiary">{label}</div>
    </div>
  );
}

function BucketCard({ title, rows }: {
  title: string;
  rows: [string, ReportBucket][];
}) {
  return (
    <section className="rounded-xl border border-white/5 bg-midnight p-6">
      <div className="mb-3 text-sm font-medium">{title}</div>
      {rows.length === 0 ? (
        <div className="text-xs text-ink-tertiary">—</div>
      ) : (
        <table className="w-full text-left text-xs">
          <thead className="text-ink-tertiary">
            <tr>
              <th className="py-1 pr-2"> </th>
              <th className="py-1 pr-2">Appareils</th>
              <th className="py-1">Échecs</th>
            </tr>
          </thead>
          <tbody>
            {rows.slice(0, 12).map(([k, v]) => (
              <tr key={k} className="border-t border-white/5">
                <td className="py-1 pr-2">{k || '—'}</td>
                <td className="py-1 pr-2 tabular-nums">{v.devices}</td>
                <td className="py-1 tabular-nums">{v.failures}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
