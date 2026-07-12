import { MacLink } from '@/components/MacLink';
import { useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { referencesApi, type ActivationReference, ApiError } from '@/lib/api';

// =========================================================
//  ReferencesPage — carnet MAC ↔ username (support)
// =========================================================
//  Pour chaque appareil activé : sa MAC + le(s) username(s) Xtream que tu
//  as mis (JAMAIS le mot de passe) + le nom du client. Une barre de
//  recherche pour retrouver vite quand un client appelle.
// =========================================================

function fmtDate(ms: number | null | undefined): string {
  if (!ms) return '—';
  try { return new Date(ms).toLocaleDateString('fr-FR'); } catch { return '—'; }
}

const PLAN_LABELS: Record<string, string> = {
  monthly: '1 mois', yearly: '1 an', lifetime: 'À vie',
  trial_24h: 'Essai 24 h', trial_48h: 'Essai 48 h', trial_7d: 'Essai 7 j',
};
function planLabel(p?: string | null): string {
  if (!p) return '—';
  return PLAN_LABELS[p] || p;
}

/// « il y a X » pour la dernière connexion.
function ago(ts?: number | null): string {
  if (!ts) return 'jamais';
  const s = Math.floor((Date.now() - ts) / 1000);
  if (s < 60) return `il y a ${s}s`;
  if (s < 3600) return `il y a ${Math.floor(s / 60)} min`;
  if (s < 86400) return `il y a ${Math.floor(s / 3600)} h`;
  return `il y a ${Math.floor(s / 86400)} j`;
}

/// Ce qu'il RESTE (le vrai « une année, ça reste combien ? ») : à vie,
/// jours restants (rouge sous 5 j), ou expiré.
function remainLabel(it: ActivationReference): { text: string; cls: string } {
  if (it.lifetime) return { text: 'À vie', cls: 'text-accent-bright' };
  if (it.status === 'expired') return { text: 'Expiré', cls: 'text-warning' };
  if (it.days_left != null) {
    const d = it.days_left;
    const cls = d <= 5 ? 'text-warning' : 'text-ink-primary';
    return { text: `${d} j restants`, cls };
  }
  return { text: '—', cls: 'text-ink-tertiary' };
}

/// Badge de statut (couleurs en dur → rendu garanti, pas de dépendance à
/// des classes Tailwind non définies dans le thème).
function RefStatus({ status }: { status: string }) {
  const map: Record<string, { bg: string; fg: string; label: string }> = {
    active: { bg: 'rgba(47,169,106,0.16)', fg: '#3FBE7C', label: 'Actif' },
    expired: { bg: 'rgba(214,160,48,0.16)', fg: '#E8B23A', label: 'Expiré' },
    frozen: { bg: 'rgba(46,125,214,0.16)', fg: '#5AA0E8', label: 'Gelé' },
    banned: { bg: 'rgba(214,58,48,0.20)', fg: '#FF5A4A', label: 'Banni' },
    none: { bg: 'rgba(255,255,255,0.05)', fg: '#7E7872', label: '—' },
  };
  const s = map[status] || map.none;
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[11px] font-medium"
      style={{ background: s.bg, color: s.fg }}
    >
      {s.label}
    </span>
  );
}

/// Tuile compacte de la vue d'ensemble.
function StatTile({
  label, value, tone,
}: {
  label: string;
  value: number;
  tone?: 'ok' | 'warn' | 'live';
}) {
  const color =
    tone === 'ok' ? 'text-emerald-400'
      : tone === 'warn' ? 'text-amber-400'
        : tone === 'live' ? 'text-sky-400'
          : 'text-ink-primary';
  return (
    <div className="rounded-xl border border-white/5 bg-midnight p-3">
      <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{label}</div>
      <div className={'mt-1 text-2xl font-bold ' + color}>{value}</div>
    </div>
  );
}

export function ReferencesPage({ onLogout }: { onLogout: () => void }) {
  const [items, setItems] = useState<ActivationReference[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [q, setQ] = useState('');
  const [copied, setCopied] = useState<string | null>(null);

  useEffect(() => {
    referencesApi.list()
      .then((r) => setItems(r.items || []))
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) onLogout();
        else setErr(e instanceof ApiError ? e.message : 'Erreur réseau.');
      })
      .finally(() => setLoading(false));
    /* eslint-disable-next-line */
  }, []);

  // Filtre : MAC, username ou nom du client (recherche support).
  const filtered = useMemo(() => {
    const t = q.trim().toLowerCase();
    if (!t) return items;
    return items.filter((it) =>
      it.mac.toLowerCase().includes(t)
      || (it.customer_name || '').toLowerCase().includes(t)
      || it.usernames.some((u) => u.toLowerCase().includes(t))
      || it.servers.some((s) => s.toLowerCase().includes(t)),
    );
  }, [items, q]);

  function copy(text: string) {
    navigator.clipboard?.writeText(text).then(() => {
      setCopied(text);
      setTimeout(() => setCopied(null), 1500);
    });
  }

  // Vue d'ensemble instantanée (au-dessus du tableau).
  const stats = useMemo(() => {
    const total = items.length;
    const active = items.filter((i) => i.status === 'active').length;
    const soon = items.filter(
      (i) => i.status === 'active' && i.days_left != null && i.days_left <= 7,
    ).length;
    const online = items.filter((i) => i.online).length;
    return { total, active, soon, online };
  }, [items]);

  return (
    <AppLayout
      title="Références"
      subtitle="MAC activées + username (pour le support). Sans mot de passe."
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

      {/* Vue d'ensemble : total / actifs / expirent ≤ 7 j / en ligne. */}
      <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatTile label="Total" value={stats.total} />
        <StatTile label="Actifs" value={stats.active} tone="ok" />
        <StatTile label="Expirent ≤ 7 j" value={stats.soon} tone="warn" />
        <StatTile label="En ligne" value={stats.online} tone="live" />
      </div>

      <div className="mb-4 flex items-center justify-between gap-3">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Rechercher une MAC, un username, un serveur ou un client…"
          className="w-full max-w-md rounded-md border border-white/10 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
        />
        <span className="whitespace-nowrap text-[11px] text-ink-tertiary">
          {filtered.length} / {items.length}
        </span>
      </div>

      <div className="overflow-hidden rounded-xl border border-white/5">
        <table className="w-full text-sm">
          <thead className="bg-midnight">
            <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
              <th className="px-4 py-3">MAC</th>
              <th className="px-4 py-3">Client</th>
              <th className="px-4 py-3">Statut</th>
              <th className="px-4 py-3">Plan</th>
              <th className="px-4 py-3">Reste</th>
              <th className="px-4 py-3">Vu</th>
              <th className="px-4 py-3">Username(s)</th>
              <th className="px-4 py-3">Serveur(s)</th>
              <th className="px-4 py-3">Activé le</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && (
              <tr><td colSpan={9} className="px-4 py-8 text-center text-sm text-ink-tertiary">Chargement…</td></tr>
            )}
            {!loading && filtered.length === 0 && (
              <tr><td colSpan={9} className="px-4 py-8 text-center text-sm text-ink-tertiary">
                {items.length === 0
                  ? 'Aucune source poussée pour l\'instant. Active un appareil avec une source.'
                  : 'Aucun résultat pour cette recherche.'}
              </td></tr>
            )}
            {filtered.map((it) => (
              <tr key={it.mac} className="bg-obsidian hover:bg-midnight">
                <td className="px-4 py-3">
                  <MacLink mac={it.mac} className="text-[12px]" />
                </td>
                <td className="px-4 py-3 text-ink-secondary">{it.customer_name || '—'}</td>
                <td className="px-4 py-3"><RefStatus status={it.status} /></td>
                <td className="px-4 py-3 text-ink-secondary">{planLabel(it.plan)}</td>
                <td className="px-4 py-3">
                  <span className={'font-medium ' + remainLabel(it).cls}>
                    {remainLabel(it).text}
                  </span>
                  {it.expires_at && !it.lifetime && (
                    <div className="text-[10px] text-ink-tertiary">
                      → {fmtDate(it.expires_at)}
                    </div>
                  )}
                </td>
                <td className="px-4 py-3">
                  <span className="inline-flex items-center gap-1.5">
                    <span
                      className={
                        'inline-block h-2 w-2 rounded-full ' +
                        (it.online ? 'bg-emerald-400' : 'bg-ink-tertiary')
                      }
                    />
                    <span className="text-[11px] text-ink-tertiary">{ago(it.last_seen)}</span>
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div className="flex flex-wrap gap-1">
                    {it.usernames.length === 0 && <span className="text-ink-tertiary">—</span>}
                    {it.usernames.map((u, i) => (
                      <button
                        key={i}
                        onClick={() => copy(u)}
                        title="Copier le username"
                        className="rounded-full border border-white/10 bg-slate px-2 py-0.5 font-mono text-[11px] text-ink-primary hover:border-accent hover:text-accent-bright"
                      >
                        {copied === u ? '✓ copié' : u}
                      </button>
                    ))}
                  </div>
                </td>
                <td className="px-4 py-3">
                  <div className="flex flex-wrap gap-1">
                    {it.servers.length === 0 && <span className="text-ink-tertiary">—</span>}
                    {it.servers.map((s, i) => (
                      <button
                        key={i}
                        onClick={() => copy(s)}
                        title="Copier le serveur"
                        className="max-w-[180px] truncate rounded-full border border-white/10 bg-slate px-2 py-0.5 font-mono text-[11px] text-ink-secondary hover:border-accent hover:text-accent-bright"
                      >
                        {copied === s ? '✓ copié' : s}
                      </button>
                    ))}
                  </div>
                </td>
                <td className="px-4 py-3 text-[11px] text-ink-tertiary">{fmtDate(it.updated_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </AppLayout>
  );
}
