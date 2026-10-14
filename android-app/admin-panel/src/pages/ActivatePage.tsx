import { FormEvent, useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { CopyLink } from '@/components/CopyLink';
import { confirmAction } from '@/components/confirm';
import { Alert, StatusBadge } from '@/components/ui';
import {
  activateApi, appsApi, planCostsApi, meApi, devicesApi,
  getCurrentUser, isOwnerRole, DOWNLOAD_URL, DOWNLOADER_CODE,
  type App, type PlanCost, type ActivateResult, type Device,
  type DeviceLicense, ApiError,
} from '@/lib/api';
import { formatDateTime, isValidMac, normalizeMac } from '@/lib/utils';

// Écran ACTIVATION — durée, activation, désactivation, expiration.
// N'envoie jamais de liste de chaînes. Le lien se gère sur /chaines.
// « Désactiver » gèle la box (appel déjà existant). Ça ne touche pas
// au lien, et ça n'efface pas la date de fin.

const PLAN_FR: Record<string, string> = {
  monthly: '1 mois', quarterly: '3 mois', biannual: '6 mois',
  yearly: '1 an', lifetime: 'À vie',
  trial_24h: 'Test 24 h', trial_48h: 'Test 48 h', trial_7d: 'Test 7 jours',
};

type BoxState = {
  device: Device;
  license: DeviceLicense | null;
};

export function ActivatePage({ onLogout }: { onLogout: () => void }) {
  const user = getCurrentUser();
  const isReseller = !isOwnerRole(user?.role);

  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [plan, setPlan] = useState(isReseller ? 'yearly' : 'monthly');
  const [customerName, setCustomerName] = useState('');
  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);
  const [box, setBox] = useState<BoxState | null>(null);
  const [looking, setLooking] = useState(false);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [warn, setWarn] = useState<string | null>(null);
  const [result, setResult] = useState<ActivateResult | null>(null);

  const primaryApp =
    apps.find((a) => !/red\s*room|nova|\btv\b/i.test(a.name)) ?? apps[0];
  const appId = primaryApp?.id ?? 'app_7motion';
  const macOk = isValidMac(mac);

  useEffect(() => {
    let active = true;
    const notices: string[] = [];

    Promise.all([appsApi.list(), planCostsApi.list()])
      .then(([a, c]) => {
        if (!active) return;
        setApps(a.items);
        setCosts(c.items);
      })
      .catch((e) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        notices.push('Impossible de charger les apps / tarifs.');
        setWarn(notices.join(' '));
      });

    meApi.get()
      .then((r) => { if (active) setBalance(r.user.credit_balance ?? null); })
      .catch((e) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        notices.push('Solde crédits indisponible.');
        setWarn(notices.join(' '));
      });

    return () => { active = false; };
  }, [onLogout]);

  useEffect(() => {
    if (!macOk) { setBox(null); return; }
    let cancel = false;
    const m = normalizeMac(mac);
    const timer = setTimeout(() => {
      setLooking(true);
      devicesApi.list(m)
        .then(async (r) => {
          const found = r.items.find((d) => d.mac.toUpperCase() === m);
          if (!found) {
            if (!cancel) setBox(null);
            return;
          }
          const ov = await devicesApi.overview(found.id);
          if (!cancel) setBox({ device: found, license: ov.license });
        })
        .catch((e) => {
          if (cancel) return;
          if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
          setBox(null);
        })
        .finally(() => { if (!cancel) setLooking(false); });
    }, 400);
    return () => { cancel = true; clearTimeout(timer); };
  }, [mac, macOk, onLogout, result]);

  const costFor = (p: string): number | null => {
    if (p.startsWith('trial')) return 0;
    const row = costs.find((c) => c.plan === p);
    return row ? row.credits : null;
  };

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    setResult(null);
    const m = normalizeMac(mac);
    if (!isValidMac(m)) {
      setErr('MAC invalide. Format attendu : MK:XX:XX:XX:XX:XX');
      setBusy(false);
      return;
    }
    try {
      // Licence seulement. Pas de lien dans cet appel.
      const res = await activateApi.activate({
        mac: m, plan, app_id: appId,
        customer_name: customerName.trim() || undefined,
      });
      setResult(res);
      if (res.credit_balance !== null) setBalance(res.credit_balance);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Activation impossible. Réessayez.');
    } finally {
      setBusy(false);
    }
  }

  async function setFrozen(frozen: boolean) {
    if (!box) return;
    const ok = await confirmAction({
      title: frozen ? 'Désactiver cette application ?' : 'Réactiver cette application ?',
      message: frozen
        ? 'La box sera bloquée tout de suite. La date de fin reste en mémoire, et la liste de chaînes n’est pas modifiée.'
        : 'La box pourra de nouveau ouvrir l’application, si la durée n’est pas terminée. La liste de chaînes n’est pas modifiée.',
      confirmLabel: frozen ? 'Désactiver' : 'Réactiver',
      danger: frozen,
    });
    if (!ok) return;
    setBusy(true);
    setErr(null);
    try {
      await devicesApi.setBlock(box.device.id, frozen ? 'frozen' : 'active');
      setBox({
        ...box,
        device: { ...box.device, block_status: frozen ? 'frozen' : 'active' },
      });
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Action impossible.');
    } finally {
      setBusy(false);
    }
  }

  const PLANS = isReseller
    ? [{ id: 'yearly', label: '1 an' }, { id: 'lifetime', label: 'À vie' }]
    : [{ id: 'monthly', label: '1 mois' }, { id: 'yearly', label: '1 an' }, { id: 'lifetime', label: 'À vie' }];
  const TRIALS = [
    { id: 'trial_24h', label: 'Test 24 h' },
    { id: 'trial_48h', label: 'Test 48 h' },
    { id: 'trial_7d', label: 'Test 7 jours' },
  ];

  const inputCls =
    'w-full rounded-md border border-white/10 bg-slate px-3 py-2.5 text-sm outline-none focus:border-accent/60 focus:ring-2 focus:ring-accent/40';

  const license = box?.license ?? null;
  const blocked = box?.device.block_status === 'frozen' || box?.device.block_status === 'banned';
  const licenseStatus = !license
    ? 'offline'
    : license.expires_at != null && license.expires_at <= Date.now()
      ? 'expired'
      : (license.status || 'active');
  const shownStatus = box?.device.block_status === 'banned'
    ? 'banned'
    : box?.device.block_status === 'frozen'
      ? 'frozen'
      : licenseStatus === 'offline'
        ? 'offline'
        : licenseStatus;

  return (
    <AppLayout
      title="Activer l'application"
      subtitle="Durée, activation et désactivation. Ça ne change pas la liste de chaînes."
      onLogout={onLogout}
      actions={
        isReseller && balance !== null ? (
          <div className="rounded-lg border border-accent/30 bg-accent/10 px-4 py-2 text-sm">
            <span className="text-ink-secondary">Crédits&nbsp;: </span>
            <span className="font-semibold text-accent-bright">{balance}</span>
          </div>
        ) : undefined
      }
    >
      {warn && <Alert>{warn}</Alert>}

      <div className="grid max-w-5xl gap-6 lg:grid-cols-2">
        <form onSubmit={submit} className="space-y-4 rounded-xl border border-white/10 bg-midnight p-6">
          <h2 className="text-base font-semibold">Activation</h2>
          <p className="text-sm leading-relaxed text-ink-secondary">
            Le lien de la liste de chaînes est sur un autre écran :{' '}
            <Link to={macOk ? `/chaines?mac=${encodeURIComponent(normalizeMac(mac))}` : '/chaines'} className="font-medium text-accent-bright underline-offset-2 hover:underline">
              Liste de chaînes
            </Link>.
          </p>

          <div>
            <label htmlFor="act-mac" className="mb-1.5 block text-xs font-medium text-ink-secondary">
              Adresse MAC de la box
            </label>
            <input
              id="act-mac"
              value={mac}
              onChange={(e) => setMac(e.target.value)}
              autoFocus
              autoComplete="off"
              placeholder="MK:XX:XX:XX:XX:XX"
              className={inputCls + ' font-mono'}
            />
          </div>

          <div>
            <p className="mb-1 text-xs font-medium text-ink-secondary">
              Lien de téléchargement (à donner au client)
            </p>
            <CopyLink url={DOWNLOAD_URL} />
            <div className="mt-2 flex flex-wrap items-center gap-2 rounded-md border border-accent/30 bg-accent/10 px-3 py-2">
              <span className="text-xs text-ink-secondary">Code Downloader</span>
              <span className="font-mono text-base font-bold tracking-wider text-accent-bright">
                {DOWNLOADER_CODE}
              </span>
              <span className="text-xs text-ink-secondary">TV / Fire TV, application Downloader</span>
            </div>
          </div>

          <div className="rounded-lg border border-white/10 bg-obsidian px-4 py-3">
            <p className="text-xs font-medium text-ink-secondary">État de cette box</p>
            {looking && <p className="mt-2 text-sm text-ink-secondary">Recherche…</p>}
            {!looking && !macOk && (
              <p className="mt-2 text-sm text-ink-secondary">Entre une MAC complète.</p>
            )}
            {!looking && macOk && !box && (
              <p className="mt-2 text-sm text-ink-secondary">Cette box n’est pas encore activée.</p>
            )}
            {!looking && box && (
              <div className="mt-2 space-y-2 text-sm">
                <StatusBadge
                  status={shownStatus === 'offline' ? 'offline' : shownStatus}
                  label={shownStatus === 'offline' ? 'Pas activée' : undefined}
                />
                <p className="text-ink-secondary">
                  Durée : {license ? (PLAN_FR[license.plan || ''] || license.plan || '—') : '—'}
                </p>
                <p className="text-ink-secondary">
                  Expire le : {license
                    ? (license.expires_at ? formatDateTime(license.expires_at) : 'À vie')
                    : '—'}
                </p>
              </div>
            )}
          </div>

          <fieldset>
            <legend className="mb-1.5 block text-xs font-medium text-ink-secondary">Durée</legend>
            <div className="grid grid-cols-2 gap-2">
              {PLANS.map((p) => {
                const c = costFor(p.id);
                const selected = plan === p.id;
                return (
                  <button
                    type="button"
                    key={p.id}
                    onClick={() => setPlan(p.id)}
                    className={
                      'flex items-center justify-between rounded-md border px-3 py-2 text-sm ' +
                      (selected
                        ? 'border-accent bg-accent/10 text-ink-primary'
                        : 'border-white/10 bg-slate text-ink-secondary hover:border-white/20')
                    }
                  >
                    <span>{p.label}</span>
                    {isReseller && c !== null && <span className="text-xs text-ink-secondary">{c} cr.</span>}
                  </button>
                );
              })}
            </div>
            <p className="mb-1 mt-3 text-xs font-medium text-ink-secondary">
              {isReseller ? 'Essai gratuit, 0 crédit' : 'Essai gratuit'}
            </p>
            <div className="grid grid-cols-3 gap-2">
              {TRIALS.map((t) => {
                const selected = plan === t.id;
                return (
                  <button
                    type="button"
                    key={t.id}
                    onClick={() => setPlan(t.id)}
                    className={
                      'rounded-md border px-3 py-2 text-sm ' +
                      (selected
                        ? 'border-success bg-success/10 text-ink-primary'
                        : 'border-white/10 bg-slate text-ink-secondary hover:border-white/20')
                    }
                  >
                    {t.label}
                  </button>
                );
              })}
            </div>
          </fieldset>

          <div>
            <label htmlFor="act-name" className="mb-1.5 block text-xs font-medium text-ink-secondary">
              Nom du client (optionnel)
            </label>
            <input
              id="act-name"
              value={customerName}
              onChange={(e) => setCustomerName(e.target.value)}
              placeholder="Ex. Salon de Karim"
              className={inputCls}
            />
          </div>

          {err && <Alert>{err}</Alert>}

          <button
            type="submit"
            disabled={busy || !macOk}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-obsidian hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy
              ? 'Activation en cours…'
              : !isReseller
                ? 'Activer l’application'
                : costFor(plan) === 0
                  ? 'Activer l’application (gratuit)'
                  : `Activer l’application (${costFor(plan) ?? '?'} crédits)`}
          </button>

          <div className="flex flex-col gap-2 sm:flex-row">
            <button
              type="button"
              onClick={() => setFrozen(true)}
              disabled={busy || !box || blocked}
              className="rounded-md border border-white/15 px-4 py-2.5 text-sm font-medium text-ink-primary hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Désactiver l’application
            </button>
            {box?.device.block_status === 'frozen' && (
              <button
                type="button"
                onClick={() => setFrozen(false)}
                disabled={busy}
                className="rounded-md border border-white/15 px-4 py-2.5 text-sm font-medium text-ink-primary hover:bg-white/5 disabled:opacity-40"
              >
                Réactiver l’application
              </button>
            )}
          </div>
          <p className="text-xs leading-relaxed text-ink-secondary">
            Désactiver bloque la box. Ça ne retire pas le lien des chaînes, et ça n’efface pas la date de fin.
          </p>
        </form>

        <div className="rounded-xl border border-white/10 bg-obsidian p-6">
          <h2 className="text-base font-semibold">Résultat</h2>
          {!result && !busy && (
            <p className="mt-3 text-sm leading-relaxed text-ink-secondary">
              Après activation, la date de fin s’affiche ici. La liste de chaînes n’est pas envoyée.
            </p>
          )}
          {busy && !result && (
            <p className="mt-3 text-sm text-ink-secondary" role="status">Activation en cours…</p>
          )}
          {result && (
            <div className="mt-3 space-y-3 text-sm">
              <StatusBadge status="active" label={result.renewed ? 'Durée prolongée' : 'Application activée'} />
              <Row k="MAC" v={result.mac} mono />
              <Row k="Durée" v={PLAN_FR[result.plan] || result.plan} />
              <Row k="Expire le" v={result.expires_at ? formatDateTime(result.expires_at) : 'À vie'} />
              <Row k="Crédits débités" v={String(result.credits_charged)} />
              {result.credit_balance !== null && (
                <Row k="Solde restant" v={String(result.credit_balance)} />
              )}
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}

function Row({ k, v, mono }: { k: string; v: string; mono?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-white/10 pb-2">
      <span className="text-ink-secondary">{k}</span>
      <span className={mono ? 'font-mono text-accent' : 'text-ink-primary'}>{v}</span>
    </div>
  );
}
