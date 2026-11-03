import { FormEvent, useEffect, useRef, useState } from 'react';
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
  const [known, setKnown] = useState(false);
  const writing = useRef(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  function load() {
    setLoading(true); setKnown(false); setErr(null);
    featuredApi.get()
      .then((r) => {
        if (typeof r.name !== 'string' || typeof r.note !== 'string') throw new Error('Réponse invalide');
        setName(r.name); setNote(r.note); setKnown(true);
      })
      .catch(fail)
      .finally(() => setLoading(false));
  }

  useEffect(() => { load(); /* eslint-disable-next-line */ }, []);

  async function save(e: FormEvent) {
    e.preventDefault();
    if (writing.current || !known || loading) return;
    writing.current = true;
    setBusy(true); setErr(null); setOk(null);
    try {
      const saved = await featuredApi.set(name.trim(), note.trim());
      if (saved.ok !== true) throw new Error('Enregistrement non confirmé');
      setOk(name.trim()
        ? `✅ « ${name.trim()} » est le favori du jour. Enregistré pour les accueils compatibles ZUNO et 7 MOTION, si cette chaîne est disponible et la carte activée.`
        : 'Favori du jour retiré. L\'app affiche son accueil normal.');
    } catch (e) { fail(e); } finally { writing.current = false; setBusy(false); }
  }

  async function clear() {
    if (writing.current || !known || loading) return;
    writing.current = true;
    setBusy(true); setErr(null); setOk(null);
    try {
      const saved = await featuredApi.set('', '');
      if (saved.ok !== true) throw new Error('Suppression non confirmée');
      setName(''); setNote('');
      setOk('Favori du jour retiré.');
    } catch (e) { fail(e); } finally { writing.current = false; setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Favori du jour"
      subtitle="Mise en avant sur les nouveaux accueils ZUNO et 7 MOTION, à partir des chaînes déjà ajoutées par le client"
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
      ) : !known ? (
        <button onClick={load} className="rounded-md border border-white/10 px-4 py-2 text-sm">Réessayer le chargement</button>
      ) : (
        <form onSubmit={save} className="max-w-lg space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          <fieldset disabled={busy} className="space-y-4">
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
          </fieldset>
        </form>
      )}
    </AppLayout>
  );
}
