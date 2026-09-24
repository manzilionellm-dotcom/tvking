import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { feedbackApi, flagEmoji, type FeedbackItem, ApiError } from '@/lib/api';

// =========================================================
//  ReviewsPage — Avis clients (owner)
// =========================================================
//  Deux blocs :
//    1. L'INVITATION : un message doux que l'app montre au client pour
//       l'inviter à écrire son avis / ses idées d'amélioration.
//    2. LES AVIS REÇUS : la liste de ce que les clients ont envoyé.
// =========================================================

export function ReviewsPage({ onLogout }: { onLogout: () => void }) {
  const [enabled, setEnabled] = useState(false);
  const [message, setMessage] = useState('');
  const [items, setItems] = useState<FeedbackItem[]>([]);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  function loadList() {
    feedbackApi.list().then((r) => setItems(r.items || [])).catch(fail);
  }

  useEffect(() => {
    Promise.all([feedbackApi.getPrompt(), feedbackApi.list()])
      .then(([p, l]) => {
        setEnabled(!!p.enabled);
        setMessage(p.message || '');
        setItems(l.items || []);
      })
      .catch(fail)
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  async function savePrompt(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    try {
      await feedbackApi.savePrompt({ enabled, message: message.trim() });
      setOk(enabled
        ? '✅ Invitation active — les clients verront le message à l\'ouverture.'
        : 'Invitation désactivée.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  const fmtDate = (ms: number) =>
    new Date(ms).toLocaleString('fr-FR', {
      day: '2-digit', month: '2-digit', year: '2-digit',
      hour: '2-digit', minute: '2-digit',
    });

  return (
    <AppLayout
      title="Avis clients"
      subtitle="Invite les clients à donner leur avis — et lis leurs réponses"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 max-w-3xl rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
      )}
      {ok && (
        <div className="mb-4 max-w-3xl rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{ok}</div>
      )}

      {loading ? (
        <div className="text-sm text-ink-tertiary">Chargement…</div>
      ) : (
        <div className="space-y-8">
          {/* ===== Invitation ===== */}
          <form onSubmit={savePrompt} className="max-w-2xl space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
            <h3 className="text-sm font-semibold">Message d'invitation</h3>
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm">Afficher l'invitation dans l'app</span>
              <button
                type="button"
                onClick={() => setEnabled((v) => !v)}
                className={'relative h-6 w-11 rounded-full transition ' + (enabled ? 'bg-accent' : 'bg-white/15')}
              >
                <span className={'absolute top-0.5 h-5 w-5 rounded-full bg-white transition ' + (enabled ? 'left-[22px]' : 'left-0.5')} />
              </button>
            </label>
            <div>
              <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                Texte du message
              </label>
              <textarea
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                rows={3}
                maxLength={500}
                placeholder="Ex. Ton avis compte ! Dis-nous comment améliorer l'application 🙏"
                className={inputCls}
              />
            </div>
            <button
              type="submit"
              disabled={busy}
              className="rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50"
            >
              {busy ? '…' : 'Enregistrer l\'invitation'}
            </button>
          </form>

          {/* ===== Avis reçus ===== */}
          <div>
            <div className="mb-3 flex items-center justify-between">
              <h3 className="text-sm font-semibold">
                Avis reçus <span className="text-ink-tertiary">({items.length})</span>
              </h3>
              <button
                onClick={loadList}
                className="rounded-md border border-white/10 px-3 py-1.5 text-xs text-ink-secondary hover:bg-white/5"
              >
                ↻ Rafraîchir
              </button>
            </div>
            {items.length === 0 ? (
              <div className="rounded-xl border border-dashed border-white/10 p-8 text-center text-sm text-ink-tertiary">
                Aucun avis pour l'instant.
              </div>
            ) : (
              <div className="space-y-3">
                {items.map((it) => (
                  <div key={it.id} className="rounded-xl border border-white/5 bg-midnight p-4">
                    <div className="mb-1.5 flex items-center gap-2 text-[11px] text-ink-tertiary">
                      {it.rating > 0 && (
                        <span className="text-amber-400">
                          {'★'.repeat(it.rating)}{'☆'.repeat(5 - it.rating)}
                        </span>
                      )}
                      {it.country && <span>{flagEmoji(it.country)} {it.country}</span>}
                      {it.mac && <span className="font-mono">{it.mac}</span>}
                      <span className="ml-auto">{fmtDate(it.created_at)}</span>
                    </div>
                    <p className="whitespace-pre-wrap text-sm text-ink-secondary">{it.message}</p>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </AppLayout>
  );
}
