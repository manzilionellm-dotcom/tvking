import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  sourcesApi, serversApi,
  type DefaultServer, type DeviceSourceInput, ApiError,
} from '@/lib/api';

/// Page « Pousser une playlist » — assigne une SOURCE IPTV (Xtream/M3U)
/// à une MAC, SANS ré-activer la licence. C'est la voie simple et sans
/// piège : ici il n'y a PAS d'option « Aucune » — on choisit forcément
/// Xtream ou M3U, donc impossible d'oublier la source (cause n°1 du
/// « abonnement actif mais aucune chaîne »).
///
/// Au submit → PUT /api/v1/sources/:mac. L'app récupère la source via
/// /api/device-source/:mac (sondage auto toutes les 6 s, ou bouton
/// « Vérifier mon abonnement »).
export function PushSourcePage({ onLogout }: { onLogout: () => void }) {
  const [mac, setMac] = useState('MK:');
  const [srcType, setSrcType] = useState<'xtream' | 'm3u'>('xtream');
  const [servers, setServers] = useState<DefaultServer[]>([]);
  const [serverChoice, setServerChoice] = useState<string>('custom');
  const [serverUrl, setServerUrl] = useState('');
  const [xtUser, setXtUser] = useState('');
  const [xtPass, setXtPass] = useState('');
  const [m3uUrl, setM3uUrl] = useState('');
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
          setServerChoice(r.items[0].id);
          setServerUrl(r.items[0].url);
        }
      })
      .catch(() => {});
    return () => { active = false; };
  }, []);

  function buildSource(): DeviceSourceInput | null {
    if (srcType === 'xtream') {
      if (!serverUrl.trim() || !xtUser.trim() || !xtPass.trim()) return null;
      const chosen = servers.find((s) => s.id === serverChoice);
      return {
        type: 'xtream',
        label: chosen?.label ?? null,
        server_url: serverUrl.trim(),
        username: xtUser.trim(),
        password: xtPass.trim(),
      };
    }
    if (!m3uUrl.trim()) return null;
    return { type: 'm3u', m3u_url: m3uUrl.trim() };
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    setOk(null);
    const m = mac.trim().toUpperCase();
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
      setErr('MAC invalide. Format attendu : MK:XX:XX:XX:XX:XX');
      setBusy(false);
      return;
    }
    const source = buildSource();
    if (!source) {
      setErr(
        srcType === 'xtream'
          ? 'Xtream : serveur, utilisateur et mot de passe sont obligatoires.'
          : "M3U : l'URL est obligatoire.",
      );
      setBusy(false);
      return;
    }
    try {
      await sourcesApi.set(m, source);
      setOk(
        `Playlist poussée sur ${m}. L'app du client la charge automatiquement `
        + "(≈ 6 s) ou via « Vérifier mon abonnement ».",
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
      subtitle="Assigne une source IPTV à une MAC (sans ré-activer la licence)"
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

        {/* Type de source — PAS de « Aucune » : on doit choisir. */}
        <div>
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Type de source
          </label>
          <div className="grid grid-cols-2 gap-2">
            {(['xtream', 'm3u'] as const).map((t) => (
              <button
                type="button"
                key={t}
                onClick={() => setSrcType(t)}
                className={
                  'rounded-md border px-3 py-2 text-sm transition ' +
                  (srcType === t
                    ? 'border-accent bg-accent/10 text-ink-primary'
                    : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                }
              >
                {t === 'xtream' ? 'Xtream Codes' : 'M3U'}
              </button>
            ))}
          </div>
        </div>

        {/* Champs Xtream */}
        {srcType === 'xtream' && (
          <div className="space-y-2">
            {servers.length > 0 && (
              <select
                value={serverChoice}
                onChange={(e) => {
                  setServerChoice(e.target.value);
                  const s = servers.find((x) => x.id === e.target.value);
                  if (s) setServerUrl(s.url);
                }}
                className={inputCls}
              >
                {servers.map((s) => (
                  <option key={s.id} value={s.id}>{s.label}</option>
                ))}
                <option value="custom">URL manuelle…</option>
              </select>
            )}
            {(serverChoice === 'custom' || servers.length === 0) && (
              <input
                value={serverUrl}
                onChange={(e) => setServerUrl(e.target.value)}
                placeholder="http://serveur.com:8080"
                className={inputCls + ' font-mono'}
              />
            )}
            <input
              value={xtUser}
              onChange={(e) => setXtUser(e.target.value)}
              placeholder="Utilisateur"
              className={inputCls}
            />
            <input
              value={xtPass}
              onChange={(e) => setXtPass(e.target.value)}
              placeholder="Mot de passe"
              className={inputCls}
            />
          </div>
        )}

        {/* Champ M3U */}
        {srcType === 'm3u' && (
          <input
            value={m3uUrl}
            onChange={(e) => setM3uUrl(e.target.value)}
            placeholder="http://serveur.com/get.php?username=…&type=m3u_plus"
            className={inputCls + ' font-mono'}
          />
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
          {busy ? 'Envoi…' : 'Pousser la playlist'}
        </button>
      </form>
    </AppLayout>
  );
}
