import { FormEvent, ReactNode, useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { confirmAction } from '@/components/confirm';
import { serversApi, type DefaultServer, ApiError } from '@/lib/api';

// =========================================================
//  ServersPage — gestion des serveurs IPTV par défaut
// =========================================================
//  Suggestions de serveur dans le formulaire Xtream. Le client choisit
//  volontairement un serveur puis saisit ses codes ; aucun flux n'est
//  importé ni démarré par la seule publication de ce catalogue.
// =========================================================

export function ServersPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<DefaultServer[]>([]);
  const [loading, setLoading] = useState(true);
  const [known, setKnown] = useState(false);
  const [busy, setBusy] = useState(false);
  const writing = useRef(false);
  const [err, setErr] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [editing, setEditing] = useState<DefaultServer | null>(null);

  function reload() {
    setLoading(true); setKnown(false);
    return serversApi.list()
      .then((r) => {
        if (!Array.isArray(r.items)) throw new Error('Liste de serveurs invalide');
        setItems(r.items); setKnown(true); setErr(null);
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e.message);
      })
      .finally(() => setLoading(false));
  }

  useEffect(() => { void reload(); }, [onLogout]);

  async function toggleEnabled(s: DefaultServer) {
    if (writing.current || loading || !known) return;
    writing.current = true; setBusy(true); setErr(null);
    try {
      const result = await serversApi.update(s.id, { enabled: !s.enabled });
      if (result.updated !== 1) throw new Error('Modification non confirmée');
      await reload();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Mise à jour impossible.');
    } finally { writing.current = false; setBusy(false); }
  }

  async function remove(s: DefaultServer) {
    if (writing.current || loading || !known) return;
    writing.current = true; setBusy(true);
    try {
      const ok = await confirmAction({
        title: 'Supprimer ce serveur ?',
        message: `Supprimer « ${s.label} » des suggestions ? Les listes déjà ajoutées par les clients restent inchangées.`,
        confirmLabel: 'Supprimer',
        danger: true,
      });
      if (!ok) return;
      const result = await serversApi.remove(s.id);
      if (result.deleted !== 1) throw new Error('Suppression non confirmée');
      await reload();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Suppression impossible.');
    } finally { writing.current = false; setBusy(false); }
  }

  return (
    <AppLayout
      title="Serveurs"
      subtitle="Serveurs proposés dans le formulaire Xtream des nouvelles applications. Le client choisit son serveur et ajoute ses propres identifiants."
      onLogout={onLogout}
      actions={
        <button
          disabled={loading || !known || busy}
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

      {!loading && !known && <button onClick={() => void reload()} className="rounded-md border border-white/10 px-4 py-2 text-sm">Réessayer le chargement</button>}

      {!loading && known && (
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
                      {s.enabled ? 'Proposé aux clients' : 'Masqué des suggestions'}
                    </span>
                  </div>
                  <p className="mt-1 truncate font-mono text-[11px] text-ink-tertiary">{s.url}</p>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <button
                    disabled={busy}
                    onClick={() => toggleEnabled(s)}
                    className="rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
                  >
                    {s.enabled ? 'Masquer' : 'Afficher'}
                  </button>
                  <button
                    disabled={busy}
                    onClick={() => setEditing(s)}
                    className="rounded-md border border-white/10 px-2.5 py-1.5 text-xs text-ink-secondary hover:bg-white/5 hover:text-ink-primary"
                  >
                    Modifier
                  </button>
                  <button
                    disabled={busy}
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
              Aucun serveur proposé. Le client peut toujours saisir son propre lien.
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
  const writing = useRef(false);
  const close = () => { if (!writing.current) onClose(); };

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (writing.current) return;
    if (!label.trim() || !url.trim()) {
      setErr('Le nom et le lien sont obligatoires.');
      return;
    }
    try {
      const parsed = new URL(url.trim());
      if (!['http:', 'https:'].includes(parsed.protocol) || !parsed.hostname || parsed.username || parsed.password) throw new Error();
    } catch { setErr('Saisis une adresse HTTP ou HTTPS de serveur, sans identifiants dans le lien.'); return; }
    writing.current = true;
    setBusy(true); setErr(null);
    try {
      if (isEdit && server) {
        const result = await serversApi.update(server.id, { label: label.trim(), url: url.trim() });
        if (result.updated !== 1) throw new Error('Modification non confirmée');
      } else {
        const result = await serversApi.create({ label: label.trim(), url: url.trim() });
        if (typeof result.id !== 'string' || !result.id) throw new Error('Création non confirmée');
      }
      onSaved();
    } catch (e: any) {
      setErr(e instanceof ApiError ? e.message : 'Enregistrement impossible.');
    } finally { writing.current = false; setBusy(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4" onClick={close}>
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <h2 className="mb-1 text-lg font-semibold tracking-tight">
          {isEdit ? 'Modifier le serveur' : 'Nouveau serveur'}
        </h2>
        <p className="mb-4 text-xs text-ink-tertiary">
          Le nom aide le client à choisir. Le lien est copié dans son formulaire ; aucun abonnement n’est ajouté automatiquement.
        </p>
        <form onSubmit={submit} className="space-y-3">
          <fieldset disabled={busy} className="space-y-3">
          <Field label="Nom affiché dans l'app">
            <input value={label} onChange={(e) => setLabel(e.target.value)} className={inputCls} placeholder="Serveur 1" maxLength={80} autoFocus />
          </Field>
          <Field label="Lien du serveur Xtream">
            <input value={url} onChange={(e) => setUrl(e.target.value)} className={`${inputCls} font-mono`} placeholder="http://exemple.com:8080" maxLength={2000} />
          </Field>
          {err && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
          <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={close} className="rounded-md px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">Annuler</button>
            <button type="submit" disabled={busy || !label || !url} className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black hover:bg-accent-bright disabled:opacity-50">
              {busy ? 'Enregistrement…' : isEdit ? 'Enregistrer' : 'Ajouter'}
            </button>
          </div>
          </fieldset>
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
