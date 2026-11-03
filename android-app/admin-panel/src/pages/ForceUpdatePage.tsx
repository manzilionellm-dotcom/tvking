import { useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { confirmAction } from '@/components/confirm';
import { forceUpdateApi, ApiError } from '@/lib/api';

/// Page « Mise à jour forcée » (owner uniquement) — un bouton qui oblige
/// TOUS les utilisateurs sur une version plus ancienne à mettre à jour.
///
/// minBuildTs / publishedBuildTs sont des secondes epoch. « Forcer » pose
/// minBuildTs = version publiée vérifiée : les apps antérieures affichent
/// l'écran « Nouvelle version disponible » au prochain lancement, mais
/// PAS celles déjà sur la dernière version. « Désactiver » remet à 0.

function fmt(ts: number): string {
  if (!ts) return '—';
  return new Date(ts * 1000).toLocaleString();
}

export function ForceUpdatePage({ onLogout }: { onLogout: () => void }) {
  const [minBuildTs, setMinBuildTs] = useState(0);
  const [configuredMinBuildTs, setConfiguredMinBuildTs] = useState(0);
  const [publishedBuildTs, setPublishedBuildTs] = useState(0);
  const [observedLatestBuildTs, setObservedLatestBuildTs] = useState(0);
  const [canForce, setCanForce] = useState(false);
  const [blockedReason, setBlockedReason] = useState('');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [platform, setPlatform] = useState<'mobile' | 'tv'>('mobile');
  const [knownPlatform, setKnownPlatform] = useState<'mobile' | 'tv' | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const writing = useRef(false);
  const locked = busy || loading || knownPlatform !== platform;

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  useEffect(() => {
    let active = true;
    setLoading(true); setKnownPlatform(null); setOk(null); setErr(null);
    forceUpdateApi.get(platform)
      .then((r) => {
        if (!active) return;
        if (!Number.isFinite(r.minBuildTs) || !Number.isFinite(r.latestBuildTs)) throw new Error('Version invalide');
        const published = r.publishedBuildTs ?? 0;
        const configured = r.configuredMinBuildTs ?? r.minBuildTs;
        const observed = r.observedLatestBuildTs ?? r.latestBuildTs;
        const verified = r.canForce === true && Number.isFinite(published) && published > 0;
        setMinBuildTs(r.minBuildTs);
        setConfiguredMinBuildTs(Number.isFinite(configured) ? configured : r.minBuildTs);
        setPublishedBuildTs(Number.isFinite(published) && published > 0 ? published : 0);
        setObservedLatestBuildTs(Number.isFinite(observed) && observed > 0 ? observed : 0);
        setCanForce(verified);
        setBlockedReason(typeof r.blockedReason === 'string' && r.blockedReason.trim()
          ? r.blockedReason : 'Aucun APK publié vérifié n’est disponible pour cette application.');
        setKnownPlatform(platform);
      })
      .catch((e) => { if (active) fail(e); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
    /* eslint-disable-next-line */
  }, [platform, reloadKey]);

  async function doForce() {
    if (writing.current || locked || !canForce || publishedBuildTs <= 0) return;
    writing.current = true; setBusy(true);
    try {
      const ok = await confirmAction({
        title: 'Forcer la mise à jour ?',
        message: 'Les APK compatibles installés directement proposeront la version requise. Les versions Google Play et les utilisateurs déjà à jour ne sont pas concernés.',
        confirmLabel: 'Forcer la mise à jour',
        danger: true,
      });
      if (!ok) return;
      setErr(null); setOk(null);
      const r = await forceUpdateApi.force(platform);
      if (r.ok !== true || !Number.isFinite(r.minBuildTs) || r.minBuildTs <= 0) throw new Error('Mise à jour non confirmée');
      setMinBuildTs(r.minBuildTs); setConfiguredMinBuildTs(r.minBuildTs);
      setOk('✅ Mise à jour forcée ACTIVÉE. Les anciennes versions seront '
        + 'bloquées à leur prochaine ouverture.');
    } catch (e) { fail(e); } finally { writing.current = false; setBusy(false); }
  }

  async function doDisable() {
    if (writing.current || locked || configuredMinBuildTs <= 0) return;
    writing.current = true;
    setBusy(true); setErr(null); setOk(null);
    try {
      const r = await forceUpdateApi.disable(platform);
      if (r.ok !== true || r.minBuildTs !== 0) throw new Error('Désactivation non confirmée');
      setMinBuildTs(0); setConfiguredMinBuildTs(0);
      setOk('Seuil de mise à jour désactivé pour cette application.');
    } catch (e) { fail(e); } finally { writing.current = false; setBusy(false); }
  }

  const active = minBuildTs > 0;

  return (
    <AppLayout
      title="Mise à jour forcée"
      subtitle="Mise à jour des APK installés directement — les versions Play restent gérées par Google Play"
      onLogout={onLogout}
    >
      {/* Bascule 📱 Mobile / 📺 TV : forçage indépendant par app. */}
      <div className="mb-5 inline-flex rounded-lg border border-white/10 bg-slate p-1">
        {([['mobile', '7 MOTION'], ['tv', 'ZUNO']] as const).map(([p, label]) => (
          <button
            key={p}
            onClick={() => setPlatform(p)}
            disabled={busy}
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
        ) : knownPlatform !== platform ? (
          <button onClick={() => setReloadKey(value => value + 1)} className="rounded-md border border-white/10 px-4 py-2 text-sm">Réessayer le chargement</button>
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
                {active ? 'Forcée active' : configuredMinBuildTs > 0 ? 'Seuil suspendu' : 'Inactive'}
              </span>
            </div>

            <div className="space-y-1 text-xs text-ink-tertiary">
              <div>Version publiée vérifiée : <span className="text-ink-secondary">{canForce ? fmt(publishedBuildTs) : 'Indisponible'}</span></div>
              {observedLatestBuildTs > 0 && (
                <div>Version signalée par un appareil : {fmt(observedLatestBuildTs)} — ne permet pas de forcer une mise à jour.</div>
              )}
              {!active && configuredMinBuildTs > 0 && (
                <div>Un ancien seuil est enregistré, mais son APK n’est pas vérifié. Tu peux le désactiver.</div>
              )}
              {active && (
                <div>Versions antérieures au <span className="text-ink-secondary">{fmt(minBuildTs)}</span> bloquées.</div>
              )}
            </div>

            {/* Explication */}
            <p className="rounded-md border border-white/5 bg-slate px-3 py-2 text-xs leading-relaxed text-ink-secondary">
              Le bouton <b>Forcer la mise à jour</b> utilise uniquement un APK
              réellement disponible sur le canal de téléchargement des clients.
              Un build de test ou une version signalée par un appareil ne suffit pas.
              Les clients déjà à jour ne sont pas concernés.
            </p>

            {/* Boutons */}
            <div className="flex gap-2">
              <button
                type="button"
                onClick={doForce}
                disabled={locked || !canForce || publishedBuildTs <= 0}
                className="flex-1 rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
              >
                {busy ? '…' : 'Forcer la mise à jour'}
              </button>
              <button
                type="button"
                onClick={doDisable}
                disabled={locked || configuredMinBuildTs <= 0}
                className="rounded-md border border-white/10 px-4 py-2.5 text-sm text-ink-secondary transition hover:bg-white/5 disabled:opacity-40"
              >
                Désactiver
              </button>
            </div>

            {!canForce && (
              <p className="text-[11px] text-amber-300/80">
                Forçage indisponible. {blockedReason}
              </p>
            )}
          </>
        )}
      </div>
    </AppLayout>
  );
}
