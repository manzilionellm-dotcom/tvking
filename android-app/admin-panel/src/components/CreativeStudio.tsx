import { useState, type CSSProperties } from 'react';
import { newCreative, type CampaignContent, type CampaignCreative } from '@/lib/campaigns';
import './creative-studio.css';

const templates = [{ id: 'orbit', title: 'Orbite', detail: 'Un halo en mouvement' }, { id: 'prism', title: 'Prisme', detail: 'Un volume lumineux' }, { id: 'spotlight', title: 'Vitrine', detail: 'Ton image en relief' }] as const;
const palettes = [{ id: 'ember', name: 'Braise' }, { id: 'ice', name: 'Glacier' }, { id: 'gold', name: 'Champagne' }] as const;
const input = 'w-full rounded-lg border border-white/10 bg-slate px-3 py-2.5 text-sm';

export function CreativeStudio({ value, onChange }: { value?: CampaignCreative | null; onChange: (value: CampaignCreative | null) => void }) {
  return <section className="space-y-4 rounded-xl border border-white/10 p-4" aria-label="Studio 3D">
    <div className="flex items-start justify-between gap-4"><div><h3 className="font-semibold">Studio 3D</h3><p className="mt-1 text-xs text-ink-secondary">Une petite carte animée à l’accueil de l’app.</p></div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!value} onChange={e => onChange(e.target.checked ? newCreative() : null)} />Activer le visuel 3D</label></div>
    {value && <>
      <div className="grid gap-2 sm:grid-cols-3">{templates.map(t => <button type="button" key={t.id} aria-pressed={value.template === t.id} onClick={() => onChange({ ...value, template: t.id })} className={`rounded-xl border p-3 text-left ${value.template === t.id ? 'border-accent bg-accent/10' : 'border-white/10'}`}><span className="block font-semibold">{t.title}</span><span className="text-xs text-ink-secondary">{t.detail}</span></button>)}</div>
      <div className="grid gap-3 sm:grid-cols-2"><label className="space-y-1 text-sm"><span>Ambiance</span><select aria-label="Ambiance" className={input} value={value.palette} onChange={e => onChange({ ...value, palette: e.target.value as CampaignCreative['palette'] })}>{palettes.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
      <label className="space-y-1 text-sm"><span>Petit badge</span><input className={input} maxLength={24} value={value.badge} onChange={e => onChange({ ...value, badge: e.target.value })} /></label></div>
      <label className="block space-y-1 text-sm"><span>Image publique HTTPS (facultative)</span><input className={input} type="url" maxLength={300} value={value.image_url} onChange={e => onChange({ ...value, image_url: e.target.value })} placeholder="https://…/produit.png" /></label>
      <div className="flex flex-wrap items-center gap-4"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={value.motion === 'gentle'} onChange={e => onChange({ ...value, motion: e.target.checked ? 'gentle' : 'still' })} />Mouvement doux</label><label className="flex items-center gap-2 text-sm">Durée de l’animation<select className={input} value={value.duration_seconds} onChange={e => onChange({ ...value, duration_seconds: Number(e.target.value) as 6 | 8 | 10 })}>{[6,8,10].map(n => <option key={n} value={n}>{n} s</option>)}</select></label></div>
      <p className="text-xs text-ink-secondary">L’animation s’arrête ensuite. La carte reste refermable et respecte le réglage « réduire les animations ». Les anciennes apps affichent le texte.</p>
    </>}
  </section>;
}

export function CreativePreview({ content }: { content: CampaignContent }) {
  const [replay, setReplay] = useState(0);
  const [failedImage, setFailedImage] = useState('');
  const c = content.creative;
  if (!c) return null;
  return <div><div key={`${replay}-${JSON.stringify(c)}`} className={`creative-card palette-${c.palette} template-${c.template} ${c.motion === 'gentle' ? 'creative-animate' : ''}`} style={{ '--creative-duration': `${c.duration_seconds}s` } as CSSProperties} aria-label="Aperçu de la publicité 3D">
    <span className="creative-disclosure">{content.type === 'event' ? 'ÉVÉNEMENT' : 'PUBLICITÉ'}</span>
    <div className="creative-stage" aria-hidden="true"><div className="creative-halo" /><div className="creative-object">{c.image_url && failedImage !== c.image_url ? <img src={c.image_url} referrerPolicy="no-referrer" alt="" onError={() => setFailedImage(c.image_url)} /> : <span className="creative-gem" />}</div></div>
    <div className="creative-copy"><span className="creative-badge">{c.badge}</span><h3>{content.title || 'Une nouvelle dimension'}</h3><p>{content.body || 'Ton message prend du relief.'}</p>{content.url && content.cta && <span className="creative-cta">{content.cta} <span aria-hidden="true">↗</span></span>}</div>
  </div><button type="button" className="mt-3 text-sm text-ink-secondary underline" onClick={() => setReplay(n => n + 1)}>Rejouer l’aperçu</button></div>;
}
