import { FormEvent, ReactNode, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { meApi, twoFaApi, getCurrentUser, isOwnerRole, type MeUser, ApiError } from '@/lib/api';
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

        {/* ===== 2FA (comptes admin uniquement) ===== */}
        {owner && <TwoFaSection />}
      </div>
    </AppLayout>
  );
}

/// Double authentification TOTP : état, activation guidée (secret à
/// saisir dans Google Authenticator/Authy + code de confirmation),
/// désactivation protégée (mot de passe + code).
function TwoFaSection() {
  const [enabled, setEnabled] = useState<boolean | null>(null);
  const [setup, setSetup] = useState<{ secret: string; otpauth: string } | null>(null);
  const [code, setCode] = useState('');
  const [pwd, setPwd] = useState('');
  const [disabling, setDisabling] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    twoFaApi.status().then((r) => setEnabled(r.enabled)).catch(() => setEnabled(null));
  }, []);

  async function startSetup() {
    setBusy(true); setMsg(null);
    try {
      const r = await twoFaApi.setup();
      setSetup({ secret: r.secret, otpauth: r.otpauth });
      setCode('');
    } catch (e: any) {
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Échec.' });
    } finally {
      setBusy(false);
    }
  }

  async function confirmEnable(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setMsg(null);
    try {
      await twoFaApi.enable(code.trim());
      setEnabled(true);
      setSetup(null);
      setCode('');
      setMsg({ ok: true, text: '2FA activée ✔ Le code sera demandé à chaque connexion.' });
    } catch (e: any) {
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Code refusé.' });
    } finally {
      setBusy(false);
    }
  }

  async function confirmDisable(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setMsg(null);
    try {
      await twoFaApi.disable(pwd, code.trim());
      setEnabled(false);
      setDisabling(false);
      setPwd(''); setCode('');
      setMsg({ ok: true, text: '2FA désactivée.' });
    } catch (e: any) {
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Échec.' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-3 rounded-xl border border-white/5 bg-midnight p-5">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold tracking-tight">Double authentification (2FA)</h2>
        {enabled !== null && (
          <span className={
            'rounded-full px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-widest ' +
            (enabled ? 'bg-success/15 text-success' : 'bg-white/5 text-ink-tertiary')
          }>
            {enabled ? 'Active' : 'Inactive'}
          </span>
        )}
      </div>
      <p className="text-xs leading-relaxed text-ink-tertiary">
        Un code à 6 chiffres (Google Authenticator, Authy, 1Password…) est
        exigé en plus du mot de passe à chaque connexion. Même un mot de
        passe volé ne suffit plus à entrer.
      </p>

      {/* --- Inactif : bouton d'activation --- */}
      {enabled === false && !setup && (
        <button onClick={startSetup} disabled={busy}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
          {busy ? 'Préparation…' : 'Activer la 2FA'}
        </button>
      )}

      {/* --- Setup en cours : secret + confirmation --- */}
      {setup && (
        <form onSubmit={confirmEnable} className="space-y-3 rounded-lg border border-accent/20 bg-accent/5 p-3">
          <p className="text-xs text-ink-secondary">
            1. Dans ton app d'authentification, ajoute un compte
            « <span className="font-semibold">saisie manuelle</span> » avec cette clé :
          </p>
          <div className="flex items-center gap-2">
            <code className="min-w-0 flex-1 break-all rounded bg-black/40 px-2 py-1.5 font-mono text-xs text-ink-primary">
              {setup.secret}
            </code>
            <button type="button"
              onClick={() => navigator.clipboard?.writeText(setup.secret)}
              className="shrink-0 rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
              Copier
            </button>
          </div>
          <p className="text-[11px] text-ink-tertiary">
            (ou colle ce lien dans une app compatible : <span className="break-all font-mono">{setup.otpauth}</span>)
          </p>
          <p className="text-xs text-ink-secondary">2. Entre le code affiché pour confirmer :</p>
          <input value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
            inputMode="numeric" maxLength={6} placeholder="000000"
            className={inputCls + ' text-center font-mono text-lg tracking-[0.4em]'} />
          <button type="submit" disabled={busy || code.length !== 6}
            className="w-full rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
            {busy ? 'Vérification…' : 'Confirmer et activer'}
          </button>
        </form>
      )}

      {/* --- Actif : désactivation protégée --- */}
      {enabled === true && !disabling && (
        <button onClick={() => { setDisabling(true); setMsg(null); }}
          className="rounded-md border border-white/10 px-4 py-2 text-sm text-ink-secondary transition hover:border-accent hover:text-accent-bright">
          Désactiver la 2FA…
        </button>
      )}
      {disabling && (
        <form onSubmit={confirmDisable} className="space-y-2 rounded-lg border border-white/10 bg-slate/30 p-3">
          <input type="password" value={pwd} onChange={(e) => setPwd(e.target.value)}
            placeholder="Mot de passe" className={inputCls} autoComplete="current-password" />
          <input value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
            inputMode="numeric" maxLength={6} placeholder="Code 2FA actuel"
            className={inputCls + ' font-mono'} />
          <div className="flex gap-2">
            <button type="submit" disabled={busy || !pwd || code.length !== 6}
              className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
              Désactiver
            </button>
            <button type="button" onClick={() => setDisabling(false)}
              className="rounded-md border border-white/10 px-4 py-2 text-sm text-ink-secondary hover:border-white/25">
              Annuler
            </button>
          </div>
        </form>
      )}

      {msg && (
        <div className={
          'rounded-md px-3 py-2 text-xs ' +
          (msg.ok ? 'border border-success/30 bg-success/10 text-success'
                  : 'border border-accent/30 bg-accent/10 text-accent-bright')
        }>
          {msg.text}
        </div>
      )}
    </div>
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
    // Aligné sur le backend : 8 caractères minimum (compte à fort privilège).
    if (next.length < 8) {
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
