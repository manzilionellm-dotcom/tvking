import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  sourcesApi, serversApi,
  type DefaultServer, type DeviceSourceInput, ApiError,
} from '@/lib/api';
import { formatMacInput } from '@/lib/utils';

/// Page « Pousser une playlist » — assigne jusqu'à 3 sources (un TRIO)
/// IPTV à une MAC, en une seule fois. Le client les charge TOUTES
/// automatiquement (≈ 6 s) et bascule de l'une à l'autre dans l'app.
/// Pas d'option « Aucune » : chaque bloc est forcément Xtream ou M3U.
///
/// Au submit → PUT /api/v1/sources/:mac { sources: [...] }.

type SrcDraft = {
  type: 'xtream' | 'm3u';
  serverChoice: string;
  serverUrl: string;
  xtUser: string;
  xtPass: string;
  m3uUrl: string;
};

const blank = (): SrcDraft => ({
  type: 'xtream', serverChoice: 'custom', serverUrl: '',
  xtUser: '', xtPass: '', m3uUrl: '',
});

const MAX_SOURCES = 3;

export function PushSourcePage({ onLogout }: { onLogout: () => void }) {
  const [mac, setMac] = useState('MK:');
  const [items, setItems] = useState<SrcDraft[]>([blank()]);
  const [servers, setServers] = useState<DefaultServer[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    serversApi.list()
      .then((r) => {
        if (!active) return;
        setServers(r.items);
        if (r.items[0]) {
          // Pré-remplit le 1er bloc avec le 1er serveur prédéfini.
          setItems((prev) => {
            const next = [...prev];
            next[0] = { ...next[0], serverChoice: r.items[0].id, serverUrl: r.items[0].url };
            return next;
          });
        }
      })
      .catch(() => {});
    return () => { active = false; };
  }, []);

  function patch(i: number, p: Partial<SrcDraft>) {
    setItems((prev) => prev.map((it, idx) => (idx === i ? { ...it, ...p } : it)));
  }
  function addItem() {
    if (items.length < MAX_SOURCES) setItems((prev) => [...prev, blank()]);
  }
  function removeItem(i: number) {
    setItems((prev) => prev.filter((_, idx) => idx !== i));
  }

  function buildSource(it: SrcDraft): DeviceSourceInput | null {
    if (it.type === 'xtream') {
      if (!it.serverUrl.trim() || !it.xtUser.trim() || !it.xtPass.trim()) return null;
      const chosen = servers.find((s) => s.id === it.serverChoice);
      return {
        type: 'xtream',
        label: chosen?.label ?? null,
        server_url: it.serverUrl.trim(),
        username: it.xtUser.trim(),
        password: it.xtPass.trim(),
      };
    }
    if (!it.m3uUrl.trim()) return null;
    return { type: 'm3u', m3u_url: it.m3uUrl.trim() };
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    const m = mac.trim().toUpperCase();
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
      setErr('MAC invalide. Format attendu : MK:XX:XX:XX:XX:XX');
      setBusy(false);
      return;
    }
    const sources: DeviceSourceInput[] = [];
    for (let i = 0; i < items.length; i++) {
      const s = buildSource(items[i]);
      if (!s) {
        setErr(`Source ${i + 1} incomplète (serveur/identifiant/mot de passe ou URL M3U).`);
        setBusy(false);
        return;
      }
      sources.push(s);
    }
    try {
      const r = await sourcesApi.setMany(m, sources);
      setOk(
        `${r.count} source(s) poussée(s) sur ${m}. L'app du client les charge `
        + 'automatiquement (≈ 6 s). Bascule entre elles via l’icône « calques » dans l’app.',
      );
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : "Échec de l'envoi.");
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Pousser une playlist"
      subtitle="Assigne jusqu'à 3 sources (un trio) à une MAC — chargées automatiquement"
      onLogout={onLogout}
    >
      <form
        onSubmit={submit}
        className="max-w-lg space-y-4 rounded-xl border border-white/5 bg-midnight p-6"
      >
        {/* MAC */}
        <div>
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Adresse MAC de l'appareil
          </label>
          <input
            value={mac}
            onChange={(e) => setMac(formatMacInput(e.target.value))}
            autoFocus
            maxLength={17}
            placeholder="MK:1A:2B:3C:4D:5E"
            className={inputCls + ' font-mono'}
          />
        </div>

        {/* Blocs de sources (1 à 3) */}
        {items.map((it, i) => (
          <div key={i} className="rounded-lg border border-white/10 bg-slate/30 p-3">
            <div className="mb-2 flex items-center justify-between">
              <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                Source {i + 1}
              </span>
              {items.length > 1 && (
                <button
                  type="button"
                  onClick={() => removeItem(i)}
                  className="text-xs text-ink-tertiary hover:text-accent-bright"
                >
                  Retirer
                </button>
              )}
            </div>

            <div className="mb-2 grid grid-cols-2 gap-2">
              {(['xtream', 'm3u'] as const).map((t) => (
                <button
                  type="button"
                  key={t}
                  onClick={() => patch(i, { type: t })}
                  className={
                    'rounded-md border px-3 py-2 text-sm transition ' +
                    (it.type === t
                      ? 'border-accent bg-accent/10 text-ink-primary'
                      : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                  }
                >
                  {t === 'xtream' ? 'Xtream Codes' : 'M3U'}
                </button>
              ))}
            </div>

            {it.type === 'xtream' && (
              <div className="space-y-2">
                {servers.length > 0 && (
                  <select
                    value={it.serverChoice}
                    onChange={(e) => {
                      const s = servers.find((x) => x.id === e.target.value);
                      patch(i, { serverChoice: e.target.value, serverUrl: s ? s.url : it.serverUrl });
                    }}
                    className={inputCls}
                  >
                    {servers.map((s) => (
                      <option key={s.id} value={s.id}>{s.label}</option>
                    ))}
                    <option value="custom">URL manuelle…</option>
                  </select>
                )}
                {(it.serverChoice === 'custom' || servers.length === 0) && (
                  <input
                    value={it.serverUrl}
                    onChange={(e) => patch(i, { serverUrl: e.target.value })}
                    placeholder="http://serveur.com:8080"
                    className={inputCls + ' font-mono'}
                  />
                )}
                <input
                  value={it.xtUser}
                  onChange={(e) => patch(i, { xtUser: e.target.value })}
                  placeholder="Utilisateur"
                  className={inputCls}
                />
                <input
                  value={it.xtPass}
                  onChange={(e) => patch(i, { xtPass: e.target.value })}
                  placeholder="Mot de passe"
                  className={inputCls}
                />
              </div>
            )}

            {it.type === 'm3u' && (
              <input
                value={it.m3uUrl}
                onChange={(e) => patch(i, { m3uUrl: e.target.value })}
                placeholder="http://serveur.com/get.php?username=…&type=m3u_plus"
                className={inputCls + ' font-mono'}
              />
            )}
          </div>
        ))}

        {items.length < MAX_SOURCES && (
          <button
            type="button"
            onClick={addItem}
            className="w-full rounded-md border border-dashed border-white/15 px-3 py-2 text-sm text-ink-secondary transition hover:border-accent/50 hover:text-accent-bright"
          >
            + Ajouter une source (trio — {items.length}/{MAX_SOURCES})
          </button>
        )}

        {err && (
          <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
            {err}
          </div>
        )}
        {ok && (
          <div className="rounded-md border border-success/30 bg-success/10 px-3 py-2 text-xs text-success">
            {ok}
          </div>
        )}

        <button
          type="submit"
          disabled={busy || mac.trim().length < 8}
          className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? 'Envoi…' : `Pousser ${items.length > 1 ? `le trio (${items.length})` : 'la playlist'}`}
        </button>
      </form>
    </AppLayout>
  );
}
