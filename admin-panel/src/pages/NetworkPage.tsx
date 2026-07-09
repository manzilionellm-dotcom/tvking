import { FormEvent, useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import {
  netExitsApi, deviceNetApi, familyRelayApi, getCurrentUser, isOwnerRole,
  type NetExit, type DeviceNet, ApiError,
} from '@/lib/api';
import { formatDateTime, formatMacInput } from '@/lib/utils';

/// Page RÉSEAU & LOCALISATION — « changer l'IP d'un client ».
///  Scénario : un client vit en Suède, part en Allemagne ; le fournisseur
///  a verrouillé son compte sur UNE IP → tout casse. Ici l'admin assigne
///  une SORTIE (un proxy qu'il contrôle, situé dans le bon pays) à la MAC
///  du client : tout son trafic IPTV sort par cette IP fixe, où qu'il
///  voyage. Livraison instantanée (l'app applique en < 20 s).
///
///  Deux zones :
///   • Assigner une sortie à un appareil (par MAC) — le geste quotidien.
///   • Gérer la liste des sorties prédéfinies (proxys pays) — owner.

const MAC_OK = /^MK(?::[0-9A-F]{2}){5}$/i;

export function NetworkPage({ onLogout }: { onLogout: () => void }) {
  const owner = isOwnerRole(getCurrentUser()?.role);
  const [exits, setExits] = useState<NetExit[]>([]);

  const reloadExits = useCallback(() => {
    if (!owner) return;
    netExitsApi.list()
      .then((r) => setExits(r.items))
      .catch((e) => { if (e instanceof ApiError && e.status === 401) onLogout(); });
  }, [owner, onLogout]);

  useEffect(() => { reloadExits(); }, [reloadExits]);

  return (
    <AppLayout
      title="Réseau & localisation"
      subtitle="Change l'IP d'un client à distance — utile quand il voyage et que le fournisseur a verrouillé son compte sur une IP."
      onLogout={onLogout}
    >
      <div className="grid max-w-5xl gap-6 lg:grid-cols-2">
        <AssignExit exits={exits} onLogout={onLogout} />
        <div className="space-y-6">
          {owner && <ManageExits exits={exits} onSaved={reloadExits} onLogout={onLogout} />}
          {owner && <FamilyRelayCard onLogout={onLogout} />}
        </div>
      </div>
    </AppLayout>
  );
}

/// Relais de FLUX MUTUALISÉ (option famille) — owner. Une base https vers
/// le serveur server/cast-remux : quand un appareil est en « flux
/// mutualisé », il lit ses chaînes via ce relais → les spectateurs d'une
/// même chaîne partagent UNE connexion fournisseur (1 flux par chaîne, pas
/// par appareil).
function FamilyRelayCard({ onLogout }: { onLogout: () => void }) {
  const [base, setBase] = useState('');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    familyRelayApi.get()
      .then((r) => setBase(r.base))
      .catch((e) => { if (e instanceof ApiError && e.status === 401) onLogout(); })
      .finally(() => setLoading(false));
  }, [onLogout]);

  async function save() {
    setBusy(true); setMsg(null);
    try {
      const r = await familyRelayApi.save(base.trim());
      setBase(r.base);
      setMsg({ ok: true, text: r.base ? 'Relais enregistré. Active « flux mutualisé » sur les appareils voulus.' : 'Relais retiré (flux mutualisé coupé partout).' });
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Échec.' });
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <div className="space-y-3 rounded-xl border border-white/5 bg-obsidian p-6">
      <h2 className="text-sm font-semibold">Flux mutualisé (option famille)</h2>
      <p className="text-[11px] leading-relaxed text-ink-tertiary">
        Colle l'adresse de ton relais <span className="font-mono">server/cast-remux</span>{' '}
        (un petit VPS, guide dans le dépôt). Quand un appareil est en « flux
        mutualisé », les membres d'une famille qui regardent la <b>même chaîne</b>{' '}
        partagent <b>une seule</b> connexion fournisseur. Chaînes différentes =
        connexions différentes (limite physique).
      </p>
      {loading ? (
        <p className="text-sm text-ink-tertiary">Chargement…</p>
      ) : (
        <>
          <input value={base} onChange={(e) => setBase(e.target.value)}
            placeholder="https://relais.mon-infra.net" className={inputCls + ' font-mono'} />
          {msg && (
            <div className={
              'rounded-md px-3 py-2 text-xs ' +
              (msg.ok ? 'border border-success/30 bg-success/10 text-success'
                      : 'border border-accent/30 bg-accent/10 text-accent-bright')
            }>
              {msg.text}
            </div>
          )}
          <button onClick={save} disabled={busy}
            className="w-full rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
            {busy ? 'Enregistrement…' : 'Enregistrer le relais'}
          </button>
        </>
      )}
    </div>
  );
}

/// Assigner / retirer une sortie pour un appareil (par MAC).
function AssignExit({ exits, onLogout }: { exits: NetExit[]; onLogout: () => void }) {
  const [sp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [current, setCurrent] = useState<DeviceNet | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  // Choix : id d'une sortie prédéfinie, 'custom' (proxy manuel), ou 'off'.
  const [choice, setChoice] = useState<string>('off');
  const [customProxy, setCustomProxy] = useState('');
  const [customLabel, setCustomLabel] = useState('');

  const macOk = MAC_OK.test(mac.trim());

  useEffect(() => {
    if (!macOk) { setCurrent(null); return; }
    let active = true;
    setLoading(true);
    deviceNetApi.get(mac.trim().toUpperCase())
      .then((r) => {
        if (!active) return;
        setCurrent(r);
        // Pré-sélectionne la sortie correspondante si elle est prédéfinie.
        const match = exits.find((e) => e.proxy === r.proxy);
        setChoice(r.proxy ? (match ? match.id : 'custom') : 'off');
        if (r.proxy && !match) { setCustomProxy(r.proxy); setCustomLabel(r.label); }
      })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        if (active) setCurrent(null);
      })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mac, exits]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setMsg(null);
    const m = mac.trim().toUpperCase();
    if (!MAC_OK.test(m)) {
      setMsg({ ok: false, text: 'MAC invalide (MK:XX:XX:XX:XX:XX).' });
      setBusy(false);
      return;
    }
    try {
      if (choice === 'off') {
        await deviceNetApi.clear(m);
        setMsg({ ok: true, text: `${m} repasse en direct (IP réelle du client) — effet en quelques secondes.` });
      } else {
        let proxy = ''; let label = '';
        if (choice === 'custom') {
          proxy = customProxy.trim(); label = customLabel.trim();
        } else {
          const ex = exits.find((x) => x.id === choice);
          if (ex) { proxy = ex.proxy; label = ex.label; }
        }
        if (!proxy) { setMsg({ ok: false, text: 'Choisis une sortie ou saisis un proxy.' }); setBusy(false); return; }
        await deviceNetApi.set(m, proxy, label);
        setMsg({ ok: true, text: `${m} sort désormais par « ${label || proxy} » — le fournisseur verra cette IP en quelques secondes.` });
      }
      const r = await deviceNetApi.get(m).catch(() => null);
      if (r) setCurrent(r);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Échec.' });
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <form onSubmit={submit} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
      <h2 className="text-sm font-semibold">Changer l'IP d'un appareil</h2>

      <div>
        <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
          Adresse MAC de l'appareil
        </label>
        <input
          value={mac}
          onChange={(e) => setMac(formatMacInput(e.target.value))}
          autoFocus maxLength={17}
          placeholder="MK:1A:2B:3C:4D:5E"
          className={inputCls + ' font-mono'}
        />
      </div>

      {macOk && (
        <div className="rounded-md border border-white/10 bg-slate/30 px-3 py-2 text-xs">
          {loading ? (
            <span className="text-ink-tertiary">Chargement de la sortie actuelle…</span>
          ) : current && current.proxy ? (
            <span className="text-ink-secondary">
              Sortie actuelle : <span className="font-semibold text-accent-bright">{current.label || current.proxy}</span>
              {current.updated_at && <span className="text-ink-tertiary"> · depuis {formatDateTime(current.updated_at)}</span>}
            </span>
          ) : (
            <span className="text-ink-tertiary">Cet appareil est en <b>direct</b> (IP réelle du client).</span>
          )}
        </div>
      )}

      {/* ===== Flux mutualisé (option famille) — bascule indépendante ===== */}
      {macOk && (
        <div className="rounded-md border border-white/10 bg-slate/30 p-3">
          <label className="flex items-start gap-2.5 text-sm">
            <input
              type="checkbox"
              className="mt-0.5"
              checked={!!current?.shared}
              disabled={busy || loading || !current?.relay_configured}
              onChange={async (e) => {
                const m = mac.trim().toUpperCase();
                setBusy(true); setMsg(null);
                try {
                  await deviceNetApi.setShared(m, e.target.checked);
                  const r = await deviceNetApi.get(m).catch(() => null);
                  if (r) setCurrent(r);
                  setMsg({ ok: true, text: e.target.checked
                    ? `Flux mutualisé activé sur ${m} — 1 connexion fournisseur par chaîne partagée.`
                    : `Flux mutualisé coupé sur ${m}.` });
                } catch (err: any) {
                  if (err instanceof ApiError && err.status === 401) { onLogout(); return; }
                  setMsg({ ok: false, text: err instanceof ApiError ? err.message : 'Échec.' });
                } finally {
                  setBusy(false);
                }
              }}
            />
            <span>
              <span className="font-medium">Flux mutualisé (option famille)</span>
              <span className="mt-0.5 block text-[11px] text-ink-tertiary">
                {current?.relay_configured
                  ? 'Les membres qui regardent la même chaîne partagent une seule connexion fournisseur.'
                  : 'Configure d\'abord le relais famille (carte à droite) pour activer cette option.'}
              </span>
            </span>
          </label>
        </div>
      )}

      <div>
        <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
          Sortie réseau à appliquer
        </label>
        <div className="space-y-1.5">
          <label className="flex items-center gap-2 rounded-md border border-white/5 bg-slate px-3 py-2 text-sm">
            <input type="radio" name="exit" checked={choice === 'off'} onChange={() => setChoice('off')} />
            <span>Direct — IP réelle du client (aucune sortie)</span>
          </label>
          {exits.map((ex) => (
            <label key={ex.id} className="flex items-center gap-2 rounded-md border border-white/5 bg-slate px-3 py-2 text-sm">
              <input type="radio" name="exit" checked={choice === ex.id} onChange={() => setChoice(ex.id)} />
              <span className="font-medium">{ex.label}</span>
            </label>
          ))}
          <label className="flex items-center gap-2 rounded-md border border-white/5 bg-slate px-3 py-2 text-sm">
            <input type="radio" name="exit" checked={choice === 'custom'} onChange={() => setChoice('custom')} />
            <span>Proxy manuel (ponctuel)</span>
          </label>
        </div>
      </div>

      {choice === 'custom' && (
        <div className="space-y-2 rounded-md border border-white/10 bg-slate/30 p-3">
          <input value={customLabel} onChange={(e) => setCustomLabel(e.target.value)}
            placeholder="Nom (ex. Allemagne — dépannage)" className={inputCls} />
          <input value={customProxy} onChange={(e) => setCustomProxy(e.target.value)}
            placeholder="http://user:pass@host:port  ou  socks5://host:port"
            className={inputCls + ' font-mono'} />
        </div>
      )}

      {msg && (
        <div className={
          'rounded-md px-3 py-2 text-xs ' +
          (msg.ok ? 'border border-success/30 bg-success/10 text-success'
                  : 'border border-accent/30 bg-accent/10 text-accent-bright')
        }>
          {msg.text}
        </div>
      )}

      <button type="submit" disabled={busy || !macOk}
        className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50">
        {busy ? 'Application…' : 'Appliquer (instantané)'}
      </button>

      <p className="text-[11px] leading-relaxed text-ink-tertiary">
        La sortie s'applique à TOUT le trafic IPTV de l'appareil (connexion,
        chaînes, vidéo). Le fournisseur voit alors une IP fixe, où que voyage
        le client. Repasser en « Direct » rend l'IP réelle.
      </p>
    </form>
  );
}

/// Gérer les sorties prédéfinies (owner) — déclarées une fois, assignées d'un clic.
function ManageExits({
  exits, onSaved, onLogout,
}: { exits: NetExit[]; onSaved: () => void; onLogout: () => void }) {
  const [draft, setDraft] = useState<NetExit[]>(exits);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => { setDraft(exits); }, [exits]);

  function patch(i: number, p: Partial<NetExit>) {
    setDraft((prev) => prev.map((e, idx) => (idx === i ? { ...e, ...p } : e)));
  }
  function add() {
    setDraft((prev) => [...prev, { id: `nx_${prev.length}_${Date.now()}`, label: '', proxy: '' }]);
  }
  function remove(i: number) {
    setDraft((prev) => prev.filter((_, idx) => idx !== i));
  }

  async function save() {
    setBusy(true); setMsg(null);
    try {
      const clean = draft
        .map((e) => ({ ...e, label: e.label.trim(), proxy: e.proxy.trim() }))
        .filter((e) => e.label && e.proxy);
      await netExitsApi.save(clean);
      setMsg({ ok: true, text: `${clean.length} sortie(s) enregistrée(s).` });
      onSaved();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Échec.' });
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

  return (
    <div className="space-y-3 rounded-xl border border-white/5 bg-obsidian p-6">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold">Sorties prédéfinies (pays)</h2>
        <button onClick={add}
          className="rounded-md border border-white/10 px-2.5 py-1 text-xs text-ink-secondary hover:border-accent hover:text-accent-bright">
          + Ajouter
        </button>
      </div>
      <p className="text-[11px] leading-relaxed text-ink-tertiary">
        Déclare ici tes proxys UNE fois (un par pays / relais). Ils apparaissent
        ensuite comme choix rapides à gauche. Un proxy :{' '}
        <span className="font-mono">http://user:pass@host:port</span> ou{' '}
        <span className="font-mono">socks5://host:port</span>. Ce sont TES relais
        (loués/hébergés) : c'est leur emplacement qui donne le « pays » vu par le fournisseur.
      </p>

      {draft.length === 0 && (
        <p className="text-sm text-ink-tertiary">Aucune sortie. Ajoute ton 1er relais (ex. « Suède 🇸🇪 »).</p>
      )}
      <div className="space-y-2">
        {draft.map((e, i) => (
          <div key={e.id} className="space-y-2 rounded-lg border border-white/10 bg-slate/30 p-3">
            <div className="flex items-center gap-2">
              <input value={e.label} onChange={(ev) => patch(i, { label: ev.target.value })}
                placeholder="Label (ex. Suède 🇸🇪)" className={inputCls} />
              <button onClick={() => remove(i)}
                className="shrink-0 rounded-md border border-white/10 px-2.5 py-2 text-xs text-ink-tertiary hover:border-accent hover:text-accent-bright">
                Retirer
              </button>
            </div>
            <input value={e.proxy} onChange={(ev) => patch(i, { proxy: ev.target.value })}
              placeholder="http://user:pass@host:port" className={inputCls + ' font-mono'} />
          </div>
        ))}
      </div>

      {msg && (
        <div className={
          'rounded-md px-3 py-2 text-xs ' +
          (msg.ok ? 'border border-success/30 bg-success/10 text-success'
                  : 'border border-accent/30 bg-accent/10 text-accent-bright')
        }>
          {msg.text}
        </div>
      )}

      <button onClick={save} disabled={busy}
        className="w-full rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
        {busy ? 'Enregistrement…' : 'Enregistrer les sorties'}
      </button>
    </div>
  );
}
