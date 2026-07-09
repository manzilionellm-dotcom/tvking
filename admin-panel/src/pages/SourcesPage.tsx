import { FormEvent, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import {
  sourcesApi, serversApi, sourceCheckApi, deviceSyncApi,
  type DefaultServer, type DeviceSourceInput, type DeviceSource,
  type SourceCheckResult, ApiError,
} from '@/lib/api';
import { formatDateTime, formatMacInput } from '@/lib/utils';

/// Page SOURCES — gestion des playlists M3U / Xtream d'un appareil,
/// SÉPARÉE de l'activation (demande produit : « l'activation des apps
/// doit être séparée de l'ajout de M3U et de l'Xtream »).
///
///  • Charge ce que la MAC a DÉJÀ (trio + playlists ajoutées par le client)
///  • Édite / remplace jusqu'à 3 sources d'un coup
///  • TESTE chaque source EN DIRECT avant de pousser (identifiants Xtream
///    valides ? M3U qui répond ?) — n'importe quel M3U, vérifié en 2 s
///  • Pousse : livraison INSTANTANÉE (l'app détecte le changement < 20 s
///    via /api/sync, sans redémarrage)

type SrcDraft = {
  type: 'xtream' | 'm3u';
  serverChoice: string;
  serverUrl: string;
  xtUser: string;
  xtPass: string;
  m3uUrl: string;
  epgUrl: string;
  check?: SourceCheckResult | null;
  checking?: boolean;
};

const blank = (): SrcDraft => ({
  type: 'xtream', serverChoice: 'custom', serverUrl: '',
  xtUser: '', xtPass: '', m3uUrl: '', epgUrl: '',
  check: null, checking: false,
});

const MAX_SOURCES = 3;
const MAC_OK = /^MK(?::[0-9A-F]{2}){5}$/i;

export function SourcesPage({ onLogout }: { onLogout: () => void }) {
  // MAC pré-remplie si on arrive depuis « Activer » ou une fiche appareil.
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [items, setItems] = useState<SrcDraft[]>([blank()]);
  const [servers, setServers] = useState<DefaultServer[]>([]);
  const [current, setCurrent] = useState<DeviceSource[] | null>(null);
  const [loadingCurrent, setLoadingCurrent] = useState(false);
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

  // Charge automatiquement l'inventaire dès que la MAC est complète.
  useEffect(() => {
    const m = mac.trim().toUpperCase();
    if (!MAC_OK.test(m)) { setCurrent(null); return; }
    let active = true;
    setLoadingCurrent(true);
    sourcesApi.get(m)
      .then((r) => {
        if (!active) return;
        setCurrent(r.sources && r.sources.length ? r.sources : (r.source ? [r.source] : []));
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        if (active) setCurrent([]);
      })
      .finally(() => { if (active) setLoadingCurrent(false); });
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mac]);

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
    const epg = it.epgUrl.trim() || undefined;
    if (it.type === 'xtream') {
      if (!it.serverUrl.trim() || !it.xtUser.trim() || !it.xtPass.trim()) return null;
      const chosen = servers.find((s) => s.id === it.serverChoice);
      return {
        type: 'xtream',
        label: chosen?.label ?? null,
        server_url: it.serverUrl.trim(),
        username: it.xtUser.trim(),
        password: it.xtPass.trim(),
        epg_url: epg,
      };
    }
    if (!it.m3uUrl.trim()) return null;
    return { type: 'm3u', m3u_url: it.m3uUrl.trim(), epg_url: epg };
  }

  /// Charge les sources ACTUELLES de la MAC dans l'éditeur (pré-rempli
  /// sauf le mot de passe Xtream, jamais renvoyé masqué par le serveur).
  function editCurrent() {
    if (!current || current.length === 0) return;
    setItems(current.slice(0, MAX_SOURCES).map((s) => ({
      type: (s.type === 'm3u' ? 'm3u' : 'xtream'),
      serverChoice: 'custom',
      serverUrl: s.server_url || '',
      xtUser: s.username || '',
      xtPass: s.password || '',
      m3uUrl: s.m3u_url || '',
      epgUrl: s.epg_url || '',
      check: null, checking: false,
    })));
  }

  async function testSource(i: number) {
    const src = buildSource(items[i]);
    if (!src) {
      patch(i, { check: { ok: false, type: items[i].type, ms: 0, code: 'incomplete' } });
      return;
    }
    patch(i, { checking: true, check: null });
    try {
      const r = await sourceCheckApi.check(src);
      patch(i, { checking: false, check: r });
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      patch(i, {
        checking: false,
        check: { ok: false, type: items[i].type, ms: 0, code: 'network', message: e?.message },
      });
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setOk(null);
    const m = mac.trim().toUpperCase();
    if (!MAC_OK.test(m)) {
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
      // Confirme la livraison instantanée : la révision de synchro a bougé,
      // l'app la détecte en < 20 s (poll /api/sync) et charge la source.
      let rev: number | null = null;
      try { rev = (await deviceSyncApi.get(m)).rev; } catch { /* facultatif */ }
      setOk(
        `${r.count} source(s) poussée(s) sur ${m} — livraison instantanée `
        + `(l'app se met à jour d'elle-même en quelques secondes${rev !== null ? ` · rév. ${rev}` : ''}).`,
      );
      // Recharge l'inventaire affiché.
      const inv = await sourcesApi.get(m).catch(() => null);
      if (inv) setCurrent(inv.sources && inv.sources.length ? inv.sources : (inv.source ? [inv.source] : []));
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : "Échec de l'envoi.");
    } finally {
      setBusy(false);
    }
  }

  async function clearAll() {
    const m = mac.trim().toUpperCase();
    if (!MAC_OK.test(m)) return;
    if (!window.confirm(`Retirer TOUTES les sources assignées à ${m} ?`)) return;
    setBusy(true); setErr(null); setOk(null);
    try {
      await sourcesApi.clear(m);
      setOk(`Sources retirées de ${m} (effet en quelques secondes sur l'app).`);
      setCurrent([]);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Sources M3U / Xtream"
      subtitle="Gestion des playlists d'un appareil — séparée de l'activation. Test en direct, livraison instantanée."
      onLogout={onLogout}
    >
      <div className="grid max-w-5xl gap-6 lg:grid-cols-2">
        {/* ===== Éditeur ===== */}
        <form onSubmit={submit} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
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

          {items.map((it, i) => (
            <div key={i} className="rounded-lg border border-white/10 bg-slate/30 p-3">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                  Source {i + 1}
                </span>
                {items.length > 1 && (
                  <button type="button" onClick={() => removeItem(i)}
                    className="text-xs text-ink-tertiary hover:text-accent-bright">
                    Retirer
                  </button>
                )}
              </div>

              <div className="mb-2 grid grid-cols-2 gap-2">
                {(['xtream', 'm3u'] as const).map((t) => (
                  <button
                    type="button"
                    key={t}
                    onClick={() => patch(i, { type: t, check: null })}
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
                        patch(i, { serverChoice: e.target.value, serverUrl: s ? s.url : it.serverUrl, check: null });
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
                    <input value={it.serverUrl}
                      onChange={(e) => patch(i, { serverUrl: e.target.value, check: null })}
                      placeholder="http://serveur.com:8080" className={inputCls + ' font-mono'} />
                  )}
                  <input value={it.xtUser}
                    onChange={(e) => patch(i, { xtUser: e.target.value, check: null })}
                    placeholder="Utilisateur" className={inputCls} />
                  <input value={it.xtPass}
                    onChange={(e) => patch(i, { xtPass: e.target.value, check: null })}
                    placeholder="Mot de passe" className={inputCls} />
                </div>
              )}

              {it.type === 'm3u' && (
                <input value={it.m3uUrl}
                  onChange={(e) => patch(i, { m3uUrl: e.target.value, check: null })}
                  placeholder="http://serveur.com/get.php?username=…&type=m3u_plus"
                  className={inputCls + ' font-mono'} />
              )}

              <input value={it.epgUrl}
                onChange={(e) => patch(i, { epgUrl: e.target.value })}
                placeholder="URL EPG (optionnel)"
                className={inputCls + ' mt-2 font-mono'} />

              {/* ===== Test en direct ===== */}
              <div className="mt-2 flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => testSource(i)}
                  disabled={it.checking}
                  className="rounded-md border border-white/10 px-3 py-1.5 text-xs font-medium text-ink-secondary transition hover:border-accent hover:text-accent-bright disabled:opacity-50"
                >
                  {it.checking ? 'Test en cours…' : '⚡ Tester la source'}
                </button>
                {it.check && <CheckBadge r={it.check} />}
              </div>
            </div>
          ))}

          {items.length < MAX_SOURCES && (
            <button type="button" onClick={addItem}
              className="w-full rounded-md border border-dashed border-white/15 px-3 py-2 text-sm text-ink-secondary transition hover:border-accent/50 hover:text-accent-bright">
              + Ajouter une source ({items.length}/{MAX_SOURCES})
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
            disabled={busy || mac.trim().length < 17}
            className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Envoi…' : `Pousser ${items.length > 1 ? `les ${items.length} sources` : 'la source'} (instantané)`}
          </button>
        </form>

        {/* ===== Inventaire actuel ===== */}
        <div className="rounded-xl border border-white/5 bg-obsidian p-6">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold">Sources actuelles de l'appareil</h2>
            {current && current.length > 0 && (
              <div className="flex gap-2">
                <button onClick={editCurrent}
                  className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                  Modifier
                </button>
                <button onClick={clearAll}
                  className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
                  Tout retirer
                </button>
              </div>
            )}
          </div>

          {!MAC_OK.test(mac.trim()) && (
            <p className="text-sm text-ink-tertiary">
              Saisis une MAC complète : ses sources actuelles s'affichent ici
              automatiquement (celles du panel et celles ajoutées par le client).
            </p>
          )}
          {MAC_OK.test(mac.trim()) && loadingCurrent && (
            <p className="text-sm text-ink-tertiary">Chargement…</p>
          )}
          {MAC_OK.test(mac.trim()) && !loadingCurrent && current && current.length === 0 && (
            <p className="text-sm text-ink-tertiary">Aucune source assignée à cette MAC.</p>
          )}
          {current && current.length > 0 && (
            <ul className="space-y-2">
              {current.map((s, i) => (
                <li key={i} className="rounded-lg border border-white/10 bg-slate/30 p-3 text-sm">
                  <div className="flex items-center justify-between">
                    <span className="font-medium">
                      {s.label || (s.type === 'm3u' ? 'Playlist M3U' : 'Xtream')}
                    </span>
                    <span className="flex items-center gap-1.5">
                      <span className="rounded-full bg-white/5 px-2 py-0.5 text-[10px] uppercase tracking-widest text-ink-tertiary">
                        {s.type}
                      </span>
                      {(s as any).origin === 'self' && (
                        <span className="rounded-full bg-warn/15 px-2 py-0.5 text-[10px] uppercase tracking-widest text-warn-bright"
                          title="Ajoutée par le client depuis Mon espace">
                          client
                        </span>
                      )}
                    </span>
                  </div>
                  <div className="mt-1 truncate font-mono text-xs text-ink-tertiary">
                    {s.type === 'm3u' ? s.m3u_url : `${s.server_url} · ${s.username || ''}`}
                  </div>
                  {s.updated_at && (
                    <div className="mt-1 text-[11px] text-ink-tertiary">
                      Mise à jour : {formatDateTime(s.updated_at)}
                    </div>
                  )}
                </li>
              ))}
            </ul>
          )}

          <div className="mt-5 rounded-lg border border-accent/20 bg-accent/5 p-3 text-xs leading-relaxed text-ink-secondary">
            <span className="font-semibold text-accent-bright">Livraison instantanée.</span>{' '}
            Dès que tu pousses, l'app du client détecte le changement en
            moins de 20 secondes (sans redémarrage) et charge la nouvelle
            source. L'activation, elle, se gère dans « Activer un appareil ».
          </div>
        </div>
      </div>
    </AppLayout>
  );
}

/// Badge résultat du test de source (vert = OK avec détails, rouge = KO).
function CheckBadge({ r }: { r: SourceCheckResult }) {
  if (r.ok) {
    const parts: string[] = [];
    if (r.type === 'xtream') {
      if (r.status) parts.push(r.status);
      if (r.max_connections) parts.push(`${r.max_connections} conn. max`);
      if (r.expires_at) parts.push(`expire ${formatDateTime(r.expires_at)}`);
      if (r.expires_at === null) parts.push('illimité');
    } else if (r.sample_channels !== undefined) {
      parts.push(`${r.sample_channels}+ chaînes détectées`);
    }
    parts.push(`${r.ms} ms`);
    return (
      <span className="rounded-full bg-success/15 px-2.5 py-1 text-[11px] font-medium text-success">
        ✓ Source valide · {parts.join(' · ')}
      </span>
    );
  }
  const label =
    r.code === 'bad_credentials' ? 'Identifiants refusés par le serveur'
    : r.code === 'not_m3u' ? "La réponse n'est pas une playlist M3U"
    : r.code === 'incomplete' ? 'Complète les champs avant de tester'
    : r.code && r.code.startsWith('http_') ? `Le serveur répond ${r.code.slice(5)}`
    : 'Serveur injoignable';
  return (
    <span className="rounded-full bg-accent/15 px-2.5 py-1 text-[11px] font-medium text-accent-bright">
      ✗ {label}
    </span>
  );
}
