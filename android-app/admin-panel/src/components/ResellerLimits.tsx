import { useEffect, useRef, useState } from 'react';
import { resellerPolicyApi, type ResellerPolicy, ApiError } from '@/lib/api';
import { useT } from '@/lib/i18n';
const PLANS = ['monthly','quarterly','biannual','yearly','lifetime','custom','trial','trial_2h','trial_24h','trial_3d','trial_7d','trial_30d'];
export function ResellerLimits({ id, label, onClose }: {id:string; label:string; onClose:()=>void}) {
  const t = useT();
  const form = useRef<HTMLFormElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const controls = () => Array.from(form.current?.querySelectorAll<HTMLElement>('input:not(:disabled),button:not(:disabled),select:not(:disabled),[tabindex="0"]') ?? []);
    controls()[0]?.focus();
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); onClose(); }
      if (event.key === 'Tab') {
        const items = controls(); const first = items[0]; const last = items[items.length - 1];
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
      }
    };
    document.addEventListener('keydown', key);
    return () => { document.removeEventListener('keydown', key); previous?.focus(); };
  }, [onClose]);
  const [policy,setPolicy] = useState<ResellerPolicy | null>(null);
  const [error,setError] = useState(''); const [busy,setBusy] = useState(false);
  useEffect(() => { let live=true; resellerPolicyApi.get(id).then(r=>{if(live)setPolicy(r);}).catch(e=>{if(live)setError(e instanceof ApiError?e.message:t('security.unavailable'));});return()=>{live=false;}; },[id,t]);
  return <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4" role="dialog" aria-modal="true" aria-label={t('limits.title')}>
    <form ref={form} data-new="2026-11-07" className="max-h-[90vh] w-full max-w-lg space-y-4 overflow-auto rounded-xl border border-blue-400/40 bg-midnight p-6" onSubmit={e=>{e.preventDefault();if(!policy||busy)return;setBusy(true);setError('');void resellerPolicyApi.save(id,policy).then(onClose).catch(e=>setError(e instanceof ApiError?e.message:t('security.unavailable'))).finally(()=>setBusy(false));}}>
      <h2 className="font-semibold text-blue-300">{t('limits.title')} — {label}</h2>
      {error&&<p role="alert" className="text-red-300">{error}</p>}
      {policy&&<>
        <label className="block text-xs">{t('limits.activations')}<input type="number" min={0} value={policy.max_activations??''} onChange={e=>setPolicy({...policy,max_activations:e.target.value===''?null:Number(e.target.value)})} className="mt-1 w-full rounded bg-slate p-2" /></label>
        <label className="block text-xs">{t('limits.expiry')}<input type="datetime-local" value={policy.expires_at?new Date(policy.expires_at-new Date(policy.expires_at).getTimezoneOffset()*60000).toISOString().slice(0,16):''} onChange={e=>setPolicy({...policy,expires_at:e.target.value?new Date(e.target.value).getTime():null})} className="mt-1 w-full rounded bg-slate p-2" /></label>
        <label className="block text-xs">{t('limits.children')}<input type="number" min={0} value={policy.max_sub_resellers} onChange={e=>setPolicy({...policy,max_sub_resellers:Number(e.target.value)})} className="mt-1 w-full rounded bg-slate p-2" /></label>
        <fieldset><legend className="mb-2 text-xs">{t('limits.plans')}</legend><div className="grid grid-cols-2 gap-2">{PLANS.map(plan=><label key={plan} className="text-xs"><input type="checkbox" checked={policy.allowed_plans.includes(plan)} onChange={e=>setPolicy({...policy,allowed_plans:e.target.checked?[...policy.allowed_plans,plan]:policy.allowed_plans.filter(p=>p!==plan)})} /> {plan}</label>)}</div></fieldset>
        <p className="text-xs text-ink-tertiary">{t('limits.note')}</p>
      </>}
      <div className="flex justify-end gap-3"><button type="button" onClick={onClose}>{t('common.cancel')}</button><button className="is-new rounded border border-blue-400 bg-blue-500/20 px-3 py-2 text-blue-200" disabled={busy||!policy} type="submit">{t('common.save')}</button></div>
    </form>
  </div>;
}
