// =========================================================
//  CallTodayQueue — « À appeler aujourd'hui » (Vague A)
// =========================================================
//  File ops : expire ≤3 j OU online sans abo. Données = GET /devices
//  (filtres déjà côté Worker) — pas de nouvel endpoint. CTA : fiche,
//  WhatsApp, +1 mois. Posée sur Radar + Overview (owner). Un revendeur
//  avec cap `devices` la voit aussi s'il ouvre ces pages (JWT scope).
// =========================================================

import { useEffect, useState } from 'react';
import { activateApi, devicesApi, type Device, ApiError } from '@/lib/api';
import { applyNew } from '@/components/NewBadge';
import { useDeviceSheet } from '@/components/DeviceSheet';
import {
  CopyWhatsAppButton, AboChip, isCallToday, isOnlineUnpaid, licenseFromActivate,
} from '@/components/DeviceOps';
import { toast, rtActionFeedback } from '@/components/Toast';
import { cn } from '@/lib/utils';

export function CallTodayQueue({
  onLogout,
}: {
  onLogout?: () => void;
}) {
  const [items, setItems] = useState<Device[]>([]);
  const [loading, setLoading] = useState(true);
  const sheet = useDeviceSheet();

  useEffect(() => {
    let alive = true;
    Promise.all([
      devicesApi.list(undefined, 'expiring_7d').catch(() => ({ items: [] as Device[] })),
      devicesApi.list(undefined, 'online_unpaid').catch(() => ({ items: [] as Device[] })),
    ])
      .then(([a, b]) => {
        if (!alive) return;
        const map = new Map<string, Device>();
        for (const d of [...(a.items || []), ...(b.items || [])]) {
          if (isCallToday(d)) map.set(d.id, d);
        }
        const list = [...map.values()].sort((x, y) => {
          const ax = x.license?.expires_at ?? 0;
          const ay = y.license?.expires_at ?? 0;
          return ax - ay;
        });
        setItems(list);
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout?.();
      })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [onLogout]);

  return (
    <section
      {...applyNew('call-today', 'mb-5 rounded-2xl border p-4')}
    >
      <div className="mb-2 flex items-baseline justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold tracking-tight">À appeler aujourd'hui</h2>
          <p className="text-[11px] text-ink-tertiary">
            Expire ≤ 3 j, ou en ligne sans abo — fiche, WhatsApp, +1 mois.
          </p>
        </div>
        <span className="rounded-full border border-white/10 px-2 py-0.5 text-[11px] font-bold tabular-nums">
          {loading ? '…' : items.length}
        </span>
      </div>

      {loading && <div className="h-16 animate-pulse rounded-lg bg-white/5" />}
      {!loading && items.length === 0 && (
        <p className="py-3 text-xs text-ink-tertiary">Rien à relancer aujourd'hui. ✨</p>
      )}
      {!loading && items.length > 0 && (
        <div className="max-h-80 space-y-2 overflow-y-auto">
          {items.map((d) => (
            <div
              key={d.id}
              className={cn(
                'flex flex-wrap items-center gap-2 rounded-lg border border-white/5 bg-obsidian/50 px-3 py-2',
                isOnlineUnpaid(d) && 'border-warning/25',
              )}
            >
              <div className="min-w-0 flex-1">
                <button
                  type="button"
                  onClick={() => sheet.open(d.mac, d)}
                  className="font-mono text-xs text-accent hover:underline"
                >
                  {d.mac}
                </button>
                <div className="truncate text-[11px] text-ink-secondary">
                  {d.customer_name || d.label || d.admin_note || '—'}
                </div>
                <AboChip license={d.license} />
                {isOnlineUnpaid(d) && (
                  <span className="ml-1 text-[10px] text-warning">online sans abo</span>
                )}
              </div>
              <div className="flex flex-wrap items-center gap-1.5">
                <button
                  type="button"
                  onClick={() => sheet.open(d.mac, d)}
                  {...applyNew(
                    'call-today-open',
                    'rounded-md border px-2 py-1 text-[11px] font-semibold',
                  )}
                >
                  Fiche
                </button>
                <span {...applyNew('call-today-wa', 'inline-flex')}>
                  <CopyWhatsAppButton
                    mac={d.mac}
                    license={d.license}
                    note={d.admin_note}
                    customerPhone={d.customer_phone}
                    renew
                    compact
                  />
                </span>
                <button
                  type="button"
                  onClick={() => {
                    void activateApi.activate({ mac: d.mac, plan: 'monthly' })
                      .then((res) => {
                        void rtActionFeedback(res.rt);
                        const lic = licenseFromActivate(res);
                        setItems((prev) => prev.map((x) => (
                          x.id === d.id ? { ...x, license: lic } : x
                        )));
                        toast('+1 mois posé.', 'success', { isNew: true });
                      })
                      .catch((e) => {
                        toast(e instanceof ApiError ? e.message : 'Échec +1 mois.', 'error');
                      });
                  }}
                  {...applyNew(
                    'call-today-renew',
                    'rounded-md border px-2 py-1 text-[11px] font-semibold',
                  )}
                >
                  +1 mois
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
