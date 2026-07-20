import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { MacLink } from '@/components/MacLink';
import { mastersApi, ApiError, type MasterRow } from '@/lib/api';
import { formatMacInput } from '@/lib/utils';

// =========================================================
//  MastersPage — Comptes MAÎTRES (démo illimitée)
// =========================================================
//  Une MAC listée ici peut, DEPUIS L'APP, envoyer des « tests » (pass invités)
//  à n'importe qui, sur la chaîne de son choix, SANS quota ni obligation
//  d'abonnement payé. Sert à attirer des clients (« essaie 1 h, gratis »).
//  Pouvoir fort → page réservée à l'owner (super_admin).
// =========================================================

const MAC_RX = /^MK(?::[0-9A-Fa-f]{2}){5}$/;

export function MastersPage({ onLogout }: { onLogout: () => void }) {
  const [rows, setRows] = useState<MasterRow[]>([]);
  const [mac, setMac] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function load() {
    try {
      const r = await mastersApi.list();
      setRows(r.items || []);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Chargement impossible.');
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function add(e: FormEvent) {
    e.preventDefault();
    setErr(null); setOk(null);
    const m = mac.trim().toUpperCase();
    if (!MAC_RX.test(m)) { setErr('MAC invalide (format MK:XX:XX:XX:XX:XX).'); return; }
    setBusy(true);
    try {
      await mastersApi.add(m, note.trim() || undefined);
      setOk(`✅ ${m} est désormais un compte maître (démo illimitée).`);
      setMac(''); setNote('');
      await load();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Ajout impossible.');
    } finally { setBusy(false); }
  }

  async function remove(m: string) {
    setErr(null); setOk(null);
    try {
      await mastersApi.remove(m);
      await load();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Suppression impossible.');
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm font-mono outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Comptes maîtres"
      subtitle="Des MAC qui peuvent envoyer des tests gratuits illimités depuis l'app — pour attirer des clients."
      onLogout={onLogout}
    >
      <div className="max-w-2xl space-y-5">
        <div className="rounded-lg border border-accent/20 bg-accent/5 px-4 py-3 text-[13px] text-ink-secondary">
          Une MAC « maître » débloque, dans son app, l'<strong>envoi de tests
          illimité</strong> : elle offre un pass (1 h, 5 h…) à n'importe qui,
          sur la chaîne de son choix, <strong>sans quota</strong> et sans être
          abonnée. Les tests passent par le gateway → <strong>invisibles au
          fournisseur</strong>. À réserver à toi (et gens de confiance).
        </div>

        <form onSubmit={add} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              MAC à promouvoir maître
            </label>
            <input
              value={mac}
              onChange={(e) => setMac(formatMacInput(e.target.value))}
              maxLength={17}
              placeholder="MK:XX:XX:XX:XX:XX"
              className={inputCls}
              autoFocus
            />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Note (optionnel)
            </label>
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={80}
              placeholder="Ex : mon téléphone, commercial Zone Nord…"
              className={inputCls.replace('font-mono', '')}
            />
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
            className="rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Ajout…' : 'Ajouter un maître'}
          </button>
        </form>

        {/* ===== Liste ===== */}
        <div className="overflow-hidden rounded-xl border border-white/5 bg-midnight">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-white/5 text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
                <th className="px-4 py-3 font-medium">MAC</th>
                <th className="px-4 py-3 font-medium">Note</th>
                <th className="px-4 py-3 font-medium text-right">Action</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr>
                  <td colSpan={3} className="px-4 py-8 text-center text-ink-tertiary">
                    Aucun compte maître pour l'instant.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <tr key={r.mac} className="border-b border-white/[0.03] last:border-0">
                  <td className="px-4 py-3"><MacLink mac={r.mac} /></td>
                  <td className="px-4 py-3 text-ink-secondary">{r.note || '—'}</td>
                  <td className="px-4 py-3 text-right">
                    <button
                      onClick={() => remove(r.mac)}
                      className="rounded-md border border-white/10 px-3 py-1 text-xs text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright"
                    >
                      Retirer
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </AppLayout>
  );
}
