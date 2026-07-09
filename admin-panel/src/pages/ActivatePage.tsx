import { FormEvent, useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { CopyLink } from '@/components/CopyLink';
import {
  activateApi, appsApi, planCostsApi, meApi,
  getCurrentUser, isOwnerRole, userCan, DOWNLOAD_URL, DOWNLOADER_CODE,
  type App, type PlanCost, type ActivateResult, ApiError,
} from '@/lib/api';
import { formatDateTime, formatMacInput } from '@/lib/utils';

/// Page ACTIVATION — UNIQUEMENT l'abonnement (licence). La gestion des
/// sources M3U/Xtream vit dans SA page dédiée « Sources » (demande
/// produit : « l'activation des apps doit être séparée de l'ajout de
/// M3U et de l'Xtream — c'est mélangé »). Après une activation réussie,
/// un bouton envoie directement sur Sources avec la MAC pré-remplie.

export function ActivatePage({ onLogout }: { onLogout: () => void }) {
  const user = getCurrentUser();
  const isReseller = !isOwnerRole(user?.role);
  const canPushSources = userCan(user, 'sources');

  // MAC pré-remplie si on arrive depuis la fiche appareil (?mac=…).
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [plan, setPlan] = useState(isReseller ? 'yearly' : 'monthly');
  const [customerName, setCustomerName] = useState('');
  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<ActivateResult | null>(null);

  // MODE LOT : activer PLUSIEURS MACs d'un coup (même plan). Une MAC par
  // ligne — pratique pour provisionner un stock de box ou migrer un parc.
  const [batchMode, setBatchMode] = useState(false);
  const [batchText, setBatchText] = useState('');
  const [batchResults, setBatchResults] = useState<
    { mac: string; ok: boolean; detail: string }[] | null
  >(null);

  // UN SEUL produit : on filtre les autres applis (NOVA+, Red Room, TV…)
  // — le client n'a qu'une app. On prend la 1re « vraie » appli.
  const primaryApp =
    apps.find((a) => !/red\s*room|nova|\btv\b/i.test(a.name)) ?? apps[0];
  const appId = primaryApp?.id ?? 'app_7motion';

  useEffect(() => {
    let active = true;
    Promise.all([appsApi.list(), planCostsApi.list()])
      .then(([a, c]) => {
        if (!active) return;
        setApps(a.items);
        setCosts(c.items);
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
      });
    meApi.get()
      .then((r) => { if (active) setBalance(r.user.credit_balance ?? null); })
      .catch(() => {});
    return () => { active = false; };
  }, [onLogout]);

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
    setBatchResults(null);

    // ----- MODE LOT : une MAC par ligne, activations séquentielles -----
    if (batchMode) {
      const macs = Array.from(new Set(
        batchText
          .split(/\r?\n/)
          .map((l) => l.trim())
          .filter(Boolean)
          .map((l) => {
            const hex = l.toUpperCase().replace(/^MK[:\s]*/, '').replace(/[^0-9A-F]/g, '');
            return hex.length === 10 ? 'MK:' + (hex.match(/.{2}/g) || []).join(':') : l.toUpperCase();
          }),
      ));
      if (macs.length === 0) {
        setErr('Colle au moins une MAC (une par ligne).');
        setBusy(false);
        return;
      }
      const results: { mac: string; ok: boolean; detail: string }[] = [];
      for (const m of macs) {
        if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
          results.push({ mac: m, ok: false, detail: 'MAC invalide' });
          continue;
        }
        try {
          const r = await activateApi.activate({ mac: m, plan, app_id: appId });
          results.push({
            mac: m, ok: true,
            detail: (r.renewed ? 'renouvelé' : 'activé')
              + (r.expires_at ? ` → ${formatDateTime(r.expires_at)}` : ' → à vie'),
          });
          if (r.credit_balance !== null) setBalance(r.credit_balance);
        } catch (e: any) {
          if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
          results.push({ mac: m, ok: false, detail: e instanceof ApiError ? e.message : 'Échec' });
        }
        setBatchResults([...results]); // progression visible au fil de l'eau
      }
      setBusy(false);
      return;
    }

    const m = mac.trim().toUpperCase();
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
      setErr('MAC invalide. Format attendu : MK:XX:XX:XX:XX:XX');
      setBusy(false);
      return;
    }
    try {
      const res = await activateApi.activate({
        mac: m, plan, app_id: appId,
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

  const PLANS = isReseller
    ? [{ id: 'yearly', label: '1 an' }, { id: 'lifetime', label: 'À vie' }]
    : [{ id: 'monthly', label: '1 mois' }, { id: 'yearly', label: '1 an' }, { id: 'lifetime', label: 'À vie' }];
  const TRIALS = [
    { id: 'trial_24h', label: 'Test 24 h' },
    { id: 'trial_48h', label: 'Test 48 h' },
    { id: 'trial_7d', label: 'Test 7 jours' },
  ];

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Activer un appareil"
      subtitle="Abonnement uniquement — instantané sur la TV. Les sources M3U/Xtream ont leur page dédiée."
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
        <form onSubmit={submit} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          {/* Un appareil ↔ Lot (plusieurs MACs, même plan) */}
          <div className="grid grid-cols-2 gap-2">
            {([['single', 'Un appareil'], ['batch', 'En lot (plusieurs MACs)']] as const).map(([m, label]) => {
              const selected = batchMode === (m === 'batch');
              return (
                <button
                  type="button"
                  key={m}
                  onClick={() => { setBatchMode(m === 'batch'); setErr(null); setResult(null); setBatchResults(null); }}
                  className={
                    'rounded-md border px-3 py-2 text-sm transition ' +
                    (selected
                      ? 'border-accent bg-accent/10 text-ink-primary'
                      : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                  }
                >
                  {label}
                </button>
              );
            })}
          </div>

          {!batchMode && (
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Adresse MAC de l'appareil
              </label>
              <input
                value={mac}
                onChange={(e) => setMac(formatMacInput(e.target.value))}
                autoFocus
                maxLength={17}
                placeholder="MK:1A:2B:3C:4D:5E"
                className={inputCls + ' font-mono'}
              />
            </div>
          )}
          {batchMode && (
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                MACs à activer — une par ligne (doublons ignorés)
              </label>
              <textarea
                value={batchText}
                onChange={(e) => setBatchText(e.target.value)}
                rows={6}
                placeholder={'MK:1A:2B:3C:4D:5E\nMK:AA:BB:CC:DD:EE\n…'}
                className={inputCls + ' resize-y font-mono'}
              />
            </div>
          )}

          {/* Téléchargement à donner au client : le lien propre OU le code
              Downloader officiel (TV / Fire TV). Domaine app.7themotion.com. */}
          <div>
            <p className="mb-1 text-[10px] uppercase tracking-widest text-ink-tertiary">
              Lien de téléchargement (à donner au client)
            </p>
            <CopyLink url={DOWNLOAD_URL} />
            <div className="mt-2 flex items-center gap-2 rounded-md border border-accent/30 bg-accent/10 px-3 py-2">
              <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                Code Downloader
              </span>
              <span className="font-mono text-base font-bold tracking-wider text-accent-bright">
                {DOWNLOADER_CODE}
              </span>
              <span className="text-[11px] text-ink-tertiary">
                (TV / Fire TV → app « Downloader »)
              </span>
            </div>
          </div>

          {/* Plan */}
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
                    {/* Le coût en crédits ne concerne QUE les revendeurs.
                        L'owner (super admin) active gratuitement et sans
                        limite → on ne lui montre aucun crédit. */}
                    {isReseller && c !== null && <span className="text-[11px] text-ink-tertiary">{c} cr.</span>}
                  </button>
                );
              })}
            </div>
            <div className="mt-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
              {isReseller ? 'Essai gratuit · 0 crédit' : 'Essai gratuit'}
            </div>
            <div className="mt-1 grid grid-cols-3 gap-2">
              {TRIALS.map((t) => {
                const selected = plan === t.id;
                return (
                  <button
                    type="button"
                    key={t.id}
                    onClick={() => setPlan(t.id)}
                    className={
                      'flex items-center justify-between rounded-md border px-3 py-2 text-sm transition ' +
                      (selected
                        ? 'border-success bg-success/10 text-ink-primary'
                        : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                    }
                  >
                    <span>{t.label}</span>
                    <span className="text-[11px] text-success">gratuit</span>
                  </button>
                );
              })}
            </div>
          </div>

          {!batchMode && (
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Nom du client (optionnel)
              </label>
              <input
                value={customerName}
                onChange={(e) => setCustomerName(e.target.value)}
                placeholder="Ex. Salon de Karim"
                className={inputCls}
              />
            </div>
          )}

          {/* Renvoi clair vers la page dédiée — plus de mélange ici. */}
          {canPushSources && (
            <div className="rounded-md border border-white/10 bg-slate/30 px-3 py-2 text-xs text-ink-tertiary">
              Les playlists M3U / Xtream se gèrent dans{' '}
              <Link
                to={/^MK(?::[0-9A-F]{2}){5}$/i.test(mac.trim()) ? `/sources?mac=${encodeURIComponent(mac.trim().toUpperCase())}` : '/sources'}
                className="font-medium text-accent-bright hover:underline"
              >
                Sources M3U / Xtream
              </Link>{' '}
              — test en direct et livraison instantanée.
            </div>
          )}

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
          )}

          <button
            type="submit"
            disabled={busy || (batchMode ? !batchText.trim() : mac.trim().length < 8)}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy
              ? 'Activation…'
              : batchMode
                ? `Activer le lot${isReseller && costFor(plan) ? ` (${costFor(plan)} cr. / MAC)` : ''}`
                : !isReseller
                  /* Owner : activation gratuite et illimitée, jamais de crédit. */
                  ? 'Activer'
                  : costFor(plan) === 0
                    ? 'Activer (gratuit)'
                    : `Activer (${costFor(plan) ?? '?'} crédits)`}
          </button>
        </form>

        {/* ===== Résultat ===== */}
        <div className="rounded-xl border border-white/5 bg-obsidian p-6">
          {!result && !batchResults && (
            <p className="text-sm text-ink-tertiary">
              Le résultat de l'activation s'affichera ici. L'appareil est
              débloqué INSTANTANÉMENT : l'app détecte l'activation en
              quelques secondes, sans redémarrage.
            </p>
          )}
          {batchResults && (
            <div className="space-y-2 text-sm">
              <div className="inline-flex rounded-full bg-success/15 px-3 py-1 text-xs font-semibold text-success">
                Lot : {batchResults.filter((r) => r.ok).length}/{batchResults.length} activé(s)
              </div>
              <ul className="max-h-96 space-y-1 overflow-y-auto">
                {batchResults.map((r, i) => (
                  <li key={i}
                    className={
                      'flex items-center justify-between gap-2 rounded-md border px-3 py-1.5 text-xs ' +
                      (r.ok ? 'border-success/20 bg-success/5' : 'border-accent/20 bg-accent/5')
                    }>
                    <span className="font-mono">{r.mac}</span>
                    <span className={r.ok ? 'text-success' : 'text-accent-bright'}>{r.detail}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {result && (
            <div className="space-y-3 text-sm">
              <div className="inline-flex rounded-full bg-success/15 px-3 py-1 text-xs font-semibold text-success">
                {result.renewed ? 'Licence renouvelée' : 'Appareil activé'} · livré à l'appareil
              </div>
              <Row k="MAC" v={result.mac} mono />
              <Row k="Plan" v={result.plan} />
              <Row k="Expire le" v={result.expires_at ? formatDateTime(result.expires_at) : 'À vie'} />
              <Row k="Crédits débités" v={String(result.credits_charged)} />
              {result.credit_balance !== null && (
                <Row k="Solde restant" v={String(result.credit_balance)} />
              )}
              {canPushSources && (
                <Link
                  to={`/sources?mac=${encodeURIComponent(result.mac)}`}
                  className="mt-2 block w-full rounded-md border border-accent/40 bg-accent/10 px-4 py-2.5 text-center text-sm font-semibold text-accent-bright transition hover:bg-accent/20"
                >
                  Étape suivante : pousser ses sources M3U / Xtream →
                </Link>
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
