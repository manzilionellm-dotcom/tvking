import { MacLink } from '@/components/MacLink';
import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import {
  statsApi, backupApi, insightsApi, PLAN_LABELS,
  type StatsOverview, type Insights, type InsightExpiring, ApiError,
  getCurrentUser, isOwnerRole,
} from '@/lib/api';
import { useLiveDevices, useRtEvent, type ChangedEvent } from '@/lib/realtime';
import { formatMoney, formatDateTime } from '@/lib/utils';
import { useT } from '@/lib/i18n';

/// Dashboard : cards de KPI lues en direct depuis /api/v1/stats/overview,
/// compteur « en ligne » branché sur le WebSocket temps réel, et section
/// « À traiter » (insights actionnables) via /api/v1/insights.
export function DashboardPage({ onLogout }: { onLogout: () => void }) {
  const t = useT();
  const [stats, setStats] = useState<StatsOverview | null>(null);
  const [insights, setInsights] = useState<Insights | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [backupBusy, setBackupBusy] = useState(false);
  const owner = isOwnerRole(getCurrentUser()?.role);
  const { devices: live, connected } = useLiveDevices();
  const navigate = useNavigate();

  // Télécharge un dump JSON complet de la base (filet de sécurité).
  async function downloadBackup() {
    setBackupBusy(true);
    try {
      const dump = await backupApi.get();
      const blob = new Blob([JSON.stringify(dump, null, 2)], {
        type: 'application/json',
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `thefew-backup-${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onLogout();
      else setErr(e instanceof ApiError ? e.message : 'Sauvegarde impossible.');
    } finally {
      setBackupBusy(false);
    }
  }

  // Numéros de requête : une réponse périmée (composant démonté ou
  // réponses arrivées dans le désordre) ne doit jamais setState.
  const statsSeq = useRef(0);
  const insightsSeq = useRef(0);

  const loadStats = useCallback(() => {
    const seq = ++statsSeq.current;
    statsApi.overview()
      .then((s) => {
        if (seq !== statsSeq.current) return; // réponse périmée
        setStats(s); setErr(null);
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) {
          onLogout();
          return;
        }
        if (seq !== statsSeq.current) return;
        setErr(e instanceof ApiError ? e.message : 'Erreur de chargement');
      })
      .finally(() => { if (seq === statsSeq.current) setLoading(false); });
  }, [onLogout]);

  // Insights « À traiter » (admin uniquement). Le backend peut ne pas
  // être déployé → on masque la section en silence (fail-open).
  const loadInsights = useCallback(() => {
    if (!owner) return;
    const seq = ++insightsSeq.current;
    insightsApi.get()
      .then((r) => { if (seq === insightsSeq.current) setInsights(r); })
      .catch(() => { if (seq === insightsSeq.current) setInsights(null); });
  }, [owner]);

  useEffect(() => {
    loadStats();
    loadInsights();
  }, [loadStats, loadInsights]);
  // Démontage : invalide toute réponse encore en vol.
  useEffect(() => () => {
    statsSeq.current += 1;
    insightsSeq.current += 1;
  }, []);

  // Une mutation a eu lieu ailleurs (autre onglet / autre admin) →
  // rafraîchit KPIs + insights, débouncé à 2 s pour absorber les rafales.
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useRtEvent('changed', (_e: ChangedEvent) => {
    if (refreshTimer.current) return;
    refreshTimer.current = setTimeout(() => {
      refreshTimer.current = null;
      loadStats();
      loadInsights();
    }, 2000);
  });
  useEffect(() => () => {
    if (refreshTimer.current) clearTimeout(refreshTimer.current);
  }, []);

  // « En ligne maintenant » : quand le WS est connecté on prend le MAX du
  // compteur live et de la valeur serveur — le WS seul sous-compte les
  // vieux APK qui heartbeatent sans WebSocket. Sinon valeur serveur, sinon tiret.
  const onlineNow: number | string = connected
    ? Math.max(live.length, stats?.online_now ?? insights?.online_now ?? 0)
    : (stats?.online_now ?? insights?.online_now ?? '—');

  return (
    <AppLayout
      title={t('nav.dashboard')}
      subtitle={t('dash.subtitle')}
      onLogout={onLogout}
      actions={owner ? (
        <button
          onClick={downloadBackup}
          disabled={backupBusy}
          title="Exporter toute la base en JSON (filet de sécurité)"
          className="rounded-md border border-white/10 px-3 py-1.5 text-xs font-semibold text-ink-secondary transition hover:border-accent/40 hover:text-ink-primary disabled:opacity-50"
        >
          {backupBusy ? 'Sauvegarde…' : '⬇ Télécharger une sauvegarde'}
        </button>
      ) : undefined}
    >
      {loading && <SkeletonCards />}
      {err && (
        <div className="rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm text-accent-bright">
          {err}
        </div>
      )}
      {stats && (
        <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
          {owner && <LiveKpiCard value={onlineNow} live={connected} />}
          <KpiCard label={t('dash.clients')}  value={stats.customers} />
          <KpiCard label={t('dash.devices')}  value={stats.devices} />
          <KpiCard label={t('dash.licenses')} value={stats.licenses} />
          <KpiCard label={t('dash.active')}   value={stats.active_licenses} accent />
          <KpiCard label={t('dash.expired')}  value={stats.expired_licenses} />
          <KpiCard label="Expirent (7 j)" value={stats.expiring_7d ?? 0} accent />
          {owner ? (
            <>
              <KpiCard label={t('dash.apps')} value={stats.apps} />
              {stats.resellers !== undefined && (
                <KpiCard label={t('dash.resellers')} value={stats.resellers} />
              )}
              <KpiCard
                label={t('dash.revenue30')}
                value={formatMoney(stats.revenue_30d_cents ?? 0)}
                wide
              />
            </>
          ) : (
            <KpiCard
              label={t('dash.myCredits')}
              value={stats.credit_balance ?? 0}
              accent
            />
          )}
        </div>
      )}

      {/* ===== À traiter — insights actionnables (admin) ===== */}
      {owner && insights && (
        <div className="mt-10">
          <h2 className="mb-3 text-[10px] uppercase tracking-widest text-ink-tertiary">
            À traiter
          </h2>
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            <InsightCard
              title="Expirent sous 7 jours"
              count={insights.expiring_7d.length}
              tone="warning"
            >
              {insights.expiring_7d.length === 0 && <EmptyRow />}
              {/* Clé composite : une MAC peut apparaître deux fois (deux licences). */}
              {insights.expiring_7d.map((it, i) => (
                <ExpiringRow
                  key={`${it.mac}:${it.expires_at ?? i}`}
                  item={it}
                  onRenew={() => navigate(`/activate?mac=${encodeURIComponent(it.mac)}`)}
                />
              ))}
            </InsightCard>

            <InsightCard
              title="Essais qui se terminent (48 h)"
              count={insights.trials_ending_48h.length}
              tone="accent"
            >
              {insights.trials_ending_48h.length === 0 && <EmptyRow />}
              {insights.trials_ending_48h.map((it, i) => (
                <ExpiringRow
                  key={`${it.mac}:${it.expires_at ?? i}`}
                  item={it}
                  renewLabel="Convertir"
                  onRenew={() => navigate(`/activate?mac=${encodeURIComponent(it.mac)}`)}
                />
              ))}
            </InsightCard>

            <InsightCard
              title="Silencieux depuis 7 j (payants)"
              count={insights.gone_quiet.length}
              tone="neutral"
            >
              {insights.gone_quiet.length === 0 && <EmptyRow />}
              {insights.gone_quiet.map((it, i) => (
                <div key={`${it.mac}:${it.expires_at ?? i}`} className="flex items-center gap-3 border-t border-white/5 py-2 first:border-t-0">
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-xs text-ink-primary">
                      {it.label || <span className="font-mono">{it.mac}</span>}
                    </div>
                    <div className="truncate text-[10px]"><MacLink mac={it.mac} className="text-[10px]" /></div>
                  </div>
                  <span className="shrink-0 text-[10px] text-ink-tertiary">
                    {it.plan ? (PLAN_LABELS[it.plan] || it.plan) : '—'}
                  </span>
                  <span className="shrink-0 text-[10px] text-ink-tertiary">
                    vu {formatDateTime(it.last_seen_at)}
                  </span>
                </div>
              ))}
            </InsightCard>

            <InsightCard
              title="Nouveaux aujourd'hui"
              count={insights.new_today.count}
              tone="success"
            >
              {insights.new_today.items.length === 0 && <EmptyRow />}
              {insights.new_today.items.map((it, i) => (
                <div key={`${it.mac}:${i}`} className="flex items-center gap-3 border-t border-white/5 py-2 first:border-t-0">
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-xs text-ink-primary">
                      {it.label || <span className="font-mono">{it.mac}</span>}
                    </div>
                    <div className="truncate text-[10px]"><MacLink mac={it.mac} className="text-[10px]" /></div>
                  </div>
                  <span className="shrink-0 text-[10px] text-ink-tertiary">
                    {formatDateTime(it.first_seen_at)}
                  </span>
                </div>
              ))}
            </InsightCard>
          </div>
        </div>
      )}

      <div className="mt-10">
        <h2 className="mb-3 text-[10px] uppercase tracking-widest text-ink-tertiary">
          Prochaines actions
        </h2>
        <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
          <NextActionCard
            title="Ajouter une app"
            desc="Créer une nouvelle application sans toucher au code."
            to="/apps"
          />
          <NextActionCard
            title="Activer un client"
            desc="Tape le MAC, choisis l'app et la durée."
            to="/activate"
          />
          <NextActionCard
            title="Pousser une playlist"
            desc="Assigner / mettre à jour la source Xtream ou M3U d'une MAC."
            to="/playlists"
          />
        </div>
      </div>
    </AppLayout>
  );
}

/// Carte KPI « En ligne maintenant » — verte, avec pastille « Direct »
/// quand la valeur vient du flux temps réel.
function LiveKpiCard({ value, live }: { value: string | number; live: boolean }) {
  return (
    <div className="rounded-xl border border-success/20 bg-success/[0.06] px-5 py-4">
      <p className="flex items-center gap-1.5 text-[10px] uppercase tracking-widest text-ink-tertiary">
        En ligne maintenant
        {live && (
          <span className="inline-flex items-center gap-1 text-success">
            <span className="h-1 w-1 animate-pulse rounded-full bg-success" />
            Direct
          </span>
        )}
      </p>
      <p className="mt-2 text-3xl font-semibold tracking-tight text-success">
        {value}
      </p>
    </div>
  );
}

/// Carte d'une liste « À traiter » (titre + compteur + lignes).
function InsightCard({
  title, count, tone, children,
}: {
  title: string;
  count: number;
  tone: 'warning' | 'accent' | 'success' | 'neutral';
  children: React.ReactNode;
}) {
  const badge = {
    warning: 'bg-warning/15 text-warning',
    accent: 'bg-accent/15 text-accent-bright',
    success: 'bg-success/15 text-success',
    neutral: 'bg-white/5 text-ink-tertiary',
  }[tone];
  return (
    <div className="rounded-xl border border-white/5 bg-midnight px-5 py-4">
      <div className="mb-2 flex items-center justify-between">
        <p className="text-sm font-semibold tracking-tight">{title}</p>
        <span className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${badge}`}>
          {count}
        </span>
      </div>
      <div className="max-h-56 overflow-y-auto">{children}</div>
    </div>
  );
}

function EmptyRow() {
  return <p className="py-2 text-xs text-ink-tertiary">Rien à signaler. 👌</p>;
}

/// Ligne d'un abonnement qui expire (ou essai qui se termine) : label/mac,
/// plan, badge jours restants, bouton → page d'activation pré-remplie.
function ExpiringRow({
  item, onRenew, renewLabel = 'Renouveler',
}: {
  item: InsightExpiring;
  onRenew: () => void;
  renewLabel?: string;
}) {
  const d = item.days_left;
  const urgency = d <= 1
    ? 'bg-accent/15 text-accent-bright'
    : d <= 3
      ? 'bg-warning/15 text-warning'
      : 'bg-white/5 text-ink-tertiary';
  return (
    <div className="flex items-center gap-3 border-t border-white/5 py-2 first:border-t-0">
      <div className="min-w-0 flex-1">
        <div className="truncate text-xs text-ink-primary">
          {item.label || item.customer_name || <span className="font-mono">{item.mac}</span>}
        </div>
        <div className="truncate text-[10px]"><MacLink mac={item.mac} className="text-[10px]" /></div>
      </div>
      <span className="shrink-0 text-[10px] text-ink-tertiary">
        {item.plan ? (PLAN_LABELS[item.plan] || item.plan) : '—'}
      </span>
      <span className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold ${urgency}`}>
        {d <= 0 ? "aujourd'hui" : `${d} j`}
      </span>
      <button
        type="button"
        onClick={onRenew}
        className="shrink-0 rounded-md border border-white/10 px-2 py-1 text-[11px] font-medium text-ink-secondary hover:border-accent/40 hover:text-ink-primary"
      >
        {renewLabel}
      </button>
    </div>
  );
}

function KpiCard({
  label,
  value,
  accent,
  wide,
}: {
  label: string;
  value: string | number;
  accent?: boolean;
  wide?: boolean;
}) {
  return (
    <div
      className={`rounded-xl border border-white/5 bg-midnight px-5 py-4 ${
        wide ? 'col-span-2' : ''
      }`}
    >
      <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">
        {label}
      </p>
      <p
        className={`mt-2 text-3xl font-semibold tracking-tight ${
          accent ? 'text-accent' : 'text-ink-primary'
        }`}
      >
        {value}
      </p>
    </div>
  );
}

function SkeletonCards() {
  return (
    <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
      {Array.from({ length: 7 }).map((_, i) => (
        <div
          key={i}
          className="h-24 animate-pulse rounded-xl border border-white/5 bg-midnight"
        />
      ))}
    </div>
  );
}

function NextActionCard({
  title,
  desc,
  to,
  soon,
}: {
  title: string;
  desc: string;
  to: string;
  soon?: boolean;
}) {
  return (
    <a
      href={`#${to}`}
      onClick={(e) => {
        if (soon) e.preventDefault();
      }}
      className={`block rounded-xl border border-white/5 bg-midnight px-5 py-4 transition hover:border-accent/30 ${
        soon ? 'cursor-not-allowed opacity-60' : ''
      }`}
    >
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold tracking-tight">{title}</p>
        {soon && (
          <span className="rounded-sm bg-white/5 px-1.5 py-0.5 text-[9px] uppercase tracking-wider text-ink-tertiary">
            bientôt
          </span>
        )}
      </div>
      <p className="mt-2 text-xs leading-relaxed text-ink-secondary">{desc}</p>
    </a>
  );
}
