// =========================================================
//  OverviewPage — « Ce qui s'est passé » (Vague C22)
// =========================================================
//  PAGE D'ACCUEIL après connexion (demande owner : « si je me connecte,
//  il me dit les nouveautés, comment les clients se sont comportés »).
//
//  Elle lit UN SEUL endpoint : GET /api/v1/insights/overview (auth admin)
//  et affiche :
//    • un en-tête « Bonjour / Bonsoir » + date du jour ;
//    • 4 cartes chiffres : Appareils totaux · Actifs 24 h · Actifs 7 j ·
//      Nouveaux 7 j ;
//    • ⚠️ une carte « Attention » : boxes silencieuses ≥ 7 j et
//      abonnements qui expirent sous 7 jours (les 2 alertes proactives) ;
//    • une carte « Santé » : erreurs remontées sur 7 jours ;
//    • une carte « Versions » : répartition des versions de l'app.
//
//  ⚠️ DÉFENSIF PAR CONSTRUCTION : le worker est déployé EN PARALLÈLE.
//    - endpoint absent (404/501/503) → message doux « pas encore dispo » ;
//    - champ manquant → « — » ou carte masquée, JAMAIS de crash ;
//    - timestamps en s / ms / ISO → normalisés par toMillis().
// =========================================================

import { useCallback, useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { MacLink } from '@/components/MacLink';
import {
  insightsApi, ApiError,
  type InsightsOverview, type OverviewSilentDevice, type OverviewExpiringDevice,
} from '@/lib/api';
import { formatDateTime, toMillis, cn } from '@/lib/utils';
import { useT } from '@/lib/i18n';

/// Nombre de lignes montrées avant de replier une liste d'alerte.
const LIST_FOLD = 5;

/// Seuil du « pic d'erreurs » : au-delà de ce nombre d'erreurs remontées
/// sur 7 jours, le bandeau d'alertes signale une anomalie. En-dessous,
/// c'est du bruit de fond normal → on ne dit rien.
const ERROR_SPIKE_THRESHOLD = 50;

/// Interpolation minimaliste : remplace {n} dans une clé i18n (le t() du
/// panel ne gère pas les variables — même approche que LabPage).
function fmt(s: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce(
    (acc, [k, v]) => acc.split(`{${k}}`).join(String(v)),
    s,
  );
}

/// Affiche un compteur, ou « — » si le worker n'a pas (encore) le champ.
function num(v: number | undefined): string {
  return typeof v === 'number' && Number.isFinite(v)
    ? v.toLocaleString('fr-FR')
    : '—';
}

/// « il y a N j » à partir de millisecondes (complément lisible de la date).
function agoDays(ms: number | null): string {
  if (!ms) return '';
  const d = Math.floor((Date.now() - ms) / 86_400_000);
  if (d <= 0) return "aujourd'hui";
  return `il y a ${d} j`;
}

/// Jours restants avant une échéance (négatif = déjà passée).
function daysLeft(ms: number | null): number | null {
  if (!ms) return null;
  return Math.ceil((ms - Date.now()) / 86_400_000);
}

type LoadState =
  | { kind: 'loading' }
  | { kind: 'ready'; data: InsightsOverview }
  // « unavailable » = le worker ne connaît pas encore l'endpoint (404…)
  | { kind: 'unavailable' }
  | { kind: 'error'; message: string };

export function OverviewPage({ onLogout }: { onLogout: () => void }) {
  const t = useT();
  const [state, setState] = useState<LoadState>({ kind: 'loading' });
  const [refreshing, setRefreshing] = useState(false);
  // Numéro de requête : une réponse périmée ne doit jamais setState
  // (même garde-fou que le reste du panel).
  const seqRef = useRef(0);

  // Ancres pour le bandeau d'alertes : cliquer une alerte fait défiler
  // jusqu'à la carte détaillée correspondante (plutôt que de dupliquer
  // les listes ici).
  const attentionRef = useRef<HTMLDivElement>(null);
  const healthRef = useRef<HTMLDivElement>(null);
  const scrollToCard = (ref: React.RefObject<HTMLDivElement>) => {
    ref.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  };

  const load = useCallback((isRefresh = false) => {
    const seq = ++seqRef.current;
    if (isRefresh) setRefreshing(true);
    else setState({ kind: 'loading' });
    insightsApi.overview()
      .then((data) => {
        if (seq !== seqRef.current) return;
        // Défense ultime : réponse non-objet (proxy, HTML d'erreur…) →
        // on la traite comme indisponible plutôt que de planter le rendu.
        if (!data || typeof data !== 'object') setState({ kind: 'unavailable' });
        else setState({ kind: 'ready', data });
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        if (seq !== seqRef.current) return;
        // 404 / 501 : worker pas encore déployé avec cet endpoint —
        // c'est un état ATTENDU pendant la vague, pas une panne.
        if (e instanceof ApiError && (e.status === 404 || e.status === 501)) {
          setState({ kind: 'unavailable' });
        } else {
          setState({
            kind: 'error',
            message: e instanceof ApiError ? e.message : 'Impossible de charger les insights.',
          });
        }
      })
      .finally(() => { if (seq === seqRef.current) setRefreshing(false); });
  }, [onLogout]);

  useEffect(() => { load(); }, [load]);
  // Démontage : invalide toute réponse encore en vol.
  useEffect(() => () => { seqRef.current += 1; }, []);

  // ----- En-tête : salutation selon l'heure + date du jour en français.
  const hour = new Date().getHours();
  const greeting = hour >= 18 || hour < 5 ? 'Bonsoir' : 'Bonjour';
  const today = new Date().toLocaleDateString('fr-FR', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
  });
  const todayCap = today.charAt(0).toUpperCase() + today.slice(1);

  const data = state.kind === 'ready' ? state.data : null;
  const dev = data?.devices;
  const generatedAt = toMillis(data?.generated_at);

  // Chaque carte n'apparaît que si le worker fournit le champ associé.
  const hasAttention = !!dev && (dev.silent_7d !== undefined || dev.expiring_7d !== undefined);
  const hasHealth = data?.errors_7d !== undefined && data?.errors_7d !== null;
  const versions = Array.isArray(data?.versions) ? data!.versions! : null;

  // ----- Bandeau d'alertes proactives (Vague C25) -----------------------
  // Comptes 100 % défensifs : champ absent / non-tableau → 0 → pas d'alerte.
  const expiringCount = Array.isArray(dev?.expiring_7d) ? dev!.expiring_7d!.length : 0;
  const silentCount = Array.isArray(dev?.silent_7d) ? dev!.silent_7d!.length : 0;
  const errorsCount = typeof data?.errors_7d?.count === 'number'
    && Number.isFinite(data.errors_7d.count)
    ? data.errors_7d.count
    : 0;
  // Une erreur ne devient une alerte que si elle dépasse le seuil de « pic ».
  const errorSpike = errorsCount > ERROR_SPIKE_THRESHOLD;

  return (
    <AppLayout
      title="Tableau de bord"
      subtitle="Ce qui s'est passé"
      onLogout={onLogout}
      actions={(
        <button
          type="button"
          onClick={() => load(true)}
          disabled={refreshing || state.kind === 'loading'}
          title="Recharger les insights"
          className="rounded-md border border-white/10 px-3 py-1.5 text-xs font-semibold text-ink-secondary transition hover:border-accent/40 hover:text-ink-primary disabled:opacity-50"
        >
          {refreshing ? 'Actualisation…' : '↻ Rafraîchir'}
        </button>
      )}
    >
      {/* ===== Salutation + date (l'owner voit ça en arrivant) ===== */}
      <div className="mb-6">
        <h2 className="text-xl font-semibold tracking-tight md:text-2xl">
          {greeting} 👋
        </h2>
        <p className="mt-1 text-sm text-ink-secondary">{todayCap}</p>
        {generatedAt !== null && (
          <p className="mt-0.5 text-[11px] text-ink-tertiary">
            Données calculées le {formatDateTime(generatedAt)}
          </p>
        )}
      </div>

      {/* ===== États de chargement / erreur ===== */}
      {state.kind === 'loading' && <OverviewSkeleton />}

      {state.kind === 'unavailable' && (
        <StateCard
          title="Le tableau de bord arrive bientôt"
          message={"Le serveur n'expose pas encore le résumé « Ce qui s'est passé » "
            + '(mise à jour du worker en cours de déploiement). '
            + 'Rien de cassé : réessaie dans quelques minutes.'}
          onRetry={() => load()}
        />
      )}

      {state.kind === 'error' && (
        <StateCard
          tone="error"
          title="Impossible de charger les insights"
          message={state.message}
          onRetry={() => load()}
        />
      )}

      {data && (
        <>
          {/* ===== Bandeau d'alertes proactives — TOUT EN HAUT =====
              N'apparaît QUE s'il y a du concret à traiter. Sinon, accueil
              propre (aucun bandeau). */}
          <AlertsBanner
            t={t}
            expiringCount={expiringCount}
            silentCount={silentCount}
            errorsCount={errorsCount}
            errorSpike={errorSpike}
            onExpiring={() => scrollToCard(attentionRef)}
            onSilent={() => scrollToCard(attentionRef)}
            onErrors={() => scrollToCard(healthRef)}
          />

          {/* ===== Cartes chiffres — le pouls du parc ===== */}
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <StatCard label="Appareils totaux" value={num(dev?.total)} />
            <StatCard label="Actifs 24 h" value={num(dev?.active_24h)} accent="success" />
            <StatCard label="Actifs 7 j" value={num(dev?.active_7d)} />
            <StatCard label="Nouveaux 7 j" value={num(dev?.new_7d)} accent="accent" />
          </div>

          {/* ===== Cartes détaillées ===== */}
          <div className="mt-6 grid grid-cols-1 gap-4 xl:grid-cols-2">
            {/* ⚠️ Attention : les 2 alertes proactives demandées.
                Ancre (attentionRef) : cible du défilement depuis le bandeau. */}
            {hasAttention && (
              <div ref={attentionRef}>
                <SectionCard
                  title="⚠️ Attention"
                  badge={(dev?.silent_7d?.length ?? 0) + (dev?.expiring_7d?.length ?? 0)}
                  badgeTone="warning"
                >
                  {dev?.silent_7d !== undefined && (
                    <SilentList items={dev.silent_7d ?? []} />
                  )}
                  {dev?.expiring_7d !== undefined && (
                    <ExpiringList items={dev.expiring_7d ?? []} />
                  )}
                </SectionCard>
              </div>
            )}

            {/* Santé : erreurs remontées par les apps sur 7 jours.
                Ancre (healthRef) : cible du défilement « pic d'erreurs ». */}
            {hasHealth && (
              <div ref={healthRef}>
                <SectionCard
                  title="Santé"
                  badge={data.errors_7d?.count ?? 0}
                  badgeTone={(data.errors_7d?.count ?? 0) > 0 ? 'error' : 'success'}
                >
                  <ErrorsBlock errors={data.errors_7d!} />
                </SectionCard>
              </div>
            )}

            {/* Versions : répartition du parc par version d'app. */}
            {versions && versions.length > 0 && (
              <SectionCard title="Versions de l'app" badge={versions.length} badgeTone="neutral">
                <VersionsBlock versions={versions} />
              </SectionCard>
            )}
          </div>

          {/* Si le worker répond mais sans AUCUN détail, on le dit
              gentiment plutôt que d'afficher une page à moitié vide. */}
          {!hasAttention && !hasHealth && (!versions || versions.length === 0) && (
            <p className="mt-6 text-xs text-ink-tertiary">
              Le serveur ne fournit pas encore le détail (alertes, santé,
              versions) — seules les cartes chiffres sont disponibles.
            </p>
          )}
        </>
      )}
    </AppLayout>
  );
}

// =========================================================
//  Bandeau d'alertes proactives (Vague C25)
// =========================================================
//  Affiché TOUT EN HAUT du tableau de bord, AVANT les cartes chiffres.
//  Il ne montre QUE ce qui est actionnable :
//    • ⏰ abonnements qui expirent cette semaine ;
//    • 🔇 boxes silencieuses depuis 7 jours ;
//    • ⚠️ pic d'erreurs (au-delà du seuil ERROR_SPIKE_THRESHOLD).
//  Si aucune alerte → le composant ne rend RIEN (accueil propre).
//  Chaque ligne = icône (dans le libellé) + compteur + action « Voir »
//  qui fait défiler jusqu'à la carte détaillée concernée.
// =========================================================
function AlertsBanner({
  t, expiringCount, silentCount, errorsCount, errorSpike,
  onExpiring, onSilent, onErrors,
}: {
  t: (k: string) => string;
  expiringCount: number;
  silentCount: number;
  errorsCount: number;
  errorSpike: boolean;
  onExpiring: () => void;
  onSilent: () => void;
  onErrors: () => void;
}) {
  // On assemble la liste des alertes réellement actionnables.
  // tone : 'warning' (ambre) pour l'informatif urgent, 'danger' (braise)
  // pour l'anomalie technique (pic d'erreurs).
  const alerts: {
    key: string; label: string; tone: 'warning' | 'danger'; onClick: () => void;
  }[] = [];

  if (expiringCount > 0) {
    alerts.push({
      key: 'expiring',
      label: fmt(t('overview.alertExpiring'), { n: expiringCount }),
      tone: 'warning',
      onClick: onExpiring,
    });
  }
  if (silentCount > 0) {
    alerts.push({
      key: 'silent',
      label: fmt(t('overview.alertSilent'), { n: silentCount }),
      tone: 'warning',
      onClick: onSilent,
    });
  }
  if (errorSpike) {
    alerts.push({
      key: 'errors',
      label: fmt(t('overview.alertErrors'), { n: errorsCount }),
      tone: 'danger',
      onClick: onErrors,
    });
  }

  // Rien d'actionnable → aucun bandeau (exigence : accueil propre).
  if (alerts.length === 0) return null;

  return (
    <div className="mb-6 rounded-xl border border-warning/25 bg-warning/[0.06] px-4 py-3">
      <p className="mb-2 text-[10px] font-semibold uppercase tracking-widest text-warning">
        {t('overview.alertsTitle')}
      </p>
      <div className="flex flex-col gap-2">
        {alerts.map((a) => {
          const toneCls = a.tone === 'danger'
            ? 'border-accent/30 bg-accent/10 text-accent-bright hover:border-accent/50'
            : 'border-warning/25 bg-warning/10 text-warning hover:border-warning/45';
          return (
            <button
              key={a.key}
              type="button"
              onClick={a.onClick}
              className={cn(
                'flex items-center justify-between gap-3 rounded-lg border px-3 py-2 text-left text-xs font-semibold transition',
                toneCls,
              )}
            >
              <span className="min-w-0 flex-1">{a.label}</span>
              <span className="shrink-0 text-[11px] font-medium opacity-80">
                {t('overview.alertAction')} →
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// =========================================================
//  Sous-blocs de la carte « Attention »
// =========================================================

/// Boxes silencieuses depuis ≥ 7 jours : MAC + dernier signe de vie.
function SilentList({ items }: { items: OverviewSilentDevice[] }) {
  return (
    <AlertBlock
      title="Boxes silencieuses depuis 7 jours"
      hint="Plus aucun signe de vie — client parti ? box débranchée ?"
      count={items.length}
    >
      <FoldableList
        items={items}
        empty="Aucune box silencieuse. Tout le monde est là."
        render={(it, i) => (
          <div
            key={`${it.mac ?? 'mac'}:${i}`}
            className="flex items-center gap-3 border-t border-white/5 py-2 first:border-t-0"
          >
            <div className="min-w-0 flex-1">
              <MacLink mac={it.mac ?? null} />
            </div>
            <span className="shrink-0 text-[10px] text-ink-tertiary">
              {(() => {
                const ms = toMillis(it.last_seen);
                return ms
                  ? `vu ${formatDateTime(ms)} · ${agoDays(ms)}`
                  : 'jamais vu';
              })()}
            </span>
          </div>
        )}
      />
    </AlertBlock>
  );
}

/// Abonnements payés qui expirent sous 7 jours : MAC + date de fin.
function ExpiringList({ items }: { items: OverviewExpiringDevice[] }) {
  return (
    <AlertBlock
      title="Abonnements qui expirent sous 7 jours"
      hint="À relancer avant la coupure."
      count={items.length}
    >
      <FoldableList
        items={items}
        empty="Aucune expiration dans les 7 prochains jours."
        render={(it, i) => {
          const ms = toMillis(it.paid_until);
          const d = daysLeft(ms);
          // Badge d'urgence : ≤ 1 j rouge braise, ≤ 3 j ambre, sinon neutre.
          const urgency = d !== null && d <= 1
            ? 'bg-accent/15 text-accent-bright'
            : d !== null && d <= 3
              ? 'bg-warning/15 text-warning'
              : 'bg-white/5 text-ink-tertiary';
          return (
            <div
              key={`${it.mac ?? 'mac'}:${i}`}
              className="flex items-center gap-3 border-t border-white/5 py-2 first:border-t-0"
            >
              <div className="min-w-0 flex-1">
                <MacLink mac={it.mac ?? null} />
              </div>
              <span className="shrink-0 text-[10px] text-ink-tertiary">
                {ms ? formatDateTime(ms) : '—'}
              </span>
              {d !== null && (
                <span className={cn(
                  'shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold',
                  urgency,
                )}
                >
                  {d <= 0 ? "aujourd'hui" : `${d} j`}
                </span>
              )}
            </div>
          );
        }}
      />
    </AlertBlock>
  );
}

/// Enveloppe d'une alerte : petit titre + compteur + contenu.
function AlertBlock({
  title, hint, count, children,
}: {
  title: string; hint?: string; count: number; children: React.ReactNode;
}) {
  return (
    <div className="mb-4 last:mb-0">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-xs font-semibold text-ink-primary">{title}</p>
        <span className={cn(
          'rounded-full px-2 py-0.5 text-[10px] font-bold',
          count > 0 ? 'bg-warning/15 text-warning' : 'bg-white/5 text-ink-tertiary',
        )}
        >
          {count}
        </span>
      </div>
      {hint && <p className="mt-0.5 text-[10px] text-ink-tertiary">{hint}</p>}
      <div className="mt-1">{children}</div>
    </div>
  );
}

/// Liste repliée au-delà de LIST_FOLD lignes, avec bouton
/// « Afficher les N autres » / « Réduire » (demande : listes compactes).
function FoldableList<T>({
  items, empty, render,
}: {
  items: T[];
  empty: string;
  render: (item: T, index: number) => React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  if (items.length === 0) {
    return <p className="py-1.5 text-xs text-ink-tertiary">{empty}</p>;
  }
  const shown = open ? items : items.slice(0, LIST_FOLD);
  const hidden = items.length - LIST_FOLD;
  return (
    <div>
      <div className="max-h-64 overflow-y-auto">{shown.map(render)}</div>
      {hidden > 0 && (
        <button
          type="button"
          onClick={() => setOpen((o) => !o)}
          className="mt-1 rounded-md px-2 py-1 text-[11px] font-medium text-accent hover:text-accent-bright"
        >
          {open ? 'Réduire' : `Afficher les ${hidden} autres`}
        </button>
      )}
    </div>
  );
}

// =========================================================
//  Carte « Santé » — erreurs remontées sur 7 jours
// =========================================================
function ErrorsBlock({ errors }: {
  errors: { count?: number; top?: { message?: string | null; count?: number }[] };
}) {
  const count = errors.count;
  const top = Array.isArray(errors.top) ? errors.top : [];
  return (
    <div>
      <div className="flex items-baseline gap-2">
        <span className={cn(
          'text-3xl font-semibold tracking-tight',
          (count ?? 0) > 0 ? 'text-warning' : 'text-success',
        )}
        >
          {num(count)}
        </span>
        <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
          erreurs sur 7 jours
        </span>
      </div>
      {(count ?? 0) === 0 && top.length === 0 && (
        <p className="mt-2 text-xs text-ink-tertiary">
          Aucune erreur remontée par les apps. Tout roule.
        </p>
      )}
      {top.length > 0 && (
        <div className="mt-3">
          <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">
            Messages les plus fréquents
          </p>
          <div className="mt-1">
            {top.map((e, i) => (
              <div
                key={`${e.message ?? 'msg'}:${i}`}
                className="flex items-center gap-3 border-t border-white/5 py-2 first:border-t-0"
              >
                <span className="min-w-0 flex-1 truncate text-xs text-ink-secondary" title={e.message ?? undefined}>
                  {e.message || '—'}
                </span>
                <span className="shrink-0 rounded-full bg-white/5 px-2 py-0.5 text-[10px] font-semibold text-ink-tertiary">
                  ×{num(e.count)}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// =========================================================
//  Carte « Versions » — répartition du parc, sans lib de graphiques :
//  une simple barre de proportion en div (sobre et lisible).
// =========================================================
function VersionsBlock({ versions }: {
  versions: { version?: string | null; count?: number }[];
}) {
  // Tri décroissant par population ; total pour les proportions.
  const rows = [...versions].sort((a, b) => (b.count ?? 0) - (a.count ?? 0));
  const total = rows.reduce((s, v) => s + (v.count ?? 0), 0);
  return (
    <div>
      {rows.map((v, i) => {
        const pct = total > 0 ? Math.round(((v.count ?? 0) / total) * 100) : 0;
        return (
          <div
            key={`${v.version ?? 'v'}:${i}`}
            className="border-t border-white/5 py-2 first:border-t-0"
          >
            <div className="flex items-center gap-3">
              <span className="min-w-0 flex-1 truncate font-mono text-xs text-ink-primary">
                {v.version || 'inconnue'}
              </span>
              <span className="shrink-0 text-xs font-semibold text-ink-secondary">
                {num(v.count)}
              </span>
              <span className="w-9 shrink-0 text-right text-[10px] text-ink-tertiary">
                {total > 0 ? `${pct} %` : '—'}
              </span>
            </div>
            {/* Barre de proportion (pas de lib : une div suffit). */}
            <div className="mt-1 h-1 overflow-hidden rounded-full bg-white/5">
              <div
                className="h-full rounded-full bg-accent/60"
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}

// =========================================================
//  Briques génériques de la page
// =========================================================

/// Carte chiffre (même gabarit que les KPI du panel).
function StatCard({
  label, value, accent,
}: {
  label: string; value: string; accent?: 'accent' | 'success';
}) {
  return (
    <div className="rounded-xl border border-white/5 bg-midnight px-5 py-4">
      <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</p>
      <p className={cn(
        'mt-2 text-3xl font-semibold tracking-tight',
        accent === 'accent' && 'text-accent',
        accent === 'success' && 'text-success',
        !accent && 'text-ink-primary',
      )}
      >
        {value}
      </p>
    </div>
  );
}

/// Grande carte à titre + badge compteur (gabarit des InsightCard du panel).
function SectionCard({
  title, badge, badgeTone, children,
}: {
  title: string;
  badge?: number;
  badgeTone?: 'warning' | 'error' | 'success' | 'neutral';
  children: React.ReactNode;
}) {
  const badgeCls = {
    warning: 'bg-warning/15 text-warning',
    error: 'bg-accent/15 text-accent-bright',
    success: 'bg-success/15 text-success',
    neutral: 'bg-white/5 text-ink-tertiary',
  }[badgeTone ?? 'neutral'];
  return (
    <div className="rounded-xl border border-white/5 bg-midnight px-5 py-4">
      <div className="mb-3 flex items-center justify-between">
        <p className="text-sm font-semibold tracking-tight">{title}</p>
        {badge !== undefined && (
          <span className={cn('rounded-full px-2 py-0.5 text-[11px] font-bold', badgeCls)}>
            {badge}
          </span>
        )}
      </div>
      {children}
    </div>
  );
}

/// Écran d'état (endpoint absent / erreur) avec bouton « Réessayer ».
function StateCard({
  title, message, onRetry, tone,
}: {
  title: string; message: string; onRetry: () => void; tone?: 'error';
}) {
  return (
    <div className={cn(
      'rounded-xl border px-5 py-6',
      tone === 'error'
        ? 'border-accent/30 bg-accent/10'
        : 'border-white/10 bg-midnight',
    )}
    >
      <p className={cn(
        'text-sm font-semibold tracking-tight',
        tone === 'error' ? 'text-accent-bright' : 'text-ink-primary',
      )}
      >
        {title}
      </p>
      <p className="mt-1 max-w-xl text-xs leading-relaxed text-ink-secondary">{message}</p>
      <button
        type="button"
        onClick={onRetry}
        className="mt-4 rounded-md border border-white/10 px-3 py-1.5 text-xs font-semibold text-ink-secondary transition hover:border-accent/40 hover:text-ink-primary"
      >
        ↻ Réessayer
      </button>
    </div>
  );
}

/// Squelette de chargement : 4 cartes chiffres + 2 grandes cartes.
function OverviewSkeleton() {
  return (
    <div>
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-24 animate-pulse rounded-xl border border-white/5 bg-midnight" />
        ))}
      </div>
      <div className="mt-6 grid grid-cols-1 gap-4 xl:grid-cols-2">
        {Array.from({ length: 2 }).map((_, i) => (
          <div key={i} className="h-64 animate-pulse rounded-xl border border-white/5 bg-midnight" />
        ))}
      </div>
    </div>
  );
}
