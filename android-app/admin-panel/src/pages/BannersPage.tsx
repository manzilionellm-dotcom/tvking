import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { bannersApi, ApiError, type PromoBannerItem } from '@/lib/api';

// Image promo de l'accueil box. Le Worker enregistre puis envoie
// l'ordre `banner` : la box relit /api/banners sans redémarrage.
// Une image qui n'est pas en https est refusée (la box l'ignorerait).

export function BannersPage({ onLogout }: { onLogout: () => void }) {
  const [id, setId] = useState('promo');
  const [image, setImage] = useState('');
  const [title, setTitle] = useState('');
  const [subtitle, setSubtitle] = useState('');
  const [channel, setChannel] = useState('');
  const [url, setUrl] = useState('');
  const [kids, setKids] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function fail(e: unknown) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  useEffect(() => {
    bannersApi.get()
      .then((r) => {
        const first = r.items?.[0];
        if (!first) return;
        setId(first.id || 'promo');
        setImage(first.image || '');
        setTitle(first.title || '');
        setSubtitle(first.subtitle || '');
        setChannel(first.channel || '');
        setUrl(first.url || '');
        setKids(!!first.kids);
      })
      .catch(fail)
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  function item(): PromoBannerItem {
    return {
      id: id.trim() || 'promo',
      image: image.trim(),
      title: title.trim(),
      subtitle: subtitle.trim(),
      label: 'Publicité',
      channel: channel.trim(),
      url: url.trim(),
      kids,
    };
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    try {
      const saved = await bannersApi.save(image.trim() ? [item()] : []);
      setOk(saved.items.length
        ? 'Bannière envoyée. La box la montre dès qu’elle reçoit l’ordre (1–2 s si elle est allumée).'
        : 'Bannière retirée. La box vide la carte à l’ordre suivant.');
    } catch (e2) { fail(e2); } finally { setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Bannières"
      subtitle="Image affichée en tête de l’accueil (libellé Publicité)"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 max-w-lg rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
      )}
      {ok && (
        <div className="mb-4 max-w-lg rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{ok}</div>
      )}
      {loading ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <form onSubmit={save} className="max-w-lg space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">Identifiant</label>
            <input value={id} onChange={(e) => setId(e.target.value)} className={inputCls} />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">Image https</label>
            <input value={image} onChange={(e) => setImage(e.target.value)} placeholder="https://…/promo.jpg" className={`${inputCls} font-mono`} />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">Titre</label>
            <input value={title} onChange={(e) => setTitle(e.target.value)} className={inputCls} />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">Sous-titre</label>
            <input value={subtitle} onChange={(e) => setSubtitle(e.target.value)} className={inputCls} />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">Chaîne à ouvrir (nom dans la liste)</label>
            <input value={channel} onChange={(e) => setChannel(e.target.value)} className={inputCls} />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">Lien https (QR, pas d’ouverture directe)</label>
            <input value={url} onChange={(e) => setUrl(e.target.value)} className={`${inputCls} font-mono`} />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={kids} onChange={(e) => setKids(e.target.checked)} />
            Visible aussi en mode enfants
          </label>
          <button
            type="submit"
            disabled={busy}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50"
          >
            {busy ? '…' : 'Envoyer à la box'}
          </button>
        </form>
      )}
    </AppLayout>
  );
}
