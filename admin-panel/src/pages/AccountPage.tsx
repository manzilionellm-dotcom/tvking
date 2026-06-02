import { FormEvent, ReactNode, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { meApi, getCurrentUser, isOwnerRole, type MeUser, ApiError } from '@/lib/api';

/// Page « Mon compte » — accessible a TOUS (admin + revendeurs).
/// Permet de changer son propre mot de passe. (Le choix de la langue
/// sera ajoute ici a la vague multilangue.)
export function AccountPage({ onLogout }: { onLogout: () => void }) {
  const [me, setMe] = useState<MeUser | null>(getCurrentUser());

  useEffect(() => {
    meApi.get()
      .then((r) => setMe(r.user))
      .catch((e) => { if (e instanceof ApiError && e.status === 401) onLogout(); });
  }, [onLogout]);

  const owner = isOwnerRole(me?.role);

  return (
    <AppLayout
      title="Mon compte"
      subtitle={me?.email}
      onLogout={onLogout}
    >
      <div className="max-w-md space-y-6">
        {/* ===== Infos ===== */}
        <div className="rounded-xl border border-white/5 bg-midnight p-5">
          <Row k="Identifiant" v={me?.email || '—'} />
          <Row k="Rôle" v={owner ? 'Administrateur' : 'Revendeur'} />
          {me?.credit_balance !== undefined && (
            <Row k="Crédits" v={String(me.credit_balance)} last />
          )}
        </div>

        {/* ===== Changer mot de passe ===== */}
        <PasswordForm />
      </div>
    </AppLayout>
  );
}

function PasswordForm() {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setMsg(null);
    if (next.length < 4) {
      setMsg({ ok: false, text: 'Le nouveau mot de passe doit faire au moins 4 caractères.' });
      return;
    }
    if (next !== confirm) {
      setMsg({ ok: false, text: 'La confirmation ne correspond pas.' });
      return;
    }
    setBusy(true);
    try {
      await meApi.changePassword(current, next);
      setMsg({ ok: true, text: 'Mot de passe modifié ✔' });
      setCurrent(''); setNext(''); setConfirm('');
    } catch (e: any) {
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Échec.' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-xl border border-white/5 bg-midnight p-5">
      <h2 className="text-sm font-semibold tracking-tight">Changer mon mot de passe</h2>
      <Field label="Mot de passe actuel">
        <input type="password" value={current} onChange={(e) => setCurrent(e.target.value)} className={inputCls} autoComplete="current-password" />
      </Field>
      <Field label="Nouveau mot de passe">
        <input type="password" value={next} onChange={(e) => setNext(e.target.value)} className={inputCls} autoComplete="new-password" />
      </Field>
      <Field label="Confirmer le nouveau">
        <input type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)} className={inputCls} autoComplete="new-password" />
      </Field>
      {msg && (
        <div className={
          'rounded-md px-3 py-2 text-xs ' +
          (msg.ok ? 'border border-success/30 bg-success/10 text-success'
                  : 'border border-accent/30 bg-accent/10 text-accent-bright')
        }>
          {msg.text}
        </div>
      )}
      <button
        type="submit"
        disabled={busy || !current || !next}
        className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
      >
        {busy ? 'Modification…' : 'Mettre à jour'}
      </button>
    </form>
  );
}

const inputCls =
  'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</label>
      {children}
    </div>
  );
}

function Row({ k, v, last }: { k: string; v: string; last?: boolean }) {
  return (
    <div className={'flex items-center justify-between py-2 ' + (last ? '' : 'border-b border-white/5')}>
      <span className="text-ink-tertiary text-sm">{k}</span>
      <span className="text-ink-primary text-sm">{v}</span>
    </div>
  );
}
