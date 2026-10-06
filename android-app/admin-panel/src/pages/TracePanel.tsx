// =========================================================
//  TracePanel.tsx — Chronologie client + latence mesurée (boîte noire)
// =========================================================
//  Une recherche (MAC, e-mail client, id client, id appareil ou trace)
//  reconstruit : action du panel → ordre créé → publié → box a reçu →
//  appliqué / échec, et les révisions de listes. La latence affichée est
//  celle MESURÉE par le Worker (p50 / p95 / p99) ; « non mesuré » sinon.
// =========================================================
import { FormEvent, useState } from 'react';
import { Alert } from '@/components/ui';
import {
  ApiError, getCurrentUser, isOwnerRole, traceApi,
  type LatencyResult, type TimelineResult,
} from '@/lib/api';
import { eventLabel, eventTone, formatMs, OP_LABELS, SEGMENT_LABELS } from '@/lib/timeline';
import { formatDateTime } from '@/lib/utils';

export function TracePanel({ initialQuery = '' }: { initialQuery?: string }) {
  const [q, setQ] = useState(initialQuery);
  const [tl, setTl] = useState<TimelineResult | null>(null);
  const [lat, setLat] = useState<LatencyResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const owner = isOwnerRole(getCurrentUser()?.role);

  async function search(e: FormEvent) {
    e.preventDefault();
    if (!q.trim()) return;
    setBusy(true);
    setErr(null);
    try {
      setTl(await traceApi.timeline(q.trim()));
    } catch (e2) {
      setErr(e2 instanceof ApiError ? e2.message : 'Recherche impossible.');
    } finally {
      setBusy(false);
    }
  }

  async function loadLatency() {
    setErr(null);
    try {
      setLat(await traceApi.latency(24));
    } catch (e2) {
      setErr(e2 instanceof ApiError ? e2.message : 'Latence illisible.');
    }
  }

  const toneCls = { bad: 'text-red-400', warn: 'text-amber-300', ok: 'text-ink-primary' } as const;

  return (
    <section className="mt-6 space-y-4 rounded-xl border border-white/10 bg-midnight p-4 sm:p-6">
      <h2 className="text-base font-semibold">Chronologie : de l’action du panel jusqu’à la box</h2>
      <form onSubmit={search} className="flex flex-col gap-2 sm:flex-row">
        <input
          aria-label="Recherche chronologie"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="MAC, e-mail client, id client, id appareil ou trace"
          className="min-w-0 flex-1 rounded-md border border-white/10 bg-slate px-3 py-2.5 text-sm outline-none focus:border-accent/60"
        />
        <button type="submit" disabled={busy} className="rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-obsidian disabled:opacity-50">
          {busy ? 'Recherche…' : 'Reconstruire'}
        </button>
      </form>
      {err && <Alert>{err}</Alert>}
      {tl && (
        <div className="space-y-3">
          <p className="text-xs text-ink-tertiary">
            {tl.devices.length} appareil(s), {tl.events.length} événement(s) sur {tl.days} jours. Heures serveur.
          </p>
          <ol className="space-y-1.5">
            {tl.events.map((ev, i) => (
              <li key={`${ev.type}-${ev.at}-${i}`} className="rounded-lg border border-white/5 bg-obsidian px-3 py-2 text-sm">
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <span className="font-mono text-xs text-ink-tertiary">{formatDateTime(ev.at)}</span>
                  <span className={toneCls[eventTone(ev.type)]}>{eventLabel(ev.type)}</span>
                  {ev.config_rev != null && <span className="text-xs text-ink-secondary">rév. {ev.config_rev}</span>}
                  {ev.rev != null && <span className="text-xs text-ink-secondary">rév. {ev.rev}</span>}
                  {ev.result && <span className="text-xs text-ink-secondary">{ev.result}</span>}
                  {ev.late_ack && <span className="text-xs text-amber-300">accusé tardif</span>}
                </div>
                {ev.error_message && <p className="mt-1 break-words text-xs text-red-300">{ev.error_message}</p>}
                {ev.trace_id && <p className="mt-0.5 break-all font-mono text-[11px] text-ink-tertiary">trace {ev.trace_id}</p>}
              </li>
            ))}
          </ol>
          {tl.box_journals.map((j) => (
            <details key={j.mac} className="rounded-lg border border-white/5 bg-obsidian px-3 py-2 text-xs">
              <summary className="cursor-pointer text-ink-secondary">Journal de la box {j.mac} ({j.clock})</summary>
              <pre className="mt-2 max-h-72 overflow-auto whitespace-pre-wrap break-words font-mono">
                {j.lines.map((l) => (l.trace_id ? `▶ ${l.line}` : l.line)).join('\n')}
              </pre>
            </details>
          ))}
        </div>
      )}
      {owner && (
        <div className="space-y-2 border-t border-white/10 pt-4">
          <div className="flex items-center justify-between gap-2">
            <h3 className="text-sm font-semibold">Latence mesurée (24 h, production)</h3>
            <button type="button" onClick={loadLatency} className="rounded-md border border-white/15 px-3 py-1.5 text-xs">Lire</button>
          </div>
          {lat && Object.keys(lat.ops).length === 0 && (
            <p className="text-xs text-ink-secondary">Aucune mesure sur la période : rien à afficher.</p>
          )}
          {lat && Object.entries(lat.ops).map(([op, o]) => (
            <div key={op} className="rounded-lg border border-white/5 bg-obsidian p-3 text-xs">
              <p className="mb-1 font-semibold text-ink-primary">{OP_LABELS[op] || op} · {o.orders} ordre(s)</p>
              <ul className="space-y-0.5">
                {Object.entries(o.segments).map(([seg, v]) => (
                  <li key={seg} className="flex flex-wrap justify-between gap-2">
                    <span className="text-ink-secondary">{SEGMENT_LABELS[seg] || seg}</span>
                    <span className="font-mono">
                      {v.n ? `p50 ${formatMs(v.p50)} · p95 ${formatMs(v.p95)} · p99 ${formatMs(v.p99)} · n=${v.n}` : 'non mesuré'}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
          {lat && <p className="text-[11px] text-ink-tertiary">{lat.clock_note}</p>}
        </div>
      )}
    </section>
  );
}
