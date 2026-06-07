import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  announcementsApi, type Announcement, ApiError,
} from '@/lib/api';

/// Page « Notifications » (owner uniquement) — écrire un message qui
/// part à TOUS les utilisateurs. Il s'affiche comme une notification
/// douce sur leur téléphone à la prochaine ouverture de l'app.
///
/// Au submit → POST /api/v1/announcements. L'app lit la dernière annonce
/// via GET /api/announcement au démarrage (et ne la montre qu'une fois).
export function NotificationsPage({ onLogout }: { onLogout: () => void }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [recent, setRecent] = useState<Announcement[]>([]);

  function load() {
    announcementsApi.list()
      .then((r) => setRecent(r.items))
      .catch(() => {});
  }

  useEffect(() => { load(); }, []);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    setOk(null);
    if (!title.trim() && !body.trim()) {
      setErr('Écris au moins un titre ou un message.');
      setBusy(false);
      return;
    }
    try {
      await announcementsApi.create({ title: title.trim(), body: body.trim() });
      setOk(
        'Notification envoyée. Tes utilisateurs la verront à la prochaine '
        + "ouverture de l'app.",
      );
      setTitle('');
      setBody('');
      load();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : "Échec de l'envoi.");
    } finally {
      setBusy(false);
    }
  }

  async function clearAll() {
    setBusy(true);
    setErr(null);
    setOk(null);
    try {
      await announcementsApi.clear();
      setOk('Annonce retirée. Plus aucune notification ne sera affichée.');
      load();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Notifications"
      subtitle="Envoie un message à tous tes utilisateurs (notification douce dans l'app)"
      onLogout={onLogout}
    >
      <form
        onSubmit={submit}
        className="max-w-lg space-y-4 rounded-xl border border-white/5 bg-midnight p-6"
      >
        <div>
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Titre
          </label>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            autoFocus
            maxLength={120}
            placeholder="Ex. Nouveau contenu ajouté 🎬"
            className={inputCls}
          />
        </div>

        <div>
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Message
          </label>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={3}
            maxLength={500}
            placeholder="Ex. De nouvelles chaînes et films viennent d'arriver, bon visionnage !"
            className={inputCls}
          />
        </div>

        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {err}
          </div>
        )}
        {ok && (
          <div className="rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
            {ok}
          </div>
        )}

        <div className="flex gap-2">
          <button
            type="submit"
            disabled={busy}
            className="flex-1 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Envoi…' : 'Envoyer à tous'}
          </button>
          <button
            type="button"
            onClick={clearAll}
            disabled={busy}
            className="rounded-md border border-white/10 px-4 py-2.5 text-sm text-ink-secondary transition hover:bg-white/5 disabled:opacity-50"
          >
            Retirer l'annonce
          </button>
        </div>
      </form>

      {/* ===== Historique récent ===== */}
      {recent.length > 0 && (
        <div className="mt-6 max-w-lg">
          <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Dernières annonces
          </div>
          <ul className="space-y-2">
            {recent.map((aRow) => (
              <li
                key={aRow.id}
                className="rounded-lg border border-white/5 bg-midnight px-4 py-3"
              >
                {aRow.title && (
                  <div className="text-sm font-semibold text-ink-primary">
                    {aRow.title}
                  </div>
                )}
                {aRow.body && (
                  <div className="mt-0.5 text-xs text-ink-secondary">
                    {aRow.body}
                  </div>
                )}
                <div className="mt-1 text-[10px] text-ink-tertiary">
                  {new Date(aRow.created_at).toLocaleString()}
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </AppLayout>
  );
}
