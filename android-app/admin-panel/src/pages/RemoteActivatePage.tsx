import { FormEvent, useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { Alert } from '@/components/ui';
import {
  activateApi, appsApi, devicesApi, planCostsApi, meApi, sourcesApi,
  getCurrentUser, isOwnerRole, userCan,
  type App, type PlanCost, type ActivateResult, type DeviceSource, ApiError,
} from '@/lib/api';
import { formatDateTime, isValidMac, normalizeMac } from '@/lib/utils';
import { createSingleFlight } from '@/lib/robust';
import {
  planActivationList, validateListInput, type SourceInput,
} from '@/lib/sources';
import {
  INSTANT_GIVE_UP_MS, INSTANT_POLL_MS, instantLabel, listOnTv, type InventoryLike,
} from '@/lib/instant';

// =========================================================
//  Activation à distance — UN bouton : licence + liste.
// =========================================================
//  Le Worker refuse volontairement la liste dans l'appel d'activation
//  (deux opérations distinctes). Cet écran les enchaîne :
//    1. la liste saisie est vérifiée AVANT tout (pas de crédit débité
//       pour une faute de frappe) ;
//    2. POST /api/v1/activate (la box est prévenue : « activate »/« renew ») ;
//    3. PUT /api/v1/sources/:mac avec les listes déjà posées par le panel
//       + la nouvelle (la box est prévenue : « source »). Les listes que le
//       client a ajoutées lui-même sont gardées par le serveur.
//  Si l'étape 3 échoue, la licence reste activée et un bouton renvoie
//  seulement la liste. Rien n'est journalisé ici (mot de passe compris).
// =========================================================

// Essais GRATUITS (0 crédit, même pour un revendeur : planCreditCost du
// Worker rend 0 pour tout plan « trial… »). La licence expire seule à la
// date, la box se bloque alors comme pour un abonnement fini.
const TRIALS = [
  { id: 'trial_3d', label: '3 jours' },
  { id: 'trial_7d', label: '7 jours' },
  { id: 'trial_30d', label: '1 mois' },
];

// Abonnements PAYÉS (crédits débités pour un revendeur).
const PLANS = [
  { id: 'yearly', label: '1 an' },
  { id: 'lifetime', label: 'À vie' },
];

export function isTrialPlan(plan: string): boolean {
  return plan.startsWith('trial');
}

type ListKind = 'm3u' | 'xtream' | 'none';

/// Décision du propriétaire (06/10/2026) : « listes à part, applications à
/// part ». Cette page n'active que la licence ; les listes se gèrent dans
/// Listes (/chaines). Faux = plus de champ de liste ici. Le code de l'envoi
/// reste (vrai le rallume) : le suivi « liste sur la TV après N s » est le
/// même que dans la fiche appareil.
const LISTS_IN_ACTIVATION = false;
type Step = 'idle' | 'busy' | 'ok' | 'skip' | 'err';

export function RemoteActivatePage({ onLogout }: { onLogout: () => void }) {
  const user = getCurrentUser();
  const isReseller = !isOwnerRole(user?.role);
  const canPush = !isReseller || userCan(user, 'sources');

  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || '');
  // Défaut : 7 jours d'essai. Un oubli ne coûte aucun crédit.
  const [plan, setPlan] = useState('trial_7d');
  const [customerName, setCustomerName] = useState('');
  const [kind, setKind] = useState<ListKind>(LISTS_IN_ACTIVATION && canPush ? 'm3u' : 'none');
  const [m3uUrl, setM3uUrl] = useState('');
  const [server, setServer] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);

  const [err, setErr] = useState<string | null>(null);
  const [licenceStep, setLicenceStep] = useState<Step>('idle');
  const [listStep, setListStep] = useState<Step>('idle');
  const [listNote, setListNote] = useState<string | null>(null);
  const [result, setResult] = useState<ActivateResult | null>(null);
  const flight = useRef(createSingleFlight());

  // ----- « Sur la TV » : preuve que la liste est arrivée -----
  // Dès que la liste est envoyée, on relit l'inventaire réel de la box
  // (heartbeat) toutes les 2 s, jusqu'à la voir ou pendant 2 min. La box
  // (107-test.158+) remonte son inventaire tout de suite après l'import.
  const [tv, setTv] = useState<{
    startedAt: number; sent: SourceInput; elapsedMs: number;
    seen: InventoryLike | null; lastSeen: number; now: number;
  } | null>(null);

  useEffect(() => {
    if (!tv || tv.seen || tv.elapsedMs >= INSTANT_GIVE_UP_MS) return;
    let alive = true;
    const m = normalizeMac(mac);
    let deviceId: string | null = null;
    const tick = async () => {
      try {
        if (!deviceId) {
          const r = await devicesApi.list(m, { limit: 5 });
          const hit = r.items.find((d) => d.mac.toUpperCase() === m.toUpperCase());
          deviceId = hit ? hit.id : null;
        }
        let seen: InventoryLike | null = null;
        let lastSeen = 0;
        if (deviceId) {
          const ov = await devicesApi.overview(deviceId);
          seen = listOnTv(ov.localSources ?? [], tv.sent);
          lastSeen = ov.presence?.last_seen ?? 0;
        }
        if (!alive) return;
        const now = Date.now();
        setTv((cur) => cur && cur.startedAt === tv.startedAt
          ? { ...cur, elapsedMs: now - cur.startedAt, seen, lastSeen, now }
          : cur);
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) onLogout();
        if (!alive) return;
        const now = Date.now();
        setTv((cur) => cur && cur.startedAt === tv.startedAt
          ? { ...cur, elapsedMs: now - cur.startedAt, now }
          : cur);
      }
    };
    tick();
    const timer = window.setInterval(tick, INSTANT_POLL_MS);
    return () => { alive = false; window.clearInterval(timer); };
    // `tv.seen` / `tv.elapsedMs` changent à chaque relecture : on ne
    // relance la boucle que pour un nouvel envoi (startedAt).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tv?.startedAt, tv?.seen, (tv?.elapsedMs ?? 0) >= INSTANT_GIVE_UP_MS]);

  const primaryApp =
    apps.find((a) => !/red\s*room|nova|\btv\b/i.test(a.name)) ?? apps[0];
  const appId = primaryApp?.id ?? 'app_7motion';
  const macOk = isValidMac(mac);
  const busy = licenceStep === 'busy' || listStep === 'busy';

  useEffect(() => {
    let active = true;
    const out = (e: unknown) => {
      if (e instanceof ApiError && e.status === 401) onLogout();
    };
    planCostsApi.list().then((c) => { if (active) setCosts(c.items); }).catch(out);
    appsApi.list().then((a) => { if (active) setApps(a.items); }).catch(out);
    meApi.get().then((r) => { if (active) setBalance(r.user.credit_balance ?? null); }).catch(out);
    return () => { active = false; };
  }, [onLogout]);

  const costFor = (p: string): number | null => {
    if (isTrialPlan(p)) return 0;
    const row = costs.find((c) => c.plan === p);
    return row ? row.credits : null;
  };

  /// Liste saisie, nettoyée. `null` = « sans liste ».
  function listInput(): SourceInput | null {
    if (kind === 'none') return null;
    if (kind === 'm3u') return { type: 'm3u', m3u_url: m3uUrl.trim() };
    return {
      type: 'xtream',
      server_url: server.trim(),
      username: username.trim(),
      password: password.trim(),
    };
  }

  /// Étape 3 seule : envoie la liste saisie à la box (elle remplace les
  /// listes du panel ; celles du client restent).
  async function sendList(m: string, input: SourceInput): Promise<void> {
    setListStep('busy');
    setListNote(null);
    try {
      let existing: DeviceSource[] = [];
      try {
        const r = await sourcesApi.get(m);
        existing = (r.sources ?? (r.source ? [r.source] : [])) as DeviceSource[];
      } catch (e) {
        // 404 = aucune liste encore : on part de zéro.
        if (!(e instanceof ApiError && e.status === 404)) throw e;
      }
      // La liste saisie REMPLACE les listes du panel (mesuré le 05/10/2026 :
      // l'ancienne règle « ajouter, maximum 3 » refusait l'envoi et la box
      // gardait l'ancien serveur). Les listes du client restent : le
      // serveur les garde d'office. Même liste déjà seule sur le serveur :
      // on renvoie quand même, c'est ce renvoi qui prévient la box.
      const planList = planActivationList(existing, input);
      await sourcesApi.setMany(m, planList.sources);
      setListStep('ok');
      setListNote(
        planList.unchanged
          ? 'Cette liste était déjà sur le serveur : la box est prévenue à nouveau.'
          : planList.replaced > 0
            ? `Liste envoyée. ${planList.replaced === 1 ? 'L’ancienne liste du panel est remplacée' : `Les ${planList.replaced} anciennes listes du panel sont remplacées`}`
              + (planList.clientKept > 0 ? ` ; ${planList.clientKept === 1 ? 'la liste ajoutée par le client reste' : `les ${planList.clientKept} listes ajoutées par le client restent`}.` : '.')
            : null,
      );
      const now = Date.now();
      setTv({ startedAt: now, sent: input, elapsedMs: 0, seen: null, lastSeen: 0, now });
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setListStep('err');
      setListNote(
        (e instanceof ApiError ? e.message : 'Envoi impossible.')
        + ' La licence reste activée : corrige la liste puis « Renvoyer la liste ».',
      );
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    await flight.current.run(async () => {
      setErr(null);
      setResult(null);
      setListNote(null);
      setListStep('idle');
      const m = normalizeMac(mac);
      if (!isValidMac(m)) {
        setErr('MAC invalide. Tape-la comme sur la box : AD:A6:98:70:6A (le « MK: » est ajouté tout seul).');
        return;
      }
      const input = listInput();
      if (input) {
        const bad = validateListInput(input);
        if (bad) { setErr(bad + ' Rien n’a été activé.'); return; }
      }
      setMac(m);
      setLicenceStep('busy');
      try {
        const res = await activateApi.activate({
          mac: m, plan, app_id: appId,
          customer_name: customerName.trim() || undefined,
        });
        setResult(res);
        if (res.credit_balance !== null) setBalance(res.credit_balance);
        setLicenceStep('ok');
      } catch (e2: unknown) {
        if (e2 instanceof ApiError && e2.status === 401) { onLogout(); return; }
        setLicenceStep('err');
        setErr((e2 instanceof ApiError ? e2.message : 'Activation impossible.') + ' Aucune liste envoyée.');
        return;
      }
      if (input) {
        await sendList(m, input);
      } else {
        setListStep('skip');
      }
    });
  }

  async function resendList() {
    const m = normalizeMac(mac);
    const input = listInput();
    if (!isValidMac(m) || !input) return;
    const bad = validateListInput(input);
    if (bad) { setListStep('err'); setListNote(bad); return; }
    await flight.current.run(() => sendList(m, input));
  }

  const inputCls =
    'w-full rounded-lg border border-white/10 bg-slate px-3 py-3 text-base outline-none focus:border-accent/60 focus:ring-2 focus:ring-accent/40';
  const credit = costFor(plan);
  const done = licenceStep === 'ok' && (listStep === 'ok' || listStep === 'skip');

  return (
    <AppLayout
      title="Activation à distance"
      onLogout={onLogout}
      actions={
        isReseller && balance !== null ? (
          <div className="rounded-lg border border-white/10 px-3 py-1.5 text-sm text-ink-secondary">
            {balance} crédit{balance > 1 ? 's' : ''}
          </div>
        ) : undefined
      }
    >
      <form onSubmit={submit} className="mx-auto w-full max-w-md space-y-5">
        <p className="text-sm leading-relaxed text-ink-secondary">
          Un seul bouton : la box est activée <em>et</em> reçoit sa liste. Elle est
          prévenue tout de suite et affiche la liste en quelques secondes.
        </p>

        <div>
          <label htmlFor="ra-mac" className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-ink-secondary">
            Adresse MAC (comme sur la box)
          </label>
          <input
            id="ra-mac"
            value={mac}
            onChange={(e) => setMac(e.target.value)}
            onBlur={() => setMac((v) => (v.trim() ? normalizeMac(v) : v))}
            autoFocus
            autoComplete="off"
            placeholder="AD:A6:98:70:6A"
            className={inputCls + ' font-mono'}
          />
        </div>

        <div>
          <label htmlFor="ra-name" className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-ink-secondary">
            Nom du client <span className="normal-case tracking-normal text-ink-tertiary">(optionnel)</span>
          </label>
          <input
            id="ra-name"
            value={customerName}
            onChange={(e) => setCustomerName(e.target.value)}
            placeholder="Ex. Salon de Karim"
            className={inputCls}
          />
        </div>

        <p className="-mb-2 text-xs font-medium uppercase tracking-wide text-ink-secondary">Essai gratuit</p>
        <div className="grid grid-cols-3 gap-3" role="group" aria-label="Essai gratuit">
          {TRIALS.map((p) => {
            const selected = plan === p.id;
            return (
              <button
                type="button"
                key={p.id}
                onClick={() => setPlan(p.id)}
                className={
                  'rounded-xl border px-3 py-3 text-left transition ' +
                  (selected
                    ? 'border-accent bg-accent/15 text-ink-primary'
                    : 'border-white/10 bg-midnight text-ink-secondary hover:border-white/25')
                }
              >
                <span className="block text-base font-semibold leading-tight">{p.label}</span>
                <span className="mt-1 block text-xs text-ink-tertiary">Gratuit</span>
              </button>
            );
          })}
        </div>

        <p className="-mb-2 text-xs font-medium uppercase tracking-wide text-ink-secondary">Abonnement payé</p>
        <div className="grid grid-cols-2 gap-3" role="group" aria-label="Abonnement payé">
          {PLANS.map((p) => {
            const selected = plan === p.id;
            const c = costFor(p.id);
            return (
              <button
                type="button"
                key={p.id}
                onClick={() => setPlan(p.id)}
                className={
                  'rounded-xl border px-4 py-4 text-left transition ' +
                  (selected
                    ? 'border-accent bg-accent/15 text-ink-primary'
                    : 'border-white/10 bg-midnight text-ink-secondary hover:border-white/25')
                }
              >
                <span className="block text-lg font-semibold leading-tight">{p.label}</span>
                {isReseller && c !== null && (
                  <span className="mt-1 block text-xs text-ink-tertiary">{c} crédit{c > 1 ? 's' : ''}</span>
                )}
              </button>
            );
          })}
        </div>

        {!LISTS_IN_ACTIVATION && canPush && (
          <div className="rounded-xl border border-white/10 bg-midnight/60 p-4 text-sm">
            <p className="font-medium text-ink-primary">Les listes se gèrent à part.</p>
            <p className="mt-1 text-ink-secondary">
              Ici on active l’application. Pour envoyer, remplacer ou retirer la liste de cette box :{' '}
              <Link
                to={`/chaines${isValidMac(normalizeMac(mac)) ? `?mac=${encodeURIComponent(normalizeMac(mac))}` : ''}`}
                className="font-medium text-accent-bright underline-offset-2 hover:underline"
              >
                Listes
              </Link>.
            </p>
          </div>
        )}

        {LISTS_IN_ACTIVATION && canPush && (
          <div className="space-y-3 rounded-xl border border-white/10 bg-midnight/60 p-4">
            <p className="text-sm font-medium text-ink-primary">Liste de chaînes du client</p>
            <div className="grid grid-cols-3 gap-2" role="group" aria-label="Type de liste">
              {(['m3u', 'xtream', 'none'] as ListKind[]).map((k) => (
                <button
                  type="button"
                  key={k}
                  onClick={() => setKind(k)}
                  className={
                    'rounded-lg border px-2 py-2 text-sm ' +
                    (kind === k
                      ? 'border-accent bg-accent/15 text-ink-primary'
                      : 'border-white/10 text-ink-secondary')
                  }
                >
                  {k === 'm3u' ? 'Lien M3U' : k === 'xtream' ? 'Code Xtream' : 'Sans liste'}
                </button>
              ))}
            </div>
            {kind === 'm3u' && (
              <input
                aria-label="Lien M3U"
                value={m3uUrl}
                onChange={(e) => setM3uUrl(e.target.value)}
                placeholder="http://…/get.php?…"
                autoComplete="off"
                className={inputCls + ' font-mono text-sm'}
              />
            )}
            {kind === 'xtream' && (
              <div className="space-y-2">
                <input
                  aria-label="Serveur Xtream"
                  value={server}
                  onChange={(e) => setServer(e.target.value)}
                  placeholder="http://serveur:port"
                  autoComplete="off"
                  className={inputCls + ' font-mono text-sm'}
                />
                <input
                  aria-label="Identifiant Xtream"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Identifiant"
                  autoComplete="off"
                  className={inputCls + ' font-mono text-sm'}
                />
                <input
                  aria-label="Mot de passe Xtream"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Mot de passe"
                  autoComplete="off"
                  className={inputCls + ' font-mono text-sm'}
                />
              </div>
            )}
            <p className="text-xs text-ink-tertiary">
              Cette liste remplace les listes du panel déjà sur la box. Les listes ajoutées par le
              client restent. Pour en ajouter une sans remplacer : fiche appareil → Liste de chaînes.
            </p>
          </div>
        )}

        {err && <Alert>{err}</Alert>}

        {(licenceStep !== 'idle' || listStep !== 'idle') && (
          <ul className="space-y-1.5 rounded-xl border border-white/10 bg-midnight/60 p-4 text-sm" role="status">
            <StepRow step={licenceStep} label={
              licenceStep === 'ok' && result
                ? (result.plan === 'lifetime' || result.expires_at == null
                  ? 'Licence activée à vie'
                  : isTrialPlan(plan)
                    ? `Essai gratuit jusqu’au ${formatDateTime(result.expires_at)}`
                    : `Licence activée jusqu’au ${formatDateTime(result.expires_at)}`)
                : 'Licence'
            } />
            {listStep !== 'skip' && (
              <StepRow step={listStep} label={listNote ?? 'Liste envoyée à la box'} />
            )}
            {done && tv && (() => {
              const l = instantLabel({
                elapsedMs: tv.elapsedMs,
                seen: tv.seen ? [tv.seen] : [],
                missing: tv.seen ? 0 : 1,
                lastSeen: tv.lastSeen,
                now: tv.now,
              });
              return (
                <li className="flex gap-2 pt-1" aria-live="polite">
                  <span className={
                    (l.kind === 'ok' ? 'text-emerald-400' : l.kind === 'late' ? 'text-accent-bright' : 'text-ink-tertiary')
                    + ' w-4 shrink-0 font-semibold'
                  }>
                    {l.kind === 'ok' ? '✓' : l.kind === 'late' ? '!' : '⚡'}
                  </span>
                  <span className="text-ink-primary">{l.text}</span>
                </li>
              );
            })()}
            {done && !tv && (
              <li className="pt-1 text-ink-secondary">
                La box est prévenue à l’instant. Sur l’accueil, la liste apparaît en
                quelques secondes.
              </li>
            )}
          </ul>
        )}

        <button
          type="submit"
          disabled={busy || !mac.trim()}
          className="w-full rounded-xl bg-accent px-4 py-3.5 text-base font-semibold text-obsidian hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy
            ? 'En cours…'
            : (kind === 'none' || !canPush ? 'Activer' : '⚡ Activer et envoyer la liste · instantané')
              + (isTrialPlan(plan)
                ? ' · essai gratuit'
                : isReseller && credit !== null ? ` · ${credit} crédit${credit > 1 ? 's' : ''}` : '')}
        </button>

        {licenceStep === 'ok' && listStep === 'err' && (
          <button
            type="button"
            onClick={resendList}
            disabled={busy || !macOk}
            className="w-full rounded-lg border border-white/15 px-4 py-2.5 text-sm font-semibold text-ink-primary hover:bg-white/5 disabled:opacity-50"
          >
            Renvoyer la liste (sans réactiver)
          </button>
        )}
      </form>
    </AppLayout>
  );
}

function StepRow({ step, label }: { step: Step; label: string }) {
  const mark = step === 'ok' ? '✓' : step === 'err' ? '✗' : step === 'busy' ? '…' : '·';
  const color = step === 'ok'
    ? 'text-emerald-400'
    : step === 'err' ? 'text-accent-bright' : 'text-ink-tertiary';
  return (
    <li className="flex gap-2">
      <span className={color + ' w-4 shrink-0 font-semibold'}>{mark}</span>
      <span className="text-ink-primary">{label}</span>
    </li>
  );
}
