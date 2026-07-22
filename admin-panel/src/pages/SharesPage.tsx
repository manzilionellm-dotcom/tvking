import { useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { MacLink } from '@/components/MacLink';
import { invitesApi, ApiError, type InviteRow } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

// =========================================================
//  SharesPage — « Partages & prêts » : le ledger anti-vol
// =========================================================
//  L'owner voit TOUTES les transactions entre clients : qui a invité qui,
//  en mode « ensemble » (5 h) ou « prêt » (24/48 h), la durée offerte, la
//  date et l'échéance du pass, et l'état. Objectif explicite : « pour qu'on
//  ne me vole pas » — repérer un abonné qui distribue des accès en masse.
//
//  100 % lecture seule : branché sur GET /api/v1/invites (handleInvitesList),
//  qui expose déjà la table app_invites avec cloisonnement revendeur.
// =========================================================

/// Libellé + couleur du MODE de partage.
function modeBadge(row: InviteRow): { label: string; cls: string } {
  const m = (row.mode || 'together').toLowerCase();
  if (m === 'lend') {
    return { label: 'Prêt', cls: 'bg-amber-500/15 text-amber-300 ring-amber-500/30' };
  }
  if (m === 'test') {
    return { label: 'Essai', cls: 'bg-sky-500/15 text-sky-300 ring-sky-500/30' };
  }
  return { label: 'Ensemble', cls: 'bg-accent/15 text-accent-bright ring-accent/30' };
}

/// État de la transaction (déduit des dates), avec couleur.
function statusOf(row: InviteRow, now: number): { label: string; cls: string } {
  const redeemed = !!row.redeemed_at;
  const guestUntil = Number(row.guest_until || 0);
  if (redeemed) {
    if (guestUntil > now) {
      return { label: 'Actif', cls: 'text-emerald-300' };
    }
    return { label: 'Terminé', cls: 'text-ink-tertiary' };
  }
  // Pas encore activé : code en attente ou expiré.
  if (Number(row.expires_at) > now) {
    return { label: 'Code en attente', cls: 'text-ink-secondary' };
  }
  return { label: 'Code expiré', cls: 'text-ink-tertiary' };
}

/// Durée offerte, lisible.
function hoursLabel(h: number | null | undefined): string {
  const n = Number(h || 0);
  if (!n) return '—';
  return `${n} h`;
}

/// Temps restant du pass invité, ou vide.
function remaining(guestUntil: number | null | undefined, now: number): string {
  const u = Number(guestUntil || 0);
  if (u <= now) return '';
  const min = Math.floor((u - now) / 60000);
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h > 0 ? `${h} h ${String(m).padStart(2, '0')}` : `${m} min`;
}

export function SharesPage({ onLogout }: { onLogout: () => void }) {
  const [rows, setRows] = useState<InviteRow[]>([]);
  const [q, setQ] = useState('');
  const [busy, setBusy] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const now = Date.now();

  async function load(query: string) {
    setBusy(true);
    setErr(null);
    try {
      const r = await invitesApi.list(query.trim() || undefined);
      setRows(r.items || []);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Chargement impossible.');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    load('');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // KPI : total, actifs, prêts, en attente.
  const kpi = useMemo(() => {
    let active = 0;
    let lend = 0;
    let pending = 0;
    for (const r of rows) {
      const redeemed = !!r.redeemed_at;
      const guestUntil = Number(r.guest_until || 0);
      if (redeemed && guestUntil > now) active++;
      if ((r.mode || '').toLowerCase() === 'lend') lend++;
      if (!redeemed && Number(r.expires_at) > now) pending++;
    }
    return { total: rows.length, active, lend, pending };
  }, [rows, now]);

  // ANTI-VOL : un émetteur qui a invité BEAUCOUP de monde ressort en tête.
  const topIssuers = useMemo(() => {
    const byIssuer = new Map<string, number>();
    for (const r of rows) {
      if (!r.redeemed_at) continue; // ne compte que les partages CONSOMMÉS
      const k = r.issuer_mac;
      byIssuer.set(k, (byIssuer.get(k) || 0) + 1);
    }
    return [...byIssuer.entries()]
      .filter(([, n]) => n >= 3)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5);
  }, [rows]);

  return (
    <AppLayout
      title="Partages & prêts"
      subtitle="Qui partage ses chaînes avec qui — et pour combien de temps. Surveille les abus."
      onLogout={onLogout}
      actions={
        <form
          onSubmit={(e) => { e.preventDefault(); load(q); }}
          className="flex items-center gap-2"
        >
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Code, MAC émetteur ou invité…"
            className="w-56 rounded-md border border-white/5 bg-slate px-3 py-1.5 text-sm font-mono outline-none focus:ring-1 focus:ring-accent"
          />
          <button
            type="submit"
            className="rounded-md bg-accent px-3 py-1.5 text-sm font-semibold text-black transition hover:bg-accent-bright"
          >
            Chercher
          </button>
        </form>
      }
    >
      <div className="space-y-5">
        {/* ===== KPIs ===== */}
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Kpi label="Transactions" value={kpi.total} />
          <Kpi label="Actives" value={kpi.active} accent />
          <Kpi label="Prêts (24/48 h)" value={kpi.lend} />
          <Kpi label="Codes en attente" value={kpi.pending} />
        </div>

        {/* ===== Alerte anti-vol : gros partageurs ===== */}
        {topIssuers.length > 0 && (
          <div className="rounded-xl border border-amber-500/25 bg-amber-500/5 p-4">
            <div className="mb-2 text-[11px] font-semibold uppercase tracking-widest text-amber-300">
              À surveiller — abonnés qui partagent beaucoup
            </div>
            <div className="flex flex-wrap gap-2">
              {topIssuers.map(([mac, n]) => (
                <div
                  key={mac}
                  className="flex items-center gap-2 rounded-md border border-white/5 bg-midnight px-2.5 py-1.5 text-xs"
                >
                  <MacLink mac={mac} />
                  <span className="rounded bg-amber-500/20 px-1.5 py-0.5 font-semibold text-amber-300">
                    {n} invités
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {err}
          </div>
        )}

        {/* ===== Table ===== */}
        <div className="overflow-x-auto rounded-xl border border-white/5 bg-midnight">
          <table className="w-full min-w-[820px] text-sm">
            <thead>
              <tr className="border-b border-white/5 text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
                <th className="px-4 py-3 font-medium">Émetteur (abonné)</th>
                <th className="px-4 py-3 font-medium">Invité</th>
                <th className="px-4 py-3 font-medium">Mode</th>
                <th className="px-4 py-3 font-medium">Durée</th>
                <th className="px-4 py-3 font-medium">Créé</th>
                <th className="px-4 py-3 font-medium">Reste</th>
                <th className="px-4 py-3 font-medium">Statut</th>
                <th className="px-4 py-3 font-medium">Code</th>
              </tr>
            </thead>
            <tbody>
              {busy && rows.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-4 py-8 text-center text-ink-tertiary">
                    Chargement…
                  </td>
                </tr>
              )}
              {!busy && rows.length === 0 && (
                <tr>
                  <td colSpan={8} className="px-4 py-8 text-center text-ink-tertiary">
                    Aucun partage pour l'instant.
                  </td>
                </tr>
              )}
              {rows.map((r) => {
                const badge = modeBadge(r);
                const st = statusOf(r, now);
                const rest = remaining(r.guest_until, now);
                let channelName: string | null = null;
                if (r.channel_json) {
                  try { channelName = JSON.parse(r.channel_json)?.name || null; } catch { /* ignore */ }
                }
                return (
                  <tr key={r.code} className="border-b border-white/[0.03] last:border-0 hover:bg-white/[0.02]">
                    <td className="px-4 py-3">
                      <MacLink mac={r.issuer_mac} />
                      {r.issuer_name && (
                        <div className="text-[11px] text-ink-tertiary">{r.issuer_name}</div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {r.redeemer_mac ? (
                        <MacLink mac={r.redeemer_mac} />
                      ) : (
                        <span className="text-ink-tertiary">— en attente —</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`rounded px-2 py-0.5 text-[11px] font-semibold ring-1 ${badge.cls}`}>
                        {badge.label}
                      </span>
                      {channelName && (
                        <div className="mt-0.5 max-w-[160px] truncate text-[11px] text-ink-tertiary" title={channelName}>
                          {channelName}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-ink-secondary">{hoursLabel(r.hours)}</td>
                    <td className="px-4 py-3 text-[12px] text-ink-tertiary">
                      {formatDateTime(r.created_at)}
                    </td>
                    <td className="px-4 py-3 text-[12px] text-ink-secondary">{rest || '—'}</td>
                    <td className={`px-4 py-3 text-[12px] font-medium ${st.cls}`}>{st.label}</td>
                    <td className="px-4 py-3 font-mono text-[12px] text-ink-tertiary">{r.code}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </AppLayout>
  );
}

function Kpi({ label, value, accent }: { label: string; value: number; accent?: boolean }) {
  return (
    <div className="rounded-xl border border-white/5 bg-midnight p-4">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</div>
      <div className={`mt-1 text-2xl font-semibold ${accent ? 'text-accent-bright' : 'text-ink-primary'}`}>
        {value}
      </div>
    </div>
  );
}
