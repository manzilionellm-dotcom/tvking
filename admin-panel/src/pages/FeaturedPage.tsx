import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { featuredApi, ApiError } from '@/lib/api';

/// Page « Favori du jour » (owner) — met une chaîne en avant chaque jour
/// pour que l'app vive au quotidien. Ex. « TF1 » + « Mondial aujourd'hui ⚽ ».
/// L'app affiche cette chaîne dans son grand HERO d'accueil. Vide = rien.

export function FeaturedPage({ onLogout }: { onLogout: () => void }) {
  const [name, setName] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  useEffect(() => {
    featuredApi.get()
      .then((r) => { setName(r.name || ''); setNote(r.note || ''); })
      .catch(fail)
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    try {
      await featuredApi.set(name.trim(), note.trim());
      setOk(name.trim()
        ? `✅ « ${name.trim()} » est le favori du jour. Visible dans l'app à la prochaine ouverture.`
        : 'Favori du jour retiré. L\'app affiche son accueil normal.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function clear() {
    setName(''); setNote('');
    setBusy(true); setErr(null); setOk(null);
    try {
      await featuredApi.set('', '');
      setOk('Favori du jour retiré.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Favori du jour"
      subtitle="Mets une chaîne en avant chaque jour — l'app vit au quotidien"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 max-w-lg rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}
      {ok && (
        <div className="mb-4 max-w-lg rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
          {ok}
        </div>
      )}

      {loading ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <form onSubmit={save} className="max-w-lg space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Nom de la chaîne à mettre en avant
            </label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoFocus
              maxLength={80}
              placeholder="Ex. TF1"
              className={inputCls}
            />
            <p className="mt-1 text-[10px] text-ink-tertiary">
              Doit correspondre au nom d'une chaîne de la playlist du client
              (recherche souple). Si absente chez lui, l'app affiche son HERO normal.
            </p>
          </div>

          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Note (optionnel)
            </label>
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={120}
              placeholder="Ex. Mondial aujourd'hui ⚽"
              className={inputCls}
            />
          </div>

          <div className="flex gap-2">
            <button
              type="submit"
              disabled={busy}
              className="flex-1 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
            >
              {busy ? '…' : 'Publier le favori du jour'}
            </button>
            <button
              type="button"
              onClick={clear}
              disabled={busy}
              className="rounded-md border border-white/10 px-4 py-2.5 text-sm text-ink-secondary transition hover:bg-white/5 disabled:opacity-50"
            >
              Retirer
            </button>
          </div>
        </form>
      )}
    </AppLayout>
  );
}
