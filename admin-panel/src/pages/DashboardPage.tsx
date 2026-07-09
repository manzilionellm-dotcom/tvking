import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import {
  statsApi, backupApi, onlineApi, auditApi, healthApi,
  type StatsOverview, type OnlineSnapshot, type AuditLog, ApiError,
  getCurrentUser, isOwnerRole,
} from '@/lib/api';
import { formatDateTime, formatMoney } from '@/lib/utils';
import { useT } from '@/lib/i18n';

/// Dashboard : KPI temps réel (rafraîchis toutes les 30 s) + apps en
/// ligne + flux d'activité (dernières actions du panel). Owner voit
/// tout ; un revendeur voit ses propres compteurs.
export function DashboardPage({ onLogout }: { onLogout: () => void }) {
  const t = useT();
  const [stats, setStats] = useState<StatsOverview | null>(null);
  const [online, setOnline] = useState<OnlineSnapshot | null>(null);
  const [activity, setActivity] = useState<AuditLog[]>([]);
  // Santé : latence API mesurée côté navigateur + latence D1 (serveur).
  const [health, setHealth] = useState<{ apiMs: number; dbMs: number | null; ok: boolean } | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [backupBusy, setBackupBusy] = useState(false);
  const owner = isOwnerRole(getCurrentUser()?.role);

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

  useEffect(() => {
    let active = true;
    const load = () => {
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
      if (owner) {
        onlineApi.get().then((o) => { if (active) setOnline(o); }).catch(() => {});
        auditApi.list().then((r) => { if (active) setActivity(r.items.slice(0, 12)); }).catch(() => {});
        const t0 = performance.now();
        healthApi.get()
          .then((h) => {
            if (active) setHealth({ apiMs: Math.round(performance.now() - t0), dbMs: h.db_ms, ok: h.ok });
          })
          .catch(() => { if (active) setHealth({ apiMs: Math.round(performance.now() - t0), dbMs: null, ok: false }); });
      }
    };
    load();
    // Temps réel « doux » : re-lecture toutes les 30 s tant que la page est ouverte.
    const timer = window.setInterval(load, 30_000);
    return () => { active = false; window.clearInterval(timer); };
  }, [onLogout, owner]);

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
          {owner && (
            <KpiCard
              label="En ligne maintenant"
              value={online ? online.onlineCount : '…'}
              accent
              to="/online"
            />
          )}
          <KpiCard label={t('dash.clients')}  value={stats.customers} to="/customers" />
          <KpiCard label={t('dash.devices')}  value={stats.devices} to="/devices" />
          <KpiCard label={t('dash.licenses')} value={stats.licenses} to="/activations" />
          <KpiCard label={t('dash.active')}   value={stats.active_licenses} accent to="/activations" />
          <KpiCard label={t('dash.expired')}  value={stats.expired_licenses} to="/activations" />
          <KpiCard label="Expirent (7 j)" value={stats.expiring_7d ?? 0} accent to="/activations" />
          {owner ? (
            <>
              <KpiCard label={t('dash.apps')} value={stats.apps} to="/apps" />
              {stats.resellers !== undefined && (
                <KpiCard label={t('dash.resellers')} value={stats.resellers} to="/resellers" />
              )}
              <KpiCard
                label={t('dash.revenue30')}
                value={formatMoney(stats.revenue_30d_cents ?? 0)}
                wide
              />
              {/* Santé système : latence mesurée en vrai, pas décorative. */}
              <div className="col-span-2 rounded-xl border border-white/5 bg-midnight px-5 py-4">
                <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                  Santé système
                </p>
                <div className="mt-2 flex items-center gap-4">
                  <span className={
                    'h-2.5 w-2.5 rounded-full ' +
                    (health === null ? 'bg-white/20' : health.ok ? 'bg-success' : 'bg-accent')
                  } />
                  <span className="text-sm text-ink-secondary">
                    {health === null
                      ? 'Mesure…'
                      : health.ok
                        ? <>API <span className="font-semibold text-ink-primary">{health.apiMs} ms</span>
                          {health.dbMs !== null && <> · Base <span className="font-semibold text-ink-primary">{health.dbMs} ms</span></>}
                          <span className="text-success"> · opérationnel</span></>
                        : <span className="text-accent-bright">Incident — la base ne répond pas</span>}
                  </span>
                </div>
              </div>
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

      <div className="mt-10 grid gap-8 lg:grid-cols-2">
        <div>
          <h2 className="mb-3 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Prochaines actions
          </h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <NextActionCard
              title="Activer un client"
              desc="Tape le MAC, choisis la durée — débloqué en quelques secondes."
              to="/activate"
            />
            <NextActionCard
              title="Pousser des sources"
              desc="M3U / Xtream par MAC, test en direct, livraison instantanée."
              to="/sources"
            />
            {owner && (
              <>
                <NextActionCard
                  title="Publier un produit"
                  desc="Nouvelle offre, accès, promo — visible sur tout le parc."
                  to="/products"
                />
                <NextActionCard
                  title="Brancher une intégration"
                  desc="Clés API à portée limitée + webhooks signés."
                  to="/integrations"
                />
              </>
            )}
          </div>
        </div>

        {/* ===== Flux d'activité (owner) — qui a fait quoi, en direct ===== */}
        {owner && (
          <div>
            <h2 className="mb-3 text-[10px] uppercase tracking-widest text-ink-tertiary">
              Activité récente
            </h2>
            <div className="rounded-xl border border-white/5 bg-midnight">
              {activity.length === 0 && (
                <p className="px-5 py-4 text-sm text-ink-tertiary">Aucune activité enregistrée.</p>
              )}
              <ul className="divide-y divide-white/5">
                {activity.map((a) => (
                  <li key={a.id} className="flex items-center justify-between gap-3 px-5 py-2.5 text-xs">
                    <span className="min-w-0">
                      <span className="font-medium text-ink-primary">{actionLabel(a.action)}</span>
                      {a.target_id && (
                        <span className="ml-2 truncate font-mono text-ink-tertiary">{a.target_id}</span>
                      )}
                    </span>
                    <span className="shrink-0 text-ink-tertiary">{formatDateTime(a.created_at)}</span>
                  </li>
                ))}
              </ul>
              {activity.length > 0 && (
                <Link to="/history"
                  className="block border-t border-white/5 px-5 py-2.5 text-center text-xs text-ink-secondary transition hover:text-accent-bright">
                  Voir tout l'historique →
                </Link>
              )}
            </div>
          </div>
        )}
      </div>
    </AppLayout>
  );
}

/// Libellé humain d'une action d'audit (repli : le code brut).
function actionLabel(action: string): string {
  const MAP: Record<string, string> = {
    'activate.create': 'Appareil activé',
    'activate.renew': 'Licence renouvelée',
    'source.set': 'Source poussée',
    'source.clear': 'Source retirée',
    'device.block': 'Appareil gelé/banni',
    'device.delete': 'Appareil supprimé',
    'device.transfer': 'Abonnement transféré',
    'license.renew': 'Licence prolongée',
    'auth.login': 'Connexion admin',
    'auth.login_failed': 'Connexion refusée',
    'password.change_self': 'Mot de passe modifié',
    'app_access.set': "Accès à l'app modifié",
    'product.create': 'Produit publié',
    'product.update': 'Produit modifié',
    'product.delete': 'Produit supprimé',
    'api_key.create': 'Clé API créée',
    'api_key.revoke': 'Clé API révoquée',
    'webhook.create': 'Webhook ajouté',
    'webhook.update': 'Webhook modifié',
    'webhook.delete': 'Webhook supprimé',
    'reseller.update': 'Revendeur modifié',
    'force_update.on': 'Mise à jour forcée activée',
    'force_update.off': 'Mise à jour forcée coupée',
  };
  return MAP[action] || action;
}

function KpiCard({
  label,
  value,
  accent,
  wide,
  to,
}: {
  label: string;
  value: string | number;
  accent?: boolean;
  wide?: boolean;
  to?: string;
}) {
  const inner = (
    <>
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
    </>
  );
  const cls = `rounded-xl border border-white/5 bg-midnight px-5 py-4 ${
    wide ? 'col-span-2' : ''
  }`;
  if (to) {
    return (
      <Link to={to} className={cls + ' block transition hover:border-accent/30'}>
        {inner}
      </Link>
    );
  }
  return <div className={cls}>{inner}</div>;
}

function SkeletonCards() {
  return (
    <div className="grid grid-cols-2 gap-4 md:grid-cols-3 lg:grid-cols-4">
      {Array.from({ length: 8 }).map((_, i) => (
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
}: {
  title: string;
  desc: string;
  to: string;
}) {
  return (
    <Link
      to={to}
      className="block rounded-xl border border-white/5 bg-midnight px-5 py-4 transition hover:border-accent/30"
    >
      <p className="text-sm font-semibold tracking-tight">{title}</p>
      <p className="mt-2 text-xs leading-relaxed text-ink-secondary">{desc}</p>
    </Link>
  );
}
