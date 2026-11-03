import { FormEvent, useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { confirmAction } from '@/components/confirm';
import { pricingApi, ApiError } from '@/lib/api';

// =========================================================
//  TarifsPage — prix affichés dans l'app + essai + promo (owner)
// =========================================================
//  L'owner fixe les prix EN € (à vie / 1 an), la durée de l'essai gratuit
//  et un message promo/bonus optionnel (« 1 acheté = 1 offert pour ta
//  famille »). L'app lit /api/pricing au démarrage et affiche le bloc
//  « Nos offres » avec ces valeurs — sans mise à jour de store.
// =========================================================

export function TarifsPage({ onLogout }: { onLogout: () => void }) {
  const [currency, setCurrency] = useState('€');
  const [lifetime, setLifetime] = useState('');
  const [yearly, setYearly] = useState('');
  const [trialDays, setTrialDays] = useState(7);
  const [promoEnabled, setPromoEnabled] = useState(false);
  const [promoMessage, setPromoMessage] = useState('');
  const [blockTitleFr, setBlockTitleFr] = useState('');
  const [blockBodyFr, setBlockBodyFr] = useState('');
  const [blockTitleEn, setBlockTitleEn] = useState('');
  const [blockBodyEn, setBlockBodyEn] = useState('');
  const [payUrl, setPayUrl] = useState('');
  const [trialEnforced, setTrialEnforced] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [known, setKnown] = useState(false);
  const writing = useRef(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [grantBusy, setGrantBusy] = useState(false);

  async function grantTrialAll() {
    if (writing.current || busy || loading || !known) return;
    writing.current = true;
    setGrantBusy(true); setErr(null); setOk(null);
    try {
      const ans = window.prompt(
        'Donner combien de jours à TOUS les appareils actifs ? '
        + 'Passé ce délai, le paiement revient automatiquement.',
        '7',
      );
      if (ans == null) return;
      const days = Number(ans.trim());
      if (!/^\d+$/.test(ans.trim()) || !Number.isInteger(days) || days <= 0 || days > 365) {
        setErr('Nombre de jours invalide.'); return;
      }
      const confirmed = await confirmAction({
        title: 'Appliquer ces jours à tout le monde ?',
        message: `Confirmer : ${days} jours pour tous les appareils actifs.`,
        confirmLabel: 'Appliquer',
        danger: true,
      });
      if (!confirmed) return;
      const r = await pricingApi.grantTrialAll(days);
      if (r.ok !== true || !Number.isFinite(r.updated) || !Number.isFinite(r.days)) throw new Error('Prolongation non confirmée');
      setOk(`✅ ${r.updated} appareil(s) mis à ${r.days} jours. Le paiement reviendra ensuite.`);
    } catch (e) { fail(e); } finally { writing.current = false; setGrantBusy(false); }
  }

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  function load() {
    setLoading(true); setKnown(false); setErr(null);
    pricingApi.get()
      .then((r) => {
        if (typeof r.currency !== 'string' || typeof r.lifetime !== 'string' || typeof r.yearly !== 'string') throw new Error('Tarifs invalides');
        setKnown(true);
        setCurrency(r.currency || '€');
        setLifetime(r.lifetime);
        setYearly(r.yearly);
        setTrialDays(Number.isFinite(r.trialDays) ? r.trialDays : 7);
        setPromoEnabled(!!r.promoEnabled);
        setPromoMessage(r.promoMessage || '');
        setBlockTitleFr(r.blockTitleFr || '');
        setBlockBodyFr(r.blockBodyFr || '');
        setBlockTitleEn(r.blockTitleEn || '');
        setBlockBodyEn(r.blockBodyEn || '');
        setPayUrl(r.payUrl || '');
        setTrialEnforced(!!r.trialEnforced);
      })
      .catch(fail)
      .finally(() => setLoading(false));
  }

  useEffect(() => { load(); /* eslint-disable-next-line */ }, []);

  async function save(e: FormEvent) {
    e.preventDefault();
    if (writing.current || loading || !known || grantBusy) return;
    const payment = payUrl.trim();
    if (payment) {
      try { const url = new URL(payment); if (url.protocol !== 'https:' || url.username || url.password) throw new Error(); }
      catch { setErr('Le lien de paiement doit être une adresse HTTPS sans identifiants.'); return; }
    }
    writing.current = true;
    setBusy(true); setErr(null); setOk(null);
    try {
      const saved = await pricingApi.save({
        currency: currency.trim() || '€',
        lifetime: lifetime.trim(),
        yearly: yearly.trim(),
        trialDays,
        promoEnabled,
        promoMessage: promoMessage.trim(),
        blockTitleFr: blockTitleFr.trim(),
        blockBodyFr: blockBodyFr.trim(),
        blockTitleEn: blockTitleEn.trim(),
        blockBodyEn: blockBodyEn.trim(),
        payUrl: payUrl.trim(),
      });
      if (saved.ok !== true || typeof saved.lifetime !== 'string' || typeof saved.yearly !== 'string') throw new Error('Tarifs non confirmés');
      setLifetime(saved.lifetime); setYearly(saved.yearly);
      setOk('Tarifs enregistrés pour les applications compatibles hors Play. Une offre vide est retirée.');
    } catch (e) { fail(e); } finally { writing.current = false; setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Tarifs"
      subtitle="Les prix affichés dans l'app (à vie / 1 an), l'essai et les promos"
      onLogout={onLogout}
    >
      <div className="grid max-w-3xl gap-6 md:grid-cols-2">
        {/* ===== Formulaire ===== */}
        <form
          onSubmit={save}
          className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6"
        >
          {loading ? (
            <p className="text-sm text-ink-tertiary">Chargement…</p>
          ) : !known ? (
            <div className="space-y-3"><p className="text-xs text-accent-bright">{err || 'Tarifs non chargés.'}</p><button type="button" onClick={load} className="rounded-md border border-white/10 px-4 py-2 text-sm">Réessayer le chargement</button></div>
          ) : (
            <fieldset disabled={busy || grantBusy} className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Prix à vie
                  </label>
                  <input
                    value={lifetime}
                    onChange={(e) => setLifetime(e.target.value)}
                    placeholder="Vide = offre masquée" maxLength={12} aria-label="Prix à vie"
                    className={inputCls + ' font-mono'}
                  />
                </div>
                <div>
                  <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Prix 1 an
                  </label>
                  <input
                    value={yearly}
                    onChange={(e) => setYearly(e.target.value)}
                    placeholder="Vide = offre masquée" maxLength={12} aria-label="Prix 1 an"
                    className={inputCls + ' font-mono'}
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Devise
                  </label>
                  <input
                    value={currency}
                    onChange={(e) => setCurrency(e.target.value)}
                    placeholder="€"
                    className={inputCls}
                  />
                </div>
                <div>
                  <label htmlFor="price-trial" className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Essai gratuit (jours)
                  </label>
                  <input
                    id="price-trial"
                    type="number"
                    min={0}
                    max={365}
                    value={trialDays}
                    onChange={(e) => setTrialDays(parseInt(e.target.value, 10) || 0)}
                    className={inputCls + ' font-mono'}
                  />
                </div>
              </div>

              {/* Promo / bonus */}
              <div className="rounded-lg border border-white/5 bg-slate/40 p-3">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={promoEnabled}
                    onChange={(e) => setPromoEnabled(e.target.checked)}
                  />
                  <span>Afficher un message promo / bonus</span>
                </label>
                <textarea
                  value={promoMessage}
                  onChange={(e) => setPromoMessage(e.target.value)}
                  rows={2}
                  maxLength={240}
                  placeholder="Ex. 1 abonnement acheté = 1 offert pour ta famille"
                  className={inputCls + ' mt-2 resize-none'}
                />
              </div>

              <div className="rounded-lg border border-white/5 bg-slate/40 p-3 space-y-2">
                <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                  Écran « essai terminé » {trialEnforced ? '· interrupteur ALLUMÉ' : '· interrupteur coupé'}
                </p>
                <p className="text-xs text-ink-secondary">
                  Laisse vide pour garder le texte intégré de l’app (français et anglais).
                  Le lien de paiement reste vide par défaut : l’app propose alors WhatsApp
                  et le site déjà connus. L’interrupteur TRIAL_ENFORCEMENT se règle sur le
                  Worker, pas ici.
                </p>
                <input value={blockTitleFr} onChange={(e) => setBlockTitleFr(e.target.value)} placeholder="Titre français (optionnel)" className={inputCls} />
                <textarea value={blockBodyFr} onChange={(e) => setBlockBodyFr(e.target.value)} rows={2} maxLength={500} placeholder="Texte français (optionnel)" className={inputCls + ' resize-none'} />
                <input value={blockTitleEn} onChange={(e) => setBlockTitleEn(e.target.value)} placeholder="English title (optional)" className={inputCls} />
                <textarea value={blockBodyEn} onChange={(e) => setBlockBodyEn(e.target.value)} rows={2} maxLength={500} placeholder="English text (optional)" className={inputCls + ' resize-none'} />
                <input value={payUrl} onChange={(e) => setPayUrl(e.target.value)} placeholder="Lien https de paiement (vide par défaut)" className={inputCls} />
              </div>

              {err && (
                <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
                  {err}
                </div>
              )}
              {ok && (
                <div className="rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
                  {ok}
                </div>
              )}

              <button
                type="submit"
                disabled={busy}
                className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
              >
                {busy ? 'Enregistrement…' : 'Enregistrer les tarifs'}
              </button>
            </fieldset>
          )}
        </form>

        {/* ===== Aperçu (comme dans l'app) ===== */}
        <div className="rounded-xl border border-white/5 bg-obsidian p-6">
          <p className="mb-4 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Aperçu des offres configurées (hors Play)
          </p>
          {!known ? <p className="text-sm text-ink-tertiary">En attente de la configuration serveur.</p> : <div className="rounded-2xl border border-white/10 bg-midnight p-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-xl border border-accent/40 bg-accent/10 p-3 text-center">
                <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">À vie</div>
                <div className="mt-1 text-2xl font-extrabold text-accent-bright">
                  {lifetime ? `${lifetime} ${currency || '€'}` : 'Non proposée'}
                </div>
              </div>
              <div className="rounded-xl border border-white/10 bg-slate p-3 text-center">
                <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">1 an</div>
                <div className="mt-1 text-2xl font-extrabold text-ink-primary">
                  {yearly ? `${yearly} ${currency || '€'}` : 'Non proposée'}
                </div>
              </div>
            </div>
            <div className="mt-3 text-center text-xs text-ink-secondary">
              La durée d’accès affichée au client vient du statut de son appareil.
            </div>
            {promoEnabled && promoMessage.trim() && (
              <div className="mt-3 rounded-lg border border-accent/40 bg-accent/10 px-3 py-2 text-center text-xs font-semibold text-accent-bright">
                🏷️ {promoMessage}
              </div>
            )}
          </div>}
        </div>
      </div>

      {/* ===== Action de bascule : +X jours à tous les actifs ===== */}
      <div className="mt-6 max-w-3xl rounded-xl border border-accent/30 bg-accent/5 p-5">
        <h3 className="text-sm font-semibold text-ink-primary">
          Lancer le modèle payant
        </h3>
        <p className="mt-1 text-xs text-ink-secondary">
          Donne AU MOINS 7 jours (modifiable) à tous les appareils actifs,
          à partir de maintenant. Ne coupe jamais ceux qui ont déjà plus de
          temps, et n'affecte pas les « à vie ». Passé le délai, l'écran de
          paiement revient automatiquement. Action ponctuelle de bascule.
        </p>
        <button
          type="button"
          onClick={grantTrialAll}
          disabled={grantBusy || busy || loading || !known}
          className="mt-3 rounded-md border border-accent/50 bg-accent/10 px-4 py-2 text-sm font-semibold text-accent-bright transition hover:bg-accent/20 disabled:opacity-50"
        >
          {grantBusy ? 'Application…' : 'Donner 7 jours à tous les appareils actifs'}
        </button>
      </div>

      {/* ===== Liens légaux (bouclier « lecteur uniquement ») ===== */}
      <div className="mt-6 max-w-3xl rounded-xl border border-white/5 bg-midnight p-5">
        <h3 className="text-sm font-semibold text-ink-primary">Liens légaux</h3>
        <p className="mt-1 text-xs text-ink-secondary">
          Positionnement « lecteur uniquement » : l'app ne vend ni ne fournit
          aucune chaîne ni lien. Colle ces liens dans tes fiches de distribution
          (stores) et tes publications — c'est ce que regardent les plateformes
          pour éviter les retraits.
        </p>
        <div className="mt-3 space-y-2">
          {[
            { label: 'Conditions d’utilisation', url: 'https://app.7themotion.com/terms' },
            { label: 'Politique de confidentialité', url: 'https://app.7themotion.com/privacy' },
          ].map((l) => (
            <div key={l.url} className="flex items-center gap-2">
              <code className="flex-1 truncate rounded-md bg-slate px-3 py-2 text-xs text-ink-primary">
                {l.url}
              </code>
              <button
                type="button"
                onClick={async () => {
                  try {
                    if (!navigator.clipboard) throw new Error('Copie indisponible');
                    await navigator.clipboard.writeText(l.url);
                    setOk(`${l.label} — lien copié.`); setErr(null);
                  } catch { setErr('Copie impossible. Sélectionne le lien pour le copier manuellement.'); setOk(null); }
                }}
                className="rounded-md border border-white/10 bg-slate px-3 py-2 text-xs transition hover:bg-white/5"
              >
                Copier
              </button>
              <a
                href={l.url}
                target="_blank"
                rel="noreferrer"
                className="rounded-md border border-accent/40 bg-accent/10 px-3 py-2 text-xs text-accent-bright transition hover:bg-accent/20"
              >
                Ouvrir
              </a>
            </div>
          ))}
        </div>
      </div>
    </AppLayout>
  );
}
