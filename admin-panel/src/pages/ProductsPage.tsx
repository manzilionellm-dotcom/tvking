import { FormEvent, useCallback, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { productsApi, type Product, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

/// Page PRODUITS — « si je veux publier quelque chose : un nouveau
/// produit, un accès… ». L'owner crée des cartes produit (titre,
/// description, image, prix, bouton d'action, badge) et les publie /
/// dépublie d'un clic. L'app les lit via GET /api/products (public) —
/// publication visible sur tout le parc en quelques secondes.

type Draft = {
  title: string;
  description: string;
  image_url: string;
  price_label: string;
  cta_label: string;
  cta_url: string;
  badge: string;
  position: string;
};

const emptyDraft = (): Draft => ({
  title: '', description: '', image_url: '', price_label: '',
  cta_label: '', cta_url: '', badge: '', position: '0',
});

export function ProductsPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Product[]>([]);
  const [draft, setDraft] = useState<Draft>(emptyDraft());
  const [editId, setEditId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  const reload = useCallback(() => {
    productsApi.list()
      .then((r) => setItems(r.items))
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
      });
  }, [onLogout]);

  useEffect(() => { reload(); }, [reload]);

  function startEdit(p: Product) {
    setEditId(p.id);
    setDraft({
      title: p.title,
      description: p.description || '',
      image_url: p.image_url || '',
      price_label: p.price_label || '',
      cta_label: p.cta_label || '',
      cta_url: p.cta_url || '',
      badge: p.badge || '',
      position: String(p.position ?? 0),
    });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    const payload = {
      title: draft.title.trim(),
      description: draft.description.trim() || null,
      image_url: draft.image_url.trim() || null,
      price_label: draft.price_label.trim() || null,
      cta_label: draft.cta_label.trim() || null,
      cta_url: draft.cta_url.trim() || null,
      badge: draft.badge.trim() || null,
      position: Number(draft.position) || 0,
    };
    try {
      if (editId) {
        await productsApi.update(editId, payload);
        setOk('Produit mis à jour — visible en quelques secondes dans les apps.');
      } else {
        await productsApi.create(payload);
        setOk('Produit publié — visible en quelques secondes dans les apps.');
      }
      setDraft(emptyDraft());
      setEditId(null);
      reload();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally {
      setBusy(false);
    }
  }

  async function toggleActive(p: Product) {
    try {
      await productsApi.update(p.id, { active: p.active ? 0 : 1 });
      reload();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) onLogout();
    }
  }

  async function remove(p: Product) {
    if (!window.confirm(`Supprimer « ${p.title} » ?`)) return;
    try {
      await productsApi.remove(p.id);
      if (editId === p.id) { setEditId(null); setDraft(emptyDraft()); }
      reload();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) onLogout();
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Produits & publications"
      subtitle="Publie un nouveau produit, une offre, un accès — en ligne sur tout le parc en quelques secondes."
      onLogout={onLogout}
    >
      <div className="grid max-w-5xl gap-6 lg:grid-cols-2">
        {/* ===== Éditeur ===== */}
        <form onSubmit={submit} className="space-y-3 rounded-xl border border-white/5 bg-midnight p-6">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold">
              {editId ? 'Modifier le produit' : 'Nouveau produit'}
            </h2>
            {editId && (
              <button type="button"
                onClick={() => { setEditId(null); setDraft(emptyDraft()); }}
                className="text-xs text-ink-tertiary hover:text-accent-bright">
                Annuler la modification
              </button>
            )}
          </div>

          <input value={draft.title} required maxLength={200}
            onChange={(e) => setDraft((d) => ({ ...d, title: e.target.value }))}
            placeholder="Titre * (ex. Abonnement Premium 12 mois)" className={inputCls} />
          <textarea value={draft.description} rows={3} maxLength={2000}
            onChange={(e) => setDraft((d) => ({ ...d, description: e.target.value }))}
            placeholder="Description (ce que le client voit sous le titre)"
            className={inputCls + ' resize-none'} />
          <div className="grid grid-cols-2 gap-2">
            <input value={draft.price_label} maxLength={100}
              onChange={(e) => setDraft((d) => ({ ...d, price_label: e.target.value }))}
              placeholder="Prix affiché (ex. 49,99 €)" className={inputCls} />
            <input value={draft.badge} maxLength={40}
              onChange={(e) => setDraft((d) => ({ ...d, badge: e.target.value }))}
              placeholder="Badge (ex. NOUVEAU)" className={inputCls} />
          </div>
          <input value={draft.image_url} maxLength={1000}
            onChange={(e) => setDraft((d) => ({ ...d, image_url: e.target.value }))}
            placeholder="Image (URL https://…)" className={inputCls + ' font-mono'} />
          <div className="grid grid-cols-2 gap-2">
            <input value={draft.cta_label} maxLength={100}
              onChange={(e) => setDraft((d) => ({ ...d, cta_label: e.target.value }))}
              placeholder="Texte du bouton (ex. Commander)" className={inputCls} />
            <input value={draft.position}
              onChange={(e) => setDraft((d) => ({ ...d, position: e.target.value }))}
              placeholder="Ordre (0 = premier)" inputMode="numeric" className={inputCls} />
          </div>
          <input value={draft.cta_url} maxLength={1000}
            onChange={(e) => setDraft((d) => ({ ...d, cta_url: e.target.value }))}
            placeholder="Lien du bouton (https://… WhatsApp, site, paiement)"
            className={inputCls + ' font-mono'} />

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
          )}
          {ok && (
            <div className="rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{ok}</div>
          )}

          <button type="submit" disabled={busy || !draft.title.trim()}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50">
            {busy ? 'Publication…' : editId ? 'Enregistrer les modifications' : 'Publier le produit'}
          </button>
        </form>

        {/* ===== Catalogue ===== */}
        <div className="space-y-3">
          {items.length === 0 && (
            <div className="rounded-xl border border-white/5 bg-obsidian p-6 text-sm text-ink-tertiary">
              Aucun produit publié. Crée ta première carte : elle apparaîtra
              dans l'app (section offres) et via l'API publique
              <span className="font-mono"> /api/products</span>.
            </div>
          )}
          {items.map((p) => (
            <div key={p.id}
              className={
                'rounded-xl border p-4 transition ' +
                (p.active
                  ? 'border-white/10 bg-midnight'
                  : 'border-white/5 bg-obsidian opacity-60')
              }>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm font-semibold">{p.title}</span>
                    {p.badge && (
                      <span className="rounded-full bg-accent/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-widest text-accent-bright">
                        {p.badge}
                      </span>
                    )}
                    <span className={
                      'rounded-full px-2 py-0.5 text-[10px] uppercase tracking-widest ' +
                      (p.active ? 'bg-success/15 text-success' : 'bg-white/5 text-ink-tertiary')
                    }>
                      {p.active ? 'En ligne' : 'Hors ligne'}
                    </span>
                  </div>
                  {p.description && (
                    <p className="mt-1 line-clamp-2 text-xs text-ink-tertiary">{p.description}</p>
                  )}
                  <div className="mt-1 flex flex-wrap gap-3 text-[11px] text-ink-tertiary">
                    {p.price_label && <span className="font-medium text-champagne">{p.price_label}</span>}
                    {p.cta_url && <span className="truncate font-mono">{p.cta_url}</span>}
                    <span>maj {formatDateTime(p.updated_at)}</span>
                  </div>
                </div>
                {p.image_url && (
                  <img src={p.image_url} alt=""
                    className="h-14 w-14 shrink-0 rounded-lg object-cover ring-1 ring-white/10" />
                )}
              </div>
              <div className="mt-3 flex gap-2">
                <button onClick={() => toggleActive(p)}
                  className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                  {p.active ? 'Dépublier' : 'Publier'}
                </button>
                <button onClick={() => startEdit(p)}
                  className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                  Modifier
                </button>
                <button onClick={() => remove(p)}
                  className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                  Supprimer
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </AppLayout>
  );
}
