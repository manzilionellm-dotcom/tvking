import { FormEvent, useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { BoxTargetPreview } from '@/components/BoxTargetPreview';
import { Alert } from '@/components/ui';
import { PlanPicker } from '@/components/PlanPicker';
import {
  activateApi, appsApi, planCostsApi, meApi,
  getCurrentUser, isOwnerRole, userCan,
  DOWNLOAD_URL, DOWNLOADER_CODE, DOWNLOAD_URL_TV, DOWNLOADER_CODE_TV,
  type App, type PlanCost, type ActivateResult, ApiError,
  newIdempotencyKey, keepIdempotencyKeyAfter,
} from '@/lib/api';
import {
  DEFAULT_PLAN, activateButtonText, activationResultText, planCost,
} from '@/lib/activation';
import { useT } from '@/lib/i18n';
import { formatDateTime, isValidMac, normalizeMac } from '@/lib/utils';
import { createSingleFlight } from '@/lib/robust';

// =========================================================
//  Activer une box — l'UNIQUE écran d'activation du panel
// =========================================================
//  Remplace (06/10/2026) deux écrans qui faisaient le même geste avec des
//  choix différents : « Grande activation de toutes les applications » et
//  « Activation à distance ». L'ancienne adresse /activation-distance mène
//  ici (App.tsx), MAC comprise.
//
//  Ici : la licence, et seulement elle. MAC (comme sur la box, « MK: »
//  ajouté tout seul), nom du client, durée (essai gratuit ou abonnement),
//  un bouton. Les listes de chaînes se gèrent dans « Listes » (/chaines) :
//  décision du propriétaire, « listes à part, applications à part ».
//
//  La box est prévenue tout de suite par le Worker (ordre « activate » ou
//  « renew »). Clé d'idempotence : un second envoi de la même intention
//  (coupure, double appui) rejoue la réponse au lieu de redébiter.
// =========================================================

export function ActivatePage({ onLogout }: { onLogout: () => void }) {
  const t = useT();
  const user = getCurrentUser();
  const isReseller = !isOwnerRole(user?.role);
  const canLists = !isReseller || userCan(user, 'sources');

  // ?mac=… : la fiche appareil, les clients et l'ancienne adresse
  // /activation-distance pré-remplissent la MAC.
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || '');
  const [plan, setPlan] = useState(DEFAULT_PLAN);
  const [customerName, setCustomerName] = useState('');
  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<{ res: ActivateResult; plan: string } | null>(null);
  const flight = useRef(createSingleFlight());
  const idem = useRef<string | null>(null);

  // Application à activer : la première app « principale » du panel
  // (ni Red Room, ni Nova, ni TV) ; repli sur app_7motion si la liste
  // n'est pas chargée. Même règle qu'avant.
  const primaryApp =
    apps.find((a) => !/red\s*room|nova|\btv\b/i.test(a.name)) ?? apps[0];
  const appId = primaryApp?.id ?? 'app_7motion';
  const normalized = normalizeMac(mac);
  const macOk = isValidMac(normalized);

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

  // Changer la MAC ou la durée = une autre intention : nouvelle clé.
  function changePlan(p: string) { setPlan(p); idem.current = null; setResult(null); }
  function changeMac(v: string) { setMac(v); idem.current = null; setResult(null); }

  async function submit(e: FormEvent) {
    e.preventDefault();
    await flight.current.run(async () => {
      setErr(null);
      setResult(null);
      if (!macOk) {
        setErr('MAC invalide. Tape-la comme sur la box, par exemple AD:A6:98:70:6A (le « MK: » est ajouté tout seul).');
        return;
      }
      setMac(normalized);
      setBusy(true);
      try {
        const key = idem.current ?? (idem.current = newIdempotencyKey());
        const res = await activateApi.activate({
          mac: normalized, plan, app_id: appId,
          customer_name: customerName.trim() || undefined,
        }, key);
        idem.current = null;
        setResult({ res, plan });
        if (res.credit_balance !== null) setBalance(res.credit_balance);
      } catch (e2: unknown) {
        if (!keepIdempotencyKeyAfter(e2)) idem.current = null;
        if (e2 instanceof ApiError && e2.status === 401) { onLogout(); return; }
        setErr(e2 instanceof ApiError ? e2.message : 'Activation impossible. Réessaie.');
      } finally {
        setBusy(false);
      }
    });
  }

  const inputCls =
    'w-full rounded-lg border border-white/10 bg-slate px-3 py-3 text-base outline-none focus:border-accent/60 focus:ring-2 focus:ring-accent/40';
  const listsHref = `/chaines${macOk ? `?mac=${encodeURIComponent(normalized)}` : ''}`;

  return (
    <AppLayout
      title={t('nav.activate')}
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
            Adresse MAC (comme sur la box)
          </label>
          <input
            id="act-mac"
            value={mac}
            disabled={busy}
            onChange={(e) => changeMac(e.target.value)}
            onBlur={() => setMac((v) => (v.trim() ? normalizeMac(v) : v))}
            autoFocus
            autoComplete="off"
            autoCapitalize="characters"
            spellCheck={false}
            placeholder="AD:A6:98:70:6A"
            className={inputCls + ' font-mono'}
          />
        </div>

        <BoxTargetPreview mac={mac} />

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

        <PlanPicker value={plan} onChange={changePlan} costs={costs} showCosts={isReseller} />

        {err && <Alert>{err}</Alert>}
        {result && (
          <p className="rounded-xl border border-emerald-400/30 bg-emerald-400/10 px-4 py-3 text-sm text-ink-primary" role="status">
            ✓ {activationResultText(result.plan, result.res, formatDateTime)} La box est prévenue à l’instant.
          </p>
        )}

        <button
          type="submit"
          disabled={busy || !mac.trim()}
          className="w-full rounded-xl bg-accent px-4 py-3.5 text-base font-semibold text-obsidian hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? 'Activation…' : activateButtonText(plan, planCost(plan, costs), isReseller)}
        </button>

        {canLists && (
          <p className="text-sm leading-relaxed text-ink-secondary">
            Les listes de chaînes se gèrent à part :{' '}
            <Link to={listsHref} className="font-medium text-accent-bright underline-offset-2 hover:underline">
              {t('nav.chaines')}
            </Link>.
          </p>
        )}

        <div className="space-y-1 border-t border-white/5 pt-4 text-xs leading-relaxed text-ink-tertiary">
          <p className="font-medium uppercase tracking-wide">Installer l’application</p>
          <CopyLine label="Téléphone" url={DOWNLOAD_URL} code={DOWNLOADER_CODE} />
          <CopyLine label="TV" url={DOWNLOAD_URL_TV} code={DOWNLOADER_CODE_TV} />
        </div>
      </form>
    </AppLayout>
  );
}

/// Lien d'installation + code Downloader, chacun copiable d'un appui.
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
    <div className="py-1">
      <p className="flex items-baseline gap-2">
        <span className="text-ink-secondary">{label}</span>
        <button type="button" onClick={() => copy(code, 'code')} className="font-mono text-ink-secondary" title="Code Downloader : appuie pour copier">
          {copied === 'code' ? 'Copié' : `code ${code}`}
        </button>
      </p>
      <button type="button" onClick={() => copy(url, 'url')} className="block max-w-full truncate font-mono text-ink-secondary underline-offset-2 hover:underline" title="Appuie pour copier">
        {copied === 'url' ? 'Copié' : url}
      </button>
    </div>
  );
}
