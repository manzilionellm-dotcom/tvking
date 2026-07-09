import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  appAccessApi, type AppAccessConfig, type AppAccessMode, ApiError,
} from '@/lib/api';

/// Page ACCÈS APP — l'interrupteur maître de l'application, séparé de
/// tout le reste (demande produit : « l'accès à l'application »).
///  • Ouvert       : fonctionnement normal.
///  • Maintenance  : l'app affiche le message, le contenu déjà chargé
///                   reste regardable.
///  • Verrouillé   : accès suspendu, message affiché (incident grave,
///                   migration serveur…).
/// Par plateforme (mobile / TV). Prise d'effet : quelques secondes
/// (bump global de synchro → toutes les apps re-vérifient).

const MODES: { id: AppAccessMode; label: string; desc: string; tone: string }[] = [
  {
    id: 'open', label: 'Ouvert',
    desc: 'Fonctionnement normal pour tous les clients.',
    tone: 'border-success bg-success/10 text-success',
  },
  {
    id: 'maintenance', label: 'Maintenance',
    desc: 'Bandeau de maintenance ; le contenu déjà chargé reste accessible.',
    tone: 'border-warn bg-warn/10 text-warn-bright',
  },
  {
    id: 'locked', label: 'Verrouillé',
    desc: 'Accès suspendu — seul ton message s\'affiche. À réserver aux urgences.',
    tone: 'border-accent bg-accent/10 text-accent-bright',
  },
];

const PLATFORMS = [
  { id: '', label: 'App mobile (7 MOTION)' },
  { id: 'tv', label: 'App TV (DeFew TV)' },
];

export function AppAccessPage({ onLogout }: { onLogout: () => void }) {
  const [platform, setPlatform] = useState('');
  const [cfg, setCfg] = useState<AppAccessConfig>({ mode: 'open', message: '' });
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [ok, setOk] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setOk(null); setErr(null);
    appAccessApi.get(platform || undefined)
      .then((r) => { if (active) setCfg(r); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [platform, onLogout]);

  async function save(next: AppAccessConfig) {
    setBusy(true); setOk(null); setErr(null);
    try {
      await appAccessApi.save(next, platform || undefined);
      setCfg(next);
      setOk(
        next.mode === 'open'
          ? 'Accès rouvert — effectif sur tout le parc en quelques secondes.'
          : `Mode « ${MODES.find((m) => m.id === next.mode)?.label} » appliqué — effectif en quelques secondes.`,
      );
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Échec de l\'enregistrement.');
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Accès à l'application"
      subtitle="Interrupteur maître — ouvert, maintenance ou verrouillé, par plateforme. Effet en quelques secondes."
      onLogout={onLogout}
    >
      <div className="max-w-2xl space-y-5">
        {/* Plateforme */}
        <div className="grid grid-cols-2 gap-2">
          {PLATFORMS.map((p) => (
            <button
              key={p.id}
              onClick={() => setPlatform(p.id)}
              className={
                'rounded-md border px-3 py-2 text-sm transition ' +
                (platform === p.id
                  ? 'border-accent bg-accent/10 text-ink-primary'
                  : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
              }
            >
              {p.label}
            </button>
          ))}
        </div>

        <div className="rounded-xl border border-white/5 bg-midnight p-6">
          {loading ? (
            <p className="text-sm text-ink-tertiary">Chargement…</p>
          ) : (
            <div className="space-y-4">
              <div className="space-y-2">
                {MODES.map((m) => {
                  const selected = cfg.mode === m.id;
                  return (
                    <button
                      key={m.id}
                      disabled={busy}
                      onClick={() => save({ ...cfg, mode: m.id })}
                      className={
                        'flex w-full items-start gap-3 rounded-lg border px-4 py-3 text-left transition disabled:opacity-60 ' +
                        (selected ? m.tone : 'border-white/5 bg-slate/40 text-ink-secondary hover:border-white/20')
                      }
                    >
                      <span className={
                        'mt-1 h-2.5 w-2.5 shrink-0 rounded-full ' +
                        (selected ? 'bg-current' : 'bg-white/20')
                      } />
                      <span>
                        <span className="block text-sm font-semibold">{m.label}</span>
                        <span className="block text-xs opacity-80">{m.desc}</span>
                      </span>
                    </button>
                  );
                })}
              </div>

              <div>
                <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
                  Message affiché aux clients (maintenance / verrouillage)
                </label>
                <textarea
                  value={cfg.message}
                  onChange={(e) => setCfg((c) => ({ ...c, message: e.target.value }))}
                  rows={3}
                  maxLength={500}
                  placeholder="Ex. Maintenance en cours — retour dans 30 minutes. Merci de votre patience !"
                  className={inputCls + ' resize-none'}
                />
                <button
                  disabled={busy}
                  onClick={() => save(cfg)}
                  className="mt-2 rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50"
                >
                  {busy ? 'Enregistrement…' : 'Enregistrer le message'}
                </button>
              </div>

              {ok && (
                <div className="rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">{ok}</div>
              )}
              {err && (
                <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
              )}
            </div>
          )}
        </div>

        <div className="rounded-lg border border-white/10 bg-slate/30 p-4 text-xs leading-relaxed text-ink-tertiary">
          <p className="mb-1 font-semibold text-ink-secondary">Comment ça marche</p>
          Le mode est servi par <span className="font-mono">GET /api/app-access</span> et
          embarqué dans la réponse de synchro : chaque app le re-vérifie en
          continu (moins de 20 secondes). « Verrouillé » ne désactive aucune
          licence — rouvrir remet tout le monde en service immédiatement.
        </div>
      </div>
    </AppLayout>
  );
}
