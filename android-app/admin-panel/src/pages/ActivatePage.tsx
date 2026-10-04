import { FormEvent, useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { Alert } from '@/components/ui';
import {
  activateApi, appsApi, planCostsApi, meApi,
  getCurrentUser, isOwnerRole,
  DOWNLOAD_URL, DOWNLOADER_CODE, DOWNLOAD_URL_TV, DOWNLOADER_CODE_TV,
  type App, type PlanCost, type ActivateResult, type TrialExtendResult, ApiError,
} from '@/lib/api';
import { formatDateTime, isValidMac, normalizeMac } from '@/lib/utils';
import { createSingleFlight } from '@/lib/robust';

// Écran d'activation — volontairement court.
// MAC, nom (optionnel), deux durées (1 an / à vie), bouton Activer,
// et un petit bloc pour ajouter des jours d'essai.
// Un seul appareil à la fois. Les liens client restent en bas, en petit.

const QUICK_DAYS = [3, 7, 14, 30];
const MAX_DAYS = 365;

const PLANS = [
  { id: 'yearly', label: 'Activation 1 an' },
  { id: 'lifetime', label: 'Activation à vie' },
];

export function ActivatePage({ onLogout }: { onLogout: () => void }) {
  const user = getCurrentUser();
  const isReseller = !isOwnerRole(user?.role);

  // ?mac=… : les autres écrans (appareils, liste de chaînes) pré-remplissent la MAC.
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [plan, setPlan] = useState('yearly');
  const [customerName, setCustomerName] = useState('');
  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<ActivateResult | null>(null);
  const flight = useRef(createSingleFlight());

  const [daysChoice, setDaysChoice] = useState('7');
  const [daysBusy, setDaysBusy] = useState(false);
  const [daysErr, setDaysErr] = useState<string | null>(null);
  const [daysOk, setDaysOk] = useState<TrialExtendResult | null>(null);

  // Application à activer : la première app « principale » du panel
  // (ni Red Room, ni Nova, ni TV) ; repli sur app_7motion si la liste
  // n'est pas chargée. Même règle que l'écran précédent.
  const primaryApp =
    apps.find((a) => !/red\s*room|nova|\btv\b/i.test(a.name)) ?? apps[0];
  const appId = primaryApp?.id ?? 'app_7motion';
  const macOk = isValidMac(mac);

  useEffect(() => {
    let active = true;
    planCostsApi.list()
      .then((c) => { if (active) setCosts(c.items); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
      });
    appsApi.list()
      .then((a) => { if (active) setApps(a.items); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        // Sinon : repli silencieux sur app_7motion.
      });
    meApi.get()
      .then((r) => { if (active) setBalance(r.user.credit_balance ?? null); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
      });
    return () => { active = false; };
  }, [onLogout]);

  const costFor = (p: string): number | null => {
    const row = costs.find((c) => c.plan === p);
    return row ? row.credits : null;
  };

  async function submit(e: FormEvent) {
    e.preventDefault();
    await flight.current.run(async () => {
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
    });
  }

  function parsedDays(): number | null {
    const s = daysChoice.trim();
    if (!/^[0-9]+$/.test(s)) return null;
    const n = Number(s);
    if (!Number.isInteger(n) || n < 1 || n > MAX_DAYS) return null;
    return n;
  }

  async function addDays() {
    setDaysErr(null);
    setDaysOk(null);
    const m = normalizeMac(mac);
    if (!isValidMac(m)) {
      setDaysErr('Indique d’abord une MAC valide, en haut.');
      return;
    }
    const n = parsedDays();
    if (n == null) {
      setDaysErr(`Jours : un entier de 1 à ${MAX_DAYS}.`);
      return;
    }
    setDaysBusy(true);
    try {
      const res = await activateApi.extendTrial(m, n);
      setDaysOk(res);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setDaysErr(e instanceof ApiError ? e.message : 'Ajout impossible.');
    } finally {
      setDaysBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-lg border border-white/10 bg-slate px-3 py-3 text-base outline-none focus:border-accent/60 focus:ring-2 focus:ring-accent/40';

  const credit = costFor(plan);

  return (
    <AppLayout
      title="Activation"
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
        <div>
          <label htmlFor="act-mac" className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-ink-secondary">
            Adresse MAC
          </label>
          <input
            id="act-mac"
            value={mac}
            onChange={(e) => setMac(e.target.value)}
            onBlur={() => setMac((v) => normalizeMac(v))}
            autoFocus
            autoComplete="off"
            inputMode="text"
            placeholder="MK:XX:XX:XX:XX:XX"
            className={inputCls + ' font-mono'}
          />
        </div>

        <div>
          <label htmlFor="act-name" className="mb-1.5 block text-xs font-medium uppercase tracking-wide text-ink-secondary">
            Nom du client <span className="normal-case tracking-normal text-ink-tertiary">(optionnel)</span>
          </label>
          <input
            id="act-name"
            value={customerName}
            onChange={(e) => setCustomerName(e.target.value)}
            placeholder="Ex. Salon de Karim"
            className={inputCls}
          />
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2" role="group" aria-label="Durée">
          {PLANS.map((p) => {
            const selected = plan === p.id;
            const c = costFor(p.id);
            return (
              <button
                type="button"
                key={p.id}
                onClick={() => setPlan(p.id)}
                className={
                  'rounded-xl border px-4 py-5 text-left transition ' +
                  (selected
                    ? 'border-accent bg-accent/15 text-ink-primary'
                    : 'border-white/10 bg-midnight text-ink-secondary hover:border-white/25')
                }
              >
                <span className="block text-lg font-semibold leading-tight">{p.label}</span>
                {isReseller && c !== null && (
                  <span className="mt-1 block text-xs text-ink-tertiary">
                    {c} crédit{c > 1 ? 's' : ''}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {err && <Alert>{err}</Alert>}
        {result && (
          <p className="text-sm text-ink-primary" role="status">
            {result.plan === 'lifetime' || result.expires_at == null
              ? 'Activé à vie.'
              : `Activé jusqu’au ${formatDateTime(result.expires_at)}.`}
          </p>
        )}

        <button
          type="submit"
          disabled={busy || !macOk}
          className="w-full rounded-xl bg-accent px-4 py-3.5 text-base font-semibold text-obsidian hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy
            ? 'Activation…'
            : isReseller && credit !== null
              ? `Activer · ${credit} crédit${credit > 1 ? 's' : ''}`
              : 'Activer'}
        </button>

        {!isReseller && (
          <div className="space-y-3 rounded-xl border border-white/10 bg-midnight/60 p-4">
            <p className="text-sm font-medium text-ink-primary">Ajouter des jours d’essai</p>
            <div className="flex flex-wrap gap-2">
              {QUICK_DAYS.map((d) => {
                const on = daysChoice === String(d);
                return (
                  <button
                    type="button"
                    key={d}
                    onClick={() => setDaysChoice(String(d))}
                    className={
                      'rounded-lg border px-3 py-2 text-sm ' +
                      (on
                        ? 'border-accent bg-accent/15 text-ink-primary'
                        : 'border-white/10 text-ink-secondary')
                    }
                  >
                    {d} j
                  </button>
                );
              })}
            </div>
            <label className="block text-xs text-ink-tertiary" htmlFor="act-days">
              Nombre de jours
            </label>
            <input
              id="act-days"
              value={daysChoice}
              onChange={(e) => setDaysChoice(e.target.value)}
              inputMode="numeric"
              className={inputCls + ' font-mono'}
            />
            {daysErr && <Alert>{daysErr}</Alert>}
            {daysOk && (
              <p className="text-sm text-ink-primary" role="status">
                Essai jusqu’au {formatDateTime(daysOk.trial_until)}.
              </p>
            )}
            <button
              type="button"
              onClick={addDays}
              disabled={daysBusy || !macOk}
              className="w-full rounded-lg border border-white/15 px-4 py-2.5 text-sm font-semibold text-ink-primary hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {daysBusy ? 'Ajout…' : 'Ajouter les jours'}
            </button>
          </div>
        )}

        <p className="text-sm leading-relaxed text-ink-secondary">
          Le lien de la liste de chaînes est sur un autre écran :{' '}
          <Link to={macOk ? `/chaines?mac=${encodeURIComponent(normalizeMac(mac))}` : '/chaines'} className="font-medium text-accent-bright underline-offset-2 hover:underline">
            Liste de chaînes
          </Link>.
        </p>

        <div className="space-y-1 pt-2 text-xs leading-relaxed text-ink-tertiary">
          <CopyLine label="Mobile" url={DOWNLOAD_URL} code={DOWNLOADER_CODE} />
          <CopyLine label="TV" url={DOWNLOAD_URL_TV} code={DOWNLOADER_CODE_TV} />
        </div>
      </form>
    </AppLayout>
  );
}

function CopyLine({ label, url, code }: { label: string; url: string; code: string }) {
  const [copied, setCopied] = useState<'url' | 'code' | null>(null);
  async function copy(text: string, which: 'url' | 'code') {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(which);
      setTimeout(() => setCopied(null), 1200);
    } catch { /* copie manuelle possible */ }
  }
  return (
    <p className="flex flex-wrap items-center gap-x-2 gap-y-1">
      <span>{label}</span>
      <button type="button" onClick={() => copy(url, 'url')} className="truncate font-mono text-ink-secondary underline-offset-2 hover:underline">
        {copied === 'url' ? 'Copié' : url}
      </button>
      <button type="button" onClick={() => copy(code, 'code')} className="font-mono text-ink-secondary">
        {copied === 'code' ? 'Copié' : code}
      </button>
    </p>
  );
}
