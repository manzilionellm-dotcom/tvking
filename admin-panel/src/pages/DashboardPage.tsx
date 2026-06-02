import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  statsApi, type StatsOverview, ApiError,
  getCurrentUser, isOwnerRole,
} from '@/lib/api';
import { formatMoney } from '@/lib/utils';

/// Dashboard : cards de KPI lues en direct depuis /api/v1/stats/overview
/// qui requete D1 en parallele. Phase 1.A : 6 metriques.
/// Phase 1.B ajoutera graphiques de revenu, top apps, etc.
export function DashboardPage({ onLogout }: { onLogout: () => void }) {
  const [stats, setStats] = useState<StatsOverview | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    statsApi.overview()
      .then((s) => { if (active) { setStats(s); setErr(null); } })
      .catch((e) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) {
          onLogout();
        } else {
          setErr(e instanceof ApiError ? e.message : 'Erreur de chargement');
        }
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [onLogout]);

  return (
    <AppLayout
      title="Dashboard"
      subtitle="Vue d'ensemble de la plateforme"
      onLogout={onLogout}
    >
      {loading && <SkeletonCards />}
      {err && (
        <div className="rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm text-accent-bright">
          {err}
        </div>
      )}
      {stats && (
        <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
          <KpiCard label="Clients"        value={stats.customers} />
          <KpiCard label="Devices"        value={stats.devices} />
          <KpiCard label="Licenses"       value={stats.licenses} />
          <KpiCard label="Actives"        value={stats.active_licenses} accent />
          <KpiCard label="Expirées"       value={stats.expired_licenses} />
          {isOwnerRole(getCurrentUser()?.role) ? (
            <>
              <KpiCard label="Apps gérées" value={stats.apps} />
              {stats.resellers !== undefined && (
                <KpiCard label="Revendeurs" value={stats.resellers} />
              )}
              <KpiCard
                label="Revenu 30j"
                value={formatMoney(stats.revenue_30d_cents ?? 0)}
                wide
              />
            </>
          ) : (
            <KpiCard
              label="Mes crédits"
              value={stats.credit_balance ?? 0}
              accent
            />
          )}
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
            desc="Mettre à jour les credentials Xtream à distance."
            to="/playlists"
            soon
          />
        </div>
      </div>
    </AppLayout>
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
