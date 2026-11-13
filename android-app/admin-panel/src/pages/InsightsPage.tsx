import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { Alert, EmptyState } from '@/components/ui';
import {
  insightsApi, flagEmoji, ApiError, isAbortError,
  type Insights, type InsightPerson, type InsightStat,
} from '@/lib/api';
import { planLabel } from '@/lib/activation';
import { countryName } from '@/lib/clientRow';
import { downloadCsv } from '@/lib/csv';
import { agoLabel, formatDateTime, qualityLevel } from '@/lib/robust';

/// Page « Pilotage » (owner) : ce qu'il faut regarder chaque matin.
///   1. Santé : est-ce que ça coupe, et où (chaîne, pays, version) ?
///   2. Ventes : nouveaux abonnés, qui expire cette semaine, qui est parti.
///   3. Fraude : la même box sous plusieurs MAC.
/// Lecture seule. Rafraîchi toutes les 30 s : ces chiffres bougent lentement.
const REFRESH_MS = 30000;

const BLOCK_NAME: Record<string, string> = {
  health: 'la santé des chaînes',
  money: 'les ventes',
  fraud: 'la détection de fraude',
};

export function InsightsPage({ onLogout }: { onLogout: () => void }) {
  const [data, setData] = useState<Insights | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const abort = useRef<AbortController | null>(null);

  const load = useCallback(() => {
    abort.current?.abort();
    const ctl = new AbortController();
    abort.current = ctl;
    insightsApi.get(ctl.signal)
      .then((raw) => { setData(raw); setErr(null); })
      .catch((e: unknown) => {
        if (isAbortError(e)) return;
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => { if (abort.current === ctl) setLoading(false); });
  }, [onLogout]);

  useEffect(() => {
    load();
    const t = setInterval(load, REFRESH_MS);
    return () => { clearInterval(t); abort.current?.abort(); };
  }, [load]);

  const h = data?.health;
  const m = data?.money;
  const missing = (data?.unavailable ?? []).map((k) => BLOCK_NAME[k] || k);

  return (
    <AppLayout
      title="Pilotage"
      subtitle="Santé des chaînes, ventes et alertes, en un coup d'œil"
      onLogout={onLogout}
    >
      {err && <Alert>{err}</Alert>}
      {missing.length > 0 && (
        <Alert>Données indisponibles pour {missing.join(', ')}. Le reste de la page est à jour.</Alert>
      )}

      {loading && !data ? (
        <div role="status" className="space-y-3">
          <div className="h-24 animate-pulse rounded-xl border border-white/10 bg-midnight" />
          <p className="text-sm text-ink-secondary">Chargement du pilotage…</p>
        </div>
      ) : data && h && m ? (
        <>
          {/* ---------- 1. SANTÉ ---------- */}
          {h.alert && (
            <div
              role="alert"
              className="mb-5 rounded-xl border px-4 py-3 text-sm"
              style={{ borderColor: 'rgba(235,87,87,0.5)', background: 'rgba(235,87,87,0.10)', color: '#F5A3A3' }}
            >
              <strong>Panne probable.</strong> {h.bad} box sur {h.watching} ont une mauvaise
              qualité de lecture en ce moment. Regarde les chaînes en rouge ci-dessous.
            </div>
          )}
          <SectionTitle>Santé en direct</SectionTitle>
          <div className="mb-5 grid gap-3 sm:grid-cols-3">
            <Stat label="Regardent maintenant" value={String(h.watching)} />
            <Stat
              label="Qualité moyenne"
              value={h.quality == null ? '—' : `${h.quality} %`}
              color={qualityColor(h.quality)}
              hint={h.quality == null ? 'Aucune box ne l’envoie encore' : undefined}
            />
            <Stat label="En difficulté (< 70 %)" value={String(h.bad)} color={h.bad > 0 ? '#EB5757' : undefined} />
          </div>
          <div className="mb-8 grid gap-4 lg:grid-cols-3">
            <QualityList title="Par chaîne" rows={h.byChannel} />
            <QualityList
              title="Par pays"
              rows={h.byCountry}
              labelOf={(k) => `${flagEmoji(k)} ${countryName(k) || k}`}
            />
            <QualityList title="Par version de l'app" rows={h.byVersion} labelOf={(k) => (k === '?' ? 'Inconnue' : `ZUNO v${k}`)} />
          </div>

          {/* ---------- 2. VENTES ---------- */}
          <SectionTitle>Abonnés</SectionTitle>
          <div className="mb-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Stat label="Abonnés payants actifs" value={String(m.paidActive)} color="#6FCF97" />
            <Stat label="Nouveaux abonnés (30 j)" value={String(m.newPaid30)} />
            <Stat label="Expirent sous 7 jours" value={String(m.expiring.length)} color={m.expiring.length ? '#F2C94C' : undefined} />
            <Stat label="Abonnements expirés" value={String(m.paidExpired)} />
          </div>
          <div className="mb-5 grid gap-4 lg:grid-cols-3">
            <DayBars days={m.perDay} />
            <CountList title="Nouveaux abonnés par plan (30 j)" rows={m.byPlan} labelOf={planLabel} />
            <CountList title="Nouveaux abonnés par revendeur (30 j)" rows={m.byReseller} />
          </div>
          <p className="mb-8 text-xs text-ink-tertiary">
            Revendeurs, 30 derniers jours : {m.resellerActivations30} activation(s) et{' '}
            {m.resellerRenewals30} renouvellement(s) payés en crédits. Tes propres activations
            directes ne passent pas par les crédits : elles ne sont pas dans ce compte.
          </p>

          <PeopleTable
            title="Expirent dans les 7 jours"
            hint="À relancer en priorité : un message avant la fin évite de perdre le client."
            file="zuno-expirent-7-jours.csv"
            rows={m.expiring}
            empty="Personne n’expire cette semaine."
          />
          <PeopleTable
            title="Clients perdus (expirés depuis 30 à 180 jours)"
            hint="Ils ont payé une fois et ne sont pas revenus."
            file="zuno-clients-perdus.csv"
            rows={m.lost}
            empty="Aucun client perdu sur cette période."
          />

          {/* ---------- 3. FRAUDE ---------- */}
          <SectionTitle>Même box, plusieurs MAC</SectionTitle>
          <p className="mb-3 text-xs text-ink-tertiary">
            Une box qui revient sous une nouvelle MAC peut chercher à refaire un essai gratuit.
            Ce n’est pas une preuve : une réinstallation peut aussi changer la MAC. À vérifier avant de bannir.
          </p>
          <div className="mb-8 overflow-x-auto rounded-xl border border-white/10">
            <table className="w-full text-left text-sm">
              <thead className="bg-midnight">
                <tr>
                  <Th>Box (identifiant masqué)</Th><Th>MAC vues</Th><Th>Détail</Th>
                </tr>
              </thead>
              <tbody>
                {data.fraud.sameBox.map((b) => (
                  <tr key={b.id + b.macs.join()} className="border-t border-white/5">
                    <td className="px-4 py-2.5 font-mono text-xs text-ink-secondary">{b.id}</td>
                    <td className="px-4 py-2.5 font-semibold" style={{ color: b.count >= 3 ? '#EB5757' : '#F2C94C' }}>{b.count}</td>
                    <td className="px-4 py-2.5 font-mono text-xs text-ink-secondary">{b.macs.join('  ·  ')}</td>
                  </tr>
                ))}
                {data.fraud.sameBox.length === 0 && (
                  <tr><td colSpan={3}><EmptyState title="Rien de suspect." hint="Aucune box vue sous plusieurs MAC." /></td></tr>
                )}
              </tbody>
            </table>
          </div>

          <p className="text-xs text-ink-tertiary">Mis à jour {agoLabel(data.generated_at)}.</p>
        </>
      ) : null}
    </AppLayout>
  );
}

function qualityColor(q: number | null): string | undefined {
  const level = qualityLevel(q);
  if (level === 'good') return '#6FCF97';
  if (level === 'medium') return '#F2C94C';
  if (level === 'bad') return '#EB5757';
  return undefined;
}

function SectionTitle({ children }: { children: ReactNode }) {
  return <h2 className="mb-3 text-sm font-semibold uppercase tracking-widest text-ink-secondary">{children}</h2>;
}

function Th({ children }: { children: ReactNode }) {
  return <th scope="col" className="px-4 py-3 text-[10px] font-semibold uppercase tracking-widest text-ink-secondary">{children}</th>;
}

function Stat({ label, value, color, hint }: { label: string; value: string; color?: string; hint?: string }) {
  return (
    <div className="rounded-xl border border-white/5 bg-midnight p-4">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</div>
      <div className="mt-1 text-3xl font-bold text-ink-primary" style={color ? { color } : undefined}>{value}</div>
      {hint && <div className="mt-1 text-[11px] text-ink-tertiary">{hint}</div>}
    </div>
  );
}

function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="rounded-xl border border-white/5 bg-midnight p-4">
      <div className="mb-3 text-[10px] uppercase tracking-widest text-ink-tertiary">{title}</div>
      {children}
    </div>
  );
}

/// Liste « nom · nombre de box · qualité », la pire qualité en rouge.
function QualityList({
  title, rows, labelOf,
}: { title: string; rows: InsightStat[]; labelOf?: (key: string) => string }) {
  return (
    <Card title={title}>
      {rows.length === 0 ? (
        <div className="text-xs text-ink-tertiary">Aucune mesure pour l’instant.</div>
      ) : (
        <ul className="space-y-2.5">
          {rows.map((r) => {
            const color = qualityColor(r.quality) || '#B6B0A8';
            return (
              <li key={r.key}>
                <div className="flex items-baseline justify-between gap-2 text-xs">
                  <span className="truncate text-ink-primary">{labelOf ? labelOf(r.key) : r.key}</span>
                  <span className="shrink-0 text-ink-tertiary">
                    {r.count} box · <strong style={{ color }}>{r.quality} %</strong>
                  </span>
                </div>
                <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-white/10">
                  <div className="h-full rounded-full" style={{ width: `${Math.max(0, Math.min(100, r.quality))}%`, background: color }} />
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </Card>
  );
}

function CountList({
  title, rows, labelOf,
}: { title: string; rows: { key: string; count: number }[]; labelOf?: (key: string) => string }) {
  const max = rows.reduce((mx, r) => Math.max(mx, r.count), 0) || 1;
  return (
    <Card title={title}>
      {rows.length === 0 ? (
        <div className="text-xs text-ink-tertiary">Rien sur la période.</div>
      ) : (
        <ul className="space-y-2.5">
          {rows.map((r) => (
            <li key={r.key}>
              <div className="flex items-baseline justify-between gap-2 text-xs">
                <span className="truncate text-ink-primary">{labelOf ? labelOf(r.key) : r.key}</span>
                <strong className="shrink-0 text-ink-primary">{r.count}</strong>
              </div>
              <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-white/10">
                <div className="h-full rounded-full bg-accent" style={{ width: `${(r.count * 100) / max}%` }} />
              </div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

/// Nouveaux abonnés par jour : une barre par jour, la date au survol.
function DayBars({ days }: { days: { day: number; count: number }[] }) {
  const max = days.reduce((mx, d) => Math.max(mx, d.count), 0) || 1;
  return (
    <Card title="Nouveaux abonnés par jour (30 j)">
      {days.length === 0 ? (
        <div className="text-xs text-ink-tertiary">Rien sur la période.</div>
      ) : (
        <div className="flex h-24 items-end gap-1" role="img" aria-label="Nouveaux abonnés par jour">
          {days.map((d) => (
            <div
              key={d.day}
              className="flex-1 rounded-t bg-accent"
              style={{ height: `${Math.max(6, (d.count * 100) / max)}%` }}
              title={`${new Date(d.day).toLocaleDateString('fr-FR', { timeZone: 'UTC' })} : ${d.count}`}
            />
          ))}
        </div>
      )}
    </Card>
  );
}

function PeopleTable({
  title, hint, file, rows, empty,
}: { title: string; hint: string; file: string; rows: InsightPerson[]; empty: string }) {
  return (
    <div className="mb-8">
      <div className="mb-2 flex flex-wrap items-end justify-between gap-3">
        <div>
          <SectionTitle>{title}</SectionTitle>
          <p className="-mt-2 text-xs text-ink-tertiary">{hint}</p>
        </div>
        <button
          type="button"
          disabled={rows.length === 0}
          onClick={() => downloadCsv(
            file,
            ['MAC', 'Client', 'Plan', 'Fin', 'Revendeur'],
            rows.map((p) => [p.mac, p.customer, planLabel(p.plan), formatDateTime(p.expires_at), p.reseller]),
          )}
          className="rounded-md border border-white/10 px-3 py-1.5 text-xs hover:border-white/30 disabled:opacity-40"
        >
          Exporter (Excel)
        </button>
      </div>
      <div className="overflow-x-auto rounded-xl border border-white/10">
        <table className="w-full text-left text-sm">
          <thead className="bg-midnight">
            <tr><Th>MAC</Th><Th>Client</Th><Th>Plan</Th><Th>Fin</Th><Th>Revendeur</Th></tr>
          </thead>
          <tbody>
            {rows.map((p) => (
              <tr key={p.mac} className="border-t border-white/5">
                <td className="px-4 py-2.5 font-mono text-xs text-ink-secondary">{p.mac}</td>
                <td className="px-4 py-2.5">{p.customer || '—'}</td>
                <td className="px-4 py-2.5 text-xs">{planLabel(p.plan)}</td>
                <td className="px-4 py-2.5 text-xs text-ink-secondary">{formatDateTime(p.expires_at)}</td>
                <td className="px-4 py-2.5 text-xs text-ink-secondary">{p.reseller || 'Direct'}</td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={5}><EmptyState title={empty} hint="" /></td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
