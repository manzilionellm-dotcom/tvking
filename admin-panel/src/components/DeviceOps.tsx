// =========================================================
//  DeviceOps — actions quotidiennes IPTV sur une MAC
// =========================================================
//  Pourquoi un module partagé : la liste /devices ET le tiroir MacLink
//  (n'importe quelle page) doivent proposer les MÊMES gestes — renouveler,
//  essai, noter, copier WhatsApp — sans recopier la logique métier.
//  Toutes les mutations passent par /activate et PATCH /devices déjà
//  existants : on n'invente pas une 2e vérité côté serveur.
// =========================================================

import { useEffect, useState } from 'react';
import {
  activateApi, devicesApi, PLAN_LABELS, ApiError,
  type ActivateResult, type Device, type DeviceLicense,
  type DeviceListCounts, type DeviceListFilter, type DeviceSource,
} from '@/lib/api';
import { toast, rtActionFeedback } from '@/components/Toast';
import { formatDateTime } from '@/lib/utils';

export const DEVICE_FILTERS: {
  id: DeviceListFilter;
  label: string;
  warn?: boolean;
}[] = [
  { id: 'all', label: 'Tout' },
  { id: 'active', label: 'Actifs' },
  { id: 'expiring_7d', label: 'Expire ≤7j', warn: true },
  { id: 'expired', label: 'Expirés', warn: true },
  { id: 'no_sub', label: 'Sans abo' },
  { id: 'frozen', label: 'Gelés' },
  { id: 'banned', label: 'Bannis' },
];

export const RENEW_PLANS = [
  { id: 'monthly', label: '+1 mois' },
  { id: 'quarterly', label: '+3 mois' },
  { id: 'biannual', label: '+6 mois' },
  { id: 'yearly', label: '+1 an' },
] as const;

export const TRIAL_PLANS = [
  { id: 'trial_24h', label: '24h' },
  { id: 'trial_48h', label: '48h' },
  { id: 'trial_7d', label: '7j' },
] as const;

const EMPTY_COUNTS: DeviceListCounts = {
  all: 0, active: 0, expiring_7d: 0, expired: 0, no_sub: 0, frozen: 0, banned: 0,
};

/// Statut licence « live » (même règle que le Worker overview).
export function isLiveLicense(lic: DeviceLicense | null | undefined, now = Date.now()): boolean {
  if (!lic) return false;
  if (lic.status && lic.status !== 'active') return false;
  return lic.expires_at == null || lic.expires_at > now;
}

export function matchesDeviceFilter(
  d: Device,
  filter: DeviceListFilter,
  now = Date.now(),
): boolean {
  if (filter === 'all') return true;
  const st = d.block_status || 'active';
  const lic = d.license ?? null;
  const live = isLiveLicense(lic, now);
  switch (filter) {
    case 'active':
      return live && st === 'active';
    case 'expiring_7d':
      return live && lic?.expires_at != null
        && lic.expires_at <= now + 7 * 86400000;
    case 'expired':
      return !!lic && !live;
    case 'no_sub':
      return !lic;
    case 'frozen':
      return st === 'frozen';
    case 'banned':
      return st === 'banned';
    default:
      return true;
  }
}

export function countDeviceFilters(items: Device[], now = Date.now()): DeviceListCounts {
  const c = { ...EMPTY_COUNTS };
  c.all = items.length;
  for (const d of items) {
    if (matchesDeviceFilter(d, 'active', now)) c.active++;
    if (matchesDeviceFilter(d, 'expiring_7d', now)) c.expiring_7d++;
    if (matchesDeviceFilter(d, 'expired', now)) c.expired++;
    if (matchesDeviceFilter(d, 'no_sub', now)) c.no_sub++;
    if (matchesDeviceFilter(d, 'frozen', now)) c.frozen++;
    if (matchesDeviceFilter(d, 'banned', now)) c.banned++;
  }
  return c;
}

/// Réponse /activate → licence affichable tout de suite (pattern PR #23).
export function licenseFromActivate(res: ActivateResult): DeviceLicense {
  return {
    id: res.license_id,
    status: 'active',
    plan: res.plan,
    expires_at: res.expires_at,
  };
}

export function planLabel(plan: string | null | undefined): string {
  if (!plan) return '—';
  return PLAN_LABELS[plan] || plan;
}

export function expireLabel(lic: DeviceLicense | null | undefined): string {
  if (!lic) return '—';
  if (lic.expires_at == null && isLiveLicense(lic)) return 'À vie';
  if (lic.expires_at == null) return '—';
  return formatDateTime(lic.expires_at);
}

export function buildWhatsAppText(opts: {
  mac: string;
  license?: DeviceLicense | null;
  note?: string | null;
  sources?: DeviceSource[];
}): string {
  const lines = [
    `MAC: ${opts.mac}`,
    `Plan: ${planLabel(opts.license?.plan)}`,
    `Expire: ${expireLabel(opts.license ?? null)}`,
  ];
  const note = (opts.note || '').trim();
  if (note) lines.push(`Note: ${note}`);
  for (const s of opts.sources || []) {
    const nom = s.label || (s.type === 'xtream' ? 'Xtream' : 'M3U');
    if (s.type === 'xtream') {
      if (s.username) {
        lines.push(`Source: ${nom}`);
        lines.push(`User: ${s.username}`);
        if (s.password) lines.push(`Pass: ${s.password}`);
      }
      if (s.server_url) lines.push(`Serveur: ${s.server_url}`);
    } else if (s.m3u_url) {
      lines.push(`M3U: ${s.m3u_url}`);
    }
  }
  return lines.join('\n') + '\n';
}

export function DeviceFilterBar({
  value,
  counts,
  onChange,
}: {
  value: DeviceListFilter;
  counts: DeviceListCounts;
  onChange: (f: DeviceListFilter) => void;
}) {
  return (
    <div className="mb-3 flex flex-wrap gap-1.5">
      {DEVICE_FILTERS.map((f) => {
        const n = counts[f.id];
        const on = value === f.id;
        return (
          <button
            key={f.id}
            type="button"
            onClick={() => onChange(f.id)}
            className={
              'rounded-full border px-2.5 py-1 text-[11px] font-semibold transition ' +
              (on
                ? 'border-accent bg-accent/15 text-accent-bright'
                : f.warn && n > 0
                  ? 'border-warning/30 bg-warning/10 text-warning hover:border-warning/50'
                  : 'border-white/10 bg-white/5 text-ink-secondary hover:border-white/25')
            }
          >
            {f.label}
            <span className={'ml-1 tabular-nums ' + (on ? 'text-accent-bright' : 'text-ink-tertiary')}>
              {n}
            </span>
          </button>
        );
      })}
    </div>
  );
}

/// +1 mois / +3 / +6 / +1 an (+ essais) → POST /activate existant.
export function QuickRenewBar({
  mac,
  compact,
  showTrials = true,
  onDone,
}: {
  mac: string;
  compact?: boolean;
  showTrials?: boolean;
  onDone: (res: ActivateResult) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);

  async function go(plan: string, label: string) {
    setBusy(plan);
    try {
      const res = await activateApi.activate({ mac, plan });
      void rtActionFeedback(res.rt);
      toast(
        res.renewed
          ? `Abonnement prolongé (${label}).`
          : `Abonnement activé (${label}).`,
        'success',
      );
      onDone(res);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec du renouvellement.', 'error');
    } finally {
      setBusy(null);
    }
  }

  const btn =
    'rounded-md border px-2 py-1 text-[11px] font-semibold disabled:opacity-40 ';
  return (
    <div className={compact ? 'flex flex-wrap gap-1' : 'space-y-1.5'}>
      <div className="flex flex-wrap gap-1">
        {!compact && (
          <span className="mr-0.5 self-center text-[10px] uppercase tracking-widest text-ink-tertiary">
            Renouveler
          </span>
        )}
        {RENEW_PLANS.map((p) => (
          <button
            key={p.id}
            type="button"
            disabled={!!busy}
            onClick={() => void go(p.id, p.label)}
            title={`Prolonger de ${p.label.replace(/^\+/, '')} (même logique qu'Activer)`}
            className={btn + 'border-accent/30 bg-accent/10 text-accent-bright hover:bg-accent/20'}
          >
            {busy === p.id ? '…' : p.label}
          </button>
        ))}
      </div>
      {showTrials && (
        <div className="flex flex-wrap gap-1">
          {!compact && (
            <span className="mr-0.5 self-center text-[10px] uppercase tracking-widest text-ink-tertiary">
              Essai
            </span>
          )}
          {TRIAL_PLANS.map((p) => (
            <button
              key={p.id}
              type="button"
              disabled={!!busy}
              onClick={() => void go(p.id, PLAN_LABELS[p.id] || p.label)}
              title={`Poser un essai ${p.label} (0 crédit, plans trial_* déjà côté Worker)`}
              className={btn + 'border-white/10 text-ink-secondary hover:border-white/30'}
            >
              {busy === p.id ? '…' : (compact ? p.label : `Essai ${p.label}`)}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export function AdminNoteField({
  deviceId,
  value,
  blockStatus,
  onSaved,
}: {
  deviceId: string;
  value: string;
  blockStatus?: 'active' | 'frozen' | 'banned' | null;
  onSaved: (note: string) => void;
}) {
  const [text, setText] = useState(value);
  const [busy, setBusy] = useState(false);
  useEffect(() => { setText(value); }, [value]);

  async function save() {
    const next = text.trim();
    if (next === (value || '').trim()) return;
    setBusy(true);
    try {
      const st = blockStatus === 'frozen' || blockStatus === 'banned' ? blockStatus : 'active';
      const r = await devicesApi.setNote(deviceId, next, st);
      // Worker pas encore déployé : le PATCH n'a pas `admin_note` dans
      // la réponse — on ne ment pas avec « enregistrée ».
      if (!('admin_note' in r)) {
        toast('Note non persistée : déploie le Worker (api_v1) pour activer ce champ.', 'warning');
        return;
      }
      const saved = r.admin_note || '';
      setText(saved);
      onSaved(saved);
      toast('Note enregistrée.', 'success');
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec de la note.', 'error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="mb-1 text-[10px] uppercase tracking-widest text-ink-tertiary">
        Note client
      </div>
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        onBlur={() => { void save(); }}
        placeholder="Nom WhatsApp, téléphone, remarque…"
        rows={2}
        maxLength={2000}
        className="w-full resize-none rounded-md border border-white/10 bg-obsidian px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
      />
      <div className="mt-1 flex items-center justify-between">
        <span className="text-[10px] text-ink-tertiary">
          Enregistré dès que tu quittes le champ
        </span>
        <button
          type="button"
          disabled={busy || text.trim() === (value || '').trim()}
          onClick={() => { void save(); }}
          className="rounded-md border border-white/10 px-2 py-0.5 text-[11px] font-semibold text-ink-secondary hover:border-white/30 disabled:opacity-40"
        >
          {busy ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

export function CopyWhatsAppButton({
  mac,
  license,
  note,
  sources,
}: {
  mac: string;
  license?: DeviceLicense | null;
  note?: string | null;
  sources?: DeviceSource[];
}) {
  async function copy() {
    const text = buildWhatsAppText({ mac, license, note, sources });
    try {
      await navigator.clipboard.writeText(text);
      toast('Copié', 'success');
    } catch {
      toast('Impossible de copier.', 'error');
    }
  }
  return (
    <button
      type="button"
      onClick={() => { void copy(); }}
      title="Copie un message prêt à coller dans WhatsApp"
      className="rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2.5 py-1 text-[11px] font-semibold text-emerald-200 hover:bg-emerald-500/20"
    >
      Copier WhatsApp
    </button>
  );
}

export function AboChip({ license }: { license?: DeviceLicense | null }) {
  if (!license) {
    return <span className="text-[11px] text-ink-tertiary">Sans abo</span>;
  }
  const live = isLiveLicense(license);
  const plan = planLabel(license.plan);
  let extra = '';
  if (license.expires_at == null && live) extra = ' · à vie';
  else if (license.expires_at != null) {
    const days = Math.ceil((license.expires_at - Date.now()) / 86400000);
    extra = days >= 0 ? ` · ${days} j` : ` · exp. ${-days} j`;
  }
  return (
    <span className={'text-[11px] font-medium ' + (live ? 'text-success' : 'text-warning')}>
      {plan}{extra}
    </span>
  );
}
