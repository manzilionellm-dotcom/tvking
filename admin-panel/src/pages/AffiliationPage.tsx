import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { ApiError, Campaign, CampaignInput, campaignsApi } from '@/lib/api';

// =========================================================
//  AffiliationPage — Affiliation & Pubs (owner)
// =========================================================
//  Campagnes cliquables NON intrusives affichées dans l'app : une carte
//  discrète (image + titre + bouton « Acheter »/CTA) sur l'accueil.
//  Gérable ici sans recompiler l'app ; le clic ouvre le lien
//  d'affiliation nativement sur Android. Stats impressions/clics/CTR
//  par campagne + export CSV.
// =========================================================

const emptyForm: CampaignInput = {
  kind: 'banner',
  title: '',
  body: '',
  image_url: '',
  target_url: '',
  cta: '',
  placement: 'home',
  start_hour: null,
  end_hour: null,
  enabled: true,
};

export function AffiliationPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<Campaign[]>([]);
  const [form, setForm] = useState<CampaignInput>({ ...emptyForm });
  const [editingId, setEditingId] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function fail(e: unknown) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  async function refresh() {
    try {
      const r = await campaignsApi.list();
      setItems(r.campaigns);
    } catch (e) { fail(e); }
  }

  useEffect(() => {
    refresh().finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  function startEdit(c: Campaign) {
    setEditingId(c.id);
    setForm({
      kind: c.kind,
      title: c.title,
      body: c.body,
      image_url: c.image_url,
      target_url: c.target_url,
      cta: c.cta,
      placement: c.placement,
      start_hour: c.start_hour,
      end_hour: c.end_hour,
      enabled: c.enabled,
    });
    setOk(null); setErr(null);
  }

  function cancelEdit() {
    setEditingId(null);
    setForm({ ...emptyForm });
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    try {
      if (editingId == null) {
        await campaignsApi.create(form);
        setOk('✅ Campagne créée — visible dans les apps en quelques secondes.');
      } else {
        await campaignsApi.update(editingId, form);
        setOk('✅ Campagne mise à jour.');
      }
      cancelEdit();
      await refresh();
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function toggle(c: Campaign) {
    setErr(null);
    try {
      await campaignsApi.update(c.id, { enabled: !c.enabled });
      await refresh();
    } catch (e) { fail(e); }
  }

  async function remove(c: Campaign) {
    if (!window.confirm(`Supprimer la campagne « ${c.title || c.target_url} » ?`)) return;
    setErr(null);
    try {
      await campaignsApi.remove(c.id);
      await refresh();
    } catch (e) { fail(e); }
  }

  function exportCsv() {
    const head = ['id', 'type', 'titre', 'lien', 'placement', 'active',
      'impressions', 'clics', 'ctr_pct', 'creee_le'];
    const rows = items.map((c) => [
      c.id,
      c.kind,
      csvCell(c.title),
      csvCell(c.target_url),
      c.placement,
      c.enabled ? 'oui' : 'non',
      c.impressions,
      c.clicks,
      ctr(c),
      c.created_at ? new Date(c.created_at).toISOString() : '',
    ].join(','));
    const blob = new Blob(['﻿' + [head.join(','), ...rows].join('\n')],
      { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'campagnes-affiliation.csv';
    a.click();
    URL.revokeObjectURL(a.href);
  }

  const totalImp = items.reduce((n, c) => n + c.impressions, 0);
  const totalClk = items.reduce((n, c) => n + c.clicks, 0);

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';
  const labelCls = 'mb-1 block text-xs text-ink-tertiary';

  return (
    <AppLayout
      title="Affiliation & Pubs"
      subtitle="Cartes cliquables discrètes dans l'app — liens d'affiliation, stats en direct"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 max-w-5xl rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
      )}
      {ok && (
        <div className="mb-4 max-w-5xl rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{ok}</div>
      )}

      {loading ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <div className="max-w-5xl space-y-6">
          {/* ----- Totaux ----- */}
          <div className="flex flex-wrap items-center gap-4">
            <Stat label="Campagnes" value={String(items.length)} />
            <Stat label="Impressions" value={String(totalImp)} />
            <Stat label="Clics" value={String(totalClk)} />
            <Stat label="CTR" value={totalImp > 0 ? ((totalClk / totalImp) * 100).toFixed(1) + ' %' : '—'} />
            <button
              type="button"
              onClick={exportCsv}
              disabled={items.length === 0}
              className="ml-auto rounded-md border border-white/10 px-3 py-1.5 text-xs hover:bg-white/5 disabled:opacity-40"
            >
              Export CSV
            </button>
          </div>

          {/* ----- Formulaire ----- */}
          <form onSubmit={save} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
            <div className="text-sm font-medium">
              {editingId == null ? 'Nouvelle campagne' : `Modifier la campagne #${editingId}`}
            </div>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div>
                <label className={labelCls}>Type</label>
                <select
                  className={inputCls}
                  value={form.kind}
                  onChange={(e) => setForm({ ...form, kind: e.target.value === 'product' ? 'product' : 'banner' })}
                >
                  <option value="banner">Bannière (image + titre)</option>
                  <option value="product">Produit (carte « Acheter »)</option>
                </select>
              </div>
              <div>
                <label className={labelCls}>Bouton (CTA) — ex. « Acheter »</label>
                <input className={inputCls} value={form.cta || ''} maxLength={40}
                  placeholder="Acheter"
                  onChange={(e) => setForm({ ...form, cta: e.target.value })} />
              </div>
              <div>
                <label className={labelCls}>Titre</label>
                <input className={inputCls} value={form.title || ''} maxLength={120}
                  placeholder="Maillot officiel 2026"
                  onChange={(e) => setForm({ ...form, title: e.target.value })} />
              </div>
              <div>
                <label className={labelCls}>Texte (optionnel)</label>
                <input className={inputCls} value={form.body || ''} maxLength={300}
                  placeholder="Petit descriptif discret"
                  onChange={(e) => setForm({ ...form, body: e.target.value })} />
              </div>
              <div>
                <label className={labelCls}>Image (URL, optionnelle)</label>
                <input className={inputCls} value={form.image_url || ''} maxLength={500}
                  placeholder="https://…/banniere.png"
                  onChange={(e) => setForm({ ...form, image_url: e.target.value })} />
              </div>
              <div>
                <label className={labelCls}>Lien d'affiliation (obligatoire)</label>
                <input className={inputCls} value={form.target_url || ''} maxLength={500}
                  placeholder="https://partenaire.com/produit?aff=moi" required
                  onChange={(e) => setForm({ ...form, target_url: e.target.value })} />
              </div>
              <div>
                <label className={labelCls}>Heure de début (0-23, vide = toujours)</label>
                <input className={inputCls} value={form.start_hour ?? ''} inputMode="numeric"
                  placeholder="ex. 18"
                  onChange={(e) => setForm({ ...form, start_hour: hourOrNull(e.target.value) })} />
              </div>
              <div>
                <label className={labelCls}>Heure de fin (0-23, vide = toujours)</label>
                <input className={inputCls} value={form.end_hour ?? ''} inputMode="numeric"
                  placeholder="ex. 23"
                  onChange={(e) => setForm({ ...form, end_hour: hourOrNull(e.target.value) })} />
              </div>
            </div>
            <div className="flex items-center gap-3">
              <button type="submit" disabled={busy}
                className="rounded-md bg-accent px-4 py-2 text-sm font-medium disabled:opacity-50">
                {editingId == null ? 'Créer la campagne' : 'Enregistrer'}
              </button>
              {editingId != null && (
                <button type="button" onClick={cancelEdit}
                  className="rounded-md border border-white/10 px-4 py-2 text-sm hover:bg-white/5">
                  Annuler
                </button>
              )}
              <span className="text-xs text-ink-tertiary">
                Diffusé aux apps en temps réel — aucun rebuild nécessaire.
              </span>
            </div>
          </form>

          {/* ----- Liste ----- */}
          <div className="overflow-x-auto rounded-xl border border-white/5 bg-midnight">
            <table className="w-full text-left text-sm">
              <thead className="text-xs text-ink-tertiary">
                <tr className="border-b border-white/5">
                  <th className="px-4 py-3">Campagne</th>
                  <th className="px-3 py-3">Type</th>
                  <th className="px-3 py-3">Heures</th>
                  <th className="px-3 py-3 text-right">Impr.</th>
                  <th className="px-3 py-3 text-right">Clics</th>
                  <th className="px-3 py-3 text-right">CTR</th>
                  <th className="px-3 py-3">Active</th>
                  <th className="px-3 py-3" />
                </tr>
              </thead>
              <tbody>
                {items.length === 0 && (
                  <tr><td colSpan={8} className="px-4 py-6 text-center text-xs text-ink-tertiary">
                    Aucune campagne — crée la première ci-dessus.
                  </td></tr>
                )}
                {items.map((c) => (
                  <tr key={c.id} className="border-b border-white/5 last:border-0">
                    <td className="px-4 py-3">
                      <div className="font-medium">{c.title || '(sans titre)'}</div>
                      <div className="max-w-[280px] truncate text-xs text-ink-tertiary">{c.target_url}</div>
                    </td>
                    <td className="px-3 py-3 text-xs">{c.kind === 'product' ? 'Produit' : 'Bannière'}</td>
                    <td className="px-3 py-3 text-xs">
                      {c.start_hour == null && c.end_hour == null
                        ? 'Toujours'
                        : `${c.start_hour ?? 0} h → ${c.end_hour ?? 23} h`}
                    </td>
                    <td className="px-3 py-3 text-right tabular-nums">{c.impressions}</td>
                    <td className="px-3 py-3 text-right tabular-nums">{c.clicks}</td>
                    <td className="px-3 py-3 text-right tabular-nums">{ctr(c)}{ctr(c) === '—' ? '' : ' %'}</td>
                    <td className="px-3 py-3">
                      <button type="button" onClick={() => toggle(c)}
                        className={'relative h-5 w-9 rounded-full transition ' + (c.enabled ? 'bg-accent' : 'bg-white/15')}>
                        <span className={'absolute top-0.5 h-4 w-4 rounded-full bg-white transition ' + (c.enabled ? 'left-[18px]' : 'left-0.5')} />
                      </button>
                    </td>
                    <td className="px-3 py-3 text-right">
                      <button type="button" onClick={() => startEdit(c)}
                        className="mr-2 text-xs text-ink-tertiary hover:text-white">Modifier</button>
                      <button type="button" onClick={() => remove(c)}
                        className="text-xs text-accent-bright hover:underline">Supprimer</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </AppLayout>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-white/5 bg-midnight px-4 py-2">
      <div className="text-lg font-semibold tabular-nums">{value}</div>
      <div className="text-xs text-ink-tertiary">{label}</div>
    </div>
  );
}

function ctr(c: Campaign): string {
  return c.impressions > 0 ? ((c.clicks / c.impressions) * 100).toFixed(1) : '—';
}

function hourOrNull(v: string): number | null {
  if (v.trim() === '') return null;
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n >= 0 && n <= 23 ? n : null;
}

/// Échappe une cellule CSV (guillemets si virgule/quote/retour ligne).
function csvCell(v: string): string {
  return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v;
}
