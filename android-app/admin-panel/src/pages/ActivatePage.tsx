import { FormEvent, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { CopyLink } from '@/components/CopyLink';
import {
  activateApi, appsApi, planCostsApi, meApi, sourcesApi,
  getCurrentUser, isOwnerRole, userCan, DOWNLOAD_URL, DOWNLOADER_CODE,
  type App, type PlanCost, type ActivateResult,
  type DeviceSourceInput, ApiError,
} from '@/lib/api';
import { buildPushedSource, type OpenPanelKind } from '@/lib/openSource';
import { formatDateTime } from '@/lib/utils';

/// Page ACTIVATION — TOUT-EN-UN (demande client : « un seul qui regroupe
/// tout »). Une MAC → on pose la licence ET on pousse un TRIO de sources
/// (0 à 6). Le client est débloqué et configuré automatiquement à
/// distance. La page « Pousser une playlist » est fusionnée ici.

type SrcDraft = {
  type: OpenPanelKind;
  serverUrl: string;
  xtUser: string;
  xtPass: string;
  m3uUrl: string;
};
const blankSrc = (): SrcDraft => ({
  type: 'xtream', serverUrl: '',
  xtUser: '', xtPass: '', m3uUrl: '',
});
const MAX_SOURCES = 6; // aligné sur MAX_SOURCES_PER_DEVICE du Worker (api_v1.js)

export function ActivatePage({ onLogout }: { onLogout: () => void }) {
  const user = getCurrentUser();
  const isReseller = !isOwnerRole(user?.role);
  // Pousser des sources = capacité 'sources' (revendeur standard+ ou admin).
  const canPushSources = userCan(user, 'sources');

  // MAC pré-remplie si on arrive depuis la fiche appareil (?mac=…).
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [plan, setPlan] = useState(isReseller ? 'yearly' : 'monthly');
  const [customerName, setCustomerName] = useState('');
  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);
  // TRIO : 0 à 6 sources poussées avec l'activation (optionnel).
  // Plus de menu « Serveur 1 » : on écrit l'adresse.
  const [items, setItems] = useState<SrcDraft[]>([]);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<ActivateResult | null>(null);

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

  // ----- helpers TRIO -----
  function patch(i: number, p: Partial<SrcDraft>) {
    setItems((prev) => prev.map((it, idx) => (idx === i ? { ...it, ...p } : it)));
  }
  function addItem() {
    if (items.length < MAX_SOURCES) {
      setItems((prev) => [...prev, blankSrc()]);
    }
  }
  function removeItem(i: number) {
    setItems((prev) => prev.filter((_, idx) => idx !== i));
  }
  function buildSource(it: SrcDraft): DeviceSourceInput | { error: string } | null {
    const built = buildPushedSource({
      type: it.type,
      serverUrl: it.serverUrl,
      username: it.xtUser,
      password: it.xtPass,
      link: it.m3uUrl,
    });
    if ('error' in built) return built;
    return built.source;
  }

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
    const m = mac.trim().toUpperCase();
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
      setErr('MAC invalide. Format attendu : MK:XX:XX:XX:XX:XX');
      setBusy(false);
      return;
    }
    // Construit le trio (chaque bloc ajouté doit être complet).
    const sources: DeviceSourceInput[] = [];
    for (let i = 0; i < items.length; i++) {
      const s = buildSource(items[i]);
      if (!s || 'error' in s) {
        setErr(s && 'error' in s
          ? `Source ${i + 1} : ${s.error}`
          : `Source ${i + 1} incomplète.`);
        setBusy(false);
        return;
      }
      sources.push(s);
    }
    try {
      // 1) Licence (débloque l'app). 2) Trio de sources (auto-chargé).
      const res = await activateApi.activate({
        mac: m, plan, app_id: appId,
        customer_name: customerName.trim() || undefined,
      });
      if (sources.length > 0) {
        await sourcesApi.setMany(m, sources);
      }
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
      subtitle="Une MAC → licence + sources, tout d'un coup. Le client est configuré automatiquement."
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
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Adresse MAC de l'appareil
            </label>
            <input
              value={mac}
              onChange={(e) => setMac(e.target.value)}
              autoFocus
              placeholder="MK:1A:2B:3C:4D:5E"
              className={inputCls + ' font-mono'}
            />
          </div>

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

          {/* ===== TRIO de sources (0 à 6) — masqué si niveau insuffisant ===== */}
          {canPushSources && (
          <div className="rounded-lg border border-white/5 bg-slate/40 p-3">
            <label className="mb-2 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Sources du client — chargées automatiquement (jusqu'à 6)
            </label>

            {items.map((it, i) => (
              <div key={i} className="mb-2 rounded-md border border-white/10 bg-slate/30 p-3">
                <div className="mb-2 flex items-center justify-between">
                  <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">Source {i + 1}</span>
                  <button type="button" onClick={() => removeItem(i)} className="text-xs text-ink-tertiary hover:text-accent-bright">
                    Retirer
                  </button>
                </div>
                <div className="mb-2 grid grid-cols-3 gap-2">
                  {([
                    ['xtream', 'Xtream Codes'],
                    ['m3u', 'M3U'],
                    ['player', 'Lien lecteur'],
                  ] as const).map(([t, label]) => (
                    <button
                      type="button"
                      key={t}
                      onClick={() => patch(i, { type: t })}
                      className={
                        'rounded-md border px-3 py-2 text-sm transition ' +
                        (it.type === t
                          ? 'border-accent bg-accent/10 text-ink-primary'
                          : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                      }
                    >
                      {label}
                    </button>
                  ))}
                </div>
                {it.type === 'xtream' && (
                  <div className="space-y-2">
                    <input value={it.serverUrl} onChange={(e) => patch(i, { serverUrl: e.target.value })}
                      placeholder="http://exemple.test:8080" className={inputCls + ' font-mono'} />
                    <input value={it.xtUser} onChange={(e) => patch(i, { xtUser: e.target.value })}
                      placeholder="Utilisateur" className={inputCls} />
                    <input value={it.xtPass} onChange={(e) => patch(i, { xtPass: e.target.value })}
                      placeholder="Mot de passe" className={inputCls} />
                  </div>
                )}
                {it.type !== 'xtream' && (
                  <input value={it.m3uUrl} onChange={(e) => patch(i, { m3uUrl: e.target.value })}
                    placeholder={it.type === 'player'
                      ? 'http://exemple.test:8080/get.php?username=…&password=…'
                      : 'http://exemple.test/liste.m3u'}
                    className={inputCls + ' font-mono'} />
                )}
              </div>
            ))}

            {items.length < MAX_SOURCES && (
              <button type="button" onClick={addItem}
                className="w-full rounded-md border border-dashed border-white/15 px-3 py-2 text-sm text-ink-secondary transition hover:border-accent/50 hover:text-accent-bright">
                {items.length === 0
                  ? '+ Ajouter une source'
                  : `+ Ajouter une source (trio — ${items.length}/${MAX_SOURCES})`}
              </button>
            )}
          </div>
          )}

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
          )}

          <button
            type="submit"
            disabled={busy || mac.trim().length < 8}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy
              ? 'Activation…'
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
          {!result && (
            <p className="text-sm text-ink-tertiary">
              Le résultat de l'activation s'affichera ici. L'appareil est débloqué et
              configuré (licence + sources) à distance dès la prochaine vérification de l'app.
            </p>
          )}
          {result && (
            <div className="space-y-3 text-sm">
              <div className="inline-flex rounded-full bg-success/15 px-3 py-1 text-xs font-semibold text-success">
                {result.renewed ? 'Licence renouvelée' : 'Appareil activé'}
              </div>
              <Row k="MAC" v={result.mac} mono />
              <Row k="Plan" v={result.plan} />
              <Row k="Expire le" v={result.expires_at ? formatDateTime(result.expires_at) : 'À vie'} />
              <Row k="Crédits débités" v={String(result.credits_charged)} />
              {result.credit_balance !== null && (
                <Row k="Solde restant" v={String(result.credit_balance)} />
              )}
              {items.length > 0 && <Row k="Sources poussées" v={String(items.length)} />}
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
