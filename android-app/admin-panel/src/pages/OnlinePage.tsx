import { useCallback, useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  Alert, EmptyState, Pager, SearchField, SortTh, StatusBadge,
  TableFrame, useClientTable,
} from '@/components/ui';
import { onlineApi, flagEmoji, ApiError, isAbortError } from '@/lib/api';
import { PANEL_POLL_MS, shouldApplyPollResult } from '@/lib/live-sync';
import {
  LIST_PAGE_SIZE, agoLabel, createAbortBag, createGeneration, onlineView,
  type OnlineView,
} from '@/lib/robust';

/// Page « En ligne » (owner) — qui utilise l'app en ce moment, depuis où.
/// Données issues de la présence (heartbeat) : IP + pays fournis par
/// Cloudflare. « En ligne » = vu il y a moins de 15 min.
/// Rafraîchissement toutes les 2 s. Une réponse lente ne réécrit pas
/// un état plus récent déjà affiché.

export function OnlinePage({ onLogout }: { onLogout: () => void }) {
  const [data, setData] = useState<OnlineView | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const gen = useRef(createGeneration());
  const aborts = useRef(createAbortBag());
  const appliedSeq = useRef(0);

  const load = useCallback(() => {
    const id = gen.current.next();
    const signal = aborts.current.next();
    onlineApi.get({ limit: LIST_PAGE_SIZE, offset: 0 }, signal)
      .then((raw) => {
        if (!gen.current.isCurrent(id) || !shouldApplyPollResult(id, appliedSeq.current)) return;
        appliedSeq.current = id;
        // Corps incomplet (sans byCountry / items) : on normalise,
        // on n'explose pas la page, et on efface l'erreur précédente.
        setData(onlineView(raw));
        setErr(null);
      })
      .catch((e: unknown) => {
        if (isAbortError(e) || !gen.current.isCurrent(id)) return;
        if (!shouldApplyPollResult(id, appliedSeq.current)) return;
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => { if (gen.current.isCurrent(id)) setLoading(false); });
  }, [onLogout]);

  useEffect(() => {
    load();
    const t = setInterval(load, PANEL_POLL_MS);
    return () => { clearInterval(t); aborts.current.abort(); };
  }, [load]);

  const byCountry = data ? data.byCountry : [];
  const table = useClientTable(data?.items ?? [], {
    textOf: (d) => [d.country, d.ip, d.mac, d.channel].filter(Boolean).join(' '),
    valueOf: (d, key) => {
      if (key === 'country') return d.country || '';
      if (key === 'ip') return d.ip || '';
      if (key === 'mac') return d.mac;
      if (key === 'channel') return d.channel || '';
      if (key === 'seen') return d.lastSeen || 0;
      return '';
    },
  });

  return (
    <AppLayout
      title="En ligne"
      subtitle="Qui utilise l'app en ce moment, et depuis quel pays (rafraîchi toutes les 2 s)"
      onLogout={onLogout}
    >
      {err && <Alert>{err}</Alert>}

      {loading && !data ? (
        <div role="status" className="space-y-3">
          <div className="h-24 animate-pulse rounded-xl border border-white/10 bg-midnight" />
          <p className="text-sm text-ink-secondary">Chargement des appareils en ligne…</p>
        </div>
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

          <SearchField
            label="Rechercher parmi les appareils en ligne"
            value={table.query}
            onChange={table.setQuery}
            placeholder="Pays, adresse IP, MAC…"
          />

          <TableFrame label="Appareils en ligne">
              <thead className="bg-midnight text-left">
                <tr>
                  <th scope="col" className="px-4 py-3 text-[10px] font-semibold uppercase tracking-widest text-ink-secondary">État</th>
                  <SortTh label="Pays" column="country" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
                  <SortTh label="Adresse IP" column="ip" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
                  <SortTh label="MAC" column="mac" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
                  <SortTh label="Regarde" column="channel" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
                  <SortTh label="Vu" column="seen" sortKey={table.sortKey} dir={table.dir} onSort={table.toggleSort} />
                </tr>
              </thead>
              <tbody>
                {table.rows.map((d) => (
                  <tr key={d.mac} className="border-t border-white/5">
                    <td className="px-4 py-2.5"><StatusBadge status="online" /></td>
                    <td className="px-4 py-2.5">
                      <span className="mr-1.5">{flagEmoji(d.country)}</span>
                      {d.country || '—'}
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs text-ink-secondary">{d.ip || '—'}</td>
                    <td className="px-4 py-2.5 font-mono text-xs text-ink-secondary">{d.mac}</td>
                    <td className="px-4 py-2.5 text-xs">
                      {d.channel
                        ? <span className="inline-flex items-center gap-1 text-accent-bright">▶ {d.channel}</span>
                        : <span className="text-ink-tertiary">—</span>}
                    </td>
                    <td className="px-4 py-2.5 text-xs text-ink-tertiary">{agoLabel(d.lastSeen)}</td>
                  </tr>
                ))}
                {table.total === 0 && (
                  <tr>
                    <td colSpan={6}>
                      <EmptyState
                        title={table.query ? `Personne ne correspond à « ${table.query} ».` : 'Personne en ligne.'}
                        hint={table.query ? 'Essaie une autre MAC ou un autre pays.' : 'Aucun appareil vu dans les 15 dernières minutes.'}
                      />
                    </td>
                  </tr>
                )}
              </tbody>
          </TableFrame>
          <Pager
            page={table.page}
            pages={table.pages}
            start={table.start}
            end={table.end}
            total={table.total}
            onPage={table.setPage}
          />
        </>
      )}
    </AppLayout>
  );
}
