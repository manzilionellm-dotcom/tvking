import { FormEvent, useEffect, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import {
  familiesApi, m3uLinkUrl, ApiError,
  type Family, type FamilyMember, type FamilySource, type FamilyLink,
} from '@/lib/api';
import { formatDateTime, formatMacInput } from '@/lib/utils';

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
  const [links, setLinks] = useState<FamilyLink[]>([]);
  const [linkLabel, setLinkLabel] = useState('');
  const [copied, setCopied] = useState<string | null>(null);
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
      .then((r) => { setDetail(r.family); setMembers(r.members); setLinks(r.links || []); })
      .catch(fail);
  }

  async function addLink() {
    if (!selected) return;
    setBusy(true); setErr(null);
    try {
      await familiesApi.createLink(selected, linkLabel.trim() || undefined);
      setLinkLabel('');
      openFamily(selected);
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  async function removeLink(linkId: string) {
    if (!selected) return;
    setBusy(true); setErr(null);
    try {
      await familiesApi.deleteLink(selected, linkId);
      openFamily(selected);
    } catch (e) { fail(e); } finally { setBusy(false); }
  }

  function copy(text: string, id: string) {
    navigator.clipboard?.writeText(text).then(() => {
      setCopied(id);
      setTimeout(() => setCopied((c) => (c === id ? null : c)), 1500);
    }).catch(() => {});
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
                <input value={mMac} onChange={(e) => setMMac(formatMacInput(e.target.value))}
                  maxLength={17}
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

              {/* ===== Liens M3U distribuables (une source → N liens séparés) ===== */}
              <div className="space-y-2 rounded-lg border border-white/5 bg-slate/40 p-3">
                <p className="text-[10px] uppercase tracking-widest text-ink-tertiary">
                  Liens M3U à distribuer (même source)
                </p>
                <div className="flex gap-2">
                  <input value={linkLabel} onChange={(e) => setLinkLabel(e.target.value)}
                    placeholder="Nom du lien (ex. Papa, Maman, Enfant)" className={inputCls} />
                  <button type="button" onClick={addLink} disabled={busy}
                    className="shrink-0 rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:opacity-50">
                    Générer
                  </button>
                </div>
                {links.length === 0 && (
                  <p className="text-xs text-ink-tertiary">Aucun lien généré.</p>
                )}
                {links.map((lk) => {
                  const url = m3uLinkUrl(lk.token);
                  return (
                    <div key={lk.id}
                      className="rounded-md border border-white/5 bg-slate px-3 py-2 text-sm">
                      <div className="flex items-center justify-between">
                        <span className="text-ink-primary">{lk.label || 'Lien'}</span>
                        <div className="flex items-center gap-3">
                          <button type="button" onClick={() => copy(url, lk.id)}
                            className="text-xs text-accent-bright hover:underline">
                            {copied === lk.id ? 'Copié ✓' : 'Copier'}
                          </button>
                          <button type="button" onClick={() => removeLink(lk.id)} disabled={busy}
                            className="text-xs text-ink-tertiary hover:text-accent-bright">
                            Révoquer
                          </button>
                        </div>
                      </div>
                      <div className="mt-1 break-all font-mono text-[11px] text-ink-tertiary">
                        {url}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
