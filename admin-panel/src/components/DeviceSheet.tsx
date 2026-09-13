// =========================================================
//  DeviceSheet — UNE fiche appareil 360° (Vague A cockpit)
// =========================================================
//  Pourquoi un seul composant : DevicesPage (modal) et MacLink (tiroir)
//  avaient divergé. Lionel ouvre une MAC depuis la liste, le Radar, le
//  Cmd+K ou n'importe quelle page — c'est TOUJOURS la même fiche :
//  abo, présence, QuickRenew, note, M-Trio, VersionCard, clone,
//  inbox + live message / force sync, Changer / Régénérer MAC,
//  liens Activer / Transférer.
//
//  Ouverture : useDeviceSheet().open(mac) — le Provider vit dans
//  AppLayout (partout sauf login). Caps revendeur inchangées : les
//  boutons se masquent, le JWT reste la vérité côté Worker.
// =========================================================

import {
  createContext, useCallback, useContext, useEffect, useMemo, useState,
  type ReactNode,
} from 'react';
import { useNavigate } from 'react-router-dom';
import {
  devicesApi, sourcesApi, activateApi, getCurrentUser, userCan, flagEmoji,
  PLAN_LABELS, ApiError,
  type Device, type DeviceOverview, type DeviceSource, type DeviceSourceInput,
  type DeviceLocalSource, type DeviceLicense, type DevicePresence,
  type DeviceVersionStatus, type DeviceMessage, type ActivateResult,
  type MacMigrateResult,
} from '@/lib/api';
import { useLiveDevices, useRtEvent, sendCmd, waitForAck, type ChangedEvent } from '@/lib/realtime';
import { toast, rtActionFeedback } from '@/components/Toast';
import { applyNew } from '@/components/NewBadge';
import { formatDateTime, cn, formatMacInput } from '@/lib/utils';
import {
  QuickRenewBar, AdminNoteField, CopyWhatsAppButton,
  ChangeMacModal, RegenerateMacModal, licenseFromActivate,
} from '@/components/DeviceOps';

type SheetState = { mac: string; seed?: Device } | null;

type SheetCtx = {
  open: (mac: string, seed?: Device) => void;
  close: () => void;
};

const DeviceSheetCtx = createContext<SheetCtx | null>(null);

export function useDeviceSheet(): SheetCtx {
  const ctx = useContext(DeviceSheetCtx);
  if (!ctx) {
    // Hors AppLayout (ne devrait pas arriver) : no-op plutôt qu'un crash.
    return { open: () => {}, close: () => {} };
  }
  return ctx;
}

export function DeviceSheetProvider({
  children,
  onChanged,
}: {
  children: ReactNode;
  onChanged?: () => void;
}) {
  const [sheet, setSheet] = useState<SheetState>(null);
  const open = useCallback((mac: string, seed?: Device) => {
    setSheet({ mac, seed });
  }, []);
  const close = useCallback(() => setSheet(null), []);
  return (
    <DeviceSheetCtx.Provider value={{ open, close }}>
      {children}
      {sheet && (
        <DeviceSheet
          mac={sheet.mac}
          seed={sheet.seed}
          onClose={close}
          onChanged={onChanged}
        />
      )}
    </DeviceSheetCtx.Provider>
  );
}

export function DeviceSheet({
  mac,
  seed,
  onClose,
  onChanged,
}: {
  mac: string;
  seed?: Device;
  onClose: () => void;
  onChanged?: () => void;
}) {
  const navigate = useNavigate();
  const user = getCurrentUser();
  const canActivate = userCan(user, 'activate');
  const canBlock = userCan(user, 'block');
  const canTransfer = userCan(user, 'transfer');
  const canSources = userCan(user, 'sources');

  const [ov, setOv] = useState<DeviceOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [changeMac, setChangeMac] = useState(false);
  const [regenMac, setRegenMac] = useState(false);
  const [activateOpen, setActivateOpen] = useState(false);
  const [adding, setAdding] = useState(false);

  const { devices: liveList, connected: rtConnected } = useLiveDevices();
  const liveOnline = rtConnected && liveList.some((d) => d.mac === mac);

  const deviceId = seed?.id || mac;

  const load = useCallback(async () => {
    try {
      const r = await devicesApi.overview(mac);
      setOv(r);
      setErr(null);
      return r;
    } catch (e) {
      const msg = e instanceof ApiError
        ? e.status === 404
          ? 'Aucune fiche trouvée pour cette MAC. Soit aucun appareil '
            + "n'a encore démarré l'app avec ce numéro, soit la fiche "
            + "appartient à un autre revendeur. Fais confirmer au client "
            + "le numéro affiché dans son app (écran « À propos »)."
          : e.message
        : 'Échec du chargement.';
      setErr(msg);
      return null;
    }
  }, [mac]);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    load().finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [load]);

  useRtEvent('changed', (e: ChangedEvent) => {
    if (e.mac && e.mac.toUpperCase() !== mac.toUpperCase()) return;
    if (e.scope && !['devices', 'licenses', 'sources', 'audit'].includes(e.scope)) return;
    void load();
  });

  const meta = ov?.device;
  const lic = ov?.license ?? seed?.license ?? null;
  const sources = ov?.sources ?? [];
  const note = meta?.admin_note ?? seed?.admin_note ?? '';
  const st = (meta?.block_status || seed?.block_status || 'active') as 'active' | 'frozen' | 'banned';
  const customerPhone = meta?.customer_phone ?? seed?.customer_phone ?? null;
  const customerName = meta?.customer_name ?? seed?.customer_name ?? seed?.label ?? null;

  const fakeDevice: Device = useMemo(() => ({
    id: deviceId,
    customer_id: seed?.customer_id || '',
    mac,
    label: meta?.label ?? seed?.label ?? null,
    admin_note: note,
    customer_name: customerName,
    customer_phone: customerPhone,
    block_status: st,
    first_seen_at: meta?.first_seen_at ?? seed?.first_seen_at ?? 0,
    last_seen_at: meta?.last_seen_at ?? seed?.last_seen_at ?? 0,
    license: lic,
    device_model: meta?.device_model ?? seed?.device_model,
    android_release: meta?.android_release ?? seed?.android_release,
    android_build: meta?.android_build ?? seed?.android_build,
    app_build: meta?.app_build ?? seed?.app_build,
    platform: meta?.platform ?? seed?.platform,
    problems: seed?.problems,
  }), [deviceId, mac, meta, seed, note, customerName, customerPhone, st, lic]);

  function applySources(next?: DeviceSource[]) {
    if (!next) return;
    setOv((prev) => (prev ? { ...prev, sources: next } : prev));
  }

  const [clearingLicense, setClearingLicense] = useState(false);
  async function handleClearLicense() {
    if (!window.confirm(
      'Effacer l’abonnement (licence) de ce client ?\n\n'
      + 'L’app rebascule en essai / paywall tout de suite s’il est en ligne.',
    )) return;
    setClearingLicense(true);
    try {
      const r = await devicesApi.clearLicense(mac);
      setOv((prev) => (prev ? { ...prev, license: null } : prev));
      void rtActionFeedback(r.rt);
      toast('Abonnement effacé.', 'success', { isNew: true });
      await load();
      onChanged?.();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec de la suppression.', 'error');
    } finally {
      setClearingLicense(false);
    }
  }

  const [clearing, setClearing] = useState(false);
  async function handleClearSource() {
    if (!window.confirm('Retirer TOUTES les sources de ce client ?')) return;
    setClearing(true);
    try {
      const r = await sourcesApi.clear(mac);
      applySources(r.sources ?? []);
      void rtActionFeedback(r.rt);
      toast('Source retirée.', 'success');
      await load();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec du retrait.', 'error');
    } finally {
      setClearing(false);
    }
  }

  const [cloning, setCloning] = useState(false);
  async function handleCloneSource() {
    const target = window.prompt(
      'CLONER la source de ce client VERS quelle MAC ?\n\nColle la MAC cible (MK:XX:…).',
    );
    if (!target) return;
    // Collage avec/sans `:` / sans `MK:` — même helper que Activer.
    const t = formatMacInput(target);
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(t)) {
      toast('MAC cible invalide.', 'error');
      return;
    }
    if (t === mac.trim().toUpperCase()) {
      toast('C’est la même MAC.', 'warning');
      return;
    }
    setCloning(true);
    try {
      const cur = await sourcesApi.get(mac);
      const srcs = (cur.sources && cur.sources.length
        ? cur.sources
        : cur.source ? [cur.source] : []);
      if (!srcs.length) {
        toast('Aucune source à cloner.', 'warning');
        return;
      }
      const inputs = srcs.map((s) =>
        s.type === 'xtream'
          ? {
              type: 'xtream' as const, label: s.label ?? null,
              server_url: s.server_url ?? '', username: s.username ?? '',
              password: s.password ?? '',
            }
          : { type: 'm3u' as const, label: s.label ?? null, m3u_url: s.m3u_url ?? '' },
      );
      const r = await sourcesApi.setMany(t, inputs);
      void rtActionFeedback(r.rt);
      toast(`Config clonée vers ${t}.`, 'success');
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Clonage impossible.', 'error');
    } finally {
      setCloning(false);
    }
  }

  async function setBlock(status: 'active' | 'frozen' | 'banned') {
    setBusy(true);
    try {
      const res = await devicesApi.setBlock(deviceId, status);
      setOv((prev) => (
        prev && prev.device
          ? { ...prev, device: { ...prev.device, block_status: status } }
          : prev
      ));
      void rtActionFeedback(res.rt);
      onChanged?.();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!window.confirm(`Supprimer définitivement la MAC ${mac} ?`)) return;
    setBusy(true);
    try {
      const res = await devicesApi.remove(deviceId);
      void rtActionFeedback(res.rt);
      onChanged?.();
      onClose();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally {
      setBusy(false);
    }
  }

  function onMigrated(r: MacMigrateResult) {
    setChangeMac(false);
    setRegenMac(false);
    toast(`MAC : ${r.old_mac} → ${r.new_mac}`, 'success', { isNew: true });
    onChanged?.();
    onClose();
  }

  const macUrl = encodeURIComponent(mac);

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/60 px-4 py-8"
      onClick={onClose}
    >
      <div
        className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold tracking-tight">Fiche appareil 360°</h2>
            <p className="mt-0.5 font-mono text-xs text-accent">{mac}</p>
          </div>
          <DeviceStatus status={st} />
        </div>

        {loading && <div className="mb-4 h-24 animate-pulse rounded-lg bg-white/5" />}
        {err && (
          <div className="mb-4 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {err}
          </div>
        )}

        {!loading && !err && (
          <>
            <VersionCard ver={ov?.version ?? null} appVersion={meta?.app_version ?? null} />

            <div className="mb-4 mt-4 grid grid-cols-2 gap-3">
              <SubscriptionBox
                license={lic}
                clearing={clearingLicense}
                onClear={handleClearLicense}
              />
              <PresenceBox presence={ov?.presence ?? null} liveOnline={liveOnline} />
            </div>

            {canActivate && (
              <div className="mb-4 rounded-lg border border-white/5 bg-obsidian px-3 py-2.5">
                <QuickRenewBar
                  mac={mac}
                  onDone={(res: ActivateResult) => {
                    const next = licenseFromActivate(res);
                    setOv((prev) => (prev ? { ...prev, license: next } : prev));
                    void load();
                    onChanged?.();
                  }}
                />
                <div className="mt-2">
                  <CopyWhatsAppButton
                    mac={mac}
                    license={lic}
                    note={note}
                    sources={sources}
                    customerPhone={customerPhone}
                  />
                </div>
              </div>
            )}

            {!canActivate && (
              <div className="mb-4">
                <CopyWhatsAppButton
                  mac={mac}
                  license={lic}
                  note={note}
                  sources={sources}
                  customerPhone={customerPhone}
                />
              </div>
            )}

            <div className="mb-4">
              <AdminNoteField
                deviceId={deviceId}
                value={note}
                blockStatus={st}
                onSaved={(n) => {
                  setOv((prev) => (
                    prev && prev.device
                      ? { ...prev, device: { ...prev.device, admin_note: n } }
                      : prev
                  ));
                  onChanged?.();
                }}
              />
            </div>

            <div className="mb-5 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <InfoRow label="Client" value={customerName || seed?.customer_email || '—'} />
              <InfoRow
                label="Plateforme"
                value={
                  (meta?.platform || seed?.platform) === 'tv'
                    ? '📺 TV'
                    : (meta?.platform || seed?.platform) === 'mobile'
                      ? '📱 Mobile'
                      : (meta?.platform || seed?.platform || '—')
                }
              />
              <InfoRow label="Modèle" value={meta?.device_model || seed?.device_model || '—'} />
              <InfoRow
                label="Android"
                value={meta?.android_release || seed?.android_release
                  ? `Android ${meta?.android_release || seed?.android_release}`
                  : '—'}
              />
              <InfoRow label="Numéro (maison)" value={meta?.build_label || '—'} />
              <InfoRow
                label="Version app"
                value={meta?.app_version || (meta?.app_build != null ? String(meta.app_build) : '—')}
              />
              <InfoRow
                label="Dernière vue"
                value={formatDateTime(meta?.last_seen_at || seed?.last_seen_at)}
              />
              <InfoRow
                label="Première vue"
                value={formatDateTime(meta?.first_seen_at || seed?.first_seen_at)}
              />
            </div>

            <SourcesBlock
              mac={mac}
              sources={sources}
              localSources={ov?.localSources ?? []}
              adding={adding}
              setAdding={setAdding}
              clearing={clearing}
              cloning={cloning}
              canMutate={canSources}
              onClear={handleClearSource}
              onClone={handleCloneSource}
              onApply={applySources}
              onRefresh={async () => { await load(); }}
              onActivatePage={() => {
                navigate(`/activate?mac=${macUrl}`);
                onClose();
              }}
            />

            <MessageComposer mac={mac} />
            <ForceSyncBar mac={mac} liveOnline={liveOnline} />

            <div className="mt-5 border-t border-white/5 pt-4">
              <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
                Actions
              </div>
              <div className="flex flex-wrap gap-1.5">
                {canActivate && (
                  <SheetBtn primary onClick={() => setActivateOpen(true)}>
                    Activer / prolonger
                  </SheetBtn>
                )}
                {canSources && (
                  <SheetBtn onClick={() => { navigate(`/activate?mac=${macUrl}`); onClose(); }}>
                    Pousser une source
                  </SheetBtn>
                )}
                <SheetBtn newId="change-mac" onClick={() => setChangeMac(true)}>
                  Changer la MAC
                </SheetBtn>
                <SheetBtn newId="regenerate-mac" onClick={() => setRegenMac(true)}>
                  Régénérer MAC
                </SheetBtn>
                {canTransfer && (
                  <SheetBtn onClick={() => { navigate(`/transfer?mac=${macUrl}`); onClose(); }}>
                    Transférer vers une autre box
                  </SheetBtn>
                )}
                {canBlock && st !== 'frozen' && (
                  <SheetBtn onClick={() => void setBlock('frozen')}>Geler</SheetBtn>
                )}
                {canBlock && st !== 'banned' && (
                  <SheetBtn onClick={() => void setBlock('banned')}>Bannir</SheetBtn>
                )}
                {canBlock && st !== 'active' && (
                  <SheetBtn onClick={() => void setBlock('active')}>Réactiver</SheetBtn>
                )}
                <SheetBtn danger busy={busy} onClick={() => void remove()}>
                  Supprimer
                </SheetBtn>
              </div>
            </div>
          </>
        )}

        <div className="flex justify-end pt-5">
          <button
            type="button"
            onClick={onClose}
            className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary"
          >
            Fermer
          </button>
        </div>
      </div>

      {changeMac && (
        <ChangeMacModal
          device={fakeDevice}
          onClose={() => setChangeMac(false)}
          onDone={onMigrated}
        />
      )}
      {regenMac && (
        <RegenerateMacModal
          device={fakeDevice}
          onClose={() => setRegenMac(false)}
          onDone={onMigrated}
        />
      )}
      {activateOpen && canActivate && (
        <MiniActivateModal
          mac={mac}
          onClose={() => setActivateOpen(false)}
          onDone={(res) => {
            setActivateOpen(false);
            const next = licenseFromActivate(res);
            setOv((prev) => (prev ? { ...prev, license: next } : prev));
            void load();
            onChanged?.();
          }}
        />
      )}
    </div>
  );
}

function SheetBtn({
  children, onClick, busy, danger, primary, newId,
}: {
  children: ReactNode;
  onClick: () => void;
  busy?: boolean;
  danger?: boolean;
  primary?: boolean;
  newId?: string;
}) {
  const cls = primary
    ? 'bg-accent text-black hover:bg-accent-bright border border-transparent'
    : danger
      ? 'border border-white/10 text-ink-secondary hover:border-accent hover:text-accent-bright'
      : 'border border-white/10 hover:border-white/30';
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={busy}
      {...applyNew(newId, 'rounded-md px-2.5 py-1 text-xs font-medium disabled:opacity-50 ' + cls)}
    >
      {children}
    </button>
  );
}

function DeviceStatus({ status }: { status: string }) {
  const map: Record<string, { label: string; cls: string }> = {
    active: { label: 'Actif', cls: 'bg-success/15 text-success' },
    frozen: { label: 'Gelé', cls: 'bg-warning/15 text-warning' },
    banned: { label: 'Banni', cls: 'bg-accent/15 text-accent-bright' },
  };
  const s = map[status] || map.active;
  return <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${s.cls}`}>{s.label}</span>;
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</div>
      <div className="truncate text-ink-secondary" title={value}>{value}</div>
    </div>
  );
}

function SubscriptionBox({
  license, clearing, onClear,
}: {
  license: DeviceLicense | null;
  clearing?: boolean;
  onClear?: () => void;
}) {
  const ok = license && license.status === 'active';
  const lifetime = license && license.expires_at == null && ok;
  let detail = 'Aucun abonnement';
  if (license) {
    const plan = license.plan ? (PLAN_LABELS[license.plan] || license.plan) : '';
    if (lifetime) detail = `${plan || 'À vie'} · illimité`;
    else if (license.expires_at != null) {
      const days = Math.ceil((license.expires_at - Date.now()) / 86400000);
      detail = days >= 0
        ? `${plan} · ${days} j restant${days > 1 ? 's' : ''}`
        : `${plan} · expiré depuis ${-days} j`;
    } else detail = plan || license.status;
  }
  return (
    <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-2.5">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Abonnement</div>
      <div className={'mt-0.5 text-sm font-semibold ' + (ok ? 'text-success' : 'text-warning')}>
        {ok ? (lifetime ? 'À vie' : 'Actif') : (license ? 'Expiré' : '—')}
      </div>
      <div className="mt-0.5 truncate text-[11px] text-ink-tertiary">{detail}</div>
      {license && onClear && (
        <button
          type="button"
          disabled={clearing}
          onClick={onClear}
          {...applyNew(
            'clear-license',
            'mt-1.5 rounded-md border px-2 py-0.5 text-[10px] font-semibold hover:underline disabled:opacity-40',
          )}
        >
          {clearing ? 'Effacement…' : 'Effacer l’abonnement'}
        </button>
      )}
    </div>
  );
}

function PresenceBox({
  presence, liveOnline,
}: {
  presence: DevicePresence | null;
  liveOnline: boolean;
}) {
  const online = liveOnline || presence?.online;
  const flag = presence?.country ? flagEmoji(presence.country) : '';
  return (
    <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-2.5">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Présence</div>
      <div className={'mt-0.5 flex items-center gap-1.5 text-sm font-semibold ' + (online ? 'text-success' : 'text-ink-tertiary')}>
        <span className={'h-2 w-2 rounded-full ' + (online ? 'bg-success' : 'bg-white/20')} />
        {online ? 'En ligne' : 'Hors ligne'}
      </div>
      <div className="mt-0.5 truncate text-[11px] text-ink-tertiary">
        {presence?.channel
          ? `▶ ${presence.channel}`
          : (presence ? `${flag} ${presence.ip || '—'}`.trim() : '—')}
      </div>
    </div>
  );
}

const _VERDICTS = {
  latest: {
    mot: 'Dernière version',
    cadre: 'border-emerald-500/30 bg-emerald-500/10',
    pastille: 'bg-emerald-500/15 text-emerald-300',
    chiffre: 'text-emerald-300',
  },
  outdated: {
    mot: 'Ancienne version',
    cadre: 'border-red-500/30 bg-red-500/10',
    pastille: 'bg-red-500/15 text-red-300',
    chiffre: 'text-red-300',
  },
  ahead: {
    mot: 'Version de test',
    cadre: 'border-amber-500/30 bg-amber-500/10',
    pastille: 'bg-amber-500/15 text-amber-300',
    chiffre: 'text-amber-300',
  },
  unknown: {
    mot: 'Version inconnue',
    cadre: 'border-white/10 bg-obsidian/40',
    pastille: 'bg-white/10 text-ink-tertiary',
    chiffre: 'text-ink-secondary',
  },
} as const;

function VersionCard({
  ver, appVersion,
}: {
  ver: DeviceVersionStatus | null;
  appVersion: string | null;
}) {
  const etat = ver?.state ?? 'unknown';
  const th = _VERDICTS[etat];
  const gros = ver?.installed || '—';
  return (
    <div className={cn('rounded-xl border p-3', th.cadre)}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">
            Version de l’app
          </h3>
          <div className={cn('mt-1 font-mono text-4xl font-black leading-none', th.chiffre)}>
            {gros}
          </div>
          {appVersion && <div className="mt-1 text-[11px] text-ink-tertiary">v{appVersion}</div>}
        </div>
        <span className={cn('rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide', th.pastille)}>
          {th.mot}
        </span>
      </div>
      <div className="mt-2 text-[11px] text-ink-tertiary">
        {ver?.latest
          ? <>Dernier publié : <span className="font-mono text-ink-secondary">{ver.latest}</span></>
          : 'Dernier numéro publié : indisponible.'}
        {etat === 'outdated' && (
          <div className="font-semibold text-red-300">Le client n’a pas la dernière mise à jour.</div>
        )}
      </div>
    </div>
  );
}

function SourcesBlock({
  mac, sources, localSources, adding, setAdding, clearing, cloning,
  onClear, onClone, onApply, onRefresh, onActivatePage, canMutate,
}: {
  mac: string;
  sources: DeviceSource[];
  localSources: DeviceLocalSource[];
  adding: boolean;
  setAdding: (v: boolean) => void;
  clearing: boolean;
  cloning: boolean;
  canMutate: boolean;
  onClear: () => void;
  onClone: () => void;
  onApply: (s?: DeviceSource[]) => void;
  onRefresh: () => Promise<void>;
  onActivatePage: () => void;
}) {
  return (
    <div className="mb-4">
      <div className="mb-2 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-ink-secondary">M-Trio · sources poussées</h3>
        <span className="text-[11px] text-ink-tertiary">{sources.length}/3</span>
      </div>
      {sources.length === 0 && (
        <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-3 text-center text-xs text-ink-tertiary">
          Aucune source poussée depuis le panel.
        </div>
      )}
      {sources.map((s, i) => (
        <SourceCard
          key={i}
          index={i}
          source={s}
          mac={mac}
          canMutate={canMutate}
          onDone={(srcs) => { onApply(srcs); void onRefresh(); }}
        />
      ))}
      {canMutate && (adding ? (
        <SourceForm
          submitLabel="Ajouter cet abonnement"
          onCancel={() => setAdding(false)}
          onSubmit={async (s) => {
            try {
              const r = await sourcesApi.add(mac, s);
              onApply(r.sources);
              void rtActionFeedback(r.rt);
              toast('Abonnement ajouté.', 'success');
              setAdding(false);
              await onRefresh();
            } catch (e) {
              toast(e instanceof ApiError ? e.message : 'Échec de l’ajout.', 'error');
            }
          }}
        />
      ) : (
        <button
          type="button"
          onClick={() => setAdding(true)}
          className="mt-1 w-full rounded-lg border border-dashed border-white/15 px-3 py-2 text-[11px] font-semibold text-ink-tertiary hover:bg-white/5"
        >
          + Ajouter un abonnement
        </button>
      ))}
      {canMutate && (
      <div className="mt-2 flex flex-wrap gap-1.5">
        <button
          type="button"
          onClick={onActivatePage}
          className="rounded-lg border border-sky-400/40 bg-sky-400/10 px-3 py-1.5 text-[11px] font-semibold text-sky-200"
        >
          {sources.length > 0 ? '＋ Changer / ajouter' : '＋ Ajouter une source'}
        </button>
        {sources.length > 0 && (
          <button
            type="button"
            onClick={onClone}
            disabled={cloning}
            className="rounded-lg border border-emerald-400/40 bg-emerald-400/10 px-3 py-1.5 text-[11px] font-semibold text-emerald-200 disabled:opacity-50"
          >
            {cloning ? 'Clonage…' : '⧉ Cloner vers…'}
          </button>
        )}
        {sources.length > 0 && (
          <button
            type="button"
            onClick={onClear}
            disabled={clearing}
            className="rounded-lg border border-accent/40 bg-accent/10 px-3 py-1.5 text-[11px] font-semibold text-accent-bright disabled:opacity-50"
          >
            {clearing ? 'Retrait…' : 'Tout supprimer'}
          </button>
        )}
      </div>
      )}
      {localSources.length > 0 && (
        <div className="mt-4">
          <h3 className="mb-2 text-sm font-semibold text-ink-secondary">
            Sur l&apos;appareil · {localSources.length}
          </h3>
          {localSources.map((s, i) => (
            <div key={i} className="mb-1.5 rounded-lg border border-white/5 bg-obsidian px-3 py-2 text-xs">
              <div className="font-semibold text-ink-secondary">
                {(s.type || '?').toUpperCase()} · {s.name || '—'}
                {s.active ? ' · ✓ active' : ''}
              </div>
              {s.server && <div className="break-all font-mono text-[11px] text-ink-tertiary">{s.server}</div>}
              {s.username && <div className="font-mono text-[11px] text-ink-tertiary">👤 {s.username}</div>}
              <div className="text-[11px] text-ink-tertiary">{s.channels} chaînes</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function SourceCard({
  index, source, mac, onDone, canMutate = true,
}: {
  index: number;
  source: DeviceSource;
  mac: string;
  canMutate?: boolean;
  onDone: (sources?: DeviceSource[]) => void;
}) {
  const isXtream = source.type === 'xtream';
  const [busy, setBusy] = useState<'' | 'act' | 'del'>('');
  const ident = source.server_url || source.m3u_url || '';
  const nom = source.label || (isXtream ? 'XTREAM' : 'M3U');

  async function activate() {
    if (!window.confirm(`Rendre « ${nom} » active chez le client ?`)) return;
    setBusy('act');
    try {
      const r = await sourcesApi.setActive(mac, index);
      void rtActionFeedback(r.rt);
      toast('Source active mise à jour.', 'success');
      onDone(r.sources);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally { setBusy(''); }
  }

  async function removeOne() {
    if (!window.confirm(`Retirer UNIQUEMENT cette source ?\n\n${nom}`)) return;
    setBusy('del');
    try {
      const r = await sourcesApi.removeAt(mac, index, ident);
      void rtActionFeedback(r.rt);
      toast(`Source retirée (${r.remaining} restante(s)).`, 'success');
      onDone(r.sources);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec du retrait.', 'error');
    } finally { setBusy(''); }
  }

  return (
    <div className="mb-2 rounded-lg border border-white/5 bg-obsidian px-3 py-3">
      <div className="mb-2 flex items-center gap-2">
        <span className="rounded bg-white/5 px-1.5 py-0.5 text-[10px] font-bold text-ink-tertiary">#{index + 1}</span>
        <span className="text-[10px] font-bold text-ink-secondary">{isXtream ? 'XTREAM' : 'M3U'}</span>
        {source.label && <span className="truncate text-xs text-ink-secondary">{source.label}</span>}
        {source.active && (
          <span className="rounded-full bg-success/15 px-2 py-0.5 text-[10px] font-semibold text-success">active</span>
        )}
      </div>
      {isXtream ? (
        <div className="space-y-0.5 text-xs text-ink-tertiary">
          {source.server_url && <div className="break-all font-mono">{source.server_url}</div>}
          {source.username && <div className="font-mono">👤 {source.username}</div>}
        </div>
      ) : (
        source.m3u_url && <div className="break-all font-mono text-xs text-ink-tertiary">{source.m3u_url}</div>
      )}
      {canMutate && (
      <div className="mt-2 flex flex-wrap gap-1.5">
        {!source.active && (
          <button type="button" disabled={busy !== ''} onClick={() => void activate()}
            className="rounded-md border border-emerald-500/30 px-2 py-1 text-[11px] font-semibold text-emerald-300 disabled:opacity-40">
            {busy === 'act' ? '…' : '● Rendre active'}
          </button>
        )}
        <button type="button" disabled={busy !== ''} onClick={() => void removeOne()}
          className="rounded-md border border-red-500/30 px-2 py-1 text-[11px] font-semibold text-red-300 disabled:opacity-40">
          {busy === 'del' ? '…' : '✕ Retirer celle-ci'}
        </button>
      </div>
      )}
    </div>
  );
}

function SourceForm({
  submitLabel, onCancel, onSubmit,
}: {
  submitLabel: string;
  onCancel: () => void;
  onSubmit: (s: DeviceSourceInput) => Promise<void>;
}) {
  const [type, setType] = useState<'xtream' | 'm3u'>('xtream');
  const [label, setLabel] = useState('');
  const [server, setServer] = useState('');
  const [user, setUser] = useState('');
  const [pass, setPass] = useState('');
  const [m3u, setM3u] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (type === 'xtream' && (!server.trim() || !user.trim() || !pass.trim())) {
      toast('Serveur, identifiant et mot de passe sont obligatoires.', 'error');
      return;
    }
    if (type === 'm3u' && !m3u.trim()) {
      toast('L’URL M3U est obligatoire.', 'error');
      return;
    }
    setBusy(true);
    try {
      await onSubmit({
        type,
        label: label.trim() || null,
        server_url: type === 'xtream' ? server.trim() : null,
        username: type === 'xtream' ? user.trim() : null,
        password: type === 'xtream' ? pass.trim() : null,
        m3u_url: type === 'm3u' ? m3u.trim() : null,
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-2 rounded-lg border border-white/10 bg-midnight px-3 py-3">
      <div className="mb-2 flex gap-1.5">
        {(['xtream', 'm3u'] as const).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setType(t)}
            className={'rounded-md px-2 py-1 text-[11px] font-semibold ' + (type === t ? 'bg-white/10' : 'border border-white/10 text-ink-tertiary')}
          >
            {t.toUpperCase()}
          </button>
        ))}
      </div>
      <input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Nom (facultatif)"
        className="mb-1.5 w-full rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs" />
      {type === 'xtream' ? (
        <>
          <input value={server} onChange={(e) => setServer(e.target.value)} placeholder="Serveur"
            className="mb-1.5 w-full rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs" />
          <input value={user} onChange={(e) => setUser(e.target.value)} placeholder="Identifiant"
            className="mb-1.5 w-full rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs" />
          <input value={pass} onChange={(e) => setPass(e.target.value)} placeholder="Mot de passe"
            className="mb-1.5 w-full rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs" />
        </>
      ) : (
        <input value={m3u} onChange={(e) => setM3u(e.target.value)} placeholder="URL M3U"
          className="mb-1.5 w-full rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs" />
      )}
      <div className="flex gap-1.5">
        <button type="button" disabled={busy} onClick={() => void submit()}
          className="rounded-md border border-emerald-500/30 px-2 py-1 text-[11px] font-semibold text-emerald-300">
          {busy ? '…' : submitLabel}
        </button>
        <button type="button" onClick={onCancel} className="rounded-md border border-white/10 px-2 py-1 text-[11px] text-ink-tertiary">
          Annuler
        </button>
      </div>
    </div>
  );
}

const _MSG_TEMPLATES: { label: string; title: string; body: string }[] = [
  { label: '🎂 Anniversaire', title: 'Joyeux anniversaire 🎂', body: "Toute l'équipe vous souhaite un très joyeux anniversaire !" },
  { label: '🙂 Satisfaction', title: 'Votre avis compte', body: 'Êtes-vous satisfait de nos services ? Écrivez-nous.' },
  { label: '📣 Promo', title: 'Offre spéciale', body: '' },
];

function MessageComposer({ mac }: { mac: string }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [durationSec, setDurationSec] = useState(45);
  const [sending, setSending] = useState(false);
  const [depositing, setDepositing] = useState(false);
  const [history, setHistory] = useState<DeviceMessage[]>([]);
  const { connected, devices } = useLiveDevices();
  const online = connected && devices.some((d) => d.mac === mac);

  function loadHistory() {
    devicesApi.messages(mac).then((r) => setHistory(r.items || [])).catch(() => {});
  }
  useEffect(() => { loadHistory(); }, [mac]);

  async function send() {
    if (!title.trim() && !body.trim()) return;
    setSending(true);
    try {
      const id = sendCmd(mac, 'message', { title: title.trim(), body: body.trim(), kind: 'info', durationSec });
      toast("⚡ Envoi à l'appareil…", 'info');
      const ack = await waitForAck(id);
      if (ack && ack.ok) {
        toast("✓ Message affiché sur l'appareil", 'success');
        setTitle(''); setBody('');
      } else if (ack) toast("L'appareil a signalé une erreur.", 'error');
      else toast("Hors ligne — utilise « Déposer ».", 'warning');
    } finally {
      setSending(false);
    }
  }

  async function deposit() {
    if (!title.trim() && !body.trim()) return;
    setDepositing(true);
    try {
      await devicesApi.sendMessage(mac, { title: title.trim(), body: body.trim(), kind: 'info', durationSec });
      toast('✓ Message déposé.', 'success');
      setTitle(''); setBody('');
      loadHistory();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec du dépôt.', 'error');
    } finally {
      setDepositing(false);
    }
  }

  const inputCls = 'w-full rounded-md border border-white/5 bg-obsidian px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <div className="mt-4 rounded-xl border border-white/5 bg-obsidian/40 p-3">
      <div className="mb-2 flex items-center gap-2">
        <h3 className="text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">⚡ Message / inbox</h3>
        <span className={cn(
          'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold',
          online ? 'bg-emerald-500/15 text-emerald-300' : 'bg-white/5 text-ink-tertiary',
        )}>
          {online ? 'En ligne' : 'Hors ligne'}
        </span>
      </div>
      <div className="mb-2 flex flex-wrap gap-1.5">
        {_MSG_TEMPLATES.map((t) => (
          <button key={t.label} type="button" onClick={() => { setTitle(t.title); setBody(t.body); }}
            className="rounded-full border border-white/10 bg-slate px-2.5 py-1 text-[11px] text-ink-secondary hover:border-accent">
            {t.label}
          </button>
        ))}
      </div>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Titre" className={inputCls} />
      <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder="Message…" rows={2}
        className={cn(inputCls, 'mt-2 resize-none')} />
      <div className="mt-2 flex gap-1">
        {[30, 45, 60].map((sec) => (
          <button key={sec} type="button" onClick={() => setDurationSec(sec)}
            className={cn('rounded-full px-2.5 py-1 text-[11px]', durationSec === sec ? 'bg-accent text-black' : 'border border-white/10 text-ink-secondary')}>
            {sec}s
          </button>
        ))}
      </div>
      <div className="mt-2 flex flex-wrap gap-2">
        <button type="button" disabled={sending || (!title.trim() && !body.trim())} onClick={() => void send()}
          className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black disabled:opacity-50">
          {sending ? 'Envoi…' : '⚡ Envoyer maintenant'}
        </button>
        <button type="button" disabled={depositing || (!title.trim() && !body.trim())} onClick={() => void deposit()}
          className="rounded-md border border-white/15 px-3 py-1.5 text-xs font-semibold disabled:opacity-50">
          {depositing ? 'Dépôt…' : '📨 Déposer'}
        </button>
      </div>
      {history.length > 0 && (
        <div className="mt-3 border-t border-white/5 pt-2">
          <div className="mb-1 text-[10px] uppercase tracking-widest text-ink-tertiary">Messages déposés</div>
          {history.slice(0, 5).map((m) => (
            <div key={m.id} className="flex justify-between gap-2 text-[11px]">
              <span className="truncate text-ink-secondary">{m.title || m.body || '—'}</span>
              <span className="shrink-0 text-ink-tertiary">
                {m.read_at ? '✓✓ Lu' : m.delivered_at ? '✓ Livré' : '⏳ En attente'}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function ForceSyncBar({ mac, liveOnline }: { mac: string; liveOnline: boolean }) {
  const [syncing, setSyncing] = useState(false);
  async function sync() {
    setSyncing(true);
    try {
      const id = sendCmd(mac, 'sync', { what: 'all' });
      toast("⚡ Synchro envoyée…", 'info');
      const ack = await waitForAck(id);
      if (ack && ack.ok) toast('✓ Synchro appliquée', 'success');
      else if (ack) toast("L'appareil a signalé une erreur.", 'error');
      else toast('Pas de confirmation (délai dépassé).', 'warning');
    } finally {
      setSyncing(false);
    }
  }
  return (
    <div className="mt-3 flex items-center justify-between rounded-lg border border-white/5 bg-obsidian px-3 py-2">
      <span className="text-[11px] text-ink-tertiary">
        {liveOnline ? 'Force la box à recharger statut + sources.' : 'Hors ligne — synchro à la prochaine connexion.'}
      </span>
      <button
        type="button"
        disabled={syncing || !liveOnline}
        onClick={() => void sync()}
        className="rounded-md border border-white/10 px-2.5 py-1 text-[11px] font-semibold disabled:opacity-40"
      >
        {syncing ? 'Synchro…' : 'Forcer la synchro'}
      </button>
    </div>
  );
}

function MiniActivateModal({
  mac, onClose, onDone,
}: {
  mac: string;
  onClose: () => void;
  onDone: (res: ActivateResult) => void;
}) {
  const [plan, setPlan] = useState('yearly');
  const [busy, setBusy] = useState(false);
  const PLANS = [
    { id: 'monthly', label: '1 mois' },
    { id: 'quarterly', label: '3 mois' },
    { id: 'biannual', label: '6 mois' },
    { id: 'yearly', label: '1 an' },
    { id: 'lifetime', label: 'À vie' },
  ];
  async function go() {
    setBusy(true);
    try {
      const res = await activateApi.activate({ mac, plan });
      void rtActionFeedback(res.rt);
      toast(res.renewed ? 'Abonnement prolongé.' : 'Abonnement activé.', 'success');
      onDone(res);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6" onClick={(e) => e.stopPropagation()}>
        <h2 className="mb-1 text-lg font-semibold">Activer / prolonger</h2>
        <p className="mb-3 font-mono text-xs text-accent">{mac}</p>
        <div className="grid grid-cols-2 gap-2">
          {PLANS.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => setPlan(p.id)}
              className={'rounded-md border px-3 py-2 text-sm ' + (plan === p.id ? 'border-accent bg-accent/10' : 'border-white/5')}
            >
              {p.label}
            </button>
          ))}
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary">Annuler</button>
          <button type="button" disabled={busy} onClick={() => void go()} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black">
            {busy ? '…' : 'Activer'}
          </button>
        </div>
      </div>
    </div>
  );
}
