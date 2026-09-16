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
  type DeviceSourceInput, type DeviceScanResult, type MacMigrateResult,
} from '@/lib/api';
import { toast, rtActionFeedback } from '@/components/Toast';
import { applyNew, NewBadge } from '@/components/NewBadge';
import { formatDateTime, formatMacInput } from '@/lib/utils';

export const DEVICE_FILTERS: {
  id: DeviceListFilter;
  label: string;
  warn?: boolean;
  newId?: string;
}[] = [
  { id: 'all', label: 'Tout' },
  { id: 'active', label: 'Actifs' },
  { id: 'expiring_7d', label: 'Expire ≤7j', warn: true, newId: 'filter-expiring-7d' },
  { id: 'expired', label: 'Expirés', warn: true, newId: 'filter-expired' },
  { id: 'online_unpaid', label: 'Online sans abo', warn: true, newId: 'filter-online-unpaid' },
  { id: 'problematic', label: 'MACs problématiques', warn: true, newId: 'filter-problematic' },
  { id: 'no_sub', label: 'Sans abo', newId: 'filter-no-sub' },
  { id: 'frozen', label: 'Gelés', newId: 'filter-frozen' },
  { id: 'banned', label: 'Bannis', newId: 'filter-banned' },
];

export const RENEW_PLANS = [
  { id: 'monthly', label: '+1 mois', newId: 'renew-monthly' },
  { id: 'quarterly', label: '+3 mois', newId: 'renew-quarterly' },
  { id: 'biannual', label: '+6 mois', newId: 'renew-biannual' },
  { id: 'yearly', label: '+1 an', newId: 'renew-yearly' },
] as const;

export const TRIAL_PLANS = [
  { id: 'trial_24h', label: '24h', newId: 'trial-24h' },
  { id: 'trial_48h', label: '48h', newId: 'trial-48h' },
  { id: 'trial_7d', label: '7j', newId: 'trial-7d' },
] as const;

const EMPTY_COUNTS: DeviceListCounts = {
  all: 0, active: 0, expiring_7d: 0, expired: 0, no_sub: 0,
  frozen: 0, banned: 0, online_unpaid: 0, problematic: 0,
};

const HUNT_MS = 24 * 60 * 60 * 1000;
const TRIAL_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

/// Heartbeat récent + pas d'abo live + essai déjà fini (chasse freeloaders).
export function isOnlineUnpaid(d: Device, now = Date.now()): boolean {
  const st = d.block_status || 'active';
  if (st === 'frozen' || st === 'banned') return false;
  const recent = Math.max(d.presence_last_seen || 0, d.last_seen_at || 0) > now - HUNT_MS;
  if (!recent) return false;
  if (isLiveLicense(d.license, now)) return false;
  const trialOk = !d.license && (d.first_seen_at || 0) > now - TRIAL_WINDOW_MS;
  return !trialOk;
}

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
    case 'online_unpaid':
      return isOnlineUnpaid(d, now);
    case 'problematic':
      return isProblematicDevice(d, now);
    default:
      return true;
  }
}

/// Signaux que le Worker attache (`problems`) + filet local si Worker ancien.
export function isProblematicDevice(d: Device, now = Date.now()): boolean {
  if (d.problems && d.problems.length > 0) {
    return d.problems.some((p) => p !== 'superseded');
  }
  return isOnlineUnpaid(d, now);
}

export const PROBLEM_LABELS: Record<string, string> = {
  multi_license: 'Plusieurs licences',
  android_id_dup: 'android_id en double',
  lifetime_masks_active: 'Lifetime inactive masque un abo',
  license_pick: 'Licence lue ≠ jouable (paid=false)',
  online_unpaid: 'En ligne sans abo',
  pending_reassign: 'MAC remplacée, app pas migrée',
  superseded: 'MAC remplacée',
};

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
    if (matchesDeviceFilter(d, 'online_unpaid', now)) c.online_unpaid++;
    if (matchesDeviceFilter(d, 'problematic', now)) c.problematic = (c.problematic || 0) + 1;
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
        const n = counts[f.id] ?? 0;
        const on = value === f.id;
        return (
          <button
            key={f.id}
            type="button"
            onClick={() => onChange(f.id)}
            {...applyNew(
              f.newId,
              'rounded-full border px-2.5 py-1 text-[11px] font-semibold transition ' +
              (on
                ? 'border-accent bg-accent/15 text-accent-bright'
                : f.warn && n > 0
                  ? 'border-warning/30 bg-warning/10 text-warning hover:border-warning/50'
                  : 'border-white/10 bg-white/5 text-ink-secondary hover:border-white/25'),
            )}
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
        { isNew: true },
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
            {...applyNew(p.newId, btn + 'border-accent/30 bg-accent/10 text-accent-bright hover:bg-accent/20')}
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
              {...applyNew(p.newId, btn + 'border-white/10 text-ink-secondary hover:border-white/30')}
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
        toast('Note non persistée : déploie le Worker (api_v1) pour activer ce champ.', 'warning', { isNew: true });
        return;
      }
      const saved = r.admin_note || '';
      setText(saved);
      onSaved(saved);
      toast('Note enregistrée.', 'success', { isNew: true });
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec de la note.', 'error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <NewBadge id="admin-note">
      <div className="mb-1 text-[10px] uppercase tracking-widest">
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
        <span className="text-[10px] opacity-70">
          Enregistré dès que tu quittes le champ
        </span>
        <button
          type="button"
          disabled={busy || text.trim() === (value || '').trim()}
          onClick={() => { void save(); }}
          className="rounded-md border border-white/10 px-2 py-0.5 text-[11px] font-semibold hover:border-white/30 disabled:opacity-40"
        >
          {busy ? '…' : 'Enregistrer'}
        </button>
      </div>
    </NewBadge>
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
      toast('Copié', 'success', { isNew: true });
    } catch {
      toast('Impossible de copier.', 'error');
    }
  }
  return (
    <button
      type="button"
      onClick={() => { void copy(); }}
      title="Copie un message prêt à coller dans WhatsApp"
      {...applyNew(
        'copy-whatsapp',
        'rounded-md border border-emerald-500/30 bg-emerald-500/10 px-2.5 py-1 text-[11px] font-semibold text-emerald-200 hover:bg-emerald-500/20',
      )}
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

export function ProblemsChip({ problems }: { problems?: string[] | null }) {
  if (!problems || problems.length === 0) return null;
  const shown = problems.filter((p) => p !== 'superseded');
  if (!shown.length) return null;
  const title = shown.map((p) => PROBLEM_LABELS[p] || p).join(' · ');
  return (
    <div
      title={title}
      {...applyNew(
        'filter-problematic',
        'mt-1 inline-block max-w-[180px] truncate rounded-full px-2 py-0.5 text-[10px] font-semibold',
      )}
    >
      {shown.length === 1 ? (PROBLEM_LABELS[shown[0]] || shown[0]) : `${shown.length} signaux`}
    </div>
  );
}

/// Changer la MAC (saisie manuelle) — confirmation danger obligatoire.
export function ChangeMacModal({
  device,
  onClose,
  onDone,
}: {
  device: Device;
  onClose: () => void;
  onDone: (r: MacMigrateResult) => void;
}) {
  const [next, setNext] = useState('');
  const [ack, setAck] = useState(false);
  const [busy, setBusy] = useState(false);

  async function go() {
    if (!ack) {
      toast('Coche la confirmation danger.', 'warning', { isNew: true });
      return;
    }
    setBusy(true);
    try {
      const r = await devicesApi.changeMac(device.id, next);
      void rtActionFeedback(r.rt);
      toast(`MAC changée : ${r.old_mac} → ${r.new_mac}`, 'success', { isNew: true });
      onDone(r);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec du changement de MAC.', 'error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div
        className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-1 text-lg font-semibold tracking-tight">Changer la MAC</h2>
        <p className="mb-3 font-mono text-xs text-accent">{device.mac}</p>
        <p className="mb-3 text-sm text-ink-secondary">
          L’ancienne adresse est <strong>invalidée</strong> (bannie, sans android_id)
          pour qu’un freeloader ne la réutilise pas. L’app mobile reçoit
          <code className="mx-1">mac_reassigned</code> et affiche le nouveau
          numéro de référence.
        </p>
        <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
          Nouvelle MAC
        </label>
        <input
          value={next}
          onChange={(e) => setNext(formatMacInput(e.target.value))}
          maxLength={17}
          placeholder="MK:XX:XX:XX:XX:XX"
          className="mb-3 w-full rounded-md border border-white/5 bg-obsidian px-3 py-2 font-mono text-sm outline-none focus:ring-1 focus:ring-accent"
        />
        <label className="mb-4 flex items-start gap-2 text-xs text-ink-secondary">
          <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} className="mt-0.5" />
          Je confirme : l’ancienne MAC sera bannie (anti-freeloader) et l’app
          devra adopter le nouveau numéro.
        </label>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary">Annuler</button>
          <button
            type="button"
            disabled={busy || !ack}
            onClick={() => { void go(); }}
            {...applyNew('change-mac', 'rounded-md px-4 py-2 text-sm font-semibold disabled:opacity-40')}
          >
            {busy ? 'Changement…' : 'Changer la MAC'}
          </button>
        </div>
      </div>
    </div>
  );
}

/// Régénère un MAC propre + option Activer + M3U (geste Lionel).
export function RegenerateMacModal({
  device,
  onClose,
  onDone,
}: {
  device: Device;
  onClose: () => void;
  onDone: (r: MacMigrateResult) => void;
}) {
  const [ack, setAck] = useState(false);
  const [activate, setActivate] = useState(true);
  const [plan, setPlan] = useState('yearly');
  const [m3u, setM3u] = useState('');
  const [busy, setBusy] = useState(false);

  async function go() {
    if (!ack) {
      toast('Coche la confirmation danger.', 'warning', { isNew: true });
      return;
    }
    setBusy(true);
    try {
      const source: DeviceSourceInput | undefined = m3u.trim()
        ? { type: 'm3u', m3u_url: m3u.trim(), label: 'Bouquet' }
        : undefined;
      const r = await devicesApi.regenerateMac(device.id, {
        activate,
        plan,
        source,
      });
      void rtActionFeedback(r.rt);
      const extra = r.activated ? ' + abo activé' : '';
      toast(`Nouveau MAC : ${r.new_mac}${extra}`, 'success', { isNew: true });
      try { await navigator.clipboard.writeText(r.new_mac.replace(/^MK:/, '')); } catch { /* */ }
      onDone(r);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec de la régénération.', 'error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div
        className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-1 text-lg font-semibold tracking-tight">Régénérer la MAC</h2>
        <p className="mb-3 font-mono text-xs text-accent">{device.mac}</p>
        <p className="mb-3 text-sm text-ink-secondary">
          Génère une identité <strong>propre</strong>, y déménage licence / sources / notes,
          invalide l’ancienne (anti-freeloader), et pousse l’app mobile pour
          qu’elle affiche le nouveau numéro de référence.
        </p>
        <label className="mb-2 flex items-center gap-2 text-xs">
          <input type="checkbox" checked={activate} onChange={(e) => setActivate(e.target.checked)} />
          Activer tout de suite
        </label>
        {activate && (
          <div className="mb-3 grid grid-cols-3 gap-1.5">
            {(['monthly', 'yearly', 'lifetime'] as const).map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setPlan(p)}
                className={
                  'rounded-md border px-2 py-1 text-[11px] font-semibold ' +
                  (plan === p ? 'border-accent bg-accent/15 text-accent-bright' : 'border-white/10 text-ink-secondary')
                }
              >
                {PLAN_LABELS[p] || p}
              </button>
            ))}
          </div>
        )}
        <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
          M3U à pousser (facultatif)
        </label>
        <input
          value={m3u}
          onChange={(e) => setM3u(e.target.value)}
          placeholder="http://…/get.php?username=…"
          className="mb-3 w-full rounded-md border border-white/5 bg-obsidian px-3 py-2 text-xs outline-none focus:ring-1 focus:ring-accent"
        />
        <label className="mb-4 flex items-start gap-2 text-xs text-ink-secondary">
          <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} className="mt-0.5" />
          Je confirme : l’ancienne MAC sera bannie. L’app doit montrer le
          NOUVEAU numéro. Copie le numéro après succès.
        </label>
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary">Annuler</button>
          <button
            type="button"
            disabled={busy || !ack}
            onClick={() => { void go(); }}
            {...applyNew('regenerate-mac', 'rounded-md px-4 py-2 text-sm font-semibold disabled:opacity-40')}
          >
            {busy ? 'Régénération…' : 'Régénérer la MAC'}
          </button>
        </div>
      </div>
    </div>
  );
}

/// Bouton « Scanner les erreurs » : le panel lit tout et DIT ce qui cloche.
export function ScanErrorsButton({ mac }: { mac: string }) {
  const [busy, setBusy] = useState(false);
  const [scan, setScan] = useState<DeviceScanResult | null>(null);

  async function go() {
    setBusy(true);
    try {
      const r = await devicesApi.scan(mac);
      setScan(r);
      if (r.verdict === 'ok') toast(r.summary, 'success');
      else toast(r.summary, r.verdict === 'critique' ? 'error' : 'warning');
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Scan impossible.', 'error');
    } finally {
      setBusy(false);
    }
  }

  const tone = scan?.verdict === 'critique'
    ? 'border-red-500/30 bg-red-500/10 text-red-200'
    : scan?.verdict === 'probleme'
      ? 'border-amber-500/30 bg-amber-500/10 text-amber-200'
      : 'border-emerald-500/20 bg-emerald-500/10 text-emerald-200';

  return (
    <div className="rounded-lg border border-sky-400/25 bg-sky-400/[0.05] px-3 py-2.5">
      <div className="flex items-center justify-between gap-2">
        <p className="text-[11px] font-semibold text-sky-200">
          L’app ne marche pas ?
        </p>
        <button
          type="button"
          disabled={busy}
          onClick={() => { void go(); }}
          className="rounded-md bg-sky-500 px-2.5 py-1 text-[11px] font-semibold text-black hover:bg-sky-400 disabled:opacity-40"
        >
          {busy ? 'Scan…' : 'Scanner les erreurs'}
        </button>
      </div>
      {scan && (
        <div className={`mt-2 rounded-md border px-2.5 py-2 text-[11px] ${tone}`}>
          <p className="font-semibold">{scan.summary}</p>
          <ul className="mt-1.5 space-y-1.5">
            {scan.findings.map((f, i) => (
              <li key={i}>
                <span className="font-semibold">{f.title}</span>
                {f.detail ? <span className="block text-[10px] opacity-80">{f.detail}</span> : null}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
