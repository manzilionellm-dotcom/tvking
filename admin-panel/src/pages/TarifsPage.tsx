import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
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
  const [lifetime, setLifetime] = useState('9,9');
  const [yearly, setYearly] = useState('4,9');
  const [trialDays, setTrialDays] = useState(7);
  const [promoEnabled, setPromoEnabled] = useState(false);
  const [promoMessage, setPromoMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [grantBusy, setGrantBusy] = useState(false);

  async function grantTrialAll() {
    const ans = window.prompt(
      'Donner combien de jours à TOUS les appareils actifs ? '
      + 'Passé ce délai, le paiement revient automatiquement.',
      '7',
    );
    if (ans == null) return;
    const days = parseInt(ans, 10);
    if (!Number.isFinite(days) || days <= 0) { setErr('Nombre de jours invalide.'); return; }
    if (!window.confirm(`Confirmer : ${days} jours pour TOUS les appareils actifs ?`)) return;
    setGrantBusy(true); setErr(null); setOk(null);
    try {
      const r = await pricingApi.grantTrialAll(days);
      setOk(`✅ ${r.updated} appareil(s) mis à ${r.days} jours. Le paiement reviendra ensuite.`);
    } catch (e) { fail(e); } finally { setGrantBusy(false); }
  }

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  useEffect(() => {
    pricingApi.get()
      .then((r) => {
        setCurrency(r.currency || '€');
        setLifetime(r.lifetime || '9,9');
        setYearly(r.yearly || '4,9');
        setTrialDays(Number.isFinite(r.trialDays) ? r.trialDays : 7);
        setPromoEnabled(!!r.promoEnabled);
        setPromoMessage(r.promoMessage || '');
      })
      .catch(fail)
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    try {
      await pricingApi.save({
        currency: currency.trim() || '€',
        lifetime: lifetime.trim() || '9,9',
        yearly: yearly.trim() || '4,9',
        trialDays,
        promoEnabled,
        promoMessage: promoMessage.trim(),
      });
      setOk('✅ Tarifs enregistrés — l\'app les affiche dès le prochain lancement.');
    } catch (e) { fail(e); } finally { setBusy(false); }
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
          ) : (
            <>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Prix à vie
                  </label>
                  <input
                    value={lifetime}
                    onChange={(e) => setLifetime(e.target.value)}
                    placeholder="9,9"
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
                    placeholder="4,9"
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
                  <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Essai gratuit (jours)
                  </label>
                  <input
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
            </>
          )}
        </form>

        {/* ===== Aperçu (comme dans l'app) ===== */}
        <div className="rounded-xl border border-white/5 bg-obsidian p-6">
          <p className="mb-4 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Aperçu « Nos offres » (app)
          </p>
          <div className="rounded-2xl border border-white/10 bg-midnight p-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-xl border border-accent/40 bg-accent/10 p-3 text-center">
                <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">À vie</div>
                <div className="mt-1 text-2xl font-extrabold text-accent-bright">
                  {lifetime || '9,9'} {currency || '€'}
                </div>
              </div>
              <div className="rounded-xl border border-white/10 bg-slate p-3 text-center">
                <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">1 an</div>
                <div className="mt-1 text-2xl font-extrabold text-ink-primary">
                  {yearly || '4,9'} {currency || '€'}
                </div>
              </div>
            </div>
            <div className="mt-3 text-center text-xs text-ink-secondary">
              🎁 Essai gratuit {trialDays} jours
            </div>
            {promoEnabled && promoMessage.trim() && (
              <div className="mt-3 rounded-lg border border-accent/40 bg-accent/10 px-3 py-2 text-center text-xs font-semibold text-accent-bright">
                🏷️ {promoMessage}
              </div>
            )}
          </div>
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
          disabled={grantBusy}
          className="mt-3 rounded-md border border-accent/50 bg-accent/10 px-4 py-2 text-sm font-semibold text-accent-bright transition hover:bg-accent/20 disabled:opacity-50"
        >
          {grantBusy ? 'Application…' : 'Donner 7 jours à tous les appareils actifs'}
        </button>
      </div>
    </AppLayout>
  );
}
