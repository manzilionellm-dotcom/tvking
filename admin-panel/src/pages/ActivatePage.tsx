import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { CopyLink } from '@/components/CopyLink';
import {
  activateApi, appsApi, planCostsApi, meApi, serversApi,
  getCurrentUser, isOwnerRole,
  type App, type PlanCost, type ActivateResult, type DefaultServer,
  type DeviceSourceInput, ApiError,
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
  // Plan par défaut selon le rôle : l'administrateur démarre sur « 1 mois »
  // (réservé), le revendeur sur « 1 an » (son plan d'entrée).
  const [plan, setPlan] = useState(isReseller ? 'yearly' : 'monthly');
  const [appId, setAppId] = useState('app_7motion');
  const [customerName, setCustomerName] = useState('');
  const [apps, setApps] = useState<App[]>([]);
  const [costs, setCosts] = useState<PlanCost[]>([]);
  const [balance, setBalance] = useState<number | null>(null);

  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<ActivateResult | null>(null);

  // ----- Source du client (optionnelle, poussée par MAC) -----
  // 'none' = on n'assigne pas de source (juste licence). 'xtream'/'m3u'
  // = on pousse la source que l'app chargera automatiquement.
  const [srcType, setSrcType] = useState<'none' | 'xtream' | 'm3u'>('none');
  const [servers, setServers] = useState<DefaultServer[]>([]);
  // Pour Xtream : on peut choisir un serveur prédéfini (Serveur 1/2/3…)
  // ou saisir une URL manuelle ('custom').
  const [serverChoice, setServerChoice] = useState<string>('custom');
  const [serverUrl, setServerUrl] = useState('');
  const [xtUser, setXtUser] = useState('');
  const [xtPass, setXtPass] = useState('');
  const [m3uUrl, setM3uUrl] = useState('');

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
    // Serveurs prédéfinis (pour assigner un Xtream rapidement).
    serversApi.list()
      .then((r) => {
        if (!active) return;
        setServers(r.items);
        if (r.items[0]) {
          setServerChoice(r.items[0].id);
          setServerUrl(r.items[0].url);
        }
      })
      .catch(() => {});
    return () => { active = false; };
  }, [onLogout]);

  // Construit l'objet source à envoyer (ou undefined si 'none' / invalide).
  function buildSource(): DeviceSourceInput | undefined {
    if (srcType === 'xtream') {
      if (!serverUrl.trim() || !xtUser.trim() || !xtPass.trim()) return undefined;
      const chosen = servers.find((s) => s.id === serverChoice);
      return {
        type: 'xtream',
        label: chosen?.label ?? null,
        server_url: serverUrl.trim(),
        username: xtUser.trim(),
        password: xtPass.trim(),
      };
    }
    if (srcType === 'm3u') {
      if (!m3uUrl.trim()) return undefined;
      return { type: 'm3u', m3u_url: m3uUrl.trim() };
    }
    return undefined;
  }

  const costFor = (p: string): number | null => {
    // Les essais sont toujours gratuits (0 crédit), même s'ils ne sont
    // pas dans la table plan_costs.
    if (p.startsWith('trial')) return 0;
    const row = costs.find((c) => c.plan === p);
    return row ? row.credits : null;
  };

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    setResult(null);
    const source = buildSource();
    if (srcType !== 'none' && !source) {
      setErr(
        srcType === 'xtream'
          ? 'Xtream : serveur, utilisateur et mot de passe sont obligatoires.'
          : 'M3U : l\'URL est obligatoire.',
      );
      setBusy(false);
      return;
    }
    try {
      const res = await activateApi.activate({
        mac: mac.trim().toUpperCase(),
        plan,
        app_id: appId,
        customer_name: customerName.trim() || undefined,
        source,
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

  // Plans proposés selon le rôle.
  //   - Revendeur : 1 an (1 crédit) et à vie (2 crédits) UNIQUEMENT.
  //   - Administrateur : peut en plus activer « 1 mois » (réservé).
  // Le « 1 mois » est aussi bloqué côté serveur (api_v1.js) : masquer
  // le bouton ne suffit pas, on refuse l'appel API d'un revendeur.
  const PLANS = isReseller
    ? [
        { id: 'yearly', label: '1 an' },
        { id: 'lifetime', label: 'À vie' },
      ]
    : [
        { id: 'monthly', label: '1 mois' },
        { id: 'yearly', label: '1 an' },
        { id: 'lifetime', label: 'À vie' },
      ];

  // Essais GRATUITS (0 crédit) — pour faire tester un prospect qui n'a
  // pas encore payé. Activables même avec un solde de crédits à zéro.
  const TRIALS = [
    { id: 'trial_24h', label: 'Test 24 h' },
    { id: 'trial_48h', label: 'Test 48 h' },
    { id: 'trial_7d', label: 'Test 7 jours' },
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

            {/* Essais gratuits (0 crédit) */}
            <div className="mt-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
              Essai gratuit · 0 crédit
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
              className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
            />
          </div>

          {/* ===== Source du client (poussée par MAC) ===== */}
          <div className="rounded-lg border border-white/5 bg-slate/40 p-3">
            <label className="mb-2 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Source du client (chargée automatiquement dans l'app)
            </label>
            <div className="mb-3 grid grid-cols-3 gap-2">
              {([
                { id: 'none', label: 'Aucune' },
                { id: 'xtream', label: 'Xtream' },
                { id: 'm3u', label: 'M3U' },
              ] as const).map((t) => (
                <button
                  type="button"
                  key={t.id}
                  onClick={() => setSrcType(t.id)}
                  className={
                    'rounded-md border px-3 py-2 text-sm transition ' +
                    (srcType === t.id
                      ? 'border-accent bg-accent/10 text-ink-primary'
                      : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                  }
                >
                  {t.label}
                </button>
              ))}
            </div>

            {srcType === 'xtream' && (
              <div className="space-y-2">
                {servers.length > 0 && (
                  <select
                    value={serverChoice}
                    onChange={(e) => {
                      setServerChoice(e.target.value);
                      const s = servers.find((x) => x.id === e.target.value);
                      if (s) setServerUrl(s.url);
                    }}
                    className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
                  >
                    {servers.map((s) => (
                      <option key={s.id} value={s.id}>{s.label}</option>
                    ))}
                    <option value="custom">URL manuelle…</option>
                  </select>
                )}
                {(serverChoice === 'custom' || servers.length === 0) && (
                  <input
                    value={serverUrl}
                    onChange={(e) => setServerUrl(e.target.value)}
                    placeholder="http://serveur.com:8080"
                    className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 font-mono text-sm outline-none focus:ring-1 focus:ring-accent"
                  />
                )}
                <input
                  value={xtUser}
                  onChange={(e) => setXtUser(e.target.value)}
                  placeholder="Utilisateur"
                  className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
                />
                <input
                  value={xtPass}
                  onChange={(e) => setXtPass(e.target.value)}
                  placeholder="Mot de passe"
                  className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
                />
              </div>
            )}

            {srcType === 'm3u' && (
              <input
                value={m3uUrl}
                onChange={(e) => setM3uUrl(e.target.value)}
                placeholder="http://serveur.com/get.php?username=…&type=m3u_plus"
                className="w-full rounded-md border border-white/5 bg-slate px-3 py-2 font-mono text-sm outline-none focus:ring-1 focus:ring-accent"
              />
            )}
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
            {busy
              ? 'Activation…'
              : costFor(plan) === 0
                ? 'Activer (gratuit)'
                : `Activer (${costFor(plan) ?? '?'} crédits)`}
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
