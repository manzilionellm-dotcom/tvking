import { useCallback, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { toast } from '@/components/Toast';
import { formatDateTime } from '@/lib/utils';
import {
  creditRequestsApi, getCurrentUser, isOwnerRole, ApiError,
  type CreditRequest,
} from '@/lib/api';

// =========================================================
//  CreditsPage — Crédits & demandes de rechargement
// =========================================================
//  OWNER : boîte de réception des demandes de rechargement (approuver /
//  rejeter). Toi seul émets les crédits.
//  REVENDEUR : voit son solde et DEMANDE un rechargement (que tu approuves).
// =========================================================

export function CreditsPage({ onLogout }: { onLogout: () => void }) {
  const user = getCurrentUser();
  const owner = isOwnerRole(user?.role);
  const [items, setItems] = useState<CreditRequest[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(() => {
    creditRequestsApi.list()
      .then((r) => { setItems(r.items); setErr(null); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      });
  }, [onLogout]);

  useEffect(() => {
    load();
    const t = setInterval(load, 20000);
    return () => clearInterval(t);
  }, [load]);

  async function decide(id: string, action: 'approve' | 'reject') {
    setBusyId(id);
    try {
      if (action === 'approve') { await creditRequestsApi.approve(id); toast('Crédits émis ✔', 'success'); }
      else { await creditRequestsApi.reject(id); toast('Demande rejetée.', 'info'); }
      load();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally { setBusyId(null); }
  }

  const pending = (items || []).filter((r) => r.status === 'pending');

  return (
    <AppLayout
      title="Crédits"
      subtitle={owner
        ? 'Demandes de rechargement des revendeurs — toi seul émets les crédits.'
        : 'Ton solde et tes demandes de rechargement.'}
      onLogout={onLogout}
      actions={!owner && user?.credit_balance !== undefined ? (
        <div className="rounded-lg border border-accent/30 bg-accent/10 px-4 py-2 text-sm">
          <span className="text-ink-tertiary">Solde&nbsp;: </span>
          <span className="font-semibold text-accent-bright">{user.credit_balance}</span>
        </div>
      ) : undefined}
    >
      {err && (
        <div className="mb-4 rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-2 text-sm text-red-300">{err}</div>
      )}

      {!owner && <ResellerRequestForm onDone={load} />}

      {owner && (
        <div className="mb-4 rounded-xl border border-amber-500/20 bg-amber-500/[0.04] px-4 py-3">
          <div className="text-[10px] uppercase tracking-widest text-amber-300/70">En attente</div>
          <div className="text-2xl font-semibold text-amber-300">{pending.length}</div>
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-white/5">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-white/5 bg-obsidian-light text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              {owner && <th className="px-4 py-2.5">Revendeur</th>}
              <th className="px-4 py-2.5">Montant</th>
              <th className="px-4 py-2.5">Statut</th>
              <th className="px-4 py-2.5">Demandé le</th>
              <th className="px-4 py-2.5">Note</th>
              {owner && <th className="px-4 py-2.5 text-right">Action</th>}
            </tr>
          </thead>
          <tbody>
            {items == null ? (
              <tr><td colSpan={owner ? 6 : 4} className="px-4 py-8 text-center text-ink-tertiary">Chargement…</td></tr>
            ) : items.length === 0 ? (
              <tr><td colSpan={owner ? 6 : 4} className="px-4 py-8 text-center text-ink-tertiary">Aucune demande.</td></tr>
            ) : items.map((r) => (
              <tr key={r.id} className="border-b border-white/5 last:border-0">
                {owner && (
                  <td className="px-4 py-2.5 text-ink-primary">
                    {r.reseller_name || r.reseller_email || r.reseller_id}
                  </td>
                )}
                <td className="px-4 py-2.5 font-semibold text-accent-bright">+{r.amount}</td>
                <td className="px-4 py-2.5"><StatusChip status={r.status} /></td>
                <td className="px-4 py-2.5 text-ink-tertiary">{formatDateTime(r.created_at)}</td>
                <td className="px-4 py-2.5 text-ink-secondary">{r.note || '—'}</td>
                {owner && (
                  <td className="px-4 py-2.5">
                    {r.status === 'pending' ? (
                      <div className="flex justify-end gap-1.5">
                        <button type="button" disabled={busyId === r.id}
                          onClick={() => decide(r.id, 'approve')}
                          className="rounded-md border border-emerald-400/40 bg-emerald-400/10 px-2.5 py-1 text-xs font-semibold text-emerald-200 hover:bg-emerald-400/20 disabled:opacity-50">
                          Approuver
                        </button>
                        <button type="button" disabled={busyId === r.id}
                          onClick={() => decide(r.id, 'reject')}
                          className="rounded-md border border-white/10 bg-white/5 px-2.5 py-1 text-xs font-semibold text-ink-secondary hover:bg-white/10 disabled:opacity-50">
                          Rejeter
                        </button>
                      </div>
                    ) : (
                      <span className="block text-right text-[11px] text-ink-tertiary">
                        {r.decided_at ? formatDateTime(r.decided_at) : ''}
                      </span>
                    )}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </AppLayout>
  );
}

function ResellerRequestForm({ onDone }: { onDone: () => void }) {
  const [amount, setAmount] = useState('10');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const input = 'rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  async function submit() {
    const n = parseInt(amount, 10);
    if (!Number.isFinite(n) || n <= 0) { toast('Montant invalide.', 'error'); return; }
    setBusy(true);
    try {
      await creditRequestsApi.create(n, note.trim() || undefined);
      toast('Demande envoyée — en attente de validation.', 'success');
      setNote('');
      onDone();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally { setBusy(false); }
  }

  return (
    <div className="mb-5 rounded-xl border border-accent/20 bg-accent/[0.04] p-4">
      <div className="mb-2 text-[10px] font-bold uppercase tracking-widest text-accent-bright">
        Demander un rechargement
      </div>
      <p className="mb-3 text-[11px] text-ink-tertiary">
        Indique le nombre de crédits souhaités. L'administrateur validera ta demande
        et créditera ton compte.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <input type="number" min={1} value={amount} onChange={(e) => setAmount(e.target.value)}
          className={input + ' w-28'} placeholder="Montant" />
        <input value={note} onChange={(e) => setNote(e.target.value)}
          className={input + ' flex-1 min-w-[180px]'} placeholder="Note (optionnel)" />
        <button type="button" onClick={submit} disabled={busy}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
          {busy ? 'Envoi…' : 'Demander'}
        </button>
      </div>
    </div>
  );
}

function StatusChip({ status }: { status: string }) {
  const map: Record<string, { cls: string; label: string }> = {
    pending: { cls: 'bg-amber-500/15 text-amber-300', label: 'En attente' },
    approved: { cls: 'bg-success/15 text-success', label: 'Approuvé' },
    rejected: { cls: 'bg-white/5 text-ink-tertiary', label: 'Rejeté' },
  };
  const s = map[status] || map.pending;
  return <span className={'rounded px-1.5 py-0.5 text-[10px] font-semibold ' + s.cls}>{s.label}</span>;
}
