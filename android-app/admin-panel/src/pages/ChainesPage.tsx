import { FormEvent, useCallback, useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { BoxTargetPreview } from '@/components/BoxTargetPreview';
import { confirmAction } from '@/components/confirm';
import { Alert } from '@/components/ui';
import {
  sourcesApi, ordersApi, userCan, getCurrentUser,
  type DeviceSource, ApiError,
} from '@/lib/api';
import { isValidMac, normalizeMac } from '@/lib/utils';
import { sameBoxTarget } from '@/lib/box-target';
import { useT } from '@/lib/i18n';
import {
  isClientList, isListOn, listDisplayName, planAddSource, planRemoveSource, planToggleSource,
  type SourceInput, type SourceLike,
} from '@/lib/sources';
import {
  DELIVERY_GIVE_UP_MS, DELIVERY_POLL_MS, deliveryStatus, findOrder, type OrderLike,
} from '@/lib/delivery';

// Écran LISTES — séparé de l'activation (n'appelle jamais /api/v1/activate).
//
// Corrigé le 06/10/2026 (parcours E2E « Ajouter conserve les deux M3U ») :
//   • « Ajouter » renvoie TOUTES les listes du panel telles quelles (éteintes
//     comprises) + la nouvelle. Avant, seules les listes Xtream étaient
//     gardées : ajouter un M3U effaçait les autres M3U de la box.
//   • Chaque liste de la box est affichée avec Allumer/Éteindre et Retirer :
//     ajouter, retirer, éteindre = un envoi, la box est prévenue à l'instant
//     (WebSocket) et ne touche qu'à cette liste.
//   • « Suivi de l'envoi » lit l'état RÉEL de l'ordre (accusés de la box).
//     Avant, « la box est prévenue » s'affichait sur la seule réponse HTTP.
// Le serveur garde d'office les listes ajoutées par le client sur sa télé
// (origin = self) : le panel ne les renvoie jamais.

type Delivery = { mac: string; orderId: string; verb: 'load' | 'remove'; startedAt: number };

export function ChainesPage({ onLogout }: { onLogout: () => void }) {
  const t = useT();
  const canPush = userCan(getCurrentUser(), 'sources');
  const [sp] = useSearchParams();
  // Même saisie que « Activer une box » : MAC comme sur la box, « MK: » ajouté seul.
  const [mac, setMac] = useState(sp.get('mac') || '');
  const [sourceType, setSourceType] = useState<SourceInput['type']>('m3u');
  const [link, setLink] = useState('');
  const [server, setServer] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  // Toutes les listes de la box, telles que le serveur les sert. Gardées en
  // mémoire pour les renvoyer intactes ; seul le nom (libellé ou hôte) est
  // affiché, jamais l'adresse complète ni les codes.
  const [sources, setSources] = useState<SourceLike[]>([]);
  // Révision du même snapshot que les listes. Un autre onglet peut les
  // changer entre la lecture et le clic : le Worker refuse alors cet envoi
  // plutôt que d'effacer son ajout. Absent = ancien Worker compatible.
  const [sourcesRev, setSourcesRev] = useState<number | undefined>(undefined);
  const [looking, setLooking] = useState(false);
  // Vrai seulement après une lecture réussie de CETTE mac. Sans ça, un
  // envoi trop tôt remplacerait les autres listes par le seul lien.
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // Décoché par défaut : on AJOUTE (« si on ajoute, on ajoute »). Coché :
  // la liste remplace celles du panel ; celles du client restent.
  const [replaceOthers, setReplaceOthers] = useState(false);
  const [delivery, setDelivery] = useState<Delivery | null>(null);
  const [order, setOrder] = useState<OrderLike | null>(null);
  const readSeq = useRef(0);
  // Une fin d'envoi peut arriver après un changement de destinataire.
  // Le numéro de lecture seul ne suffit pas : on conserve aussi la MAC.
  const currentMac = useRef(normalizeMac(mac));
  currentMac.current = normalizeMac(mac);

  const macOk = isValidMac(mac);

  // Relit les listes servies à cette box (après chaque envoi aussi : l'écran
  // montre l'état du serveur, pas une supposition).
  const reload = useCallback(async (m: string): Promise<void> => {
    if (!sameBoxTarget(m, currentMac.current)) return;
    const seq = ++readSeq.current;
    setLooking(true);
    try {
      const r = await sourcesApi.get(m);
      if (seq !== readSeq.current || !sameBoxTarget(m, currentMac.current)) return;
      setSources((r.sources || []) as SourceLike[]);
      setSourcesRev(Number.isSafeInteger(r.rev) && Number(r.rev) >= 0 ? r.rev : undefined);
      setErr(null);
      setLoaded(true);
    } catch (e) {
      if (seq !== readSeq.current || !sameBoxTarget(m, currentMac.current)) return;
      setSources([]);
      setSourcesRev(undefined);
      setLoaded(false);
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      // 404 = aucune liste pour cette box : on peut en ajouter une.
      if (e instanceof ApiError && e.status === 404) { setLoaded(true); return; }
      setErr(e instanceof ApiError ? e.message : 'Impossible de lire les listes de cette box.');
    } finally {
      if (seq === readSeq.current && sameBoxTarget(m, currentMac.current)) setLooking(false);
    }
  }, [onLogout]);

  useEffect(() => {
    setLoaded(false);
    setSources([]);
    setSourcesRev(undefined);
    if (!macOk || !canPush) return;
    const m = normalizeMac(mac);
    const timer = setTimeout(() => { void reload(m); }, 400);
    return () => { clearTimeout(timer); readSeq.current++; };
  }, [mac, macOk, canPush, reload]);

  // Suivi de l'ordre : relu toutes les 1,5 s jusqu'à un état final
  // (appliqué, refusé, expiré) ou 11 min. Un nouvel envoi remplace le suivi.
  useEffect(() => {
    if (!delivery) return;
    let stop = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const tick = async () => {
      if (stop) return;
      try {
        const r = await ordersApi.list(delivery.mac);
        if (stop) return;
        const o = findOrder(r.items, delivery.orderId);
        setOrder(o);
        if (deliveryStatus(o, delivery.verb).done) {
          // La box a fini : on relit les listes servies.
          void reload(delivery.mac);
          return;
        }
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        // Erreur réseau passagère : on garde le dernier état connu.
      }
      if (Date.now() - delivery.startedAt < DELIVERY_GIVE_UP_MS) {
        timer = setTimeout(tick, DELIVERY_POLL_MS);
      }
    };
    void tick();
    return () => { stop = true; if (timer) clearTimeout(timer); };
  }, [delivery, onLogout, reload]);

  function track(m: string, orderId: string | null | undefined, verb: 'load' | 'remove') {
    if (!sameBoxTarget(m, currentMac.current)) return;
    setOrder(null);
    setDelivery(orderId ? { mac: m, orderId, verb, startedAt: Date.now() } : null);
  }

  async function send(m: string, next: SourceInput[], verb: 'load' | 'remove') {
    const r = await sourcesApi.setMany(m, next, sourcesRev);
    track(m, r.order_id, verb);
    await reload(m);
  }

  async function failed(e: unknown, fallback: string, m: string) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    if (e instanceof ApiError && e.status === 409 && e.code === 'sources_conflict') {
      // La saisie reste en place. On ne rejoue pas automatiquement une
      // intention destructive sur des listes que l'opérateur n'avait pas vues.
      await reload(m);
      if (sameBoxTarget(m, currentMac.current)) {
        setErr('Les listes ont changé. Vérifie l’état relu ci-dessous, puis renvoie ta saisie.');
      }
      return;
    }
    setErr(e instanceof ApiError ? e.message : fallback);
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    if (!canPush || busy || looking) return;
    setErr(null);
    const m = normalizeMac(mac);
    if (!isValidMac(m)) {
      setErr('MAC invalide. Tape-la comme sur la box, par exemple AD:A6:98:70:6A (le « MK: » est ajouté tout seul).');
      return;
    }
    if (!loaded) {
      setErr('Attends que l’état de cette box soit lu, puis réessaie.');
      return;
    }
    const fresh: SourceInput = sourceType === 'xtream'
      ? { type: 'xtream', server_url: server, username, password }
      : { type: 'm3u', m3u_url: link };
    const plan = planAddSource(sources, fresh, replaceOthers);
    if (plan.kind === 'invalid') { setErr(plan.message); return; }
    if (plan.kind === 'full') {
      setErr('Cette box a déjà 3 listes du panel. Retire-en une ci-dessous, ou coche « remplacer ».');
      return;
    }
    setBusy(true);
    try {
      await send(m, plan.sources, 'load');
      setLink('');
      setServer('');
      setUsername('');
      setPassword('');
    } catch (e2) {
      await failed(e2, 'Enregistrement impossible.', m);
    } finally {
      setBusy(false);
    }
  }

  async function toggle(index: number) {
    if (!canPush || busy || looking || !loaded) return;
    setErr(null);
    const m = normalizeMac(mac);
    const plan = planToggleSource(sources, index);
    if (plan.kind !== 'send') return;
    setBusy(true);
    try {
      await send(m, plan.sources, 'load');
    } catch (e) {
      await failed(e, 'Changement impossible.', m);
    } finally {
      setBusy(false);
    }
  }

  async function remove(index: number) {
    if (!canPush || busy || looking || !loaded) return;
    setErr(null);
    const m = normalizeMac(mac);
    const s = sources[index];
    if (!s) return;
    const okConfirm = await confirmAction({
      title: `Retirer « ${listDisplayName(s)} » de cette box ?`,
      message: 'Seule cette liste est retirée. Les autres listes et l’activation ne changent pas.',
      confirmLabel: 'Retirer',
      danger: true,
    });
    if (!okConfirm) return;
    const plan = planRemoveSource(sources, index);
    setBusy(true);
    try {
      if (plan.kind === 'keep') {
        await send(m, plan.sources, 'remove');
      } else if (plan.kind === 'clear') {
        const r = await sourcesApi.clear(m, sourcesRev);
        track(m, r.order_id, 'remove');
        await reload(m);
      } else if (plan.kind === 'client' && plan.id) {
        await sourcesApi.removeClientList(m, plan.id);
        setDelivery(null);
        await reload(m);
      } else {
        setErr('Cette liste ne peut pas être retirée d’ici.');
      }
    } catch (e) {
      await failed(e, 'Retrait impossible.', m);
    } finally {
      setBusy(false);
    }
  }

  const status = delivery ? deliveryStatus(order, delivery.verb) : null;
  const statusTone = status?.kind === 'ok'
    ? 'border-success/30 bg-success/10 text-success'
    : status?.kind === 'failed' || status?.kind === 'late'
      ? 'border-warning/30 bg-warning/10 text-warning'
      : 'border-white/10 bg-obsidian text-ink-secondary';
  const panelCount = sources.filter((s) => !isClientList(s)).length;
  const inputReady = sourceType === 'xtream'
    ? !!(server.trim() && username.trim() && password.trim())
    : !!link.trim();

  const inputCls =
    'w-full rounded-md border border-white/10 bg-slate px-3 py-2.5 text-sm outline-none focus:border-accent/60 focus:ring-2 focus:ring-accent/40';
  const smallBtn =
    'rounded-md border border-white/15 px-3 py-1.5 text-xs font-medium text-ink-primary hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-40';

  return (
    <AppLayout
      title="Listes"
      subtitle="Ajoute, éteins ou retire les listes d’une box. Ça n’active pas l’application, et ça ne change pas la durée."
      onLogout={onLogout}
    >
      {!canPush && (
        <Alert>Ton compte ne peut pas modifier la liste de chaînes.</Alert>
      )}

      <div className="grid max-w-3xl gap-6">
        <form onSubmit={save} className="space-y-4 rounded-xl border border-white/10 bg-midnight p-6">
          <h2 className="text-base font-semibold">Ajouter une liste</h2>
          <p className="text-sm leading-relaxed text-ink-secondary">
            Ici, seulement les listes de chaînes (3 au maximum). Pour la licence (essai, durée) :{' '}
            <Link
              to={isValidMac(normalizeMac(mac)) ? `/activate?mac=${encodeURIComponent(normalizeMac(mac))}` : '/activate'}
              className="font-medium text-accent-bright underline-offset-2 hover:underline"
            >
              {t('nav.activate')}
            </Link>.
          </p>

          <div>
            <label htmlFor="chaines-mac" className="mb-1.5 block text-xs font-medium text-ink-secondary">
              Adresse MAC (comme sur la box)
            </label>
            <input
              id="chaines-mac"
              value={mac}
              onChange={(e) => {
                currentMac.current = normalizeMac(e.target.value);
                readSeq.current++;
                setLoaded(false);
                setSources([]);
                setSourcesRev(undefined);
                setMac(e.target.value);
                setDelivery(null);
              }}
              disabled={busy}
              onBlur={() => setMac((v) => (v.trim() ? normalizeMac(v) : v))}
              autoFocus
              autoComplete="off"
              placeholder="AD:A6:98:70:6A"
              className={inputCls + ' font-mono'}
            />
          </div>

          <BoxTargetPreview mac={mac} />

          <fieldset disabled={busy} className="space-y-2">
            <legend className="text-xs font-medium text-ink-secondary">Type de source</legend>
            <div className="flex flex-wrap gap-4 text-sm">
              <label className="flex cursor-pointer items-center gap-2">
                <input type="radio" name="source-type" value="m3u"
                  checked={sourceType === 'm3u'} onChange={() => setSourceType('m3u')} />
                M3U
              </label>
              <label className="flex cursor-pointer items-center gap-2">
                <input type="radio" name="source-type" value="xtream"
                  checked={sourceType === 'xtream'} onChange={() => setSourceType('xtream')} />
                Xtream
              </label>
            </div>
          </fieldset>

          {sourceType === 'm3u' ? <div>
            <label htmlFor="chaines-lien" className="mb-1.5 block text-xs font-medium text-ink-secondary">
              Nouveau lien
            </label>
            <input
              id="chaines-lien"
              value={link}
              disabled={busy}
              onChange={(e) => setLink(e.target.value)}
              autoComplete="off"
              spellCheck={false}
              placeholder="Colle le lien de la liste ici"
              className={inputCls + ' font-mono'}
            />
          </div> : <div className="space-y-4">
            <div>
              <label htmlFor="chaines-server" className="mb-1.5 block text-xs font-medium text-ink-secondary">
                Serveur Xtream
              </label>
              <input id="chaines-server" value={server} disabled={busy}
                onChange={(e) => setServer(e.target.value)} autoComplete="off" spellCheck={false}
                placeholder="Adresse du serveur, avec le port si nécessaire" className={inputCls + ' font-mono'} />
            </div>
            <div>
              <label htmlFor="chaines-username" className="mb-1.5 block text-xs font-medium text-ink-secondary">
                Identifiant Xtream
              </label>
              <input id="chaines-username" value={username} disabled={busy}
                onChange={(e) => setUsername(e.target.value)} autoComplete="off" spellCheck={false}
                className={inputCls} />
            </div>
            <div>
              <label htmlFor="chaines-password" className="mb-1.5 block text-xs font-medium text-ink-secondary">
                Mot de passe Xtream
              </label>
              <input id="chaines-password" type="password" value={password} disabled={busy}
                onChange={(e) => setPassword(e.target.value)} autoComplete="off" className={inputCls} />
            </div>
          </div>}

          <label className="flex cursor-pointer items-start gap-2 text-sm text-ink-secondary">
            <input
              type="checkbox"
              checked={replaceOthers}
              disabled={busy}
              onChange={(e) => setReplaceOthers(e.target.checked)}
              className="mt-0.5"
            />
            <span>
              Remplacer les listes du panel déjà sur la box par celle-ci
              <span className="block text-xs text-ink-tertiary">
                Décoché : elle s’ajoute aux autres. Les listes ajoutées par le client restent dans les deux cas.
              </span>
            </span>
          </label>

          {err && <Alert>{err}</Alert>}

          <button
            type="submit"
            disabled={!canPush || busy || looking || !loaded || !macOk || !inputReady}
            className="rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-obsidian hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Envoi…' : replaceOthers ? 'Remplacer par cette liste'
              : sourceType === 'xtream' ? 'Ajouter la source Xtream' : 'Ajouter la liste'}
          </button>
        </form>

        {delivery && status && (
          <section
            aria-label="Suivi de l’envoi"
            aria-live="polite"
            className={'rounded-xl border px-4 py-3 text-sm ' + statusTone}
          >
            <p>{status.text}</p>
          </section>
        )}

        {macOk && (
          <section aria-label="Listes de cette box" className="rounded-xl border border-white/10 bg-midnight p-6">
            <h2 className="mb-3 text-base font-semibold">
              Listes de cette box {loaded ? `(${sources.length})` : ''}
            </h2>
            {looking && sources.length === 0 && <p className="text-sm text-ink-secondary">Recherche…</p>}
            {!looking && loaded && sources.length === 0 && (
              <p className="text-sm text-ink-secondary">Aucune liste sur cette box.</p>
            )}
            <ul className="divide-y divide-white/5">
              {sources.map((s, i) => {
                const on = isListOn(s);
                const client = isClientList(s);
                const name = listDisplayName(s);
                return (
                  <li key={`${i}-${name}`} className="flex flex-wrap items-center justify-between gap-2 py-2.5">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-ink-primary">{name}</p>
                      <p className="text-xs text-ink-tertiary">
                        {s.type === 'xtream' ? 'Xtream' : 'M3U'}
                        {' · '}
                        {client ? 'ajoutée par le client' : on ? 'allumée' : 'éteinte'}
                      </p>
                    </div>
                    <div className="flex gap-2">
                      {!client && (
                        <button
                          type="button"
                          onClick={() => void toggle(i)}
                          disabled={!canPush || busy || looking || !loaded}
                          aria-label={`${on ? 'Éteindre' : 'Allumer'} ${name}`}
                          className={smallBtn}
                        >
                          {on ? 'Éteindre' : 'Allumer'}
                        </button>
                      )}
                      <button
                        type="button"
                        onClick={() => void remove(i)}
                        disabled={!canPush || busy || looking || !loaded || (client && !s.id)}
                        aria-label={`Retirer ${name}`}
                        className={smallBtn}
                      >
                        Retirer
                      </button>
                    </div>
                  </li>
                );
              })}
            </ul>
            {loaded && panelCount >= 3 && (
              <p className="mt-3 text-xs text-ink-tertiary">3 listes du panel : retire-en une pour en ajouter une autre.</p>
            )}
          </section>
        )}
      </div>
    </AppLayout>
  );
}
