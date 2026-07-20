import { Fragment, FormEvent, useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { MacLink } from '@/components/MacLink';
import {
  mastersApi, ApiError,
  type MasterRow, type MasterCategory, type MasterChannel,
} from '@/lib/api';
import { formatMacInput } from '@/lib/utils';

// =========================================================
//  MastersPage — Comptes MAÎTRES (démo illimitée)
// =========================================================
//  Une MAC listée ici peut, DEPUIS L'APP, envoyer des « tests » (pass invités)
//  à n'importe qui, sur la chaîne de son choix, SANS quota ni obligation
//  d'abonnement payé. Sert à attirer des clients (« essaie 1 h, gratis »).
//  Pouvoir fort → page réservée à l'owner (super_admin).
// =========================================================

const MAC_RX = /^MK(?::[0-9A-Fa-f]{2}){5}$/;

// =========================================================
//  COPIEUR INTELLIGENT + LISTE DE TEST INDÉPENDANTE (par maître)
// =========================================================
//  Le maître clique « Copier mes chaînes » : le serveur lit sa ligne (Xtream/
//  M3U), range TOUT en catégories, et on affiche des cases à cocher. Il coche
//  les quelques chaînes à partager en test → on bâtit le petit M3U. Tous les
//  tests servent CETTE liste → chaînes partagées → le gateway mutualise → le
//  fournisseur ne voit qu'UNE connexion (un seul trio suffit). Sans liste : le
//  test donne accès à tout le bouquet (repli).

// Échappe une valeur pour un attribut M3U entre guillemets.
function m3uAttr(s: string): string {
  return String(s || '').replace(/"/g, "'").replace(/[\r\n]/g, ' ');
}

// Construit le M3U de test à partir des chaînes cochées.
function buildM3u(sel: Map<string, MasterChannel & { group: string }>): string {
  const lines = ['#EXTM3U'];
  for (const c of sel.values()) {
    lines.push(
      `#EXTINF:-1 tvg-logo="${m3uAttr(c.logo)}" group-title="${m3uAttr(c.group)}",${m3uAttr(c.name)}`,
    );
    lines.push(c.url);
  }
  return lines.join('\n') + '\n';
}

function TestListEditor({ mac, onLogout }: { mac: string; onLogout: () => void }) {
  // Sélection courante : clé = URL (identifie une chaîne de façon unique).
  const [sel, setSel] = useState<Map<string, MasterChannel & { group: string }>>(new Map());
  const [savedCount, setSavedCount] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  // Copieur (catégories chargées depuis la ligne du maître).
  const [cats, setCats] = useState<MasterCategory[] | null>(null);
  const [copying, setCopying] = useState(false);
  const [copyErr, setCopyErr] = useState<string | null>(null);
  const [truncated, setTruncated] = useState(false);
  const [openCat, setOpenCat] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [m3uText, setM3uText] = useState('');
  // Lien collé par le maître (Xtream get.php ou URL M3U) à copier directement.
  const [paste, setPaste] = useState('');

  // Charge la liste déjà enregistrée → pré-coche les URLs connues.
  useEffect(() => {
    (async () => {
      try {
        const r = await mastersApi.getTestList(mac);
        setSavedCount(r.count || 0);
        setM3uText(r.m3u || '');
        const m = new Map<string, MasterChannel & { group: string }>();
        // Parse le M3U enregistré pour reconstituer la sélection (nom/url).
        const lines = (r.m3u || '').split(/\r?\n/);
        let pending: { name: string; logo: string; group: string } | null = null;
        for (const raw of lines) {
          const line = raw.trim();
          if (line.startsWith('#EXTINF')) {
            const group = (line.match(/group-title="([^"]*)"/i) || [])[1] || '';
            const logo = (line.match(/tvg-logo="([^"]*)"/i) || [])[1] || '';
            const name = (line.split(',').slice(1).join(',') || '').trim() || 'Chaîne';
            pending = { name, logo, group };
          } else if (line && !line.startsWith('#') && pending) {
            m.set(line, { id: line, name: pending.name, logo: pending.logo, url: line, group: pending.group });
            pending = null;
          }
        }
        setSel(m);
      } catch (e: any) {
        if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
        setErr(e instanceof ApiError ? e.message : 'Chargement impossible.');
      } finally { setLoaded(true); }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mac]);

  async function copyChannels() {
    setCopyErr(null); setCopying(true);
    try {
      // Si tu as collé un lien → on copie CELUI-LÀ ; sinon la ligne assignée.
      const r = await mastersApi.channels(mac, paste);
      setCats(r.categories || []);
      setTruncated(!!r.truncated);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setCopyErr(e instanceof ApiError ? e.message : 'Copie impossible.');
    } finally { setCopying(false); }
  }

  function toggle(ch: MasterChannel, group: string) {
    setSel((prev) => {
      const next = new Map(prev);
      if (next.has(ch.url)) next.delete(ch.url);
      else next.set(ch.url, { ...ch, group });
      return next;
    });
  }

  function clearSel() { setSel(new Map()); }

  async function save() {
    setErr(null); setMsg(null); setBusy(true);
    try {
      const m3u = sel.size ? buildM3u(sel) : '';
      const r = await mastersApi.putTestList(mac, m3u);
      setSavedCount(r.count || 0);
      setM3uText(m3u);
      setMsg(r.count > 0
        ? `✅ Liste enregistrée — ${r.count} chaîne${r.count > 1 ? 's' : ''} partagée${r.count > 1 ? 's' : ''}.`
        : '✅ Liste vidée — les tests redonnent tout le bouquet.');
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Enregistrement impossible.');
    } finally { setBusy(false); }
  }

  async function saveAdvanced() {
    setErr(null); setMsg(null); setBusy(true);
    try {
      const r = await mastersApi.putTestList(mac, m3uText);
      setSavedCount(r.count || 0);
      setMsg(`✅ M3U enregistré — ${r.count} chaîne(s).`);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Enregistrement impossible.');
    } finally { setBusy(false); }
  }

  // Catégories filtrées par le champ de recherche (nom de catégorie/chaîne).
  const shownCats = useMemo(() => {
    if (!cats) return [];
    const q = filter.trim().toLowerCase();
    if (!q) return cats;
    return cats
      .map((c) => ({
        ...c,
        channels: c.name.toLowerCase().includes(q)
          ? c.channels
          : c.channels.filter((ch) => ch.name.toLowerCase().includes(q)),
      }))
      .filter((c) => c.channels.length > 0);
  }, [cats, filter]);

  const selCount = sel.size;
  const tooMany = selCount > 5;

  return (
    <div className="space-y-3 border-t border-white/5 bg-slate/40 px-4 py-4">
      <div className="text-[13px] text-ink-secondary">
        <strong>Copieur intelligent.</strong> Clique « Copier mes chaînes » : je
        lis ta ligne, je range tout en <strong>catégories</strong>, et tu coches
        les quelques chaînes à partager en test (idéalement{' '}
        <strong>moins de 5</strong>). Tous les tests servent cette sélection :
        les testeurs partagent les mêmes chaînes, le gateway les mutualise et{' '}
        <strong>le fournisseur ne voit qu'une connexion</strong> — un seul trio
        suffit. Aucune sélection = accès à tout le bouquet.
      </div>

      {/* ===== Source à copier : C'EST TOI qui la colles ===== */}
      <div>
        <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
          Lien à copier — ton Xtream (get.php…) ou ton URL M3U
        </label>
        <input
          value={paste}
          onChange={(e) => setPaste(e.target.value)}
          spellCheck={false}
          placeholder="http://serveur:8080/get.php?username=…&password=…  ·  ou  ·  http://…/playlist.m3u"
          className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 font-mono text-xs outline-none focus:ring-1 focus:ring-accent"
        />
        <p className="mt-1 text-[11px] text-ink-tertiary">
          Laisse vide pour copier la ligne déjà assignée à ce maître dans le panel.
        </p>
      </div>

      {/* ===== Barre d'action ===== */}
      <div className="flex flex-wrap items-center gap-3">
        <button
          onClick={copyChannels}
          disabled={copying}
          className="rounded-md border border-accent/40 px-3 py-2 text-sm font-medium text-accent-bright transition hover:bg-accent/10 disabled:opacity-50"
        >
          {copying ? 'Copie en cours…' : cats ? 'Recopier mes chaînes' : 'Copier mes chaînes'}
        </button>
        <button
          onClick={save}
          disabled={busy || !loaded}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? 'Enregistrement…' : `Enregistrer la sélection (${selCount})`}
        </button>
        {selCount > 0 && (
          <button onClick={clearSel} className="text-xs text-ink-tertiary underline hover:text-ink-secondary">
            Tout décocher
          </button>
        )}
        <span className={`text-xs ${tooMany ? 'text-warning' : 'text-ink-tertiary'}`}>
          {selCount} sélectionnée{selCount > 1 ? 's' : ''}
          {tooMany ? " — au-delà de 5, l'indépendance faiblit" : ''}
          {loaded && savedCount !== selCount ? ' (non enregistré)' : ''}
        </span>
      </div>

      {copyErr && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{copyErr}</div>}
      {truncated && (
        <div className="rounded-md border border-warning/30 bg-warning/10 px-3 py-2 text-xs text-warning">
          Beaucoup de chaînes — la liste a été tronquée à l'affichage. Utilise la
          recherche pour trouver celles à partager.
        </div>
      )}

      {/* ===== Arbre catégories → chaînes ===== */}
      {cats && (
        <div className="space-y-2">
          <input
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filtrer une chaîne ou une catégorie…"
            className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
          />
          <div className="max-h-96 space-y-1 overflow-y-auto rounded-md border border-white/5 bg-midnight p-2">
            {shownCats.length === 0 && (
              <div className="px-2 py-4 text-center text-xs text-ink-tertiary">Aucune chaîne.</div>
            )}
            {shownCats.map((c) => {
              const nSel = c.channels.filter((ch) => sel.has(ch.url)).length;
              const isOpen = openCat === c.id || !!filter.trim();
              return (
                <div key={c.id} className="rounded-md border border-white/[0.04]">
                  <button
                    onClick={() => setOpenCat(isOpen && !filter.trim() ? null : c.id)}
                    className="flex w-full items-center justify-between px-3 py-2 text-left text-sm hover:bg-white/[0.02]"
                  >
                    <span className="text-ink-secondary">
                      {isOpen ? '▾' : '▸'} {c.name}
                      <span className="ml-2 text-[10px] text-ink-tertiary">{c.channels.length}</span>
                    </span>
                    {nSel > 0 && (
                      <span className="rounded-full bg-accent/20 px-2 py-0.5 text-[10px] text-accent-bright">{nSel} ✓</span>
                    )}
                  </button>
                  {isOpen && (
                    <div className="border-t border-white/[0.04] px-2 py-1">
                      {c.channels.map((ch) => {
                        const on = sel.has(ch.url);
                        return (
                          <label
                            key={ch.url}
                            className="flex cursor-pointer items-center gap-2 rounded px-2 py-1 text-[13px] hover:bg-white/[0.02]"
                          >
                            <input type="checkbox" checked={on} onChange={() => toggle(ch, c.name)} className="accent-accent" />
                            <span className={on ? 'text-ink-primary' : 'text-ink-secondary'}>{ch.name}</span>
                          </label>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* ===== Repli avancé : M3U brut à la main ===== */}
      <button
        onClick={() => setShowAdvanced((v) => !v)}
        className="text-xs text-ink-tertiary underline hover:text-ink-secondary"
      >
        {showAdvanced ? 'Masquer' : 'Avancé : coller un M3U à la main'}
      </button>
      {showAdvanced && (
        <div className="space-y-2">
          <textarea
            value={m3uText}
            onChange={(e) => setM3uText(e.target.value)}
            rows={6}
            spellCheck={false}
            placeholder={'#EXTM3U\n#EXTINF:-1,Chaîne 1\nhttps://ton-gateway/live/...'}
            className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 font-mono text-xs outline-none focus:ring-1 focus:ring-accent"
          />
          <button
            onClick={saveAdvanced}
            disabled={busy}
            className="rounded-md border border-white/10 px-3 py-1.5 text-xs text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright disabled:opacity-50"
          >
            Enregistrer ce M3U
          </button>
        </div>
      )}

      {err && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
      {msg && <div className="rounded-md px-3 py-2 text-xs" style={{ background: 'rgba(47,169,106,0.15)', color: '#3FBE7C' }}>{msg}</div>}
    </div>
  );
}

export function MastersPage({ onLogout }: { onLogout: () => void }) {
  const [rows, setRows] = useState<MasterRow[]>([]);
  const [mac, setMac] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [openList, setOpenList] = useState<string | null>(null);

  async function load() {
    try {
      const r = await mastersApi.list();
      setRows(r.items || []);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Chargement impossible.');
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function add(e: FormEvent) {
    e.preventDefault();
    setErr(null); setOk(null);
    const m = mac.trim().toUpperCase();
    if (!MAC_RX.test(m)) { setErr('MAC invalide (format MK:XX:XX:XX:XX:XX).'); return; }
    setBusy(true);
    try {
      await mastersApi.add(m, note.trim() || undefined);
      setOk(`✅ ${m} est désormais un compte maître (démo illimitée).`);
      setMac(''); setNote('');
      await load();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Ajout impossible.');
    } finally { setBusy(false); }
  }

  async function remove(m: string) {
    setErr(null); setOk(null);
    try {
      await mastersApi.remove(m);
      await load();
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Suppression impossible.');
    }
  }

  const inputCls =
    'w-full rounded-md border border-white/5 bg-slate px-3 py-2 text-sm font-mono outline-none focus:ring-1 focus:ring-accent';

  return (
    <AppLayout
      title="Comptes maîtres"
      subtitle="Des MAC qui peuvent envoyer des tests gratuits illimités depuis l'app — pour attirer des clients."
      onLogout={onLogout}
    >
      <div className="max-w-2xl space-y-5">
        <div className="rounded-lg border border-accent/20 bg-accent/5 px-4 py-3 text-[13px] text-ink-secondary">
          Une MAC « maître » débloque, dans son app, l'<strong>envoi de tests
          illimité</strong> : elle offre un pass (1 h, 5 h…) à n'importe qui,
          sur la chaîne de son choix, <strong>sans quota</strong> et sans être
          abonnée. Les tests passent par le gateway → <strong>invisibles au
          fournisseur</strong>. À réserver à toi (et gens de confiance).
        </div>

        <form onSubmit={add} className="space-y-4 rounded-xl border border-white/5 bg-midnight p-6">
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              MAC à promouvoir maître
            </label>
            <input
              value={mac}
              onChange={(e) => setMac(formatMacInput(e.target.value))}
              maxLength={17}
              placeholder="MK:XX:XX:XX:XX:XX"
              className={inputCls}
              autoFocus
            />
          </div>
          <div>
            <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
              Note (optionnel)
            </label>
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={80}
              placeholder="Ex : mon téléphone, commercial Zone Nord…"
              className={inputCls.replace('font-mono', '')}
            />
          </div>

          {err && (
            <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>
          )}
          {ok && (
            <div className="rounded-md px-3 py-2 text-xs" style={{ background: 'rgba(47,169,106,0.15)', color: '#3FBE7C' }}>{ok}</div>
          )}

          <button
            type="submit"
            disabled={busy}
            className="rounded-md bg-accent px-4 py-2.5 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Ajout…' : 'Ajouter un maître'}
          </button>
        </form>

        {/* ===== Liste ===== */}
        <div className="overflow-hidden rounded-xl border border-white/5 bg-midnight">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-white/5 text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
                <th className="px-4 py-3 font-medium">MAC</th>
                <th className="px-4 py-3 font-medium">Note</th>
                <th className="px-4 py-3 font-medium text-right">Action</th>
              </tr>
            </thead>
            <tbody>
              {rows.length === 0 && (
                <tr>
                  <td colSpan={3} className="px-4 py-8 text-center text-ink-tertiary">
                    Aucun compte maître pour l'instant.
                  </td>
                </tr>
              )}
              {rows.map((r) => (
                <Fragment key={r.mac}>
                  <tr className="border-b border-white/[0.03] last:border-0">
                    <td className="px-4 py-3"><MacLink mac={r.mac} /></td>
                    <td className="px-4 py-3 text-ink-secondary">{r.note || '—'}</td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => setOpenList(openList === r.mac ? null : r.mac)}
                          className={`rounded-md border px-3 py-1 text-xs transition ${
                            openList === r.mac
                              ? 'border-accent/40 text-accent-bright'
                              : 'border-white/10 text-ink-secondary hover:border-accent/40 hover:text-accent-bright'
                          }`}
                        >
                          Liste de test
                        </button>
                        <button
                          onClick={() => remove(r.mac)}
                          className="rounded-md border border-white/10 px-3 py-1 text-xs text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright"
                        >
                          Retirer
                        </button>
                      </div>
                    </td>
                  </tr>
                  {openList === r.mac && (
                    <tr>
                      <td colSpan={3} className="p-0">
                        <TestListEditor mac={r.mac} onLogout={onLogout} />
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </AppLayout>
  );
}
