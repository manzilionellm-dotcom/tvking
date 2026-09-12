import { FormEvent, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { transferApi, ApiError } from '@/lib/api';
import { formatMacInput } from '@/lib/utils';

// =========================================================
//  TransferPage — CHANGER LA MAC d'un client
// =========================================================
//  RIGUEUR BUSINESS : un client qui a payé ne perd JAMAIS son temps s'il
//  change de téléphone (ou si l'ID a changé après une mise à jour). On
//  déplace sa licence + sa source de l'ancienne MAC vers la nouvelle, en
//  gardant tout le temps restant. GRATUIT (aucun crédit débité).
//
//  POURQUOI CETTE PAGE S'APPELLE « CHANGER LA MAC » (12/09/2026).
//  Elle s'est longtemps appelée « Transférer un abonnement ». Le
//  propriétaire a demandé qu'on AJOUTE de quoi « changer le numéro MAC,
//  car certaines MAC ne marchent pas » — alors que la page existait déjà,
//  complète, depuis des mois. Il ne l'avait simplement jamais reconnue
//  sous ce nom. Une fonctionnalité qu'on ne trouve pas n'existe pas : le
//  vocabulaire de l'écran doit être celui du problème vécu (« cette MAC
//  ne marche pas »), pas celui de la mécanique interne (« transfert »).
// =========================================================

const MAC_RX = /^MK(?::[0-9A-Fa-f]{2}){5}$/;

export function TransferPage({ onLogout }: { onLogout: () => void }) {
  // Ancienne MAC pré-remplie si on arrive depuis la fiche appareil (?mac=…).
  const [sp] = useSearchParams();
  const [oldMac, setOldMac] = useState(sp.get('mac') || '');
  const [newMac, setNewMac] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setErr(null); setOk(null);
    const o = oldMac.trim().toUpperCase();
    const n = newMac.trim().toUpperCase();
    if (!MAC_RX.test(o)) { setErr('MAC actuelle invalide (format MK:XX:XX:XX:XX:XX).'); return; }
    if (!MAC_RX.test(n)) { setErr('Nouvelle MAC invalide (format MK:XX:XX:XX:XX:XX).'); return; }
    if (o === n) { setErr('Les deux MAC sont identiques.'); return; }
    setBusy(true);
    try {
      const r = await transferApi.transfer(o, n);
      //  On affiche le DÉTAIL de ce qui a suivi, pas seulement « OK ».
      //  Le Worker renvoie `moved` : « device_profiles.mac:1 », etc. Sans
      //  cette liste, un changement complet et un changement qui a laissé
      //  les profils enfants derrière lui donnent le même bandeau vert.
      //  Le champ est optionnel : un Worker plus ancien ne le renvoie pas,
      //  et dans ce cas on ne ment pas — on n'affiche simplement rien.
      const detail = (r.moved && r.moved.length > 0)
        ? ` Ont suivi : ${r.moved.join(', ')}.`
        : '';
      setOk(
        `✅ MAC changée : ${r.old_mac} → ${r.new_mac}. `
        + `${r.moved_licenses} licence(s) déplacée(s), temps restant conservé.${detail} `
        + `Le nouvel appareil sera actif à sa prochaine ouverture.`,
      );
      setOldMac(''); setNewMac('');
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Changement de MAC impossible.');
    } finally { setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm font-mono outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Changer la MAC d'un client"
      subtitle="Une MAC qui ne marche pas, un appareil remplacé ? On bascule tout sur la nouvelle, sans faire repayer."
      onLogout={onLogout}
    >
      <div className="max-w-xl space-y-5">
        <div className="rounded-lg border border-accent/20 bg-accent/5 px-4 py-3 text-[13px] text-ink-secondary">
          Sers-toi de ça quand un client a <strong>déjà payé</strong> mais que
          sa <strong>MAC ne marche pas</strong>, qu'il a changé d'appareil,
          réinstallé l'app, ou que son identifiant a bougé après une mise à
          jour. Tout le suit : licence, sources, profils (mode Enfants,
          contrôle parental), sauvegardes, famille, commandes et messages.
          Son <strong>temps restant est conservé</strong> et
          {' '}<strong>aucun crédit</strong> n'est débité.
        </div>

        <form onSubmit={submit} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              MAC actuelle (celle du client aujourd'hui, celle qui pose problème)
            </label>
            <input
              value={oldMac}
              onChange={(e) => setOldMac(formatMacInput(e.target.value))}
              maxLength={17}
              placeholder="MK:XX:XX:XX:XX:XX"
              className={inputCls}
              autoFocus
            />
          </div>
          <div className="flex justify-center text-ink-tertiary">↓</div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Nouvelle MAC (celle qu'on lui donne à la place)
            </label>
            <input
              value={newMac}
              onChange={(e) => setNewMac(formatMacInput(e.target.value))}
              maxLength={17}
              placeholder="MK:XX:XX:XX:XX:XX"
              className={inputCls}
            />
            <p className="mt-1 text-[10px] text-ink-tertiary">
              Le client trouve sa nouvelle MAC dans l'app (écran « À propos »).
            </p>
          </div>

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
          )}
          {ok && (
            <div className="rounded-md px-3 py-2 text-xs" style={{ background: 'rgba(47,169,106,0.15)', color: '#3FBE7C' }}>{ok}</div>
          )}

          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Changement en cours…' : 'Changer la MAC'}
          </button>
        </form>
      </div>
    </AppLayout>
  );
}
