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
      || it.usernames.some((u) => u.toLowerCase().includes(t)),
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
          placeholder="Rechercher une MAC, un username ou un client…"
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
              <th className="px-4 py-3">Username(s)</th>
              <th className="px-4 py-3">Activé le</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {loading && (
              <tr><td colSpan={4} className="px-4 py-8 text-center text-sm text-ink-tertiary">Chargement…</td></tr>
            )}
            {!loading && filtered.length === 0 && (
              <tr><td colSpan={4} className="px-4 py-8 text-center text-sm text-ink-tertiary">
                {items.length === 0
                  ? 'Aucune source poussée pour l\'instant. Active un appareil avec une source.'
                  : 'Aucun résultat pour cette recherche.'}
              </td></tr>
            )}
            {filtered.map((it) => (
              <tr key={it.mac} className="bg-obsidian hover:bg-midnight">
                <td className="px-4 py-3">
                  <button
                    onClick={() => copy(it.mac)}
                    title="Copier la MAC"
                    className="font-mono text-[12px] text-ink-secondary hover:text-accent-bright"
                  >
                    {copied === it.mac ? '✓ copié' : it.mac}
                  </button>
                </td>
                <td className="px-4 py-3 text-ink-secondary">{it.customer_name || '—'}</td>
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
                <td className="px-4 py-3 text-[11px] text-ink-tertiary">{fmtDate(it.updated_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </AppLayout>
  );
}
