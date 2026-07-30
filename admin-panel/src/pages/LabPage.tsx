// =========================================================
//  LabPage — « 🔬 Labo du Maître » (ADMIN UNIQUEMENT)
// =========================================================
//  L'espace PRIVÉ du patron pour tester ses M3U sans qu'aucune
//  donnée ne sorte : les sources de test sont poussées uniquement
//  sur ses appareils maîtres, invisibles des revendeurs et des
//  clients, exclues des statistiques.
//
//  Trois endpoints (implémentés par un worker déployé EN PARALLÈLE) :
//    • GET    /api/v1/lab/sources      → { sources: [...] }
//    • POST   /api/v1/lab/sources      → crée + attache aux maîtres
//    • DELETE /api/v1/lab/sources/:id  → retire des maîtres + supprime
//
//  ⚠️ DÉFENSIF PAR CONSTRUCTION (même pattern qu'OverviewPage) :
//    - endpoint absent (404/501) → carte « Le Labo arrive bientôt » ;
//    - champ manquant → « — », JAMAIS de crash ;
//    - l'URL affichée est DÉJÀ masquée côté serveur (on ne fait que
//      la montrer en mono, on ne détient jamais le flux complet).
// =========================================================

import { useCallback, useEffect, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { toast } from '@/components/Toast';
import { labApi, ApiError, type LabSource } from '@/lib/api';
import { useT } from '@/lib/i18n';
import { cn, formatDateTime, toMillis } from '@/lib/utils';

/// Interpolation minimaliste : remplace {n} / {name} dans une clé i18n
/// (le t() du panel ne gère pas les variables — on le fait à la main,
/// comme les autres pages).
function fmt(s: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce(
    (acc, [k, v]) => acc.split(`{${k}}`).join(String(v)),
    s,
  );
}

/// Validation d'URL SIMPLE (demande produit) : http(s) uniquement.
/// On ne va pas plus loin — c'est un espace de test, le serveur revalide.
function isValidHttpUrl(raw: string): boolean {
  try {
    const u = new URL(raw.trim());
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch {
    return false;
  }
}

type LoadState =
  | { kind: 'loading' }
  | { kind: 'ready'; sources: LabSource[] }
  // « unavailable » = le worker ne connaît pas encore l'endpoint (404…)
  | { kind: 'unavailable' }
  | { kind: 'error'; message: string };

export function LabPage({ onLogout }: { onLogout: () => void }) {
  const t = useT();
  const [state, setState] = useState<LoadState>({ kind: 'loading' });
  // Numéro de requête : une réponse périmée ne doit jamais setState
  // (même garde-fou que le reste du panel).
  const seqRef = useRef(0);

  // ----- Formulaire d'ajout
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [formError, setFormError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  // ----- Suppression en cours (id de la source, pour désactiver SON bouton)
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const load = useCallback(() => {
    const seq = ++seqRef.current;
    setState({ kind: 'loading' });
    labApi.list()
      .then((r) => {
        if (seq !== seqRef.current) return;
        // Défense : réponse non conforme (proxy, HTML d'erreur…) →
        // « bientôt » plutôt qu'un crash de rendu.
        // `items` est le nom historique servi par le worker : on l'accepte
        // aussi, sinon un worker plus ancien que le panel affiche « bientôt »
        // sur un endpoint qui répond pourtant 200 avec la liste.
        const sources = Array.isArray(r?.sources) ? r.sources
          : (Array.isArray(r?.items) ? r.items : null);
        if (!sources) setState({ kind: 'unavailable' });
        else setState({ kind: 'ready', sources });
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        if (seq !== seqRef.current) return;
        // 404 / 501 : worker pas encore déployé avec cet endpoint —
        // c'est un état ATTENDU pendant la vague, pas une panne.
        if (e instanceof ApiError && (e.status === 404 || e.status === 501)) {
          setState({ kind: 'unavailable' });
        } else {
          setState({
            kind: 'error',
            message: e instanceof ApiError ? e.message : t('lab.errorTitle'),
          });
        }
      });
  }, [onLogout, t]);

  useEffect(() => { load(); }, [load]);
  // Démontage : invalide toute réponse encore en vol.
  useEffect(() => () => { seqRef.current += 1; }, []);

  // ----- Ajout d'une source : valider → POST → toast « Copiée sur N » → reload.
  const handleAdd = useCallback((e: React.FormEvent) => {
    e.preventDefault();
    const n = name.trim();
    const u = url.trim();
    if (!n) { setFormError(t('lab.nameRequired')); return; }
    if (!isValidHttpUrl(u)) { setFormError(t('lab.invalidUrl')); return; }
    setFormError(null);
    setAdding(true);
    labApi.create(n, u)
      .then((r) => {
        // Nombre d'appareils maîtres servis : réponse POST prioritaire,
        // sinon la fiche source, sinon 0 (défensif — worker en parallèle).
        const count = typeof r?.attached_masters === 'number'
          ? r.attached_masters
          : (typeof r?.source?.attached_masters === 'number' ? r.source.attached_masters : 0);
        toast(fmt(t('lab.addedOk'), { n: count }), 'success');
        setName('');
        setUrl('');
        load();
      })
      .catch((e2) => {
        if (e2 instanceof ApiError && e2.status === 401) { onLogout(); return; }
        if (e2 instanceof ApiError && (e2.status === 404 || e2.status === 501)) {
          // Le POST n'existe pas encore → même message doux que le GET.
          setState({ kind: 'unavailable' });
          return;
        }
        toast(e2 instanceof ApiError ? e2.message : t('lab.errorAdd'), 'error');
      })
      .finally(() => setAdding(false));
  }, [name, url, t, load, onLogout]);

  // ----- Suppression : confirmation explicite (la source part AUSSI des maîtres).
  const handleDelete = useCallback((s: LabSource) => {
    const label = s.name || s.id;
    if (!confirm(fmt(t('lab.deleteConfirm'), { name: label }))) return;
    setDeletingId(s.id);
    labApi.remove(s.id)
      .then(() => {
        toast(t('lab.deletedOk'), 'success');
        load();
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        toast(e instanceof ApiError ? e.message : t('lab.errorDelete'), 'error');
      })
      .finally(() => setDeletingId(null));
  }, [t, load, onLogout]);

  const ready = state.kind === 'ready';

  return (
    <AppLayout
      title={`🔬 ${t('lab.title')}`}
      subtitle={t('lab.subtitle')}
      onLogout={onLogout}
    >
      {/* ===== Bandeau : ici, TOUT est privé — dit clairement, en tête. ===== */}
      <div className="mb-6 rounded-xl border border-accent/30 bg-accent/10 px-5 py-4">
        <p className="text-sm font-semibold tracking-tight text-accent-bright">
          🔒 {t('lab.subtitle')}
        </p>
        <p className="mt-1 max-w-2xl text-xs leading-relaxed text-ink-secondary">
          {t('lab.banner')}
        </p>
      </div>

      {/* ===== États de chargement / indisponible / erreur ===== */}
      {state.kind === 'loading' && <LabSkeleton />}

      {state.kind === 'unavailable' && (
        <StateCard
          title={t('lab.soonTitle')}
          message={t('lab.soonMsg')}
          retryLabel={t('lab.retry')}
          onRetry={() => load()}
        />
      )}

      {state.kind === 'error' && (
        <StateCard
          tone="error"
          title={t('lab.errorTitle')}
          message={state.message}
          retryLabel={t('lab.retry')}
          onRetry={() => load()}
        />
      )}

      {ready && (
        <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
          {/* ===== Formulaire d'ajout ===== */}
          <div className="rounded-xl border border-white/5 bg-midnight px-5 py-4">
            <p className="mb-3 text-sm font-semibold tracking-tight">{t('lab.addTitle')}</p>
            <form onSubmit={handleAdd} className="space-y-3">
              <div>
                <label htmlFor="lab-name" className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                  {t('lab.name')}
                </label>
                <input
                  id="lab-name"
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder={t('lab.namePh')}
                  className="mt-1 w-full rounded-md border border-white/10 bg-obsidian px-3 py-2 text-sm text-ink-primary placeholder:text-ink-tertiary outline-none focus:ring-1 focus:ring-accent"
                />
              </div>
              <div>
                <label htmlFor="lab-url" className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                  {t('lab.url')}
                </label>
                <input
                  id="lab-url"
                  type="text"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  placeholder={t('lab.urlPh')}
                  // dir=ltr : une URL reste gauche→droite même en arabe (RTL).
                  dir="ltr"
                  className="mt-1 w-full rounded-md border border-white/10 bg-obsidian px-3 py-2 font-mono text-xs text-ink-primary placeholder:text-ink-tertiary outline-none focus:ring-1 focus:ring-accent"
                />
              </div>
              {formError && (
                <p className="text-xs text-accent-bright">{formError}</p>
              )}
              <button
                type="submit"
                disabled={adding}
                className="rounded-md border border-accent/40 bg-accent/15 px-4 py-2 text-xs font-semibold text-accent-bright transition hover:bg-accent/25 disabled:opacity-50"
              >
                {adding ? t('lab.adding') : t('lab.add')}
              </button>
            </form>
          </div>

          {/* ===== Liste des sources labo ===== */}
          <div className="rounded-xl border border-white/5 bg-midnight px-5 py-4">
            <div className="mb-3 flex items-center justify-between">
              <p className="text-sm font-semibold tracking-tight">{t('lab.listTitle')}</p>
              <span className="rounded-full bg-white/5 px-2 py-0.5 text-[11px] font-bold text-ink-tertiary">
                {state.sources.length}
              </span>
            </div>

            {state.sources.length === 0 && (
              <p className="py-2 text-xs text-ink-tertiary">{t('lab.empty')}</p>
            )}

            {state.sources.map((s) => {
              const createdMs = toMillis(s.created_at);
              const deleting = deletingId === s.id;
              return (
                <div
                  key={s.id}
                  className="border-t border-white/5 py-3 first:border-t-0"
                >
                  <div className="flex items-start gap-3">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-ink-primary">
                        {s.name || '—'}
                      </p>
                      {/* URL déjà masquée côté serveur — affichée telle
                          quelle, en mono, jamais reconstituée ici. */}
                      <p dir="ltr" className="mt-0.5 truncate font-mono text-[11px] text-ink-tertiary" title={s.url ?? undefined}>
                        {s.url || '—'}
                      </p>
                      <p className="mt-1 text-[10px] text-ink-tertiary">
                        {createdMs !== null ? formatDateTime(createdMs) : '—'}
                        {' · '}
                        <span className="text-ink-secondary">
                          {fmt(t('lab.masters'), { n: s.attached_masters ?? 0 })}
                        </span>
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleDelete(s)}
                      disabled={deleting}
                      className={cn(
                        'shrink-0 rounded-md border border-white/10 px-2.5 py-1.5 text-[11px] font-semibold text-ink-secondary transition',
                        'hover:border-accent/40 hover:text-accent-bright disabled:opacity-50',
                      )}
                    >
                      {deleting ? t('lab.deleting') : t('lab.delete')}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </AppLayout>
  );
}

// =========================================================
//  Briques d'état (mêmes gabarits sobres que le reste du panel)
// =========================================================

/// Écran d'état (endpoint absent / erreur) avec bouton « Réessayer ».
function StateCard({
  title, message, retryLabel, onRetry, tone,
}: {
  title: string; message: string; retryLabel: string;
  onRetry: () => void; tone?: 'error';
}) {
  return (
    <div className={cn(
      'rounded-xl border px-5 py-6',
      tone === 'error'
        ? 'border-accent/30 bg-accent/10'
        : 'border-white/10 bg-midnight',
    )}
    >
      <p className={cn(
        'text-sm font-semibold tracking-tight',
        tone === 'error' ? 'text-accent-bright' : 'text-ink-primary',
      )}
      >
        {title}
      </p>
      <p className="mt-1 max-w-xl text-xs leading-relaxed text-ink-secondary">{message}</p>
      <button
        type="button"
        onClick={onRetry}
        className="mt-4 rounded-md border border-white/10 px-3 py-1.5 text-xs font-semibold text-ink-secondary transition hover:border-accent/40 hover:text-ink-primary"
      >
        {retryLabel}
      </button>
    </div>
  );
}

/// Squelette de chargement : formulaire + liste (2 grandes cartes).
function LabSkeleton() {
  return (
    <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
      {Array.from({ length: 2 }).map((_, i) => (
        <div key={i} className="h-64 animate-pulse rounded-xl border border-white/5 bg-midnight" />
      ))}
    </div>
  );
}
