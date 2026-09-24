import { FormEvent, ReactNode, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { serversApi, type DefaultServer, ApiError } from '@/lib/api';

// =========================================================
//  ServersPage — gestion des serveurs IPTV par défaut
// =========================================================
//  Ces serveurs sont ceux proposés dans l'app cliente. Le client
//  ne saisit JAMAIS d'URL : il choisit « Serveur 1 / 2 / 3… » et tape
//  seulement son code Xtream. On peut ici ajouter autant de serveurs
//  qu'on veut, changer leur lien, les renommer, les (dés)activer.
//  L'app les récupère via GET /api/servers.
// =========================================================

export function ServersPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<DefaultServer[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [editing, setEditing] = useState<DefaultServer | null>(null);

  function reload() {
    setLoading(true);
    serversApi.list()
      .then((r) => { setItems(r.items); setErr(null); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => setLoading(false));
  }

  useEffect(reload, [onLogout]);

  async function toggleEnabled(s: DefaultServer) {
    try {
      await serversApi.update(s.id, { enabled: !s.enabled });
      reload();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Mise à jour impossible.');
    }
  }

  async function remove(s: DefaultServer) {
    if (!confirm(`Supprimer « ${s.label} » ? Le client ne pourra plus le choisir.`)) {
      return;
    }
    try {
      await serversApi.remove(s.id);
      reload();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Suppression impossible.');
    }
  }

  return (
    <AppLayout
      title="Serveurs"
      subtitle="Serveurs proposés dans l'app (« Serveur 1, 2, 3… »). Le client choisit et saisit juste son code — l'URL reste cachée."
      onLogout={onLogout}
      actions={
        <button
          onClick={() => setShowCreate(true)}
          className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black hover:bg-accent-bright"
        >
          + Nouveau serveur
        </button>
      }
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      {loading && (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-20 animate-pulse rounded-xl border border-white/5 bg-midnight" />
          ))}
        </div>
      )}

      {!loading && (
        <div className="space-y-3">
          {items.map((s) => (
            <div key={s.id} className="rounded-xl border border-white/5 bg-midnight p-5">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-base font-semibold tracking-tight">{s.label}</p>
                    <span
                      className={`rounded-sm px-2 py-0.5 text-[9px] uppercase tracking-widest ${
                        s.enabled ? 'bg-accent/20 text-accent' : 'bg-white/5 text-ink-tertiary'
                      }`}
                    >
                      {s.enabled ? 'Visible' : 'Masqué'}
                    </span>
                  </div>
                  <p className="mt-1 truncate font-mono text-[11px] text-ink-tertiary">{s.url}</p>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <button
                    onClick={() => toggleEnabled(s)}
                    className="rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
                  >
                    {s.enabled ? 'Masquer' : 'Afficher'}
                  </button>
                  <button
                    onClick={() => setEditing(s)}
                    className="rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
                  >
                    Modifier
                  </button>
                  <button
                    onClick={() => remove(s)}
                    className="rounded-md border border-accent/30 px-2.5 py-1.5 text-xs text-accent hover:bg-accent/10"
                  >
                    Supprimer
                  </button>
                </div>
              </div>
            </div>
          ))}
          {items.length === 0 && (
            <div className="rounded-xl border border-dashed border-white/10 p-8 text-center text-sm text-ink-tertiary">
              Aucun serveur. Clique « + Nouveau serveur » pour en ajouter un.
            </div>
          )}
        </div>
      )}

      {(showCreate || editing) && (
        <ServerModal
          server={editing}
          onClose={() => { setShowCreate(false); setEditing(null); }}
          onSaved={() => { setShowCreate(false); setEditing(null); reload(); }}
        />
      )}
    </AppLayout>
  );
}

function ServerModal({
  server, onClose, onSaved,
}: { server: DefaultServer | null; onClose: () => void; onSaved: () => void }) {
  const isEdit = server !== null;
  const [label, setLabel] = useState(server?.label ?? '');
  const [url, setUrl] = useState(server?.url ?? '');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!label.trim() || !url.trim()) {
      setErr('Le nom et le lien sont obligatoires.');
      return;
    }
    setBusy(true); setErr(null);
    try {
      if (isEdit && server) {
        await serversApi.update(server.id, { label: label.trim(), url: url.trim() });
      } else {
        await serversApi.create({ label: label.trim(), url: url.trim() });
      }
      onSaved();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Enregistrement impossible.');
    } finally { setBusy(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={onClose}>
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h2 className="mb-1 text-lg font-semibold tracking-tight">
          {isEdit ? 'Modifier le serveur' : 'Nouveau serveur'}
        </h2>
        <p className="mb-4 text-xs text-ink-tertiary">
          Le client verra le nom (« Serveur 1 »…) mais jamais le lien.
        </p>
        <form onSubmit={submit} className="space-y-3">
          <Field label="Nom affiché dans l'app">
            <input value={label} onChange={(e) => setLabel(e.target.value)} className={inputCls} placeholder="Serveur 1" autoFocus />
          </Field>
          <Field label="Lien Xtream (caché côté client)">
            <input value={url} onChange={(e) => setUrl(e.target.value)} className={`${inputCls} font-mono`} placeholder="http://exemple.com:8080" />
          </Field>
          {err && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={onClose} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Annuler</button>
            <button type="submit" disabled={busy || !label || !url} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
              {busy ? 'Enregistrement…' : isEdit ? 'Enregistrer' : 'Ajouter'}
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
