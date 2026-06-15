import { FormEvent, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { transferApi, ApiError } from '@/lib/api';

// =========================================================
//  TransferPage — déplacer un abonnement vers un nouvel appareil
// =========================================================
//  RIGUEUR BUSINESS : un client qui a payé ne perd JAMAIS son temps s'il
//  change de téléphone (ou si l'ID a changé après une mise à jour). On
//  déplace sa licence + sa source de l'ancienne MAC vers la nouvelle, en
//  gardant tout le temps restant. GRATUIT (aucun crédit débité).
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
    if (!MAC_RX.test(o)) { setErr('Ancienne MAC invalide (format MK:XX:XX:XX:XX:XX).'); return; }
    if (!MAC_RX.test(n)) { setErr('Nouvelle MAC invalide (format MK:XX:XX:XX:XX:XX).'); return; }
    if (o === n) { setErr('Les deux MAC sont identiques.'); return; }
    setBusy(true);
    try {
      const r = await transferApi.transfer(o, n);
      setOk(
        `✅ Abonnement transféré de ${r.old_mac} → ${r.new_mac}. `
        + `${r.moved_licenses} licence(s) déplacée(s), temps restant conservé. `
        + `Le nouvel appareil sera actif à sa prochaine ouverture.`,
      );
      setOldMac(''); setNewMac('');
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Transfert impossible.');
    } finally { setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm font-mono outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Transférer un abonnement"
      subtitle="Le client change d'appareil ? On déplace son temps, sans le faire repayer."
      onLogout={onLogout}
    >
      <div className="max-w-xl space-y-5">
        <div className="rounded-lg border border-accent/20 bg-accent/5 px-4 py-3 text-[13px] text-ink-secondary">
          Sers-toi de ça quand un client a <strong>déjà payé</strong> mais a
          changé de téléphone, réinstallé l'app, ou que son identifiant a
          bougé après une mise à jour. Son <strong>temps restant est
          conservé</strong> et <strong>aucun crédit</strong> n'est débité.
        </div>

        <form onSubmit={submit} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Ancienne MAC (l'appareil/abonnement actuel)
            </label>
            <input
              value={oldMac}
              onChange={(e) => setOldMac(e.target.value)}
              placeholder="MK:XX:XX:XX:XX:XX"
              className={inputCls}
              autoFocus
            />
          </div>
          <div className="flex justify-center text-ink-tertiary">↓</div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Nouvelle MAC (le nouvel appareil du client)
            </label>
            <input
              value={newMac}
              onChange={(e) => setNewMac(e.target.value)}
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
            {busy ? 'Transfert…' : 'Transférer l\'abonnement'}
          </button>
        </form>
      </div>
    </AppLayout>
  );
}
