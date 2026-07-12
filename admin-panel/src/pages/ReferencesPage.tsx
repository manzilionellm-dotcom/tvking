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

function fmtDate(ms: number | null): string {
  if (!ms) return '—';
  try { return new Date(ms).toLocaleDateString('fr-FR'); } catch { return '—'; }
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

  return (
    <AppLayout
      title="Références"
      subtitle="MAC activées + username (pour le support). Sans mot de passe."
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-lg border border-accent/30 bg-accent/10 px-4 py-3 text-sm">{err}</div>
      )}

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
              <th className="px-4 py-3">Username(s)</th>
              <th className="px-4 py-3">Serveur(s)</th>
              <th className="px-4 py-3">Activé le</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && (
              <tr><td colSpan={6} className="px-4 py-8 text-center text-sm text-ink-tertiary">Chargement…</td></tr>
            )}
            {!loading && filtered.length === 0 && (
              <tr><td colSpan={6} className="px-4 py-8 text-center text-sm text-ink-tertiary">
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
