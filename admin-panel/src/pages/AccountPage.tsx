import { FormEvent, ReactNode, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { meApi, getCurrentUser, isOwnerRole, type MeUser, ApiError } from '@/lib/api';
import { useT, LangSelect } from '@/lib/i18n';

/// Page « Mon compte » — accessible a TOUS (admin + revendeurs).
/// Changer son mot de passe + sa langue.
export function AccountPage({ onLogout }: { onLogout: () => void }) {
  const t = useT();
  const [me, setMe] = useState<MeUser | null>(getCurrentUser());

  useEffect(() => {
    meApi.get()
      .then((r) => setMe(r.user))
      .catch((e) => { if (e instanceof ApiError && e.status === 401) onLogout(); });
  }, [onLogout]);

  const owner = isOwnerRole(me?.role);

  return (
    <AppLayout
      title={t('nav.account')}
      subtitle={me?.email}
      onLogout={onLogout}
    >
      <div className="max-w-md space-y-6">
        {/* ===== Infos ===== */}
        <div className="rounded-xl border border-white/5 bg-midnight p-5">
          <Row k={t('account.identifier')} v={me?.email || '—'} />
          <Row k={t('account.role')} v={owner ? t('role.adminFull') : t('role.reseller')} />
          {me?.credit_balance !== undefined && (
            <Row k={t('common.credits')} v={String(me.credit_balance)} last />
          )}
        </div>

        {/* ===== Langue ===== */}
        <div className="flex items-center justify-between rounded-xl border border-white/5 bg-midnight p-5">
          <span className="text-sm font-semibold tracking-tight">{t('common.language')}</span>
          <LangSelect />
        </div>

        {/* ===== Changer mot de passe ===== */}
        <PasswordForm />
      </div>
    </AppLayout>
  );
}

function PasswordForm() {
  const t = useT();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setMsg(null);
    if (next.length < 4) {
      setMsg({ ok: false, text: t('account.pwdShort') });
      return;
    }
    if (next !== confirm) {
      setMsg({ ok: false, text: t('account.pwdMismatch') });
      return;
    }
    setBusy(true);
    try {
      await meApi.changePassword(current, next);
      setMsg({ ok: true, text: t('account.pwdOk') });
      setCurrent(''); setNext(''); setConfirm('');
    } catch (e: any) {
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Échec.' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-xl border border-white/5 bg-midnight p-5">
      <h2 className="text-sm font-semibold tracking-tight">{t('account.changePwd')}</h2>
      <Field label={t('account.current')}>
        <input type="password" value={current} onChange={(e) => setCurrent(e.target.value)} className={inputCls} autoComplete="current-password" />
      </Field>
      <Field label={t('account.new')}>
        <input type="password" value={next} onChange={(e) => setNext(e.target.value)} className={inputCls} autoComplete="new-password" />
      </Field>
      <Field label={t('account.confirm')}>
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
        {busy ? t('account.updating') : t('account.update')}
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
