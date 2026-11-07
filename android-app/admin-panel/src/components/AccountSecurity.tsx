import { useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { securityApi, ApiError } from '@/lib/api';
import { useT } from '@/lib/i18n';

export function AccountSecurity({ onLogout }: {onLogout: () => void}) {
  const t = useT();
  const [enabled, setEnabled] = useState<boolean | null>(null);
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [setup, setSetup] = useState<{secret: string; uri: string} | null>(null);
  const [recovery, setRecovery] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => { let active = true; securityApi.status().then(r => { if (active) setEnabled(r.enabled); }).catch(() => { if (active) setError(t('security.unavailable')); }); return () => { active = false; }; }, [t]);
  async function run(action: () => Promise<void>) {
    if (busy) return; setBusy(true); setError('');
    try { await action(); } catch (e) { setError(e instanceof ApiError ? e.message : t('security.unavailable')); } finally { setBusy(false); }
  }
  const input = 'w-full rounded border border-blue-400/30 bg-slate px-3 py-2 text-sm';
  const button = 'is-new rounded border border-blue-400/50 bg-blue-500/15 px-3 py-2 text-sm text-blue-200 disabled:opacity-40';
  return <section data-new="2026-11-07" className="space-y-3 rounded-xl border border-blue-400/40 bg-midnight p-5">
    {/* Nouveau : sécurité locale Google Authenticator, aucun QR externe. */}
    <h2 className="text-sm font-semibold text-blue-300">{t('security.title')}</h2>
    <p className="text-xs">{enabled === null ? '…' : enabled ? t('security.enabled') : t('security.disabled')}</p>
    {error && <p role="alert" className="text-sm text-red-300">{error}</p>}
    <label className="block text-xs">{t('account.current')}<input className={input} type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} /></label>
    {!enabled && !setup && <button className={button} disabled={busy || !password || enabled === null} onClick={() => void run(async () => { setSetup(await securityApi.setup(password)); setRecovery([]); })}>{t('security.setup')}</button>}
    {setup && <div className="space-y-2">
      <div className="inline-block rounded bg-white p-3"><QRCodeSVG value={setup.uri} size={180} /></div>
      <p className="break-all font-mono text-xs" aria-label={t('security.manual')}>{setup.secret}</p>
      <p className="text-xs">{t('security.scan')}</p>
    </div>}
    {(setup || enabled) && <label className="block text-xs">{t('security.code')}<input className={input} autoComplete="one-time-code" inputMode="numeric" value={code} onChange={e => setCode(e.target.value.trim())} /></label>}
    {setup && <button className={button} disabled={busy || !code || !password} onClick={() => void run(async () => { const r = await securityApi.confirm(password, code); setRecovery(r.recovery_codes); setSetup(null); setEnabled(true); setCode(''); setPassword(''); })}>{t('security.confirm')}</button>}
    {enabled && <button className={button} disabled={busy || !code || !password} onClick={() => void run(async () => { await securityApi.disable(password, code); setEnabled(false); setRecovery([]); setPassword(''); setCode(''); })}>{t('security.disable')}</button>}
    {recovery.length > 0 && <div role="status" className="rounded border border-amber-400/40 p-3"><p className="mb-2 text-xs">{t('security.recovery')}</p><pre className="select-all text-sm">{recovery.join('\n')}</pre></div>}
    <button className={button} disabled={busy} onClick={() => { if (window.confirm(t('security.logoutConfirm'))) void run(async () => { await securityApi.logoutAll(); onLogout(); }); }}>{t('security.logoutAll')}</button>
  </section>;
}
