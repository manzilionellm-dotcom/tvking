import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { toast } from '@/components/Toast';
import {
  gatewayApi, getGatewayConfig, setGatewayConfig, hasGatewayConfig,
  genPassword, fmtBytes, GatewayError,
  type GwStatus, type GwFamily,
} from '@/lib/gateway';

// =========================================================
//  GatewayPage — « Passerelle » (maison mère)
// =========================================================
//  Pilote le VPS de mutualisation : tableau de bord live (connexions
//  fournisseur, qui regarde quoi, bande passante) + gestion des familles
//  et de leurs clones (papa/maman/enfants). Le panel appelle la passerelle
//  directement ; l'URL + le jeton sont stockés dans ce navigateur.
// =========================================================

function dur(ms: number): string {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`;
  return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}

export function GatewayPage({ onLogout }: { onLogout: () => void }) {
  const initial = getGatewayConfig();
  const [base, setBase] = useState(initial.base);
  const [token, setToken] = useState(initial.token);
  const [configured, setConfigured] = useState(hasGatewayConfig());

  const [status, setStatus] = useState<GwStatus | null>(null);
  const [families, setFamilies] = useState<GwFamily[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [live, setLive] = useState(false);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  const refreshStatus = useCallback(async () => {
    try {
      const s = await gatewayApi.status();
      setStatus(s); setLive(true); setErr(null);
    } catch (e) {
      setLive(false);
      setErr(e instanceof GatewayError ? e.message : 'Erreur passerelle.');
    }
  }, []);

  const refreshFamilies = useCallback(async () => {
    try {
      const r = await gatewayApi.families();
      setFamilies(r.families);
    } catch { /* le statut porte déjà l'erreur */ }
  }, []);

  const refreshAll = useCallback(async () => {
    await Promise.all([refreshStatus(), refreshFamilies()]);
  }, [refreshStatus, refreshFamilies]);

  useEffect(() => {
    if (!configured) return;
    refreshAll();
    timer.current = setInterval(refreshStatus, 5000);
    return () => { if (timer.current) clearInterval(timer.current); };
  }, [configured, refreshAll, refreshStatus]);

  function saveConfig() {
    if (!base.trim() || !token.trim()) { toast('URL et jeton requis.', 'error'); return; }
    setGatewayConfig(base, token);
    setConfigured(true);
    toast('Passerelle enregistrée.', 'success');
    refreshAll();
  }

  // ---- Actions familles -------------------------------------------------
  async function onCreateFamily(id: string, max: number) {
    try {
      const r = await gatewayApi.createFamily(id, max);
      if (!r.ok) { toast(r.code === 'exists' ? 'Cette famille existe déjà.' : 'Création refusée.', 'error'); return; }
      toast('Famille créée.', 'success');
      refreshFamilies();
    } catch (e) { toast(e instanceof GatewayError ? e.message : 'Échec.', 'error'); }
  }
  async function onDeleteFamily(id: string) {
    if (!window.confirm(`Supprimer la famille « ${id} » et tous ses clones ?`)) return;
    try { await gatewayApi.deleteFamily(id); toast('Famille supprimée.', 'success'); refreshAll(); }
    catch (e) { toast(e instanceof GatewayError ? e.message : 'Échec.', 'error'); }
  }
  async function onAddUser(familyId: string, username: string, password: string, max: number) {
    try {
      const r = await gatewayApi.addUser(familyId, username, password, max);
      if (!r.ok) { toast(r.code === 'username_taken' ? 'Cet identifiant existe déjà.' : 'Ajout refusé.', 'error'); return; }
      toast('Clone ajouté.', 'success');
      refreshAll();
    } catch (e) { toast(e instanceof GatewayError ? e.message : 'Échec.', 'error'); }
  }
  async function onDeleteUser(familyId: string, username: string) {
    if (!window.confirm(`Retirer le clone « ${username} » ?`)) return;
    try { await gatewayApi.deleteUser(familyId, username); toast('Clone retiré.', 'success'); refreshAll(); }
    catch (e) { toast(e instanceof GatewayError ? e.message : 'Échec.', 'error'); }
  }

  return (
    <AppLayout
      title="Passerelle"
      subtitle="Maison mère : mutualise les flux identiques, protège ta ligne, et gère papa + clones."
      onLogout={onLogout}
      actions={
        <span
          className={
            'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ' +
            (live ? 'bg-success/15 text-success' : 'bg-white/5 text-ink-tertiary')
          }
        >
          <span className={'h-1.5 w-1.5 rounded-full ' + (live ? 'animate-pulse bg-success' : 'bg-white/20')} />
          {live ? 'Connectée' : 'Hors ligne'}
        </span>
      }
    >
      <ConfigCard
        base={base} token={token}
        onBase={setBase} onToken={setToken} onSave={saveConfig}
      />

      {!configured ? (
        <EmptyHint />
      ) : (
        <>
          {err && (
            <div className="mb-4 rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-2 text-sm text-red-300">
              {err}
            </div>
          )}
          {status && <Dashboard status={status} />}
          <FamiliesManager
            families={families}
            providerMax={status?.hub.providerMax ?? 0}
            onCreateFamily={onCreateFamily}
            onDeleteFamily={onDeleteFamily}
            onAddUser={onAddUser}
            onDeleteUser={onDeleteUser}
          />
        </>
      )}
    </AppLayout>
  );
}

// ---- Config -------------------------------------------------------------
function ConfigCard({
  base, token, onBase, onToken, onSave,
}: {
  base: string; token: string;
  onBase: (v: string) => void; onToken: (v: string) => void; onSave: () => void;
}) {
  const input = 'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';
  return (
    <div className="mb-5 rounded-xl border border-white/5 bg-midnight p-4">
      <div className="mb-2 text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">
        Connexion à la passerelle (stockée dans ce navigateur)
      </div>
      <div className="grid gap-2 md:grid-cols-[2fr_2fr_auto]">
        <input value={base} onChange={(e) => onBase(e.target.value)}
          placeholder="https://tv.mondomaine.com" className={input + ' font-mono'} />
        <input value={token} onChange={(e) => onToken(e.target.value)} type="password"
          placeholder="Jeton admin (ADMIN_TOKEN)" className={input + ' font-mono'} />
        <button type="button" onClick={onSave}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright">
          Connecter
        </button>
      </div>
      <p className="mt-2 text-[11px] text-ink-tertiary">
        La passerelle doit être en HTTPS (sinon le navigateur bloque). Le jeton
        reste local ; il n'est jamais envoyé au panel.
      </p>
    </div>
  );
}

function EmptyHint() {
  return (
    <div className="rounded-xl border border-white/5 bg-obsidian-light py-16 text-center">
      <div className="text-sm font-medium text-ink-secondary">Passerelle non connectée</div>
      <div className="mx-auto mt-1 max-w-md text-xs text-ink-tertiary">
        Déploie le service <code className="text-accent-bright">gateway/</code> sur ton VPS
        (<code>docker compose up -d</code>), mets-le en HTTPS, puis renseigne son URL
        et son jeton admin ci-dessus.
      </div>
    </div>
  );
}

// ---- Tableau de bord ----------------------------------------------------
function Dashboard({ status }: { status: GwStatus }) {
  const c = status.metrics.counters;
  const g = status.metrics.gauges;
  const used = status.hub.upstreamActive;
  const max = status.hub.providerMax || 1;
  const pct = Math.min(100, Math.round((used / max) * 100));
  const barColor = pct >= 100 ? 'bg-red-500' : pct >= 70 ? 'bg-amber-400' : 'bg-emerald-400';

  const tiles = useMemo(() => ([
    { label: 'Spectateurs actifs', value: String(g['gw_clients_active'] ?? 0) },
    { label: 'Mutualisations', value: String(c['gw_mux_join_total'] ?? 0), hint: 'flux partagés (économisés)' },
    { label: 'Refusés (ligne pleine)', value: String(c['gw_rejected_provider_limit_total'] ?? 0) },
    { label: 'Reçu du fournisseur', value: fmtBytes(c['gw_bytes_upstream_total'] ?? 0) },
    { label: 'Envoyé aux clients', value: fmtBytes(c['gw_bytes_clients_total'] ?? 0) },
    { label: 'Reconnexions', value: String(c['gw_upstream_reconnects_total'] ?? 0) },
  ]), [c, g]);

  return (
    <div className="mb-5 space-y-4">
      {/* Jauge connexions fournisseur */}
      <div className="rounded-xl border border-white/5 bg-obsidian-light p-4">
        <div className="mb-1.5 flex items-baseline justify-between">
          <span className="text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">
            Connexions fournisseur
          </span>
          <span className="text-sm font-semibold text-ink-primary">
            {used} / {max}
          </span>
        </div>
        <div className="h-2.5 w-full overflow-hidden rounded-full bg-white/5">
          <div className={'h-full rounded-full transition-all ' + barColor} style={{ width: `${pct}%` }} />
        </div>
        <div className="mt-1.5 flex justify-between text-[11px] text-ink-tertiary">
          <span>{status.hub.liveSessions} live · {status.hub.vodSessions} VOD</span>
          <span>{pct >= 100 ? 'Ligne pleine — nouvelles chaînes refusées' : 'Ligne protégée (jamais dépassée)'}</span>
        </div>
      </div>

      {/* Tuiles */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
        {tiles.map((t) => (
          <div key={t.label} className="rounded-xl border border-white/5 bg-obsidian-light px-4 py-3">
            <div className="text-[10px] uppercase tracking-widest text-ink-tertiary">{t.label}</div>
            <div className="mt-0.5 text-xl font-semibold text-ink-primary">{t.value}</div>
            {t.hint && <div className="text-[10px] text-ink-tertiary">{t.hint}</div>}
          </div>
        ))}
      </div>

      {/* Sessions en cours */}
      <div className="overflow-hidden rounded-xl border border-white/5">
        <div className="border-b border-white/5 bg-obsidian-light px-4 py-2 text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">
          Flux en cours ({status.hub.sessions.length})
        </div>
        {status.hub.sessions.length === 0 ? (
          <div className="px-4 py-8 text-center text-xs text-ink-tertiary">Aucun flux actif pour l'instant.</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
                <th className="px-4 py-2">Chaîne</th>
                <th className="px-4 py-2">État</th>
                <th className="px-4 py-2">Spectateurs</th>
                <th className="px-4 py-2">Depuis</th>
                <th className="px-4 py-2 text-right">Reçu</th>
              </tr>
            </thead>
            <tbody>
              {status.hub.sessions.map((s) => (
                <tr key={s.key} className="border-t border-white/5">
                  <td className="px-4 py-2 font-mono text-xs text-accent">{s.key}</td>
                  <td className="px-4 py-2">
                    <span className={
                      'rounded px-1.5 py-0.5 text-[10px] font-semibold ' +
                      (s.state === 'live' ? 'bg-success/15 text-success'
                        : s.state === 'reconnecting' ? 'bg-amber-500/15 text-amber-300'
                          : 'bg-white/5 text-ink-tertiary')
                    }>{s.state}</span>
                  </td>
                  <td className="px-4 py-2">
                    {s.subscribers}
                    {s.subscribers > 1 && (
                      <span className="ml-1 text-[10px] text-emerald-300">· mutualisé</span>
                    )}
                  </td>
                  <td className="px-4 py-2 text-ink-secondary">{dur(s.sinceMs)}</td>
                  <td className="px-4 py-2 text-right text-ink-secondary">{fmtBytes(s.bytesIn)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

// ---- Gestion des familles ----------------------------------------------
function FamiliesManager({
  families, providerMax, onCreateFamily, onDeleteFamily, onAddUser, onDeleteUser,
}: {
  families: GwFamily[] | null;
  providerMax: number;
  onCreateFamily: (id: string, max: number) => void;
  onDeleteFamily: (id: string) => void;
  onAddUser: (familyId: string, username: string, password: string, max: number) => void;
  onDeleteUser: (familyId: string, username: string) => void;
}) {
  const [newId, setNewId] = useState('');
  const [newMax, setNewMax] = useState(providerMax || 5);
  const input = 'rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <div className="rounded-xl border border-white/5 bg-midnight p-4">
      <div className="mb-3 text-[10px] font-bold uppercase tracking-widest text-ink-tertiary">
        Familles &amp; clones
      </div>

      {/* Créer une famille */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <input value={newId} onChange={(e) => setNewId(e.target.value)}
          placeholder="Nom de la famille (ex. famille-karim)" className={input + ' flex-1 min-w-[200px]'} />
        <input value={newMax} onChange={(e) => setNewMax(parseInt(e.target.value, 10) || 1)}
          type="number" min={1} title="Écrans simultanés max" className={input + ' w-28'} />
        <button type="button"
          onClick={() => { if (newId.trim()) { onCreateFamily(newId.trim(), newMax); setNewId(''); } }}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright">
          + Créer
        </button>
      </div>

      {families == null ? (
        <div className="py-8 text-center text-xs text-ink-tertiary">Chargement…</div>
      ) : families.length === 0 ? (
        <div className="py-8 text-center text-xs text-ink-tertiary">Aucune famille. Crée-en une ci-dessus.</div>
      ) : (
        <div className="space-y-3">
          {families.map((f) => (
            <FamilyCard key={f.id} family={f}
              onDelete={() => onDeleteFamily(f.id)}
              onAddUser={(u, p, m) => onAddUser(f.id, u, p, m)}
              onDeleteUser={(u) => onDeleteUser(f.id, u)} />
          ))}
        </div>
      )}
    </div>
  );
}

function FamilyCard({
  family, onDelete, onAddUser, onDeleteUser,
}: {
  family: GwFamily;
  onDelete: () => void;
  onAddUser: (username: string, password: string, max: number) => void;
  onDeleteUser: (username: string) => void;
}) {
  const [uname, setUname] = useState('');
  const [pass, setPass] = useState(genPassword());
  const input = 'rounded-md border border-white/5 bg-obsidian px-2.5 py-1.5 text-xs outline-none focus:ring-1 focus:ring-accent';

  function copy(text: string) {
    navigator.clipboard?.writeText(text).then(() => toast('Copié.', 'success')).catch(() => {});
  }

  return (
    <div className="rounded-lg border border-white/5 bg-obsidian p-3">
      <div className="mb-2 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-ink-primary">👨‍👩‍👧 {family.id}</span>
          <span className="rounded bg-white/5 px-1.5 py-0.5 text-[10px] text-ink-tertiary">
            {family.users.length} clone(s) · {family.maxStreams} écrans max
          </span>
        </div>
        <button type="button" onClick={onDelete}
          className="text-xs text-ink-tertiary hover:text-red-300">Supprimer la famille</button>
      </div>

      {/* Clones */}
      <div className="mb-2 space-y-1">
        {family.users.map((u) => (
          <div key={u.username} className="flex items-center gap-2 rounded-md bg-white/[0.02] px-2 py-1.5 text-xs">
            <span className="font-mono font-semibold text-ink-primary">{u.username}</span>
            <button type="button" onClick={() => copy(u.password)}
              className="font-mono text-ink-tertiary hover:text-accent" title="Cliquer pour copier le mot de passe">
              {u.password}
            </button>
            <span className="text-[10px] text-ink-tertiary">{u.maxStreams} écran(s)</span>
            <button type="button" onClick={() => onDeleteUser(u.username)}
              className="ml-auto text-ink-tertiary hover:text-red-300">retirer</button>
          </div>
        ))}
        {family.users.length === 0 && (
          <div className="px-2 py-1 text-[11px] text-ink-tertiary">Aucun clone. Ajoute papa ci-dessous.</div>
        )}
      </div>

      {/* Ajouter un clone */}
      <div className="flex flex-wrap items-center gap-2">
        <input value={uname} onChange={(e) => setUname(e.target.value)}
          placeholder="papa / maman / enfant1" className={input + ' flex-1 min-w-[120px]'} />
        <input value={pass} onChange={(e) => setPass(e.target.value)}
          className={input + ' w-28 font-mono'} />
        <button type="button" onClick={() => setPass(genPassword())} title="Générer"
          className={input + ' cursor-pointer text-ink-tertiary hover:text-accent'}>↻</button>
        <button type="button"
          onClick={() => { if (uname.trim()) { onAddUser(uname.trim(), pass, 1); setUname(''); setPass(genPassword()); } }}
          className="rounded-md border border-accent/40 bg-accent/10 px-3 py-1.5 text-xs font-semibold text-accent-bright hover:bg-accent/20">
          + Ajouter le clone
        </button>
      </div>
    </div>
  );
}
