import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { forceUpdateApi, ApiError } from '@/lib/api';

/// Page « Mise à jour forcée » (owner uniquement) — un bouton qui oblige
/// TOUS les utilisateurs sur une version plus ancienne à mettre à jour.
///
/// minBuildTs / latestBuildTs sont des secondes epoch. « Forcer » pose
/// minBuildTs = dernier build connu : les apps antérieures affichent
/// l'écran « Nouvelle version disponible » au prochain lancement, mais
/// PAS celles déjà sur la dernière version. « Désactiver » remet à 0.

function fmt(ts: number): string {
  if (!ts) return '—';
  return new Date(ts * 1000).toLocaleString();
}

export function ForceUpdatePage({ onLogout }: { onLogout: () => void }) {
  const [minBuildTs, setMinBuildTs] = useState(0);
  const [latestBuildTs, setLatestBuildTs] = useState(0);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [platform, setPlatform] = useState<'mobile' | 'tv'>('mobile');

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  function load() {
    setLoading(true); setOk(null); setErr(null);
    forceUpdateApi.get(platform)
      .then((r) => { setMinBuildTs(r.minBuildTs); setLatestBuildTs(r.latestBuildTs); })
      .catch(fail)
      .finally(() => setLoading(false));
  }

  useEffect(() => { load(); /* eslint-disable-next-line */ }, [platform]);

  async function doForce() {
    if (!window.confirm(
      'Forcer la mise à jour ?\n\nTous les utilisateurs sur une version '
      + 'plus ancienne que la dernière verront un écran les obligeant à '
      + 'télécharger la nouvelle version. Les utilisateurs déjà à jour ne '
      + 'sont pas affectés.')) return;
    setBusy(true); setErr(null); setOk(null);
    try {
      const r = await forceUpdateApi.force(platform);
      setMinBuildTs(r.minBuildTs);
      setOk('✅ Mise à jour forcée ACTIVÉE. Les anciennes versions seront '
        + 'bloquées à leur prochaine ouverture.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function doDisable() {
    setBusy(true); setErr(null); setOk(null);
    try {
      const r = await forceUpdateApi.disable(platform);
      setMinBuildTs(r.minBuildTs);
      setOk('Mise à jour forcée désactivée. Plus aucun blocage.');
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  const active = minBuildTs > 0;

  return (
    <AppLayout
      title="Mise à jour forcée"
      subtitle="Oblige tous les utilisateurs à installer la dernière version — en un clic"
      onLogout={onLogout}
    >
      {/* Bascule 📱 Mobile / 📺 TV : forçage indépendant par app. */}
      <div className="mb-5 inline-flex rounded-lg border border-white/10 bg-slate p-1">
        {([['mobile', '📱 Mobile'], ['tv', '📺 TV']] as const).map(([p, label]) => (
          <button
            key={p}
            onClick={() => setPlatform(p)}
            className={
              'rounded-md px-4 py-2 text-sm font-semibold transition ' +
              (platform === p ? 'bg-accent text-black' : 'text-ink-secondary hover:text-ink-primary')
            }
          >
            {label}
          </button>
        ))}
      </div>

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

      <div className="max-w-lg space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
        {loading ? (
          <div className="text-sm text-ink-tertiary">Chargement…</div>
        ) : (
          <>
            {/* État */}
            <div className="flex items-center justify-between rounded-lg border border-white/5 bg-slate px-4 py-3">
              <span className="text-sm text-ink-secondary">État actuel</span>
              <span
                className={`rounded-full px-3 py-1 text-xs font-bold uppercase tracking-wide ${
                  active
                    ? 'border border-accent/40 bg-accent/10 text-accent-bright'
                    : 'border border-white/10 text-ink-tertiary'
                }`}
              >
                {active ? 'Forcée active' : 'Inactive'}
              </span>
            </div>

            <div className="space-y-1 text-xs text-ink-tertiary">
              <div>Dernière version connue : <span className="text-ink-secondary">{fmt(latestBuildTs)}</span></div>
              {active && (
                <div>Versions antérieures au <span className="text-ink-secondary">{fmt(minBuildTs)}</span> bloquées.</div>
              )}
            </div>

            {/* Explication */}
            <p className="rounded-md border border-white/5 bg-slate px-3 py-2 text-xs leading-relaxed text-ink-secondary">
              Quand tu publies une nouvelle version, appuie sur <b>Forcer la
              mise à jour</b> : tous ceux qui sont sur une version plus
              ancienne verront un écran les obligeant à télécharger la
              dernière. Ceux déjà à jour ne sont pas dérangés.
            </p>

            {/* Boutons */}
            <div className="flex gap-2">
              <button
                type="button"
                onClick={doForce}
                disabled={busy}
                className="flex-1 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
              >
                {busy ? '…' : 'Forcer la mise à jour'}
              </button>
              <button
                type="button"
                onClick={doDisable}
                disabled={busy || !active}
                className="rounded-md border border-white/10 px-4 py-2.5 text-sm text-ink-secondary transition hover:bg-white/5 disabled:opacity-40"
              >
                Désactiver
              </button>
            </div>

            {latestBuildTs === 0 && (
              <p className="text-[11px] text-amber-300/80">
                ⚠️ Aucune version récente détectée pour l'instant. Ouvre une
                fois la dernière app (elle se signale automatiquement), puis
                le bouton saura quelle version exiger.
              </p>
            )}
          </>
        )}
      </div>
    </AppLayout>
  );
}
