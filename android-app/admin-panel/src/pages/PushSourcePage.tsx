import { FormEvent, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  sourcesApi,
  type DeviceSourceInput, ApiError,
} from '@/lib/api';
import { buildPushedSource, type OpenPanelKind } from '@/lib/openSource';

/// Page « Pousser une playlist » — assigne jusqu'à 6 sources (un TRIO)
/// IPTV à une MAC, en une seule fois. Le client les charge TOUTES
/// automatiquement (≈ 6 s) et bascule de l'une à l'autre dans l'app.
/// Pas d'option « Aucune » : chaque bloc est forcément Xtream ou M3U.
///
/// Au submit → PUT /api/v1/sources/:mac { sources: [...] }.

type SrcDraft = {
  type: OpenPanelKind;
  serverUrl: string;
  xtUser: string;
  xtPass: string;
  m3uUrl: string;
};

const blank = (): SrcDraft => ({
  type: 'xtream', serverUrl: '',
  xtUser: '', xtPass: '', m3uUrl: '',
});

const MAX_SOURCES = 6; // aligné sur MAX_SOURCES_PER_DEVICE du Worker (api_v1.js)

export function PushSourcePage({ onLogout }: { onLogout: () => void }) {
  const [mac, setMac] = useState('MK:');
  const [items, setItems] = useState<SrcDraft[]>([blank()]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  // Plus de catalogue : on n'interroge plus la liste des serveurs.

  function patch(i: number, p: Partial<SrcDraft>) {
    setItems((prev) => prev.map((it, idx) => (idx === i ? { ...it, ...p } : it)));
  }
  function addItem() {
    if (items.length < MAX_SOURCES) setItems((prev) => [...prev, blank()]);
  }
  function removeItem(i: number) {
    setItems((prev) => prev.filter((_, idx) => idx !== i));
  }

  function buildSource(it: SrcDraft): DeviceSourceInput | { error: string } | null {
    const built = buildPushedSource({
      type: it.type,
      serverUrl: it.serverUrl,
      username: it.xtUser,
      password: it.xtPass,
      link: it.m3uUrl,
    });
    if ('error' in built) return built;
    return built.source;
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
      if (!s || 'error' in s) {
        setErr(s && 'error' in s ? `Source ${i + 1} : ${s.error}` : `Source ${i + 1} incomplète.`);
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
      subtitle="Assigne jusqu'à 6 sources (un trio) à une MAC — chargées automatiquement"
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
            onChange={(e) => setMac(e.target.value)}
            autoFocus
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

            <div className="mb-2 grid grid-cols-3 gap-2">
              {([
                ['xtream', 'Xtream Codes'],
                ['m3u', 'M3U'],
                ['player', 'Lien lecteur'],
              ] as const).map(([t, label]) => (
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
                  {label}
                </button>
              ))}
            </div>

            {it.type === 'xtream' && (
              <div className="space-y-2">
                <input
                  value={it.serverUrl}
                  onChange={(e) => patch(i, { serverUrl: e.target.value })}
                  placeholder="http://exemple.test:8080"
                  className={inputCls + ' font-mono'}
                />
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

            {it.type !== 'xtream' && (
              <input
                value={it.m3uUrl}
                onChange={(e) => patch(i, { m3uUrl: e.target.value })}
                placeholder={it.type === 'player'
                  ? 'http://exemple.test:8080/get.php?username=…&password=…'
                  : 'http://exemple.test/liste.m3u'}
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
