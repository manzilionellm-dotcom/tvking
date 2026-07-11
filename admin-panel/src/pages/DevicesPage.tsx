import { ReactNode, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import {
  devicesApi, activateApi, flagEmoji, PLAN_LABELS,
  type Device, type DeviceSource, type DeviceOverview, type DeviceLocalSource,
  type DeviceLicense, type DevicePresence, ApiError,
} from '@/lib/api';
import { useLiveDevices, useRtEvent, sendCmd, waitForAck, type ChangedEvent } from '@/lib/realtime';
import { toast, rtActionFeedback } from '@/components/Toast';
import { formatDateTime } from '@/lib/utils';

/// Scopes de mutation qui concernent cette page (évènement `changed`).
const CHANGED_SCOPES = ['devices', 'licenses', 'sources', 'audit'];

export function DevicesPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Device[]>([]);
  const [q, setQ] = useState('');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [activateFor, setActivateFor] = useState<Device | null>(null);
  // Appareil dont on affiche la « fiche complète » (infos + M-Trio).
  const [detailFor, setDetailFor] = useState<Device | null>(null);
  // MACs connectées au hub temps réel → pastille verte instantanée.
  const { devices: liveList, connected: rtConnected } = useLiveDevices();
  const liveMacs = useMemo(
    () => new Set(liveList.map((d) => d.mac)),
    [liveList],
  );

  const load = useCallback(() => {
    setLoading(true);
    devicesApi.list(q)
      .then((r) => { setItems(r.items); setErr(null); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => setLoading(false));
  }, [q, onLogout]);

  useEffect(() => {
    const id = setTimeout(load, 200); // petit debounce sur la recherche
    return () => clearTimeout(id);
  }, [load]);

  // Une mutation a eu lieu ailleurs (autre onglet / autre admin) →
  // recharge la liste, débouncé à 2 s pour absorber les rafales
  // (même patron que le Dashboard). Scope absent = prudence, on recharge.
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useRtEvent('changed', (e: ChangedEvent) => {
    if (e.scope && !CHANGED_SCOPES.includes(e.scope)) return;
    if (refreshTimer.current) return;
    refreshTimer.current = setTimeout(() => {
      refreshTimer.current = null;
      load();
    }, 2000);
  });
  useEffect(() => () => {
    if (refreshTimer.current) clearTimeout(refreshTimer.current);
  }, []);

  async function setBlock(d: Device, status: 'active' | 'frozen' | 'banned') {
    setBusyId(d.id); setErr(null);
    try {
      const res = await devicesApi.setBlock(d.id, status);
      load();
      // Feedback instantané : l'appareil a-t-il reçu le push en direct ?
      void rtActionFeedback(res.rt);
    }
    catch (e: any) { setErr(e instanceof ApiError ? e.message : 'Échec.'); }
    finally { setBusyId(null); }
  }

  async function remove(d: Device) {
    if (!window.confirm(`Supprimer définitivement la MAC ${d.mac} ?\n(Si l'app reste installée, elle réapparaîtra avec un nouvel essai. Pour stopper un abuseur, utilise plutôt « Bannir ».)`)) return;
    setBusyId(d.id); setErr(null);
    try {
      const res = await devicesApi.remove(d.id);
      load();
      void rtActionFeedback(res.rt);
    }
    catch (e: any) { setErr(e instanceof ApiError ? e.message : 'Échec.'); }
    finally { setBusyId(null); }
  }

  return (
    <AppLayout
      title="Appareils"
      subtitle={`${items.length} appareil(s)`}
      onLogout={onLogout}
    >
      <input
        type="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Recherche par MAC, label, client…"
        className="mb-4 w-full max-w-md rounded-md border border-white/5 bg-midnight px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
      />

      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      <div className="overflow-x-auto rounded-xl border border-white/5">
        <table className="w-full min-w-[640px] text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">MAC</th>
              <th className="px-4 py-3">Client</th>
              <th className="px-4 py-3">Appareil</th>
              <th className="px-4 py-3">Statut</th>
              <th className="px-4 py-3">Dernière vue</th>
              <th className="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && Array.from({ length: 5 }).map((_, i) => (
              <tr key={i} className="bg-obsidian">
                <td className="px-4 py-3" colSpan={6}>
                  <div className="h-4 w-full animate-pulse rounded bg-white/5" />
                </td>
              </tr>
            ))}
            {!loading && items.length === 0 && (
              <tr><td colSpan={6} className="px-4 py-8 text-center text-sm text-ink-tertiary">
                Aucun appareil pour l'instant. Dès qu'une app contacte le serveur,
                sa MAC apparaît ici automatiquement.
              </td></tr>
            )}
            {items.map((d) => {
              const st = d.block_status || 'active';
              const busy = busyId === d.id;
              const liveOnline = rtConnected && liveMacs.has(d.mac);
              return (
                <tr key={d.id} className="bg-obsidian hover:bg-midnight">
                  <td className="px-4 py-3">
                    <span className="inline-flex items-center gap-1.5">
                      {liveOnline && (
                        <span
                          title="En ligne maintenant (temps réel)"
                          className="h-1.5 w-1.5 shrink-0 animate-pulse rounded-full bg-success"
                        />
                      )}
                      <button
                        type="button"
                        onClick={() => setDetailFor(d)}
                        title="Voir la fiche complète (M-Trio + infos appareil)"
                        className="font-mono text-xs text-accent underline-offset-2 hover:underline"
                      >
                        {d.mac}
                      </button>
                    </span>
                  </td>
                  <td className="px-4 py-3">{d.customer_name || d.customer_email || '—'}</td>
                  <td className="px-4 py-3">
                    <PlatformChip device={d} />
                    {d.device_model ? (
                      <div className="mt-1">
                        <div className="text-xs text-ink-secondary">{d.device_model}</div>
                        <div className="text-[10px] text-ink-tertiary">
                          {d.android_release ? `Android ${d.android_release}` : ''}
                          {d.android_build ? ` · ${d.android_build}` : ''}
                        </div>
                      </div>
                    ) : (
                      <span className="text-ink-tertiary">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3"><DeviceStatus status={st} /></td>
                  <td className="px-4 py-3 text-ink-tertiary">{formatDateTime(d.last_seen_at)}</td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap justify-end gap-1.5">
                      <ActionBtn busy={busy} onClick={() => setDetailFor(d)} title="Fiche complète : M-Trio + infos appareil">Détails</ActionBtn>
                      <ActionBtn busy={busy} primary onClick={() => setActivateFor(d)} title="Activer / prolonger (le client a payé)">Activer</ActionBtn>
                      {st !== 'frozen' && (
                        <ActionBtn busy={busy} onClick={() => setBlock(d, 'frozen')} title="Geler (rappel de paiement)">Geler</ActionBtn>
                      )}
                      {st !== 'banned' && (
                        <ActionBtn busy={busy} onClick={() => setBlock(d, 'banned')} title="Bannir (abus)">Bannir</ActionBtn>
                      )}
                      {st !== 'active' && (
                        <ActionBtn busy={busy} onClick={() => setBlock(d, 'active')} title="Réactiver">Réactiver</ActionBtn>
                      )}
                      <ActionBtn busy={busy} danger onClick={() => remove(d)} title="Supprimer la MAC">Suppr.</ActionBtn>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {activateFor && (
        <ActivatePlanModal
          device={activateFor}
          onClose={() => setActivateFor(null)}
          onDone={() => { setActivateFor(null); load(); }}
        />
      )}

      {detailFor && (
        <DeviceDetailModal
          device={detailFor}
          liveOnline={rtConnected && liveMacs.has(detailFor.mac)}
          busy={busyId === detailFor.id}
          onClose={() => setDetailFor(null)}
          onActivate={() => { const d = detailFor; setDetailFor(null); setActivateFor(d); }}
          onBlock={(status) => setBlock(detailFor, status)}
          onRemove={() => { const d = detailFor; setDetailFor(null); remove(d); }}
        />
      )}
    </AppLayout>
  );
}

// =========================================================
//  FICHE COMPLÈTE D'UN APPAREIL — « tout ce que le client a dans le ventre »
// =========================================================
//  Le client donne sa MAC → on affiche ici TOUT : ses infos appareil
//  (modèle, Android, plateforme, dernière vue) ET son M-Trio (les 1 à 3
//  sources Xtream/M3U poussées depuis le panel, avec identifiants) pour
//  pouvoir l'aider/diagnostiquer. Les sources sont lues via /api/v1/sources/:mac.
//
//  NOTE : seules les sources POUSSÉES par le panel sont visibles ici. Si le
//  client a ajouté lui-même une liste M3U/Xtream depuis l'app (« Mes sources »),
//  celle-ci reste stockée localement sur sa TV et n'est pas remontée au serveur.
function DeviceDetailModal({
  device, liveOnline, busy, onClose, onActivate, onBlock, onRemove,
}: {
  device: Device;
  liveOnline: boolean;   // connecté au hub temps réel EN CE MOMENT
  busy: boolean;
  onClose: () => void;
  onActivate: () => void;
  onBlock: (status: 'active' | 'frozen' | 'banned') => void;
  onRemove: () => void;
}) {
  const navigate = useNavigate();
  const [ov, setOv] = useState<DeviceOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    devicesApi.overview(device.id)
      .then((r) => { if (alive) { setOv(r); setErr(null); } })
      .catch((e) => { if (alive) setErr(e instanceof ApiError ? e.message : 'Échec.'); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [device.id]);

  const st = device.block_status || 'active';
  const sources = ov?.sources ?? [];
  const macUrl = encodeURIComponent(device.mac);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div
        className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold tracking-tight">Centre de contrôle appareil</h2>
            <p className="mt-0.5 font-mono text-xs text-accent">{device.mac}</p>
          </div>
          <DeviceStatus status={st} />
        </div>

        {/* ----- Abonnement + Présence live (résumé d'un coup d'œil) ----- */}
        <div className="mb-4 grid grid-cols-2 gap-3">
          <SubscriptionBox loading={loading} license={ov?.license ?? null} />
          <PresenceBox loading={loading} presence={ov?.presence ?? null} />
        </div>

        {/* ----- Infos appareil (le « ventre ») ----- */}
        <div className="mb-5 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
          <InfoRow label="Client" value={device.customer_name || device.customer_email || '—'} />
          <InfoRow label="Plateforme" value={device.platform === 'tv' ? '📺 TV' : device.platform === 'mobile' ? '📱 Mobile' : '—'} />
          <InfoRow label="Modèle" value={device.device_model || '—'} />
          <InfoRow label="Android" value={device.android_release ? `Android ${device.android_release}` : '—'} />
          <InfoRow label="Build Android" value={device.android_build || '—'} />
          <InfoRow label="Version app" value={device.app_build != null ? String(device.app_build) : '—'} />
          <InfoRow label="Étiquette" value={device.label || '—'} />
          <InfoRow label="Dernière vue" value={formatDateTime(device.last_seen_at)} />
          <InfoRow label="Première vue" value={formatDateTime(device.first_seen_at)} />
        </div>

        {/* ----- M-Trio : les sources poussées ----- */}
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-sm font-semibold text-ink-secondary">
            M-Trio · sources poussées
          </h3>
          {!loading && !err && (
            <span className="text-[11px] text-ink-tertiary">{sources.length}/3</span>
          )}
        </div>

        {loading && (
          <div className="h-16 animate-pulse rounded-lg bg-white/5" />
        )}
        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
        )}
        {!loading && !err && sources.length === 0 && (
          <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-4 text-center text-xs text-ink-tertiary">
            Aucune source poussée depuis le panel pour cette MAC.
            <br />
            (Le client a peut-être ajouté sa propre liste M3U/Xtream sur sa TV —
            elle reste stockée localement et n'apparaît pas ici.)
          </div>
        )}
        {!loading && !err && sources.map((s, i) => (
          <SourceCard key={i} index={i} source={s} />
        ))}

        {/* ----- Inventaire RÉEL sur la TV (remonté par l'app) ----- */}
        {!loading && !err && (ov?.localSources?.length ?? 0) > 0 && (
          <div className="mt-4">
            <div className="mb-2 flex items-center justify-between">
              <h3 className="text-sm font-semibold text-ink-secondary">
                Sur la TV du client · inventaire réel
              </h3>
              <span className="text-[11px] text-ink-tertiary">{ov!.localSources!.length}</span>
            </div>
            <p className="mb-2 text-[11px] text-ink-tertiary">
              Toutes les sources réellement chargées sur l'appareil (poussées
              par le panel <em>et</em> ajoutées par le client). Sans mot de passe.
            </p>
            {ov!.localSources!.map((s, i) => (
              <LocalSourceCard key={i} source={s} />
            ))}
          </div>
        )}

        {/* ----- Temps réel : message direct + synchro forcée ----- */}
        <LiveActions mac={device.mac} liveOnline={liveOnline} />

        {/* ----- Actions : tout piloter depuis ici (gauche/droite/nord/sud) ----- */}
        <div className="mt-5 border-t border-white/5 pt-4">
          <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">Actions</div>
          <div className="flex flex-wrap gap-1.5">
            <ActionBtn busy={busy} primary onClick={onActivate} title="Activer / prolonger l'abonnement">Activer / prolonger</ActionBtn>
            <ActionBtn busy={busy} onClick={() => navigate(`/activate?mac=${macUrl}`)} title="Pousser ou modifier le M-Trio de sources">Pousser une source</ActionBtn>
            <ActionBtn busy={busy} onClick={() => navigate(`/transfer?mac=${macUrl}`)} title="Transférer l'abonnement vers une nouvelle MAC">Transférer</ActionBtn>
            {st !== 'frozen' && (
              <ActionBtn busy={busy} onClick={() => onBlock('frozen')} title="Geler (rappel de paiement)">Geler</ActionBtn>
            )}
            {st !== 'banned' && (
              <ActionBtn busy={busy} onClick={() => onBlock('banned')} title="Bannir (abus)">Bannir</ActionBtn>
            )}
            {st !== 'active' && (
              <ActionBtn busy={busy} onClick={() => onBlock('active')} title="Réactiver">Réactiver</ActionBtn>
            )}
            <ActionBtn busy={busy} danger onClick={onRemove} title="Supprimer la MAC">Supprimer</ActionBtn>
          </div>
        </div>

        <div className="flex justify-end pt-5">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Fermer</button>
        </div>
      </div>
    </div>
  );
}

/// Actions TEMPS RÉEL de la fiche appareil : envoyer un message affiché
/// immédiatement sur la TV du client + forcer une resynchro complète.
/// Visible uniquement quand l'appareil est connecté au hub EN CE MOMENT
/// (sinon la commande n'atteindrait personne → simple indication).
function LiveActions({ mac, liveOnline }: { mac: string; liveOnline: boolean }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);
  const [syncing, setSyncing] = useState(false);

  // Envoie la commande via le WS puis attend l'ack de l'appareil.
  async function runCmd(
    action: 'sync' | 'message',
    payload: unknown,
    setBusyFlag: (b: boolean) => void,
  ) {
    setBusyFlag(true);
    try {
      const id = sendCmd(mac, action, payload);
      toast("⚡ Envoyé à l'appareil…", 'info');
      const ack = await waitForAck(id);
      if (ack && ack.ok) {
        // Latence affichée seulement si le hub la connaît (jamais « null ms »).
        toast(
          typeof ack.latencyMs === 'number'
            ? `✓ Appliqué en ${ack.latencyMs} ms`
            : "✓ Appliqué sur l'appareil",
          'success',
        );
      }
      else if (ack) toast("L'appareil a signalé une erreur.", 'error');
      else toast("Pas de confirmation de l'appareil (délai dépassé).", 'warning');
    } finally {
      setBusyFlag(false);
    }
  }

  async function sendMessage() {
    if (!title.trim() && !body.trim()) return;
    await runCmd('message', {
      title: title.trim(),
      body: body.trim(),
      kind: 'info',
    }, setSending);
    setTitle(''); setBody('');
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-obsidian px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <div className="mt-5 border-t border-white/5 pt-4">
      <div className="mb-2 flex items-center gap-2">
        <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Temps réel</div>
        <span
          className={
            'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold ' +
            (liveOnline ? 'bg-success/15 text-success' : 'bg-white/5 text-ink-tertiary')
          }
        >
          <span className={'h-1.5 w-1.5 rounded-full ' + (liveOnline ? 'animate-pulse bg-success' : 'bg-white/20')} />
          {liveOnline ? 'En ligne' : 'Hors ligne'}
        </span>
      </div>

      {liveOnline ? (
        <div className="space-y-2">
          <div className="text-xs text-ink-tertiary">
            Envoyer un message — affiché immédiatement sur l'écran du client.
          </div>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Titre (ex. Rappel de paiement)"
            className={inputCls}
          />
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Message…"
            rows={2}
            className={inputCls + ' resize-none'}
          />
          <div className="flex flex-wrap gap-1.5">
            <button
              type="button"
              disabled={sending || (!title.trim() && !body.trim())}
              onClick={sendMessage}
              className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black hover:bg-accent-bright disabled:opacity-50"
            >
              {sending ? 'Envoi…' : 'Envoyer le message'}
            </button>
            <button
              type="button"
              disabled={syncing}
              onClick={() => runCmd('sync', { what: 'all' }, setSyncing)}
              title="L'appareil re-télécharge immédiatement statut + sources + config"
              className="rounded-md border border-white/10 px-3 py-1.5 text-xs font-medium hover:border-white/30 disabled:opacity-50"
            >
              {syncing ? 'Synchro…' : 'Forcer la synchro'}
            </button>
          </div>
        </div>
      ) : (
        <p className="text-xs text-ink-tertiary">
          Hors ligne — message direct et synchro forcée indisponibles.
          Les actions (gel, activation…) seront appliquées à sa prochaine connexion.
        </p>
      )}
    </div>
  );
}

/// Encart « Abonnement » : statut + plan + expiration (jours restants).
function SubscriptionBox({ loading, license }: { loading: boolean; license: DeviceLicense | null }) {
  if (loading) return <div className="h-16 animate-pulse rounded-lg bg-white/5" />;
  const ok = license && license.status === 'active';
  const lifetime = license && license.expires_at == null && ok;
  let detail = 'Aucun abonnement';
  if (license) {
    const plan = license.plan ? (PLAN_LABELS[license.plan] || license.plan) : '';
    if (lifetime) {
      detail = `${plan || 'À vie'} · illimité`;
    } else if (license.expires_at != null) {
      const days = Math.ceil((license.expires_at - Date.now()) / 86400000);
      detail = days >= 0
        ? `${plan} · ${days} j restant${days > 1 ? 's' : ''}`
        : `${plan} · expiré depuis ${-days} j`;
    } else {
      detail = plan || license.status;
    }
  }
  return (
    <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-2.5">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Abonnement</div>
      <div className={'mt-0.5 text-sm font-semibold ' + (ok ? 'text-success' : 'text-warning')}>
        {ok ? (lifetime ? 'À vie' : 'Actif') : (license ? 'Expiré' : '—')}
      </div>
      <div className="mt-0.5 truncate text-[11px] text-ink-tertiary" title={detail}>{detail}</div>
    </div>
  );
}

/// Encart « Présence » : en ligne maintenant ? + chaîne en cours + IP/pays.
function PresenceBox({ loading, presence }: { loading: boolean; presence: DevicePresence | null }) {
  if (loading) return <div className="h-16 animate-pulse rounded-lg bg-white/5" />;
  const online = presence?.online;
  const flag = presence?.country ? flagEmoji(presence.country) : '';
  return (
    <div className="rounded-lg border border-white/5 bg-obsidian px-3 py-2.5">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">Présence</div>
      <div className={'mt-0.5 flex items-center gap-1.5 text-sm font-semibold ' + (online ? 'text-success' : 'text-ink-tertiary')}>
        <span className={'h-2 w-2 rounded-full ' + (online ? 'bg-success' : 'bg-white/20')} />
        {online ? 'En ligne' : 'Hors ligne'}
      </div>
      <div className="mt-0.5 truncate text-[11px] text-ink-tertiary" title={presence?.channel || ''}>
        {presence?.channel ? `▶ ${presence.channel}` : (presence ? `${flag} ${presence.ip || '—'}`.trim() : '—')}
      </div>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</div>
      <div className="truncate text-ink-secondary" title={value}>{value}</div>
    </div>
  );
}

/// Carte d'une source du M-Trio (avec identifiants Xtream ou URL M3U).
function SourceCard({ index, source }: { index: number; source: DeviceSource }) {
  const isXtream = source.type === 'xtream';
  return (
    <div className="mb-2 rounded-lg border border-white/5 bg-obsidian px-3 py-3">
      <div className="mb-2 flex items-center gap-2">
        <span className="rounded bg-white/5 px-1.5 py-0.5 text-[10px] font-bold text-ink-tertiary">#{index + 1}</span>
        <span
          className="rounded px-1.5 py-0.5 text-[10px] font-bold"
          style={{
            background: isXtream ? 'rgba(202,162,74,0.18)' : 'rgba(90,160,232,0.18)',
            color: isXtream ? '#CAA24A' : '#5AA0E8',
          }}
        >
          {isXtream ? 'XTREAM' : 'M3U'}
        </span>
        {source.label && <span className="truncate text-xs text-ink-secondary">{source.label}</span>}
      </div>
      <div className="grid grid-cols-1 gap-y-1.5 text-xs">
        {isXtream ? (
          <>
            <CredRow label="Serveur" value={source.server_url || '—'} />
            <CredRow label="Identifiant" value={source.username || '—'} />
            <CredRow label="Mot de passe" value={source.password || '—'} mono />
            {source.epg_url && <CredRow label="EPG" value={source.epg_url} />}
          </>
        ) : (
          <>
            <CredRow label="URL M3U" value={source.m3u_url || '—'} />
            {source.epg_url && <CredRow label="EPG" value={source.epg_url} />}
          </>
        )}
      </div>
    </div>
  );
}

/// Carte d'une source réellement présente sur la TV (inventaire heartbeat).
/// Compacte, sans mot de passe ; badge « active » sur celle en cours d'usage.
function LocalSourceCard({ source }: { source: DeviceLocalSource }) {
  const isXtream = source.type === 'xtream';
  return (
    <div className="mb-2 rounded-lg border border-white/5 bg-obsidian px-3 py-2.5">
      <div className="mb-1 flex items-center gap-2">
        <span
          className="rounded px-1.5 py-0.5 text-[10px] font-bold"
          style={{
            background: isXtream ? 'rgba(202,162,74,0.18)' : 'rgba(90,160,232,0.18)',
            color: isXtream ? '#CAA24A' : '#5AA0E8',
          }}
        >
          {isXtream ? 'XTREAM' : 'M3U'}
        </span>
        <span className="min-w-0 flex-1 truncate text-xs text-ink-secondary">{source.name || '—'}</span>
        {source.active && (
          <span className="rounded-full bg-success/15 px-2 py-0.5 text-[10px] font-semibold text-success">active</span>
        )}
      </div>
      <div className="grid grid-cols-1 gap-y-1.5 text-xs">
        <CredRow label="Serveur" value={source.server || '—'} />
        {isXtream && <CredRow label="Identifiant" value={source.username || '—'} />}
        <CredRow label="Chaînes" value={source.channels ? String(source.channels) : '—'} />
      </div>
    </div>
  );
}

/// Ligne identifiant copiable (clic = copie dans le presse-papier).
function CredRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  const [copied, setCopied] = useState(false);
  function copy() {
    if (!value || value === '—') return;
    navigator.clipboard?.writeText(value).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    }).catch(() => {});
  }
  return (
    <div className="flex items-baseline gap-2">
      <span className="w-24 shrink-0 text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</span>
      <button
        type="button"
        onClick={copy}
        title="Cliquer pour copier"
        className={'min-w-0 flex-1 truncate text-left text-ink-secondary hover:text-accent ' + (mono ? 'font-mono' : '')}
      >
        {copied ? 'Copié ✔' : value}
      </button>
    </div>
  );
}

function ActivatePlanModal({
  device, onClose, onDone,
}: { device: Device; onClose: () => void; onDone: () => void }) {
  const [plan, setPlan] = useState('yearly');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const PLANS = [
    { id: 'monthly', label: '1 mois' },
    { id: 'quarterly', label: '3 mois' },
    { id: 'biannual', label: '6 mois' },
    { id: 'yearly', label: '1 an' },
    { id: 'lifetime', label: 'À vie' },
  ];

  async function go() {
    setBusy(true); setErr(null);
    try {
      const res = await activateApi.activate({ mac: device.mac, plan });
      setDone(true);
      // L'appareil est-il en ligne ? → toast « appliqué en X ms ».
      void rtActionFeedback(res.rt);
      setTimeout(onDone, 900);
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h2 className="mb-1 text-lg font-semibold tracking-tight">Activer / prolonger</h2>
        <p className="mb-4 font-mono text-xs text-accent">{device.mac}</p>
        <p className="mb-3 text-sm text-ink-tertiary">
          Le client a payé ? Choisis la durée — elle s'ajoute au temps restant
          et débloque l'app immédiatement.
        </p>
        <div className="grid grid-cols-2 gap-2">
          {PLANS.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => setPlan(p.id)}
              className={
                'rounded-md border px-3 py-2 text-sm transition ' +
                (plan === p.id
                  ? 'border-accent bg-accent/10 text-ink-primary'
                  : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
              }
            >
              {p.label}
            </button>
          ))}
        </div>
        {err && <div className="mt-3 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
        {done && <div className="mt-3 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">Activé ✔</div>}
        <div className="flex justify-end gap-2 pt-4">
          <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Annuler</button>
          <button disabled={busy || done} onClick={go} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
            {busy ? 'Activation…' : 'Activer'}
          </button>
        </div>
      </div>
    </div>
  );
}

/// Pastille 📱 Mobile / 📺 TV. Priorité au champ `platform` (rapporté par
/// l'app) ; à défaut, heuristique sur le modèle (box TV connues).
function PlatformChip({ device }: { device: Device }) {
  const isTv =
    device.platform === 'tv' ||
    /\btv\b|aftt|aftb|aftm|afts|fire\s*tv|firetv|shield|bravia|chromecast|google\s*tv|mibox|mi\s*box|adt-|homatics|formuler|dune|nvidia/i.test(
      device.device_model || '',
    );
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold"
      style={{
        background: isTv ? 'rgba(106,141,176,0.18)' : 'rgba(255,255,255,0.06)',
        color: isTv ? '#8FB4D6' : '#B6B0A8',
      }}
    >
      {isTv ? '📺 TV' : '📱 Mobile'}
    </span>
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

function ActionBtn({
  children, onClick, busy, danger, primary, title,
}: { children: ReactNode; onClick: () => void; busy?: boolean; danger?: boolean; primary?: boolean; title?: string }) {
  const cls = primary
    ? 'bg-accent text-black hover:bg-accent-bright border border-transparent'
    : danger
      ? 'border border-white/10 text-ink-secondary hover:border-accent hover:text-accent-bright'
      : 'border border-white/10 hover:border-white/30';
  return (
    <button
      onClick={onClick}
      disabled={busy}
      title={title}
      className={'rounded-md px-2.5 py-1 text-xs font-medium disabled:opacity-50 ' + cls}
    >
      {children}
    </button>
  );
}
