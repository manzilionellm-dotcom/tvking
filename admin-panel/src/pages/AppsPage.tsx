import { FormEvent, ReactNode, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { CopyLink } from '@/components/CopyLink';
import { appsApi, type App, ApiError } from '@/lib/api';

export function AppsPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<App[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  // App en cours d'édition (null = aucune). Réutilise la même modale.
  const [editApp, setEditApp] = useState<App | null>(null);

  function reload() {
    setLoading(true);
    appsApi.list()
      .then((r) => { setItems(r.items); setErr(null); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => setLoading(false));
  }

  useEffect(reload, [onLogout]);

  // Variantes retirées (Red Room, NOVA) restent cachées.
  // L'app TV officielle (id app_thefew_tv, affichage « 7 MOTION TV »)
  // reste visible. Les IDs package ne sont jamais renommés.
  const REMOVED = /redroom|red\s*room|sevenmotion\.tv|seven-?tv|nova/i;
  const isOfficialTv = (a: App) =>
    a.id === 'app_thefew_tv' ||
    /defew\s*tv|7\s*motion\s*tv/i.test(a.name || '');
  const visible = items.filter(
    (a) =>
      isOfficialTv(a) ||
      (!REMOVED.test(a.package_name || '') && !REMOVED.test(a.name || '')),
  );

  return (
    <AppLayout
      title="Applications"
      subtitle="Ajoute autant d'apps que tu veux (nom, package, branding, prix)."
      onLogout={onLogout}
      actions={
        <button
          onClick={() => setShowCreate(true)}
          className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black hover:bg-accent-bright"
        >
          + Nouvelle app
        </button>
      }
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      {loading && (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {[0, 1].map((i) => (
            <div key={i} className="h-32 animate-pulse rounded-xl border border-white/5 bg-midnight" />
          ))}
        </div>
      )}

      {!loading && (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {visible.map((a) => (
            <div key={a.id} className="rounded-xl border border-white/5 bg-midnight p-5">
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-3">
                  <span
                    className="h-8 w-8 shrink-0 rounded-lg ring-1 ring-white/10"
                    style={{ backgroundColor: a.primary_color || '#D63A30' }}
                  />
                  <div>
                    <p className="text-base font-semibold tracking-tight">{a.name}</p>
                    <p className="mt-0.5 font-mono text-[11px] text-ink-tertiary">{a.package_name}</p>
                  </div>
                </div>
                <span
                  className={`rounded-sm px-2 py-0.5 text-[9px] uppercase tracking-widest ${
                    a.is_active ? 'bg-accent/20 text-accent' : 'bg-white/5 text-ink-tertiary'
                  }`}
                >
                  {a.is_active ? 'Active' : 'Inactive'}
                </span>
              </div>
              {a.tagline && <p className="mt-3 text-xs text-ink-secondary">{a.tagline}</p>}
              {a.download_url && (
                <div className="mt-4">
                  <p className="mb-1.5 text-[10px] uppercase tracking-widest text-ink-tertiary">
                    Lien de téléchargement (à donner au client)
                  </p>
                  <CopyLink url={a.download_url} />
                </div>
              )}
              <div className="mt-4 flex justify-end">
                <button
                  onClick={() => setEditApp(a)}
                  className="rounded-md border border-white/10 px-3 py-1.5 text-xs font-medium text-ink-secondary transition hover:border-accent hover:text-ink-primary"
                >
                  ✎ Modifier
                </button>
              </div>
            </div>
          ))}
          {visible.length === 0 && (
            <div className="col-span-full rounded-xl border border-dashed border-white/10 p-8 text-center text-sm text-ink-tertiary">
              Aucune app. Clique « + Nouvelle app » pour en créer une.
            </div>
          )}
        </div>
      )}

      {(showCreate || editApp) && (
        <AppModal
          app={editApp}
          onClose={() => { setShowCreate(false); setEditApp(null); }}
          onSaved={() => { setShowCreate(false); setEditApp(null); reload(); }}
        />
      )}
    </AppLayout>
  );
}

/// Modale CRÉATION ou ÉDITION d'app. Si `app` est fourni → édition
/// (PATCH), sinon création (POST). Sert notamment à corriger le LIEN
/// DE TÉLÉCHARGEMENT donné aux clients.
function AppModal({
  app, onClose, onSaved,
}: { app: App | null; onClose: () => void; onSaved: () => void }) {
  const editing = !!app;
  const [name, setName] = useState(app?.name ?? '');
  const [pkg, setPkg] = useState(app?.package_name ?? '');
  const [tagline, setTagline] = useState(app?.tagline ?? '');
  const [color, setColor] = useState(app?.primary_color ?? '#D63A30');
  const [download, setDownload] = useState(app?.download_url ?? '');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!name.trim() || !pkg.trim()) {
      setErr('Le nom et le package sont obligatoires.');
      return;
    }
    setBusy(true); setErr(null);
    const payload = {
      name: name.trim(),
      package_name: pkg.trim(),
      tagline: tagline.trim() || null,
      primary_color: color,
      download_url: download.trim() || null,
    };
    try {
      if (editing && app) {
        await appsApi.update(app.id, payload);
      } else {
        await appsApi.create(payload);
      }
      onSaved();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Enregistrement impossible.');
    } finally { setBusy(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h2 className="mb-4 text-lg font-semibold tracking-tight">
          {editing ? 'Modifier l\'application' : 'Nouvelle application'}
        </h2>
        <form onSubmit={submit} className="space-y-3">
          <Field label="Nom de l'app">
            <input value={name} onChange={(e) => setName(e.target.value)} className={inputCls} placeholder="Ex. The Few" autoFocus />
          </Field>
          <Field label="Package (identifiant Android)">
            <input value={pkg} onChange={(e) => setPkg(e.target.value)} className={`${inputCls} font-mono`} placeholder="com.exemple.monapp" />
          </Field>
          <Field label="Slogan (optionnel)">
            <input value={tagline} onChange={(e) => setTagline(e.target.value)} className={inputCls} placeholder="THE FEW · NOT FOR EVERYONE" />
          </Field>
          <Field label="Couleur principale">
            <div className="flex items-center gap-3">
              <input type="color" value={color} onChange={(e) => setColor(e.target.value)} className="h-9 w-12 cursor-pointer rounded border border-white/10 bg-slate" />
              <input value={color} onChange={(e) => setColor(e.target.value)} className={`${inputCls} font-mono`} />
            </div>
          </Field>
          <Field label="Lien de téléchargement (à donner aux clients)">
            <input value={download} onChange={(e) => setDownload(e.target.value)} className={`${inputCls} font-mono`} placeholder="https://app.7themotion.com/vip" />
          </Field>
          {err && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Annuler</button>
            <button type="submit" disabled={busy || !name || !pkg} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
              {busy ? 'Enregistrement…' : (editing ? 'Enregistrer' : 'Créer l\'app')}
            </button>
          </div>
        </form>
      </div>
    </div>
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
