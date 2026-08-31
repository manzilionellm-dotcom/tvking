import { FormEvent, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  profilesApi, ApiError,
  type FamilyProfile, type FamilyProfileInput,
} from '@/lib/api';
import { formatMacInput } from '@/lib/utils';

/// Page « Profils » — les cinq profils de la famille d'une box.
///
///  Le propriétaire colle UNE source M3U, et le serveur génère
///  automatiquement papa, maman et trois enfants, chacun avec son code,
///  ses règles et son historique. Ici, on les règle.
///
///  ---------------------------------------------------------
///  TROIS CHOSES QUE CETTE PAGE FAIT EXPRÈS
///  ---------------------------------------------------------
///   1. LE CHAMP « CODE » RESTE VIDE À L'OUVERTURE. Le serveur ne renvoie
///      que l'empreinte d'un code, jamais le code. On ne peut donc pas
///      pré-remplir — et surtout on ne DOIT pas : un champ vide qu'on
///      enregistre ne change rien, alors qu'un champ pré-rempli d'étoiles
///      donnerait l'illusion qu'on peut le relire. La légende dit ce que
///      chaque valeur fait.
///
///   2. LE MAC EST NORMALISÉ EN LE TAPANT. L'app AFFICHE l'adresse SANS
///      le « MK: » : le client la lit sur sa télé et la dicte comme ça.
///      `formatMacInput` remet le préfixe pendant la frappe, sinon
///      l'adresse serait refusée pour une raison qu'aucun message
///      n'expliquerait.
///
///   3. ON ENREGISTRE LES CINQ D'UN BLOC. Un seul PUT : deux profils
///      modifiés dans la même session ne peuvent pas s'écraser.

/// Un profil en cours d'édition : le profil du serveur + le code TAPÉ
/// (qui n'existe que dans cette page, jamais dans la réponse serveur).
type Draft = FamilyProfile & { pinInput: string };

export function ProfilesPage({ onLogout }: { onLogout: () => void }) {
  const [mac, setMac] = useState('MK:');
  const [loadedMac, setLoadedMac] = useState<string | null>(null);
  const [items, setItems] = useState<Draft[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  async function load(e: FormEvent) {
    e.preventDefault();
    const m = mac.trim().toUpperCase();
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
      setErr('Adresse incomplète. Format attendu : MK:XX:XX:XX:XX:XX');
      return;
    }
    setBusy(true); setErr(null); setOk(null);
    try {
      const r = await profilesApi.get(m);
      setItems(r.profiles.map((p) => ({ ...p, pinInput: '' })));
      setLoadedMac(r.mac);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setItems(null);
      setErr(e instanceof ApiError ? e.message : 'Chargement impossible.');
    } finally {
      setBusy(false);
    }
  }

  function patch(id: string, p: Partial<Draft>) {
    setItems((prev) => prev && prev.map((it) => (it.id === id ? { ...it, ...p } : it)));
    setOk(null);
  }

  async function save() {
    if (!items || !loadedMac) return;
    setBusy(true); setErr(null); setOk(null);
    const payload: FamilyProfileInput[] = items.map((p) => {
      const base: FamilyProfileInput = {
        id: p.id,
        name: p.name,
        emoji: p.emoji,
        enabled: p.enabled,
        kids: p.kids,
        blockedCategories: p.blockedCategories,
      };
      const tape = p.pinInput.trim();
      // « - » efface, un code pose, VIDE ne touche à rien. On n'ajoute la
      // clé `pin` que dans les deux premiers cas : son ABSENCE est
      // justement ce qui dit au serveur « garde le code existant ».
      if (tape === '-') return { ...base, pin: '' };
      if (tape) return { ...base, pin: tape };
      return base;
    });
    try {
      const r = await profilesApi.set(loadedMac, payload);
      setOk(
        `${r.count} profils enregistrés sur ${r.mac}. `
        + (r.rt && r.rt.delivered > 0
          ? "La box a reçu le changement à l'instant."
          : "La box appliquera le changement à sa prochaine synchro (5 min max)."),
      );
      // On relit : le serveur est la référence, et les codes tapés doivent
      // disparaître de l'écran une fois posés.
      const fresh = await profilesApi.get(loadedMac);
      setItems(fresh.profiles.map((p) => ({ ...p, pinInput: '' })));
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : "Échec de l'enregistrement.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <AppLayout
      title="Profils"
      subtitle="Les cinq profils de la famille — code, mode enfant, catégories, activation à distance"
      onLogout={onLogout}
    >
      {/* ===== Adresse de la box ===== */}
      <form
        onSubmit={load}
        className="mb-5 max-w-xl rounded-xl border border-white/5 bg-midnight p-5"
      >
        <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
          Adresse MAC de la box
        </label>
        <div className="flex gap-2">
          <input
            value={mac}
            onChange={(e) => setMac(formatMacInput(e.target.value))}
            autoFocus
            maxLength={17}
            placeholder="MK:1A:2B:3C:4D:5E"
            className={inputCls + ' font-mono'}
          />
          <button
            type="submit"
            disabled={busy}
            className="shrink-0 rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? '…' : 'Ouvrir'}
          </button>
        </div>
        <p className="mt-2 text-xs text-ink-tertiary">
          Le client la trouve sur sa télé : <b>Réglages → À propos</b>. Il la lit
          sans le <code className="font-mono">MK:</code> — colle-la telle quelle,
          le préfixe se remet tout seul.
        </p>
      </form>

      {err && (
        <div className="mb-4 max-w-xl rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}
      {ok && (
        <div className="mb-4 max-w-xl rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
          {ok}
        </div>
      )}

      {/* ===== Les cinq profils ===== */}
      {items && (
        <div className="rounded-xl border border-white/5 bg-midnight p-5">
          <div className="mb-4 flex items-center justify-between">
            <span className="font-mono text-sm text-ink-secondary">{loadedMac}</span>
            <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
              {items.length} profils
            </span>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead>
                <tr className="border-b border-white/5 text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
                  <th className="pb-2 pr-3">Profil</th>
                  <th className="pb-2 pr-3">Actif</th>
                  <th className="pb-2 pr-3">Mode enfant</th>
                  <th className="pb-2 pr-3">Code</th>
                  <th className="pb-2">Catégories bloquées</th>
                </tr>
              </thead>
              <tbody>
                {items.map((p) => (
                  <tr key={p.id} className="border-b border-white/[0.03]">
                    <td className="py-3 pr-3 whitespace-nowrap">
                      <span className="mr-2 text-lg">{p.emoji}</span>
                      <span className={p.enabled ? '' : 'text-ink-tertiary line-through'}>
                        {p.name}
                      </span>
                    </td>
                    <td className="py-3 pr-3">
                      <input
                        type="checkbox"
                        checked={p.enabled}
                        onChange={(e) => patch(p.id, { enabled: e.target.checked })}
                        className="h-4 w-4 accent-accent"
                      />
                    </td>
                    <td className="py-3 pr-3">
                      <input
                        type="checkbox"
                        checked={p.kids}
                        onChange={(e) => patch(p.id, { kids: e.target.checked })}
                        className="h-4 w-4 accent-accent"
                      />
                    </td>
                    <td className="py-3 pr-3">
                      <input
                        value={p.pinInput}
                        onChange={(e) => patch(p.id, { pinInput: e.target.value })}
                        maxLength={8}
                        // Le placeholder DIT s'il y a déjà un code, sans le
                        // révéler : c'est tout ce que le serveur permet de
                        // savoir, et c'est tout ce dont l'admin a besoin.
                        placeholder={p.pin ? 'code posé' : 'aucun'}
                        className={inputCls + ' w-28 font-mono'}
                      />
                    </td>
                    <td className="py-3">
                      <input
                        value={p.blockedCategories.join(', ')}
                        onChange={(e) => patch(p.id, {
                          blockedCategories: e.target.value
                            .split(',').map((x) => x.trim()).filter(Boolean),
                        })}
                        placeholder="Adulte, XXX"
                        className={inputCls}
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="mt-4 space-y-1 text-xs text-ink-tertiary">
            <p>
              <b>Code</b> — laisser vide ne change rien.
              Écrire 4 à 8 chiffres pose un nouveau code.
              Écrire <code className="font-mono">-</code> efface le code.
            </p>
            <p>
              <b>Actif</b> — décoché, le profil reste visible sur la télé mais
              grisé et verrouillé. Volontairement visible : un enfant dont le
              profil disparaît croit à une panne.
            </p>
            <p>
              <b>Mode enfant</b> — retire le contenu adulte pour ce profil
              seulement, même si l'interrupteur de la box est éteint.
            </p>
          </div>

          <button
            onClick={save}
            disabled={busy}
            className="mt-4 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Enregistrement…' : 'Enregistrer les profils'}
          </button>
        </div>
      )}
    </AppLayout>
  );
}
