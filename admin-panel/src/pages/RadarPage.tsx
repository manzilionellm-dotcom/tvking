import { useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { MacLink } from '@/components/MacLink';
import { toast, rtActionFeedback } from '@/components/Toast';
import { licensesApi, devicesApi, type License, ApiError } from '@/lib/api';

// =========================================================
//  RadarPage — « Radar d'expiration »
// =========================================================
//  SUPER-POUVOIR : le panel surveille TOUT le parc à ta place et fait
//  remonter, triés par urgence, les abonnements qui expirent bientôt
//  (ou déjà expirés). Pour chacun, deux gestes en 1 clic :
//    • Renouveler (1 an / à vie) — prolonge la licence + push temps réel.
//    • Prévenir — dépose un mot sur l'écran du client (« ton abo expire »).
//
//  Aucune donnée nouvelle côté serveur : on lit `GET /api/v1/licenses`
//  (déjà exposé) et on réutilise `renew` + `devices/:mac/message`. Zéro
//  risque pour l'app / la lecture. Rafraîchi toutes les 60 s.
// =========================================================

const DAY = 86_400_000;

// Fenêtres de veille proposées (jours). « Expirés inclus » toujours.
const WINDOWS = [3, 7, 14, 30] as const;

type Row = {
  lic: License;
  mac: string;
  daysLeft: number; // < 0 = déjà expiré (nb de jours de retard = -daysLeft)
};

function fmtDate(ts: number | null): string {
  if (!ts) return '—';
  try {
    return new Date(ts).toLocaleDateString('fr-FR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
    });
  } catch {
    return '—';
  }
}

/// Libellé humain d'un plan (aligné sur les offres actuelles).
function planLabel(plan: string | null): string {
  switch (plan) {
    case 'lifetime':
      return 'À vie';
    case '1y':
    case 'yearly':
      return '1 an';
    case '6m':
      return '6 mois';
    case '3m':
      return '3 mois';
    case '1m':
    case 'monthly':
      return '1 mois';
    default:
      return plan && plan.startsWith('trial') ? 'Essai' : plan || '—';
  }
}

export function RadarPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<License[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [win, setWin] = useState<number>(7);
  const [busy, setBusy] = useState<string | null>(null); // id licence en cours

  function load() {
    licensesApi
      .list()
      .then((r) => {
        setItems(r.items);
        setErr(null);
      })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) {
          onLogout();
          return;
        }
        setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => setLoading(false));
  }

  useEffect(() => {
    load();
    const t = setInterval(load, 60_000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Lignes = licences AVEC échéance (pas « à vie », pas essai infini),
  // dont l'échéance tombe dans la fenêtre OU est déjà passée. Triées par
  // urgence (les plus en retard / les plus proches d'abord).
  const rows: Row[] = useMemo(() => {
    if (!items) return [];
    const now = Date.now();
    const out: Row[] = [];
    for (const lic of items) {
      if (lic.expires_at == null) continue; // à vie → jamais concerné
      if (lic.plan === 'lifetime') continue;
      const daysLeft = Math.ceil((lic.expires_at - now) / DAY);
      if (daysLeft > win) continue; // encore loin → pas sur le radar
      out.push({ lic, mac: lic.device_mac || '', daysLeft });
    }
    out.sort((a, b) => a.daysLeft - b.daysLeft);
    return out;
  }, [items, win]);

  const expiredCount = rows.filter((r) => r.daysLeft < 0).length;
  const todayCount = rows.filter((r) => r.daysLeft >= 0 && r.daysLeft <= 1).length;

  async function renew(lic: License, plan: '1y' | 'lifetime') {
    const who = lic.customer_name || lic.device_mac || lic.id;
    const label = plan === 'lifetime' ? 'À VIE' : '1 AN';
    if (
      !window.confirm(
        `Renouveler l'abonnement de ${who} pour ${label} ?\n\n` +
          `La nouvelle échéance part de maintenant. L'appareil est prévenu en temps réel.`,
      )
    )
      return;
    setBusy(lic.id);
    try {
      const r = await licensesApi.renew(lic.id, plan);
      void rtActionFeedback(r.rt);
      toast(
        plan === 'lifetime'
          ? `✅ ${who} passé à vie.`
          : `✅ ${who} renouvelé — expire le ${fmtDate(r.expires_at)}.`,
        'success',
      );
      load();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Renouvellement impossible.', 'error');
    } finally {
      setBusy(null);
    }
  }

  async function warn(row: Row) {
    if (!row.mac) {
      toast('Aucune MAC pour prévenir ce client.', 'warning');
      return;
    }
    const late = row.daysLeft < 0;
    const body = late
      ? 'Votre abonnement a expiré. Contactez-nous pour le réactiver et ne rien manquer.'
      : `Votre abonnement se termine dans ${row.daysLeft} jour${row.daysLeft > 1 ? 's' : ''}. Pensez à le renouveler pour continuer sans coupure.`;
    setBusy(row.lic.id);
    try {
      await devicesApi.sendMessage(row.mac, {
        title: late ? 'Abonnement expiré' : 'Abonnement bientôt terminé',
        body,
        kind: late ? 'warning' : 'info',
        durationSec: 60,
      });
      toast(`✉️ Message envoyé à ${row.lic.customer_name || row.mac}.`, 'success');
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Envoi impossible.', 'error');
    } finally {
      setBusy(null);
    }
  }

  // Pastille d'urgence (couleur = temps restant).
  function urgencyBadge(daysLeft: number) {
    if (daysLeft < 0)
      return (
        <span className="rounded-md bg-red-500/15 px-2 py-0.5 text-xs font-semibold text-red-300 ring-1 ring-red-500/30">
          Expiré · {-daysLeft} j
        </span>
      );
    if (daysLeft <= 1)
      return (
        <span className="rounded-md bg-red-500/15 px-2 py-0.5 text-xs font-semibold text-red-300 ring-1 ring-red-500/30">
          {daysLeft === 0 ? "Aujourd'hui" : 'Demain'}
        </span>
      );
    if (daysLeft <= 3)
      return (
        <span className="rounded-md bg-amber-500/15 px-2 py-0.5 text-xs font-semibold text-amber-300 ring-1 ring-amber-500/30">
          {daysLeft} j
        </span>
      );
    return (
      <span className="rounded-md bg-white/5 px-2 py-0.5 text-xs font-semibold text-ink-secondary ring-1 ring-white/10">
        {daysLeft} j
      </span>
    );
  }

  return (
    <AppLayout
      title="Radar d'expiration"
      subtitle="Les abonnements qui expirent bientôt — renouvelle ou préviens en 1 clic. Le panel veille à ta place."
      onLogout={onLogout}
      actions={
        <div className="flex items-center gap-1.5">
          {WINDOWS.map((w) => (
            <button
              key={w}
              type="button"
              onClick={() => setWin(w)}
              className={
                'rounded-md px-2.5 py-1 text-xs font-semibold transition ' +
                (win === w
                  ? 'bg-accent/20 text-accent-bright ring-1 ring-accent/40'
                  : 'bg-white/5 text-ink-secondary hover:bg-white/10')
              }
              title={`Voir ce qui expire d'ici ${w} jours`}
            >
              ≤ {w} j
            </button>
          ))}
        </div>
      }
    >
      {/* Bandeau de synthèse */}
      <div className="mb-4 grid grid-cols-3 gap-3">
        <div className="rounded-xl border border-white/5 bg-obsidian-light px-4 py-3">
          <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">
            Sur le radar
          </div>
          <div className="text-2xl font-semibold text-ink-primary">{rows.length}</div>
        </div>
        <div className="rounded-xl border border-red-500/20 bg-red-500/[0.04] px-4 py-3">
          <div className="text-[10px] uppercase tracking-widest text-red-300/70">
            Déjà expirés
          </div>
          <div className="text-2xl font-semibold text-red-300">{expiredCount}</div>
        </div>
        <div className="rounded-xl border border-amber-500/20 bg-amber-500/[0.04] px-4 py-3">
          <div className="text-[10px] uppercase tracking-widest text-amber-300/70">
            ≤ 24 h
          </div>
          <div className="text-2xl font-semibold text-amber-300">{todayCount}</div>
        </div>
      </div>

      {err && (
        <div className="mb-4 rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-2 text-sm text-red-300">
          {err}
        </div>
      )}

      {loading && !items ? (
        <div className="py-16 text-center text-sm text-ink-tertiary">Chargement…</div>
      ) : rows.length === 0 ? (
        <div className="rounded-xl border border-white/5 bg-obsidian-light py-16 text-center">
          <div className="text-sm font-medium text-ink-secondary">
            Rien à l'horizon ✨
          </div>
          <div className="mt-1 text-xs text-ink-tertiary">
            Aucun abonnement n'expire d'ici {win} jours.
          </div>
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-white/5">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-white/5 bg-obsidian-light text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
                <th className="px-4 py-2.5 font-semibold">Échéance</th>
                <th className="px-4 py-2.5 font-semibold">Client</th>
                <th className="px-4 py-2.5 font-semibold">Appareil</th>
                <th className="px-4 py-2.5 font-semibold">Offre</th>
                <th className="px-4 py-2.5 font-semibold">Expire le</th>
                <th className="px-4 py-2.5 text-right font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => {
                const b = busy === row.lic.id;
                return (
                  <tr
                    key={row.lic.id}
                    className="border-b border-white/5 last:border-0 hover:bg-white/[0.02]"
                  >
                    <td className="px-4 py-2.5">{urgencyBadge(row.daysLeft)}</td>
                    <td className="px-4 py-2.5 text-ink-primary">
                      {row.lic.customer_name || (
                        <span className="text-ink-tertiary">—</span>
                      )}
                    </td>
                    <td className="px-4 py-2.5">
                      {row.mac ? (
                        <MacLink mac={row.mac} />
                      ) : (
                        <span className="text-ink-tertiary">—</span>
                      )}
                    </td>
                    <td className="px-4 py-2.5 text-ink-secondary">
                      {planLabel(row.lic.plan)}
                    </td>
                    <td className="px-4 py-2.5 text-ink-secondary">
                      {fmtDate(row.lic.expires_at)}
                    </td>
                    <td className="px-4 py-2.5">
                      <div className="flex flex-wrap justify-end gap-1.5">
                        <button
                          type="button"
                          disabled={b}
                          onClick={() => renew(row.lic, '1y')}
                          className="rounded-lg border border-emerald-400/40 bg-emerald-400/10 px-2.5 py-1.5 text-xs font-semibold text-emerald-200 transition hover:bg-emerald-400/20 disabled:opacity-50"
                          title="Prolonger d'un an à partir de maintenant"
                        >
                          {b ? '…' : '↻ 1 an'}
                        </button>
                        <button
                          type="button"
                          disabled={b}
                          onClick={() => renew(row.lic, 'lifetime')}
                          className="rounded-lg border border-sky-400/40 bg-sky-400/10 px-2.5 py-1.5 text-xs font-semibold text-sky-200 transition hover:bg-sky-400/20 disabled:opacity-50"
                          title="Passer cet abonnement à vie"
                        >
                          ∞ À vie
                        </button>
                        <button
                          type="button"
                          disabled={b || !row.mac}
                          onClick={() => warn(row)}
                          className="rounded-lg border border-white/10 bg-white/5 px-2.5 py-1.5 text-xs font-semibold text-ink-secondary transition hover:bg-white/10 disabled:opacity-40"
                          title="Déposer un rappel sur l'écran du client"
                        >
                          ✉️ Prévenir
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </AppLayout>
  );
}
