import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  familiesApi, ApiError,
  type Family, type FamilyMember, type FamilySource,
} from '@/lib/api';
import { formatDateTime } from '@/lib/utils';

/// Page FAMILLE — UNE ligne Xtream (multi-connexions) partagée par plusieurs
/// appareils. On crée la famille (nom + source), puis on ajoute les appareils
/// (papa, maman, enfants…). Chaque appareil reçoit la MÊME source + une
/// licence active. Le nombre d'écrans simultanés dépend du `max_connections`
/// de la ligne (réglé chez le fournisseur).

const inputCls =
  'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent';

export function FamiliesPage({ onLogout }: { onLogout: () => void }) {
  const [families, setFamilies] = useState<Family[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [members, setMembers] = useState<FamilyMember[]>([]);
  const [detail, setDetail] = useState<Family | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Formulaire création.
  const [name, setName] = useState('');
  const [server, setServer] = useState('');
  const [user, setUser] = useState('');
  const [pass, setPass] = useState('');

  // Ajout d'un membre.
  const [mMac, setMMac] = useState('MK:');
  const [mLabel, setMLabel] = useState('');

  function fail(e: unknown) {
    if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
    setErr(e instanceof ApiError ? e.message : 'Erreur.');
  }

  function loadList() {
    familiesApi.list().then((r) => setFamilies(r.items)).catch(fail);
  }
  useEffect(() => { loadList(); /* eslint-disable-next-line */ }, []);

  function openFamily(id: string) {
    setSelected(id);
    setErr(null);
    familiesApi.get(id)
      .then((r) => { setDetail(r.family); setMembers(r.members); })
      .catch(fail);
  }

  async function createFamily(e: FormEvent) {
    e.preventDefault();
    setErr(null);
    if (!name.trim() || !server.trim() || !user.trim() || !pass.trim()) {
      setErr('Remplis le nom, le serveur, l\'utilisateur et le mot de passe.');
      return;
    }
    setBusy(true);
    const source: FamilySource = {
      type: 'xtream',
      server_url: server.trim(),
      username: user.trim(),
      password: pass.trim(),
    };
    try {
      const r = await familiesApi.create(name.trim(), source);
      setName(''); setServer(''); setUser(''); setPass('');
      loadList();
      openFamily(r.family.id);
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function addMember(e: FormEvent) {
    e.preventDefault();
    if (!selected) return;
    const m = mMac.trim().toUpperCase();
    if (!/^MK(?::[0-9A-F]{2}){5}$/i.test(m)) {
      setErr('MAC invalide. Format : MK:XX:XX:XX:XX:XX');
      return;
    }
    setBusy(true); setErr(null);
    try {
      await familiesApi.addMember(selected, m, mLabel.trim() || undefined);
      setMMac('MK:'); setMLabel('');
      openFamily(selected);
      loadList();
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function removeMember(mac: string) {
    if (!selected) return;
    setBusy(true); setErr(null);
    try {
      await familiesApi.removeMember(selected, mac);
      openFamily(selected);
      loadList();
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function deleteFamily(id: string) {
    setBusy(true); setErr(null);
    try {
      await familiesApi.remove(id);
      if (selected === id) { setSelected(null); setDetail(null); setMembers([]); }
      loadList();
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  return (
    <AppLayout
      title="Famille"
      subtitle="Une ligne Xtream partagée par plusieurs appareils (papa, maman, enfants…)."
      onLogout={onLogout}
    >
      {err && (
        <div className="mb-4 rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">
          {err}
        </div>
      )}

      {/* Rappel honnête sur les connexions simultanées. */}
      <div className="mb-5 max-w-3xl rounded-lg border border-white/5 bg-slate/40 px-4 py-3 text-xs text-ink-secondary">
        ⚠️ Le nombre d'écrans qui regardent <b>en même temps</b> = le
        <b> max_connections</b> de la ligne Xtream (réglé chez ton fournisseur).
        Pour une famille de 10 écrans, prends une ligne à 10 connexions.
      </div>

      <div className="grid max-w-5xl gap-6 md:grid-cols-2">
        {/* ===== Colonne gauche : créer + liste ===== */}
        <div className="space-y-6">
          <form onSubmit={createFamily} className="space-y-3 rounded-xl border border-white/5 bg-midnight p-6">
            <h2 className="text-sm font-semibold text-ink-primary">Nouvelle famille</h2>
            <input value={name} onChange={(e) => setName(e.target.value)}
              placeholder="Nom de la famille (ex. Famille Karim)" className={inputCls} />
            <input value={server} onChange={(e) => setServer(e.target.value)}
              placeholder="http://serveur.com:port" className={inputCls + ' font-mono'} />
            <input value={user} onChange={(e) => setUser(e.target.value)}
              placeholder="Utilisateur Xtream" className={inputCls} />
            <input value={pass} onChange={(e) => setPass(e.target.value)}
              placeholder="Mot de passe Xtream" className={inputCls} />
            <button type="submit" disabled={busy}
              className="w-full rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
              {busy ? '…' : 'Créer la famille'}
            </button>
          </form>

          <div className="rounded-xl border border-white/5 bg-midnight p-4">
            <h2 className="mb-3 text-sm font-semibold text-ink-primary">Familles</h2>
            {families.length === 0 && (
              <p className="text-xs text-ink-tertiary">Aucune famille pour l'instant.</p>
            )}
            <div className="space-y-2">
              {families.map((f) => (
                <button key={f.id} type="button" onClick={() => openFamily(f.id)}
                  className={
                    'flex w-full items-center justify-between rounded-md border px-3 py-2 text-left text-sm transition ' +
                    (selected === f.id
                      ? 'border-accent bg-accent/10 text-ink-primary'
                      : 'border-white/5 bg-slate text-ink-secondary hover:border-white/20')
                  }>
                  <span className="font-medium">{f.name}</span>
                  <span className="text-[11px] text-ink-tertiary">
                    {f.member_count ?? 0} appareil(s)
                  </span>
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* ===== Colonne droite : détail famille sélectionnée ===== */}
        <div className="rounded-xl border border-white/5 bg-obsidian p-6">
          {!detail && (
            <p className="text-sm text-ink-tertiary">
              Sélectionne une famille pour voir ses appareils et en ajouter.
            </p>
          )}
          {detail && (
            <div className="space-y-4">
              <div className="flex items-start justify-between">
                <div>
                  <h2 className="text-base font-semibold text-ink-primary">{detail.name}</h2>
                  {detail.source && (
                    <p className="font-mono text-[11px] text-ink-tertiary">
                      {detail.source.server_url} · {detail.source.username}
                    </p>
                  )}
                </div>
                <button type="button" onClick={() => deleteFamily(detail.id)} disabled={busy}
                  className="text-xs text-ink-tertiary hover:text-accent-bright">
                  Supprimer
                </button>
              </div>

              {/* Ajouter un appareil */}
              <form onSubmit={addMember} className="space-y-2 rounded-lg border border-white/5 bg-slate/40 p-3">
                <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                  Ajouter un appareil
                </p>
                <input value={mMac} onChange={(e) => setMMac(e.target.value)}
                  placeholder="MK:1A:2B:3C:4D:5E" className={inputCls + ' font-mono'} />
                <input value={mLabel} onChange={(e) => setMLabel(e.target.value)}
                  placeholder="Étiquette (ex. Salon, Chambre, Enfant)" className={inputCls} />
                <button type="submit" disabled={busy}
                  className="w-full rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
                  {busy ? '…' : 'Activer + ajouter à la famille'}
                </button>
              </form>

              {/* Liste des membres */}
              <div className="space-y-2">
                {members.length === 0 && (
                  <p className="text-xs text-ink-tertiary">Aucun appareil dans cette famille.</p>
                )}
                {members.map((m) => (
                  <div key={m.mac}
                    className="flex items-center justify-between rounded-md border border-white/5 bg-slate px-3 py-2 text-sm">
                    <div>
                      <span className="font-mono text-ink-primary">{m.mac}</span>
                      {m.label && <span className="ml-2 text-ink-tertiary">· {m.label}</span>}
                      <div className="text-[10px] text-ink-tertiary">
                        {m.created_at ? formatDateTime(m.created_at) : ''}
                      </div>
                    </div>
                    <button type="button" onClick={() => removeMember(m.mac)} disabled={busy}
                      className="text-xs text-ink-tertiary hover:text-accent-bright">
                      Retirer
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
