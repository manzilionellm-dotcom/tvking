import { useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  homeLayoutApi, type HomeSection, type HomeLayoutSnapshot,
  HOME_RIBBONS, HOME_SECTION_LABELS, ApiError,
} from '@/lib/api';

/// Page « Accueil » (Centre de contrôle, Module 1/8) — owner uniquement.
/// Pilote en TEMPS RÉEL l'accueil de l'app, sans mise à jour de store :
///   - réordonner les sections par glisser-déposer (ou flèches) ;
///   - afficher / masquer une section ;
///   - mettre une section en vedette ;
///   - lui attacher un ruban (NOUVEAU, EN DIRECT, COUPE DU MONDE, …).
/// « Publier » écrit la disposition (PUT). Chaque publication archive
/// l'état précédent → restauration en un clic (rollback).

// Couleur d'un ruban (cohérent avec _RibbonBadge côté app).
function ribbonColor(r: string): string {
  switch (r) {
    case 'NOUVEAU': return '#5FA975';
    case 'EXCLUSIF':
    case 'VIP': return '#D69847';
    case 'EN DIRECT':
    case 'COUPE DU MONDE':
    case 'EURO 2028':
    case 'UFC':
    case 'CHAMPIONS LEAGUE': return '#E84A3E';
    case 'POPULAIRE': return '#D63A30';
    default: return '#7E7872';
  }
}

export function HomeManagerPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<HomeSection[]>([]);
  const [history, setHistory] = useState<HomeLayoutSnapshot[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [dragIdx, setDragIdx] = useState<number | null>(null);

  function fail(e: any) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
  }

  function load() {
    setLoading(true);
    homeLayoutApi.get()
      .then((r) => setItems(r.items))
      .catch(fail)
      .finally(() => setLoading(false));
    homeLayoutApi.history().then((r) => setHistory(r.items)).catch(() => {});
  }

  useEffect(() => { load(); /* eslint-disable-next-line */ }, []);

  function mutate(next: HomeSection[]) {
    setItems(next.map((it, i) => ({ ...it, position: i })));
    setDirty(true);
    setOk(null);
  }

  function move(from: number, to: number) {
    if (to < 0 || to >= items.length || from === to) return;
    const next = [...items];
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    mutate(next);
  }

  function toggle(i: number, field: 'enabled' | 'featured') {
    const next = [...items];
    next[i] = { ...next[i], [field]: next[i][field] ? 0 : 1 };
    mutate(next);
  }

  function setRibbon(i: number, ribbon: string) {
    const next = [...items];
    next[i] = { ...next[i], ribbon };
    mutate(next);
  }

  async function publish() {
    setBusy(true); setErr(null); setOk(null);
    try {
      const r = await homeLayoutApi.save(items, 'Disposition accueil');
      setItems(r.items);
      setDirty(false);
      setOk('Accueil publié ✅ — visible dans l\'app en quelques secondes.');
      homeLayoutApi.history().then((h) => setHistory(h.items)).catch(() => {});
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function restore(id: number) {
    if (!window.confirm('Restaurer cette version de l\'accueil ?')) return;
    setBusy(true); setErr(null); setOk(null);
    try {
      await homeLayoutApi.restore(id);
      setOk('Version restaurée ✅');
      load();
      setDirty(false);
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  return (
    <AppLayout
      title="Accueil"
      subtitle="Réorganise les sections de l'app en temps réel — ordre, visibilité, rubans, vedette (sans mise à jour du store)"
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}
      {ok && (
        <div className="mb-4 rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
          {ok}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_280px]">
        {/* ===== Liste des sections ===== */}
        <div>
          <div className="mb-3 flex items-center justify-between">
            <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">
              Sections de l'accueil — glisse pour réorganiser
            </div>
            <button
              type="button"
              onClick={publish}
              disabled={busy || !dirty}
              className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-40"
            >
              {busy ? 'Publication…' : dirty ? 'Publier' : 'Publié ✓'}
            </button>
          </div>

          {loading ? (
            <div className="text-sm text-ink-tertiary">Chargement…</div>
          ) : (
            <ul className="space-y-2">
              {items.map((it, i) => (
                <li
                  key={it.key}
                  draggable
                  onDragStart={() => setDragIdx(i)}
                  onDragOver={(e) => e.preventDefault()}
                  onDrop={() => {
                    if (dragIdx !== null) move(dragIdx, i);
                    setDragIdx(null);
                  }}
                  className={`flex items-center gap-3 rounded-lg border bg-midnight px-3 py-2.5 transition ${
                    dragIdx === i ? 'border-accent/60 opacity-60' : 'border-white/5'
                  } ${it.enabled ? '' : 'opacity-50'}`}
                >
                  {/* Poignée + flèches */}
                  <div className="flex flex-col items-center gap-0.5 text-ink-tertiary">
                    <button type="button" onClick={() => move(i, i - 1)}
                      className="hover:text-ink-primary" title="Monter">▲</button>
                    <span className="cursor-grab select-none text-base leading-none" title="Glisser">⋮⋮</span>
                    <button type="button" onClick={() => move(i, i + 1)}
                      className="hover:text-ink-primary" title="Descendre">▼</button>
                  </div>

                  {/* Position + nom */}
                  <div className="w-6 text-center text-xs font-bold text-ink-tertiary">
                    {i + 1}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-semibold text-ink-primary">
                      {HOME_SECTION_LABELS[it.key] ?? it.key}
                    </div>
                    {it.ribbon && (
                      <span
                        className="mt-1 inline-block rounded px-1.5 py-0.5 text-[9px] font-black tracking-wide"
                        style={{
                          color: ribbonColor(it.ribbon),
                          backgroundColor: `${ribbonColor(it.ribbon)}22`,
                        }}
                      >
                        {it.ribbon}
                      </span>
                    )}
                  </div>

                  {/* Ruban */}
                  <select
                    value={it.ribbon || ''}
                    onChange={(e) => setRibbon(i, e.target.value)}
                    className="rounded-md border border-white/10 bg-slate px-2 py-1.5 text-xs outline-none focus:ring-1 focus:ring-accent"
                  >
                    {HOME_RIBBONS.map((r) => (
                      <option key={r} value={r}>{r === '' ? '— ruban —' : r}</option>
                    ))}
                  </select>

                  {/* Vedette */}
                  <button
                    type="button"
                    onClick={() => toggle(i, 'featured')}
                    title="Mettre en vedette"
                    className={`rounded-md px-2 py-1.5 text-sm transition ${
                      it.featured ? 'text-amber-400' : 'text-ink-tertiary hover:text-ink-secondary'
                    }`}
                  >
                    {it.featured ? '★' : '☆'}
                  </button>

                  {/* Visible / masqué */}
                  <button
                    type="button"
                    onClick={() => toggle(i, 'enabled')}
                    title={it.enabled ? 'Masquer' : 'Afficher'}
                    className={`rounded-md border px-2.5 py-1.5 text-xs font-medium transition ${
                      it.enabled
                        ? 'border-success/40 text-success'
                        : 'border-white/10 text-ink-tertiary'
                    }`}
                  >
                    {it.enabled ? 'Visible' : 'Masqué'}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* ===== Historique / Rollback ===== */}
        <div className="lg:sticky lg:top-6 lg:self-start">
          <div className="mb-2 text-[10px] uppercase tracking-widest text-ink-tertiary">
            Historique (rollback)
          </div>
          {history.length === 0 ? (
            <div className="rounded-lg border border-white/5 bg-midnight px-4 py-3 text-xs text-ink-tertiary">
              Aucune version archivée pour l'instant.
            </div>
          ) : (
            <ul className="space-y-2">
              {history.map((h) => (
                <li
                  key={h.id}
                  className="flex items-center justify-between gap-2 rounded-lg border border-white/5 bg-midnight px-3 py-2"
                >
                  <div className="min-w-0">
                    <div className="truncate text-xs text-ink-secondary">{h.label}</div>
                    <div className="text-[10px] text-ink-tertiary">
                      {new Date(h.created_at).toLocaleString()}
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => restore(h.id)}
                    disabled={busy}
                    className="shrink-0 rounded-md border border-white/10 px-2.5 py-1 text-[11px] text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright disabled:opacity-40"
                  >
                    Restaurer
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
