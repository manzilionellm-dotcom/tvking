import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { CopyLink } from '@/components/CopyLink';
import {
  activateApi, appsApi, planCostsApi, meApi,
  getCurrentUser, isOwnerRole,
  type App, type PlanCost, type ActivateResult, ApiError,
} from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

/// Page ACTIVATION — le coeur du portail revendeur.
/// Saisir la MAC d'un appareil + un plan → on cree/renouvelle la
/// licence et on debite les credits du revendeur. L'app figee est
/// debloquee a distance (pont KV->D1 cote Worker).
export function ActivatePage({ onLogout }: { onLogout: () => void }) {
  const user = getCurrentUser();
  const isReseller = !isOwnerRole(user?.role);

  const [mac, setMac] = useState('MK:');
  const [plan, setPlan] = useState('monthly');
  const [appId, setAppId] = useState('app_7motion');
  const [customerName, setCustomerName] = useState('');
  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<ActivateResult | null>(null);

  useEffect(() => {
    let active = true;
    Promise.all([appsApi.list(), planCostsApi.list()])
      .then(([a, c]) => {
        if (!active) return;
        setApps(a.items);
        setCosts(c.items);
        if (a.items[0]) setAppId(a.items[0].id);
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
      });
    // Solde du revendeur (si revendeur).
    meApi.get()
      .then((r) => { if (active) setBalance(r.user.credit_balance ?? null); })
      .catch(() => {});
    return () => { active = false; };
  }, [onLogout]);

  const costFor = (p: string): number | null => {
    const row = costs.find((c) => c.plan === p);
    return row ? row.credits : null;
  };

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    setResult(null);
    try {
      const res = await activateApi.activate({
        mac: mac.trim().toUpperCase(),
        plan,
        app_id: appId,
        customer_name: customerName.trim() || undefined,
      });
      setResult(res);
      if (res.credit_balance !== null) setBalance(res.credit_balance);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Activation impossible.');
    } finally {
      setBusy(false);
    }
  }

  const PLANS = [
    { id: 'monthly', label: '1 mois' },
    { id: 'quarterly', label: '3 mois' },
    { id: 'biannual', label: '6 mois' },
    { id: 'yearly', label: '1 an' },
    { id: 'lifetime', label: 'À vie' },
  ];

  return (
    <AppLayout
      title="Activer un appareil"
      subtitle="Saisis la MAC affichée dans l'app, choisis un plan"
      onLogout={onLogout}
      actions={
        isReseller && balance !== null ? (
          <div className="rounded-lg border border-accent/30 bg-accent/10 px-4 py-2 text-sm">
            <span className="text-ink-tertiary">Crédits&nbsp;: </span>
            <span className="font-semibold text-accent-bright">{balance}</span>
          </div>
        ) : undefined
      }
    >
      <div className="grid max-w-4xl gap-6 md:grid-cols-2">
        {/* ===== Formulaire ===== */}
        <form
          onSubmit={submit}
          className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6"
        >
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Adresse MAC de l'appareil
            </label>
            <input
              value={mac}
              onChange={(e) => setMac(e.target.value)}
              autoFocus
              placeholder="MK:1A:2B:3C:4D:5E"
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 font-mono text-sm outline-none focus:ring-1 focus:ring-accent"
            />
          </div>

          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Application
            </label>
            <select
              value={appId}
              onChange={(e) => setAppId(e.target.value)}
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
            >
              {apps.map((a) => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </select>
            {(() => {
              const dl = apps.find((a) => a.id === appId)?.download_url;
              return dl ? (
                <div className="mt-2">
                  <p className="mb-1 text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Lien de téléchargement (à donner au client)
                  </p>
                  <CopyLink url={dl} />
                </div>
              ) : null;
            })()}
          </div>

          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Plan
            </label>
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
                      'flex items-center justify-between rounded-md border px-3 py-2 text-sm transition ' +
                      (selected
                        ? 'border-accent bg-accent/10 text-ink-primary'
                        : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                    }
                  >
                    <span>{p.label}</span>
                    {c !== null && (
                      <span className="text-[11px] text-ink-tertiary">
                        {c} cr.
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>

          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Nom du client (optionnel)
            </label>
            <input
              value={customerName}
              onChange={(e) => setCustomerName(e.target.value)}
              placeholder="Ex. Salon de Karim"
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
            />
          </div>

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
              {err}
            </div>
          )}

          <button
            type="submit"
            disabled={busy || mac.trim().length < 8}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Activation…' : `Activer (${costFor(plan) ?? '?'} crédits)`}
          </button>
        </form>

        {/* ===== Résultat ===== */}
        <div className="rounded-xl border border-white/5 bg-obsidian p-6">
          {!result && (
            <p className="text-sm text-ink-tertiary">
              Le résultat de l'activation s'affichera ici. L'appareil est
              débloqué à distance dès la prochaine vérification de l'app.
            </p>
          )}
          {result && (
            <div className="space-y-3 text-sm">
              <div className="inline-flex rounded-full bg-success/15 px-3 py-1 text-xs font-semibold text-success">
                {result.renewed ? 'Licence renouvelée' : 'Appareil activé'}
              </div>
              <Row k="MAC" v={result.mac} mono />
              <Row k="Plan" v={result.plan} />
              <Row
                k="Expire le"
                v={result.expires_at ? formatDateTime(result.expires_at) : 'À vie'}
              />
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
    <div className="flex items-center justify-between border-b border-white/5 pb-2">
      <span className="text-ink-tertiary">{k}</span>
      <span className={mono ? 'font-mono text-accent' : 'text-ink-primary'}>{v}</span>
    </div>
  );
}
