import { Fragment, FormEvent, useEffect, useMemo, useState } from 'react';
import { AppLayout } from '@/components/AppLayout';
import { MacLink } from '@/components/MacLink';
import {
  mastersApi, ApiError, MASTER_TEST_DURATIONS,
  type MasterRow, type MasterCategory, type MasterChannel, type MasterDiag,
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

// Pagination d'AFFICHAGE d'une catégorie du copieur : tranche initiale puis
// pas d'élargissement (« Afficher plus »). Le serveur, lui, renvoie TOUT.
const CAT_PAGE = 200;
const CAT_PAGE_STEP = 500;

// Une chaîne CURÉE dans la liste de test. L'ORDRE du tableau EST l'ordre de
// lecture (respecté dans le M3U servi). Le maître range/renomme/regroupe à sa
// main — « c'est lui qui gère ».
//   • `group` = nom du DOSSIER déroulant (group-title M3U). L'app regroupe les
//     chaînes par ce champ et affiche un dossier qu'on déroule.
//   • `id` = identifiant LOCAL unique (jamais écrit dans le M3U) : deux
//     « sous-chaînes même flux » partagent la MÊME url mais restent deux lignes
//     distinctes — sans id local, React et les cases à cocher les confondraient.
type CuratedItem = { id: string; url: string; name: string; logo: string; group: string };

// Génère un id local court et unique (rendu + suivi des variantes). Pas de
// crypto : sert uniquement de clé d'UI, jamais persisté.
let _uidSeq = 0;
function uid(): string { _uidSeq += 1; return 'c' + Date.now().toString(36) + '_' + _uidSeq; }

// Construit le M3U de test À PARTIR DE LA LISTE ORDONNÉE (ordre = lecture).
// `id` n'est PAS écrit : les variantes « même flux » sortent comme plusieurs
// lignes de même URL + même group-title → l'app les montre dans un dossier, le
// gateway les sert depuis UNE seule connexion (1 flux garanti).
function buildM3u(list: CuratedItem[]): string {
  const lines = ['#EXTM3U'];
  for (const c of list) {
    lines.push(
      `#EXTINF:-1 tvg-logo="${m3uAttr(c.logo)}" group-title="${m3uAttr(c.group)}",${m3uAttr(c.name)}`,
    );
    lines.push(c.url);
  }
  return lines.join('\n') + '\n';
}

// Parse un M3U en liste ORDONNÉE (préserve l'ordre, la catégorie et le nom).
// Sert à recharger la liste enregistrée pour l'éditer/réordonner à la main.
// Chaque ligne reçoit un id local frais (les URLs peuvent se répéter → variantes).
function parseM3uToList(m3u: string): CuratedItem[] {
  const out: CuratedItem[] = [];
  const lines = (m3u || '').split(/\r?\n/);
  let pending: { name: string; logo: string; group: string } | null = null;
  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      const group = (line.match(/group-title="([^"]*)"/i) || [])[1] || '';
      const logo = (line.match(/tvg-logo="([^"]*)"/i) || [])[1] || '';
      const name = (line.split(',').slice(1).join(',') || '').trim() || 'Chaîne';
      pending = { name, logo, group };
    } else if (line && !line.startsWith('#')) {
      out.push({
        id: uid(),
        url: line,
        name: pending?.name || 'Chaîne',
        logo: pending?.logo || '',
        group: pending?.group || '',
      });
      pending = null;
    }
  }
  return out;
}

function TestListEditor({ mac, onLogout }: { mac: string; onLogout: () => void }) {
  // Liste curée ORDONNÉE : l'ordre du tableau EST l'ordre de lecture. Le maître
  // coche depuis le copieur, puis range/renomme/regroupe/ajoute à sa main.
  const [list, setList] = useState<CuratedItem[]>([]);
  // Index en cours de glisser-déposer (réordonnancement à la souris).
  const [dragIdx, setDragIdx] = useState<number | null>(null);
  const [savedCount, setSavedCount] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // Note HONNÊTE renvoyée à l'enregistrement quand la façade est http/IP :
  // acceptée (les apps la joignent) mais non vérifiable par le relais.
  const [facadeNote, setFacadeNote] = useState<string | null>(null);

  // Copieur (catégories chargées depuis la ligne du maître).
  const [cats, setCats] = useState<MasterCategory[] | null>(null);
  const [copying, setCopying] = useState(false);
  const [copyErr, setCopyErr] = useState<string | null>(null);
  const [truncated, setTruncated] = useState(false);
  const [openCat, setOpenCat] = useState<string | null>(null);
  // RENDU PAR PAGES d'une catégorie ouverte : une très grosse ligne (des
  // milliers de chaînes) se PARCOURT sans geler le navigateur — on affiche
  // CAT_PAGE chaînes, puis « Afficher plus » recharge par tranches.
  const [shownByCat, setShownByCat] = useState<Record<string, number>>({});
  const [filter, setFilter] = useState('');
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [m3uText, setM3uText] = useState('');
  // Lien collé par le maître (Xtream get.php ou URL M3U) à copier directement.
  const [paste, setPaste] = useState('');
  // Façade (gateway) : URLs reconstruites dessus → plus stable + privé.
  const [gateway, setGateway] = useState('');
  // Identité de DIFFUSION (= BROADCAST_USER/PASS du gateway) : embarquée dans
  // les URLs de test → masque la ligne fournisseur. Le mot de passe n'est
  // JAMAIS réaffiché ; `hasGwPass` dit seulement qu'il est enregistré.
  const [gwUser, setGwUser] = useState('');
  const [gwPass, setGwPass] = useState('');
  const [hasGwPass, setHasGwPass] = useState(false);
  // Champs d'AJOUT MANUEL d'une chaîne dans la liste curée (nom + URL + cat).
  const [addName, setAddName] = useState('');
  const [addUrl, setAddUrl] = useState('');
  const [addGroup, setAddGroup] = useState('');

  // Charge la liste déjà enregistrée → pré-coche les URLs connues.
  useEffect(() => {
    (async () => {
      try {
        const r = await mastersApi.getTestList(mac);
        setSavedCount(r.count || 0);
        setM3uText(r.m3u || '');
        setGateway(r.gateway_base || '');
        setGwUser(r.gateway_user || '');
        setHasGwPass(!!r.has_gateway_pass);
        setGwPass(''); // le secret n'est jamais réaffiché
        // Recharge la liste ORDONNÉE (ordre = lecture) pour l'éditer à la main.
        setList(parseM3uToList(r.m3u || ''));
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
      // La façade (gateway) reconstruit les URLs dessus → stable + privé, et
      // l'identité de diffusion masque la ligne fournisseur dans les URLs.
      const r = await mastersApi.channels(mac, paste, gateway, gwUser, gwPass);
      setCats(r.categories || []);
      setTruncated(!!r.truncated);
      setShownByCat({}); // nouvelle copie → pagination d'affichage remise à zéro
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setCopyErr(e instanceof ApiError ? e.message : 'Copie impossible.');
    } finally { setCopying(false); }
  }

  // Coche/décoche depuis le copieur : on AJOUTE en fin de liste (l'ordre se
  // gère ensuite à la main) ou on RETIRE. Clé d'unicité = URL.
  function toggle(ch: MasterChannel, group: string) {
    setList((prev) => {
      if (prev.some((i) => i.url === ch.url)) return prev.filter((i) => i.url !== ch.url);
      return [...prev, { id: uid(), url: ch.url, name: ch.name, logo: ch.logo, group }];
    });
  }

  function clearSel() { setList([]); }

  // ---- Rangement à la main (ordre respecté à la lecture) -----------------
  // Déplace un élément d'un cran (▲/▼) — stable, sans dépendance.
  function moveItem(idx: number, dir: -1 | 1) {
    setList((prev) => {
      const j = idx + dir;
      if (j < 0 || j >= prev.length) return prev;
      const next = prev.slice();
      [next[idx], next[j]] = [next[j], next[idx]];
      return next;
    });
  }
  // Réordonnancement par glisser-déposer : insère la ligne tirée à la place cible.
  function dropOn(target: number) {
    setList((prev) => {
      if (dragIdx === null || dragIdx === target) return prev;
      const next = prev.slice();
      const [moved] = next.splice(dragIdx, 1);
      next.splice(target, 0, moved);
      return next;
    });
    setDragIdx(null);
  }
  function editField(idx: number, field: 'name' | 'group', value: string) {
    setList((prev) => prev.map((it, i) => (i === idx ? { ...it, [field]: value } : it)));
  }
  function removeItem(idx: number) {
    setList((prev) => prev.filter((_, i) => i !== idx));
  }
  // Ajout MANUEL d'une chaîne (nom + URL + catégorie) directement dans la liste.
  function addManual(item: Omit<CuratedItem, 'id'>) {
    setList((prev) => (prev.some((i) => i.url === item.url) ? prev : [...prev, { id: uid(), ...item }]));
  }

  // ---- DOSSIERS (déroulants) + SOUS-CHAÎNES « MÊME FLUX » ------------------
  // Ajoute une SOUS-CHAÎNE « même flux » juste après [idx] : elle partage la
  // MÊME url que la chaîne source (→ 1 seul flux fournisseur, garanti par la
  // mutualisation du gateway) et le MÊME dossier. Si la source n'a pas encore
  // de dossier, on en crée un à son nom → les deux entrent dans « ce » dossier.
  function addSameFluxVariant(idx: number) {
    setList((prev) => {
      const src = prev[idx];
      if (!src) return prev;
      const folder = src.group || src.name || 'Dossier';
      const next = prev.slice();
      // La source rejoint le dossier (si elle était « hors dossier »).
      if (!src.group) next[idx] = { ...src, group: folder };
      next.splice(idx + 1, 0, {
        id: uid(), url: src.url, logo: src.logo, group: folder,
        name: src.name + ' •', // nom modifiable ensuite
      });
      return next;
    });
  }
  // Range TOUT un dossier sur UN SEUL flux : toutes ses chaînes prennent l'url
  // de la 1re → le fournisseur ne voit plus qu'une connexion pour ce dossier.
  // (Les sous-chaînes montrent alors le même direct — c'est le prix du « 1 flux
  // garanti ».) Réversible en ré-éditant les URLs à la main (mode avancé).
  function mergeFolderToOneFlux(folder: string) {
    setList((prev) => {
      const first = prev.find((i) => i.group === folder);
      if (!first) return prev;
      return prev.map((i) => (i.group === folder ? { ...i, url: first.url } : i));
    });
  }
  // « Ranger par catégorie » : tri STABLE — les catégories gardent leur ordre
  // de première apparition, et les chaînes gardent leur ordre relatif dans
  // chaque catégorie. Un clic range tout, puis on affine à la main.
  function sortByGroup() {
    setList((prev) => {
      const order = new Map<string, number>();
      for (const it of prev) {
        const g = it.group || '';
        if (!order.has(g)) order.set(g, order.size);
      }
      return prev
        .map((it, i) => ({ it, i }))
        .sort((a, b) =>
          (order.get(a.it.group || '')! - order.get(b.it.group || '')!) || (a.i - b.i))
        .map((x) => x.it);
    });
  }

  async function save() {
    setErr(null); setMsg(null); setBusy(true);
    try {
      const m3u = list.length ? buildM3u(list) : '';
      const r = await mastersApi.putTestList(mac, m3u, gateway, gwUser, gwPass);
      setSavedCount(r.count || 0);
      setM3uText(m3u);
      setHasGwPass(!!r.has_gateway_pass);
      setFacadeNote(r.facade_note || null);
      if (gwPass) setGwPass(''); // secret enregistré → on vide le champ
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
      const r = await mastersApi.putTestList(mac, m3uText, gateway, gwUser, gwPass);
      setSavedCount(r.count || 0);
      setList(parseM3uToList(m3uText)); // synchronise la vue « rangement »
      setHasGwPass(!!r.has_gateway_pass);
      setFacadeNote(r.facade_note || null);
      if (gwPass) setGwPass('');
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

  // RECHERCHE À PLAT : dès qu'on tape, on liste directement les CHAÎNES qui
  // correspondent (nom de chaîne OU de catégorie), avec leur catégorie en
  // libellé — plus besoin d'ouvrir une catégorie à la main. Plafonné pour
  // rester fluide même sur une très grosse ligne.
  const flatMatches = useMemo(() => {
    if (!cats) return [] as { ch: MasterChannel; group: string }[];
    const q = filter.trim().toLowerCase();
    if (!q) return [] as { ch: MasterChannel; group: string }[];
    const out: { ch: MasterChannel; group: string }[] = [];
    for (const c of cats) {
      const catHit = c.name.toLowerCase().includes(q);
      for (const ch of c.channels) {
        if (catHit || ch.name.toLowerCase().includes(q)) {
          out.push({ ch, group: c.name });
          if (out.length >= 500) return out;
        }
      }
    }
    return out;
  }, [cats, filter]);

  const searching = filter.trim().length > 0;
  const inList = (url: string) => list.some((i) => i.url === url);
  const selCount = list.length;
  const tooMany = selCount > 5;
  // Catégories déjà présentes dans la liste → proposées en autocomplétion
  // quand on regroupe/ajoute à la main (regrouper « comme je veux »).
  const knownGroups = useMemo(
    () => Array.from(new Set(list.map((i) => i.group).filter(Boolean))),
    [list],
  );

  // ---- COMPTE HONNÊTE DES FLUX PAR DOSSIER (fidèle à la réalité réseau) ----
  // Un dossier (group) coûte au fournisseur : 1 flux par URL DISTINCTE qu'il
  // contient (mutualisation du gateway = 1 connexion par chaîne, quel que soit
  // le nombre de testeurs). Si toutes ses chaînes partagent 1 seule URL →
  // « 1 flux garanti » (variantes même flux). Sinon « jusqu'à N flux ».
  // Recherche vérifiée : des chaînes DIFFÉRENTES regardées en même temps = des
  // connexions distinctes (impossible de les fondre en 1 sans mosaïque).
  const folders = useMemo(() => {
    const map = new Map<string, { count: number; urls: Set<string> }>();
    for (const it of list) {
      const g = it.group || '';
      if (!g) continue; // « hors dossier » = chaîne simple, pas un dossier
      if (!map.has(g)) map.set(g, { count: 0, urls: new Set() });
      const f = map.get(g)!;
      f.count += 1;
      f.urls.add(it.url);
    }
    return [...map.entries()].map(([name, f]) => ({
      name, count: f.count, flux: f.urls.size, oneFlux: f.urls.size === 1,
    }));
  }, [list]);
  // URLs présentes plusieurs fois dans la liste = variantes « même flux » →
  // badge « 1 flux » sur ces lignes (le fournisseur ne les compte qu'une fois).
  const urlCounts = useMemo(() => {
    const m = new Map<string, number>();
    for (const it of list) m.set(it.url, (m.get(it.url) || 0) + 1);
    return m;
  }, [list]);

  return (
    <div className="space-y-3 border-t border-white/5 bg-slate/40 px-4 py-4">
      <div className="text-[13px] text-ink-secondary">
        <strong>Copieur intelligent.</strong> Clique « Copier mes chaînes » : je
        lis ta ligne, je range tout en <strong>catégories</strong>, et tu coches
        les quelques chaînes à partager en test (idéalement{' '}
        <strong>moins de 5</strong>). Dans <strong>« Ma liste de test »</strong>,
        tu <strong>ranges tout comme tu veux</strong> : glisser pour réordonner,
        renommer, regrouper, retirer, ou ajouter une chaîne à la main — l'ordre
        est <strong>respecté à la lecture</strong>. Tous les tests servent cette
        liste : les testeurs partagent les mêmes chaînes, le gateway les
        mutualise et <strong>le fournisseur ne voit qu'une connexion</strong>.
        Aucune liste = accès à tout le bouquet.
      </div>

      {/* Dossiers + flux : explication HONNÊTE (recherche vérifiée). */}
      <div className="rounded-md border border-white/5 bg-midnight/60 px-3 py-2 text-[12px] text-ink-tertiary">
        <strong className="text-ink-secondary">Dossiers &amp; flux.</strong> Mets
        un même nom de <strong>dossier</strong> à plusieurs chaînes → l'app les
        affiche dans un dossier déroulant. Un dossier coûte au fournisseur{' '}
        <strong>1 flux par chaîne différente réellement regardée</strong> (le
        gateway mutualise : 1000 testeurs sur la même chaîne = 1 flux). Pour
        garantir <strong>1 seul flux</strong> quoi qu'il arrive, utilise{' '}
        <strong>＋flux</strong> : la sous-chaîne partage le même lien (même
        direct sous plusieurs noms). Des chaînes <em>différentes</em> regardées
        en même temps restent des flux distincts — c'est incontournable.
      </div>

      {/* ===== Façade (gateway) : stabilité + confidentialité ===== */}
      <div>
        <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
          Ta façade (gateway) — recommandé : plus stable + privé
        </label>
        <input
          value={gateway}
          onChange={(e) => setGateway(e.target.value)}
          spellCheck={false}
          placeholder="https://tv.mondomaine.com"
          className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 font-mono text-xs outline-none focus:ring-1 focus:ring-accent"
        />
        <p className="mt-1 text-[11px] text-ink-tertiary">
          Réglée une fois : je reconstruis toutes les chaînes copiées sur ton
          gateway → reconnexion auto, ligne de secours, tampon anti-coupure
          (plus stable que l'original, y compris au cast) et le fournisseur ne
          voit qu'une IP. Une façade <strong>http:// ou par IP marche aussi</strong>{' '}
          (tes apps la joignent directement) — mais le diagnostic ne pourra pas
          la vérifier d'ici (contrôles en ambre). Recommandé :{' '}
          <strong>https:// + vrai domaine</strong> pour un diagnostic complet.
          Vide = lecture directe (fonctionne, moins privé).
        </p>
      </div>

      {/* ===== Identité de diffusion : masque la ligne fournisseur ===== */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Utilisateur gateway (identité de diffusion)
          </label>
          <input
            value={gwUser}
            onChange={(e) => setGwUser(e.target.value)}
            spellCheck={false}
            placeholder="diffusion"
            className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 font-mono text-xs outline-none focus:ring-1 focus:ring-accent"
          />
        </div>
        <div>
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Mot de passe gateway
            {hasGwPass && <span className="ml-1 text-success">· enregistré</span>}
          </label>
          <input
            value={gwPass}
            onChange={(e) => setGwPass(e.target.value)}
            spellCheck={false}
            type="password"
            autoComplete="new-password"
            placeholder={hasGwPass ? '•••••••• (laisse vide pour conserver)' : 'secret partagé du gateway'}
            className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 font-mono text-xs outline-none focus:ring-1 focus:ring-accent"
          />
        </div>
        <p className="text-[11px] text-ink-tertiary sm:col-span-2">
          Mêmes valeurs que <strong>BROADCAST_USER</strong> /{' '}
          <strong>BROADCAST_PASS</strong> de ton gateway. Je les embarque dans
          les URLs de test à la place de tes identifiants fournisseur → ta ligne
          réelle <strong>n'apparaît jamais</strong> dans la liste servie. Le mot
          de passe n'est jamais réaffiché.
        </p>
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
          Ligne exceptionnellement grosse : le serveur s'est arrêté à 20 000
          chaînes (filet anti-abus). Tout ce qui est copié est bien là — utilise
          la recherche pour trouver le reste si besoin.
        </div>
      )}

      {/* ===== MA LISTE (rangement à la main) — l'ordre EST celui de lecture ===== */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-[10px] uppercase tracking-widest text-ink-tertiary">
            Ma liste de test — glisse pour ranger (l'ordre est respecté à la lecture)
          </span>
          <div className="flex items-center gap-2">
            {list.length > 1 && (
              <button
                onClick={sortByGroup}
                className="rounded border border-white/10 px-2 py-0.5 text-[10px] text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright"
                title="Regroupe les chaînes par catégorie (ordre relatif conservé)"
              >
                Ranger par catégorie
              </button>
            )}
            <span className="text-[10px] text-ink-tertiary">{list.length} chaîne(s)</span>
          </div>
        </div>

        {/* Récap DOSSIERS : compte de flux HONNÊTE par dossier (recherche
            vérifiée : 1 flux par URL distincte, mutualisé). « Tout sur 1 flux »
            fond le dossier sur un seul lien (variantes = même direct). */}
        {folders.length > 0 && (
          <div className="flex flex-wrap gap-1.5 rounded-md border border-white/5 bg-midnight/60 p-2">
            {folders.map((f) => (
              <div
                key={f.name}
                className="flex items-center gap-1.5 rounded border border-white/10 bg-midnight px-2 py-1 text-[11px]"
              >
                <span className="text-ink-secondary">📁 {f.name}</span>
                <span className="text-ink-tertiary">{f.count} ch.</span>
                {f.oneFlux ? (
                  <span className="rounded bg-success/15 px-1.5 py-0.5 font-semibold" style={{ color: '#3FBE7C' }}>
                    1 flux garanti
                  </span>
                ) : (
                  <>
                    <span className="rounded bg-warning/15 px-1.5 py-0.5 font-semibold text-warning">
                      jusqu'à {f.flux} flux
                    </span>
                    <button
                      onClick={() => mergeFolderToOneFlux(f.name)}
                      className="rounded border border-white/10 px-1.5 py-0.5 text-ink-tertiary transition hover:border-accent/40 hover:text-accent-bright"
                      title="Toutes les chaînes du dossier prennent le MÊME lien (le même direct) → 1 flux garanti"
                    >
                      Tout sur 1 flux
                    </button>
                  </>
                )}
              </div>
            ))}
          </div>
        )}

        {list.length === 0 ? (
          <div className="rounded-md border border-dashed border-white/10 bg-midnight px-3 py-4 text-center text-xs text-ink-tertiary">
            Vide. Coche des chaînes ci-dessous, ou ajoute-en une à la main.
          </div>
        ) : (
          <div className="space-y-1 rounded-md border border-white/5 bg-midnight p-2">
            {list.map((it, idx) => (
              <div
                key={it.id}
                draggable
                onDragStart={() => setDragIdx(idx)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => dropOn(idx)}
                onDragEnd={() => setDragIdx(null)}
                className={`flex items-center gap-1.5 rounded px-1.5 py-1 ${dragIdx === idx ? 'opacity-50' : ''} hover:bg-white/[0.02]`}
              >
                {/* Poignée + rang (numéro d'ordre de lecture). */}
                <span className="cursor-grab select-none px-1 text-ink-tertiary" title="Glisser pour ranger">⠿</span>
                <span className="w-5 shrink-0 text-center text-[10px] text-ink-tertiary">{idx + 1}</span>
                {/* Réordonnancement stable au clavier/souris (▲/▼). */}
                <div className="flex shrink-0 flex-col">
                  <button
                    onClick={() => moveItem(idx, -1)}
                    disabled={idx === 0}
                    className="px-1 text-[9px] leading-none text-ink-tertiary hover:text-accent-bright disabled:opacity-20"
                    title="Monter"
                  >▲</button>
                  <button
                    onClick={() => moveItem(idx, 1)}
                    disabled={idx === list.length - 1}
                    className="px-1 text-[9px] leading-none text-ink-tertiary hover:text-accent-bright disabled:opacity-20"
                    title="Descendre"
                  >▼</button>
                </div>
                {/* Renommer (nom affiché). */}
                <input
                  value={it.name}
                  onChange={(e) => editField(idx, 'name', e.target.value)}
                  spellCheck={false}
                  className="min-w-0 flex-1 rounded border border-transparent bg-transparent px-1.5 py-1 text-[13px] text-ink-primary outline-none focus:border-white/10 focus:bg-white/[0.02]"
                  placeholder="Nom de la chaîne"
                />
                {/* Badge « 1 flux » quand cette URL est partagée par plusieurs
                    lignes (variantes même flux → 1 seule connexion fournisseur). */}
                {urlCounts.get(it.url)! > 1 && (
                  <span
                    className="shrink-0 rounded bg-success/15 px-1.5 py-0.5 text-[9px] font-semibold"
                    style={{ color: '#3FBE7C' }}
                    title="Même lien qu'une autre ligne → le fournisseur ne compte qu'un seul flux"
                  >1 flux</span>
                )}
                {/* Regrouper (dossier / group-title), autocomplétion des groupes connus. */}
                <input
                  value={it.group}
                  onChange={(e) => editField(idx, 'group', e.target.value)}
                  list="master-known-groups"
                  spellCheck={false}
                  className="w-28 shrink-0 rounded border border-transparent bg-transparent px-1.5 py-1 text-[11px] text-ink-secondary outline-none focus:border-white/10 focus:bg-white/[0.02]"
                  placeholder="Dossier"
                />
                {/* Ajouter une SOUS-CHAÎNE « même flux » (même lien) dans le
                    dossier → 1 flux garanti, plusieurs noms affichés. */}
                <button
                  onClick={() => addSameFluxVariant(idx)}
                  className="shrink-0 rounded px-1.5 text-[11px] text-ink-tertiary transition hover:text-accent-bright"
                  title="Ajouter une sous-chaîne qui partage CE flux (même lien) dans le dossier — 1 flux garanti"
                >＋flux</button>
                {/* Supprimer. */}
                <button
                  onClick={() => removeItem(idx)}
                  className="shrink-0 px-1.5 text-ink-tertiary hover:text-accent-bright"
                  title="Retirer de la liste"
                >✕</button>
              </div>
            ))}
          </div>
        )}
        <datalist id="master-known-groups">
          {knownGroups.map((g) => <option key={g} value={g} />)}
        </datalist>

        {/* Ajout MANUEL d'une chaîne (nom + URL + catégorie). */}
        <div className="flex flex-wrap items-end gap-2 rounded-md border border-white/5 bg-midnight/60 p-2">
          <div className="min-w-[120px] flex-1">
            <label className="mb-1 block text-[9px] uppercase tracking-widest text-ink-tertiary">Nom</label>
            <input
              value={addName}
              onChange={(e) => setAddName(e.target.value)}
              spellCheck={false}
              placeholder="Ma chaîne"
              className="w-full rounded border border-white/5 bg-midnight px-2 py-1.5 text-xs outline-none focus:ring-1 focus:ring-accent"
            />
          </div>
          <div className="min-w-[180px] flex-[2]">
            <label className="mb-1 block text-[9px] uppercase tracking-widest text-ink-tertiary">URL</label>
            <input
              value={addUrl}
              onChange={(e) => setAddUrl(e.target.value)}
              spellCheck={false}
              placeholder="https://ton-gateway/live/…"
              className="w-full rounded border border-white/5 bg-midnight px-2 py-1.5 font-mono text-[11px] outline-none focus:ring-1 focus:ring-accent"
            />
          </div>
          <div className="min-w-[100px] flex-1">
            <label className="mb-1 block text-[9px] uppercase tracking-widest text-ink-tertiary">Catégorie</label>
            <input
              value={addGroup}
              onChange={(e) => setAddGroup(e.target.value)}
              list="master-known-groups"
              spellCheck={false}
              placeholder="(optionnel)"
              className="w-full rounded border border-white/5 bg-midnight px-2 py-1.5 text-xs outline-none focus:ring-1 focus:ring-accent"
            />
          </div>
          <button
            onClick={() => {
              const url = addUrl.trim();
              if (!/^https?:\/\//i.test(url)) return; // URL requise (http/https)
              addManual({ url, name: addName.trim() || 'Chaîne', logo: '', group: addGroup.trim() });
              setAddName(''); setAddUrl(''); setAddGroup('');
            }}
            disabled={!/^https?:\/\//i.test(addUrl.trim())}
            className="rounded-md border border-accent/40 px-3 py-1.5 text-xs font-medium text-accent-bright transition hover:bg-accent/10 disabled:opacity-40"
          >
            Ajouter
          </button>
        </div>
      </div>

      {/* ===== Arbre catégories → chaînes ===== */}
      {cats && (
        <div className="space-y-2">
          <input
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filtrer une chaîne ou une catégorie…"
            className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
          />
          {/* Recherche active → LISTE PLATE de chaînes (coche directe). */}
          {searching && (
            <div className="max-h-96 space-y-0.5 overflow-y-auto rounded-md border border-white/5 bg-midnight p-2">
              {flatMatches.length === 0 && (
                <div className="px-2 py-4 text-center text-xs text-ink-tertiary">
                  Aucune chaîne ne correspond à « {filter} ».
                </div>
              )}
              {flatMatches.map(({ ch, group }) => {
                const on = inList(ch.url);
                return (
                  <label
                    key={ch.url}
                    className="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-[13px] hover:bg-white/[0.02]"
                  >
                    <input type="checkbox" checked={on} onChange={() => toggle(ch, group)} className="accent-accent" />
                    <span className={on ? 'text-ink-primary' : 'text-ink-secondary'}>{ch.name}</span>
                    <span className="ml-auto shrink-0 text-[10px] text-ink-tertiary">{group}</span>
                  </label>
                );
              })}
              {flatMatches.length >= 500 && (
                <div className="px-2 py-1 text-center text-[10px] text-ink-tertiary">
                  500 premiers résultats — affine ta recherche.
                </div>
              )}
            </div>
          )}

          {/* Pas de recherche → ARBRE catégories → chaînes. */}
          {!searching && (
          <div className="max-h-96 space-y-1 overflow-y-auto rounded-md border border-white/5 bg-midnight p-2">
            {shownCats.length === 0 && (
              <div className="px-2 py-4 text-center text-xs text-ink-tertiary">Aucune chaîne.</div>
            )}
            {shownCats.map((c) => {
              const nSel = c.channels.filter((ch) => inList(ch.url)).length;
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
                      {/* Tranche affichée (CAT_PAGE par défaut) : le DOM reste
                          léger même pour une catégorie de plusieurs milliers
                          de chaînes — « Afficher plus » élargit la tranche. */}
                      {c.channels.slice(0, shownByCat[c.id] ?? CAT_PAGE).map((ch) => {
                        const on = inList(ch.url);
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
                      {c.channels.length > (shownByCat[c.id] ?? CAT_PAGE) && (
                        <button
                          onClick={() => setShownByCat((prev) => ({
                            ...prev,
                            [c.id]: (prev[c.id] ?? CAT_PAGE) + CAT_PAGE_STEP,
                          }))}
                          className="mt-1 w-full rounded border border-white/10 px-2 py-1.5 text-[11px] text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright"
                        >
                          Afficher plus ({c.channels.length - (shownByCat[c.id] ?? CAT_PAGE)} restantes)
                        </button>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
          )}
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
      {/* Façade http/IP acceptée : nuance honnête (les apps la joignent, le
          relais ne peut pas la vérifier) — informatif, non bloquant. */}
      {facadeNote && (
        <div className="rounded-md border border-warning/30 bg-warning/10 px-3 py-2 text-xs text-warning">
          {facadeNote}
        </div>
      )}
    </div>
  );
}

// =========================================================
//  DONNER UN TEST — depuis le panel (sans passer par l'app maître)
// =========================================================
//  Deux gestes : ATTRIBUER directement à une MAC (le testeur n'a rien à
//  taper — licence + liste servie poussées en temps réel), ou GÉNÉRER un
//  code 6 chiffres à transmettre (valable 48 h, le testeur le tape dans
//  l'app). Durée au choix de 1 h à 1 an. La liste servie est la liste de
//  test curée du maître (référence opaque), sinon tout le bouquet (repli).
function GiveTestPanel({ mac, onLogout }: { mac: string; onLogout: () => void }) {
  const [guestMac, setGuestMac] = useState('');
  const [hours, setHours] = useState(1);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // Résultat du dernier geste : code généré ou attribution confirmée.
  const [result, setResult] = useState<string | null>(null);
  const [bigCode, setBigCode] = useState<string | null>(null);

  async function grant() {
    setErr(null); setResult(null); setBigCode(null);
    const g = guestMac.trim().toUpperCase();
    if (!MAC_RX.test(g)) { setErr('MAC invité invalide (format MK:XX:XX:XX:XX:XX).'); return; }
    setBusy(true);
    try {
      const r = await mastersApi.testGrant(mac, g, hours);
      const label = MASTER_TEST_DURATIONS.find((d) => d.hours === r.hours)?.label || `${r.hours} h`;
      setResult(`✅ Test ${label} attribué à ${r.guest_mac} — échéance ${new Date(r.guest_until).toLocaleString()}. L'appareil reçoit l'accès et la liste immédiatement.`);
      setGuestMac('');
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Attribution impossible.');
    } finally { setBusy(false); }
  }

  async function genCode() {
    setErr(null); setResult(null); setBigCode(null);
    setBusy(true);
    try {
      const r = await mastersApi.testCode(mac, hours);
      const label = MASTER_TEST_DURATIONS.find((d) => d.hours === r.hours)?.label || `${r.hours} h`;
      setBigCode(r.code);
      setResult(`Code ${label} — à taper dans l'app avant le ${new Date(r.expires_at).toLocaleString()}.`);
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Génération impossible.');
    } finally { setBusy(false); }
  }

  return (
    <div className="space-y-3 border-t border-white/5 bg-slate/40 px-4 py-4">
      <div className="text-[13px] text-ink-secondary">
        <strong>Donner un test — sans l'app maître.</strong> Choisis la durée,
        puis : <strong>attribue</strong> directement à la MAC du testeur (rien à
        taper chez lui), ou <strong>génère un code</strong> à lui transmettre.
        Le test sert la <strong>liste de test</strong> de ce maître (référence
        opaque — jamais ta ligne réelle) ; sans liste curée, tout le bouquet.
        Le suivi (prolonger, révoquer) est dans « Partages &amp; prêts ».
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            Durée du test
          </label>
          <select
            value={hours}
            onChange={(e) => setHours(Number(e.target.value))}
            className="rounded-md border border-white/5 bg-midnight px-3 py-2 text-sm outline-none focus:ring-1 focus:ring-accent"
          >
            {MASTER_TEST_DURATIONS.map((d) => (
              <option key={d.hours} value={d.hours}>{d.label}</option>
            ))}
          </select>
        </div>
        <div className="min-w-[220px] flex-1">
          <label className="mb-1.5 block text-[10px] uppercase tracking-widest text-ink-tertiary">
            MAC du testeur (attribution directe)
          </label>
          <input
            value={guestMac}
            onChange={(e) => setGuestMac(formatMacInput(e.target.value))}
            maxLength={17}
            placeholder="MK:XX:XX:XX:XX:XX"
            className="w-full rounded-md border border-white/5 bg-midnight px-3 py-2 font-mono text-sm outline-none focus:ring-1 focus:ring-accent"
          />
        </div>
        <button
          onClick={grant}
          disabled={busy || !guestMac.trim()}
          className="rounded-md bg-accent px-4 py-2 text-sm font-semibold text-black transition hover:bg-accent-bright disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? '…' : 'Attribuer le test'}
        </button>
        <span className="text-[11px] text-ink-tertiary">ou</span>
        <button
          onClick={genCode}
          disabled={busy}
          className="rounded-md border border-accent/40 px-4 py-2 text-sm font-medium text-accent-bright transition hover:bg-accent/10 disabled:opacity-50"
        >
          {busy ? '…' : 'Générer un code'}
        </button>
      </div>

      {err && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}
      {bigCode && (
        <div className="rounded-md border border-white/10 bg-midnight px-4 py-3 text-center">
          <div className="font-mono text-3xl font-bold tracking-[0.3em] text-accent-bright">{bigCode}</div>
        </div>
      )}
      {result && (
        <div className="rounded-md px-3 py-2 text-xs" style={{ background: 'rgba(47,169,106,0.15)', color: '#3FBE7C' }}>
          {result}
        </div>
      )}
    </div>
  );
}

// =========================================================
//  BOÎTE NOIRE — DIAGNOSTIC (par maître)
// =========================================================
//  Lance des contrôles ACTIFS côté serveur (façade en ligne ?, liste servie ?,
//  1re chaîne jouable ?) et affiche un verdict + un score + un conseil de
//  réparation par ligne. L'outil « qui détecte le problème n'importe quand ».
const LVL_COLOR = ['var(--diag-ok)', 'var(--diag-warn)', 'var(--diag-bad)'];
function DiagPanel({ mac, onLogout }: { mac: string; onLogout: () => void }) {
  const [diag, setDiag] = useState<MasterDiag | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function run() {
    setErr(null); setBusy(true);
    try {
      setDiag(await mastersApi.diag(mac));
    } catch (e: any) {
      if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
      setErr(e instanceof ApiError ? e.message : 'Diagnostic impossible.');
    } finally { setBusy(false); }
  }

  useEffect(() => { run(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [mac]);

  const vColor = diag
    ? (diag.verdict === 'green' ? 'var(--diag-ok)' : diag.verdict === 'red' ? 'var(--diag-bad)' : 'var(--diag-warn)')
    : 'var(--diag-warn)';
  const icon = (lvl: number) => (lvl === 0 ? '✓' : lvl === 2 ? '✕' : '!');

  return (
    <div
      className="space-y-3 border-t border-white/5 bg-slate/40 px-4 py-4"
      style={{ ['--diag-ok' as any]: '#3FBE7C', ['--diag-warn' as any]: '#E0A83C', ['--diag-bad' as any]: '#E5484D' }}
    >
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold">🛰️ Boîte noire — diagnostic</span>
          {diag && (
            <span
              className="rounded-full px-2 py-0.5 text-[11px] font-bold"
              style={{ color: vColor, background: `color-mix(in srgb, ${vColor} 16%, transparent)`, border: `1px solid ${vColor}` }}
            >
              {diag.score}%
            </span>
          )}
        </div>
        <button
          onClick={run}
          disabled={busy}
          className="rounded-md border border-white/10 px-3 py-1 text-xs text-ink-secondary transition hover:border-accent/40 hover:text-accent-bright disabled:opacity-50"
        >
          {busy ? 'Analyse…' : 'Relancer'}
        </button>
      </div>

      {err && <div className="rounded-md border border-accent/30 bg-accent/10 px-3 py-2 text-xs text-accent-bright">{err}</div>}

      {busy && !diag && (
        <div className="text-xs text-ink-tertiary">Contrôles actifs en cours (façade, liste, chaîne)…</div>
      )}

      {diag && (
        <ul className="space-y-2">
          {diag.checks.map((c) => (
            <li key={c.key} className="flex items-start gap-2.5">
              <span
                className="mt-0.5 grid h-5 w-5 flex-none place-items-center rounded-full text-[11px] font-black"
                style={{ color: LVL_COLOR[c.level], background: `color-mix(in srgb, ${LVL_COLOR[c.level]} 16%, transparent)` }}
              >
                {icon(c.level)}
              </span>
              <div>
                <div className="text-[13px] font-semibold text-ink-primary">{c.label}</div>
                {c.detail && <div className="text-[12px] text-ink-secondary">{c.detail}</div>}
                {c.fix && c.level !== 0 && (
                  <div className="text-[12px] font-medium" style={{ color: LVL_COLOR[c.level] }}>→ {c.fix}</div>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
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
  const [openDiag, setOpenDiag] = useState<string | null>(null);
  const [openGive, setOpenGive] = useState<string | null>(null);

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
                          onClick={() => { setOpenList(openList === r.mac ? null : r.mac); setOpenDiag(null); setOpenGive(null); }}
                          className={`rounded-md border px-3 py-1 text-xs transition ${
                            openList === r.mac
                              ? 'border-accent/40 text-accent-bright'
                              : 'border-white/10 text-ink-secondary hover:border-accent/40 hover:text-accent-bright'
                          }`}
                        >
                          Liste de test
                        </button>
                        <button
                          onClick={() => { setOpenGive(openGive === r.mac ? null : r.mac); setOpenList(null); setOpenDiag(null); }}
                          className={`rounded-md border px-3 py-1 text-xs transition ${
                            openGive === r.mac
                              ? 'border-accent/40 text-accent-bright'
                              : 'border-white/10 text-ink-secondary hover:border-accent/40 hover:text-accent-bright'
                          }`}
                        >
                          Donner un test
                        </button>
                        <button
                          onClick={() => { setOpenDiag(openDiag === r.mac ? null : r.mac); setOpenList(null); setOpenGive(null); }}
                          className={`rounded-md border px-3 py-1 text-xs transition ${
                            openDiag === r.mac
                              ? 'border-accent/40 text-accent-bright'
                              : 'border-white/10 text-ink-secondary hover:border-accent/40 hover:text-accent-bright'
                          }`}
                        >
                          Diagnostic
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
                  {openGive === r.mac && (
                    <tr>
                      <td colSpan={3} className="p-0">
                        <GiveTestPanel mac={r.mac} onLogout={onLogout} />
                      </td>
                    </tr>
                  )}
                  {openDiag === r.mac && (
                    <tr>
                      <td colSpan={3} className="p-0">
                        <DiagPanel mac={r.mac} onLogout={onLogout} />
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
