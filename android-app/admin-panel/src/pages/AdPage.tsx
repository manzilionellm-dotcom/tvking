import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { adApi, ApiError } from '@/lib/api';

// =========================================================
//  AdPage — vidéo publicitaire jouée au démarrage de l'app (owner)
// =========================================================
//  L'owner colle l'URL d'une vidéo (fichier direct .mp4/.m3u8). Quand un
//  client ouvre l'app, la vidéo se joue d'abord, avec un bouton « Passer »
//  qui apparaît après quelques secondes. Désactivable. Aperçu intégré.
// =========================================================

export function AdPage({ onLogout }: { onLogout: () => void }) {
  const [enabled, setEnabled] = useState(false);
  const [url, setUrl] = useState('');
  const [skip, setSkip] = useState(5);
  const [freq, setFreq] = useState<'always' | 'daily'>('always');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  useEffect(() => {
    adApi.get()
      .then((r) => {
        setEnabled(!!r.enabled);
        setUrl(r.url || '');
        setSkip(Number.isFinite(r.skip) ? r.skip : 5);
        setFreq(r.freq === 'daily' ? 'daily' : 'always');
      })
      .catch(fail)
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    try {
      await adApi.save({ enabled, url: url.trim(), skip, freq });
      setOk(enabled && url.trim()
        ? '✅ Pub vidéo active — elle se jouera au démarrage de l\'app.'
        : 'Pub vidéo désactivée.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';
  const isVideoUrl = /\.(mp4|m3u8|webm|mov|mkv)(\?|$)/i.test(url.trim());

  return (
    <AppLayout
      title="Pub vidéo"
      subtitle="Une vidéo qui se joue au démarrage de l'app (skippable)"
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
        <div className="grid max-w-4xl grid-cols-1 gap-6 md:grid-cols-2">
          <form onSubmit={save} className="space-y-5 rounded-xl border border-white/5 bg-midnight p-6">
            <label className="flex items-center justify-between gap-3">
              <span className="text-sm">Activer la pub au démarrage</span>
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
                URL de la vidéo (fichier .mp4 / .m3u8)
              </label>
              <input
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                placeholder="https://…/promo.mp4"
                className={`${inputCls} font-mono`}
              />
              <p className="mt-1 text-[10px] text-ink-tertiary">
                Lien direct vers un fichier vidéo. Les liens YouTube ne
                fonctionnent pas (il faut un fichier .mp4/.m3u8 hébergé).
              </p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                  « Passer » après (sec.)
                </label>
                <input
                  type="number" min={0} max={60}
                  value={skip}
                  onChange={(e) => setSkip(Math.max(0, Math.min(60, parseInt(e.target.value || '0', 10))))}
                  className={inputCls}
                />
              </div>
              <div>
                <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                  Fréquence
                </label>
                <select
                  value={freq}
                  onChange={(e) => setFreq(e.target.value === 'daily' ? 'daily' : 'always')}
                  className={inputCls}
                >
                  <option value="always">À chaque ouverture</option>
                  <option value="daily">Une fois par jour</option>
                </select>
              </div>
            </div>

            <button
              type="submit"
              disabled={busy}
              className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50"
            >
              {busy ? '…' : 'Enregistrer'}
            </button>
          </form>

          {/* Aperçu vidéo */}
          <div className="flex flex-col items-center">
            <div className="mb-3 text-[10px] uppercase tracking-widest text-ink-tertiary">Aperçu</div>
            {url.trim() && isVideoUrl ? (
              <video
                src={url.trim()}
                controls
                className="w-full max-w-sm rounded-xl border border-white/10 bg-black"
              />
            ) : (
              <div className="grid h-48 w-full max-w-sm place-items-center rounded-xl border border-dashed border-white/10 text-xs text-ink-tertiary">
                {url.trim() ? 'URL non reconnue comme vidéo' : 'Colle une URL .mp4 pour voir l\'aperçu'}
              </div>
            )}
          </div>
        </div>
      )}
    </AppLayout>
  );
}
