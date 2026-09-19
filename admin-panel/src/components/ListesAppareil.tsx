// =========================================================
//  ListesAppareil — ajouter et retirer les listes d'un client
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026), depuis la page « Prendre la
//  main » :
//
//    « Dans cette option, je dois avoir le secteur de supprimer /
//      ajouter la liste. »
//
//  Il a raison, et c'est une question de moment : quand on a un client
//  au téléphone et qu'on conduit son app, le geste suivant est presque
//  toujours « je lui remets sa liste ». L'envoyer changer de page pour
//  ça, c'est lui faire perdre le fil — et la MAC qu'il vient de coller.
//
//  ---------------------------------------------------------
//  POURQUOI CE BLOC EST DEVENU UN COMPOSANT
//  ---------------------------------------------------------
//  Il vivait dans `DeviceScreenPage` (Téléphone / Télévision). Le
//  recopier dans « Prendre la main » aurait fait DEUX panneaux qui
//  font la même chose — et le jour où l'un gagne un bouton, ou corrige
//  un bug de retrait, l'autre reste en arrière. Le support dépendrait
//  alors de la porte par laquelle il est entré.
//
//  Même raison que `ci/build_label.sh`, `cloudflare/stream_proxy.js`
//  et `PrendreLaMain` lui-même : une seule implémentation, autant
//  d'appelants qu'on veut.
//
//  ---------------------------------------------------------
//  IL CHARGE SES PROPRES DONNÉES
//  ---------------------------------------------------------
//  Pour qu'une page nue (« Prendre la main ») puisse le poser avec une
//  simple MAC, sans rien savoir des listes. La page qui a déjà ces
//  données (`DeviceScreenPage`, qui en tire ses onglets de chaînes)
//  passe [onChange] et se recharge quand quelque chose bouge — ce qui
//  garde les deux vues d'accord au lieu de les laisser diverger.
//
//  ---------------------------------------------------------
//  DEUX SORTES DE LISTES, DEUX GESTES DIFFÉRENTS
//  ---------------------------------------------------------
//  C'est la distinction la plus importante de ce panneau, et elle se
//  dit au client de vive voix :
//
//   • CELLES POUSSÉES DEPUIS LE PANEL vivent chez nous. Les retirer,
//     c'est FAIT, tout de suite.
//   • CELLES QUE LE CLIENT A AJOUTÉES LUI-MÊME vivent sur son
//     appareil. On ne peut qu'envoyer un ORDRE, qu'il exécutera à sa
//     prochaine synchro — même s'il est éteint au moment du clic.
//
//  « C'est parti, ça s'appliquera dès qu'il rallume » n'est pas la
//  même promesse que « c'est fait ».
// =========================================================

import { FormEvent, useCallback, useEffect, useState } from 'react';
import { toast, rtActionFeedback } from '@/components/Toast';
import {
  devicesApi, sourcesApi, ApiError,
  type DeviceSource, type DeviceLocalSource, type DeviceSourceInput,
} from '@/lib/api';

// ---------------------------------------------------------
//  Le nom qu'on affiche pour une liste.
// ---------------------------------------------------------
//  Un M3U sans étiquette donnerait une URL de 200 caractères dans un
//  onglet : on garde l'hôte, qui est ce que le support reconnaît au
//  téléphone (« celle de tel fournisseur »).
export function nomListe(s: DeviceSource, i: number): string {
  if (s.label) return s.label;
  const brut = s.type === 'xtream' ? s.server_url : s.m3u_url;
  if (brut) {
    try {
      return new URL(brut.startsWith('http') ? brut : 'http://' + brut).host;
    } catch {
      /* URL illisible : on retombe sur le numéro */
    }
  }
  return `Liste ${i + 1}`;
}

export function ListesAppareil({
  mac,
  kind,
  enLigne,
  onChange,
}: {
  mac: string;
  kind: 'phone' | 'tv';
  enLigne: boolean;
  /// Appelé après CHAQUE changement, pour que la page qui nous
  /// héberge rafraîchisse ce qu'elle affiche par ailleurs (onglets de
  /// chaînes, aperçu). Sans ça, on retirerait une liste sous les yeux
  /// du support tout en lui laissant ses chaînes à l'écran.
  onChange?: () => void;
}) {
  const [sources, setSources] = useState<DeviceSource[]>([]);
  const [locales, setLocales] = useState<DeviceLocalSource[]>([]);
  const [busy, setBusy] = useState(false);
  const [charge, setCharge] = useState(true);
  const [ajout, setAjout] = useState(false);

  const possessif = kind === 'tv' ? 'sa box' : 'son téléphone';

  const recharger = useCallback(async () => {
    if (!mac || mac.trim().length < 8) return;
    setCharge(true);
    try {
      //  LES DEUX EN PARALLÈLE, et chacune a le droit d'échouer sans
      //  emporter l'autre. Une fiche injoignable ne doit pas cacher au
      //  support les listes qu'il est venu changer.
      const [fiche, listes] = await Promise.all([
        devicesApi.overview(mac).catch(() => null),
        sourcesApi.get(mac).catch(() => null),
      ]);
      setSources(listes?.sources ?? (listes?.source ? [listes.source] : []));
      setLocales(fiche?.localSources ?? []);
    } finally {
      setCharge(false);
    }
  }, [mac]);

  useEffect(() => { void recharger(); }, [recharger]);

  function apresChangement() {
    void recharger();
    onChange?.();
  }

  async function activer(i: number) {
    setBusy(true);
    try {
      const r = await sourcesApi.setActive(mac, i);
      void rtActionFeedback(r.rt);
      toast('C’est cette liste que le client regarde maintenant.', 'success');
      apresChangement();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally {
      setBusy(false);
    }
  }

  async function retirer(i: number, s: DeviceSource) {
    if (!window.confirm(
      `Retirer « ${nomListe(s, i)} » de ${possessif} ?\n\n`
      + 'Elle disparaît de son app à sa prochaine synchro.',
    )) return;
    setBusy(true);
    try {
      // `match` : le serveur REFUSE si la liste a bougé depuis
      // l'affichage. Sans ça, deux onglets ouverts en même temps
      // effaceraient la mauvaise ligne — et on ne le saurait jamais.
      const empreinte = s.type === 'xtream'
        ? (s.server_url || '')
        : (s.m3u_url || '');
      const r = await sourcesApi.removeAt(mac, i, empreinte || undefined);
      void rtActionFeedback(r.rt);
      toast('Liste retirée.', 'success');
      apresChangement();
    } catch (e) {
      toast(
        e instanceof ApiError
          ? (e.status === 409
            ? 'La liste a changé depuis l’affichage — rien n’a été '
              + 'effacé. Recharge la page et recommence.'
            : e.message)
          : 'Échec du retrait.',
        'error',
      );
    } finally {
      setBusy(false);
    }
  }

  async function retirerLocale(l: DeviceLocalSource) {
    if (!window.confirm(
      `Retirer « ${l.name || l.server} » ?\n\n`
      + `Cette liste, c’est le CLIENT qui l’a ajoutée sur ${possessif} : `
      + 'elle n’est pas chez nous. On envoie l’ordre, l’appareil '
      + 'l’exécutera à sa prochaine synchro — même s’il est éteint en '
      + 'ce moment.',
    )) return;
    setBusy(true);
    try {
      const r = await sourcesApi.order(mac, 'source_remove', {
        type: l.type,
        name: l.name,
        server: l.server,
        username: l.username,
      });
      void rtActionFeedback(r.rt);
      toast(
        `Ordre envoyé. Il s’appliquera dès que ${possessif} se `
        + 'resynchronise.',
        'success',
      );
      apresChangement();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec de l’ordre.', 'error');
    } finally {
      setBusy(false);
    }
  }

  async function ajouter(src: DeviceSourceInput, active: boolean) {
    setBusy(true);
    try {
      const r = await sourcesApi.add(mac, src, active);
      void rtActionFeedback(r.rt);
      //  ON DIT CE QUI VA SE PASSER, selon qu'il est là ou pas. « C'est
      //  ajouté » tout court laisserait le support promettre au
      //  téléphone quelque chose qui n'arrivera qu'au rallumage.
      toast(
        enLigne
          ? `Liste ajoutée. ${kind === 'tv' ? 'La box' : 'Le téléphone'} la charge dans la seconde.`
          : `Liste ajoutée. ${kind === 'tv' ? 'La box la prendra' : 'Le téléphone la prendra'} à son prochain démarrage.`,
        'success',
      );
      setAjout(false);
      apresChangement();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Ajout impossible.', 'error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <section>
        <h3 className="mb-2 text-sm font-semibold">
          Listes poussées depuis le panel
        </h3>
        {charge && sources.length === 0 ? (
          <p className="text-xs text-ink-tertiary">Lecture…</p>
        ) : sources.length === 0 ? (
          <p className="text-xs text-ink-tertiary">
            Aucune. Ajoutes-en une ci-dessous.
          </p>
        ) : (
          <ul className="space-y-2">
            {sources.map((s, i) => (
              <li
                key={i}
                className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-white/10 bg-obsidian px-3 py-2"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm text-ink-primary">
                    {nomListe(s, i)}
                    {s.active && (
                      <span className="ml-2 rounded bg-accent/20 px-1.5 py-0.5 text-[10px] text-accent-bright">
                        regardée
                      </span>
                    )}
                  </p>
                  <p className="truncate text-[11px] text-ink-tertiary">
                    {s.type === 'xtream' ? 'Xtream' : 'M3U'}
                    {s.username ? ` · ${s.username}` : ''}
                  </p>
                </div>
                <div className="flex gap-1.5">
                  {!s.active && (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => { void activer(i); }}
                      className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30 disabled:opacity-50"
                    >
                      Rendre active
                    </button>
                  )}
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => { void retirer(i, s); }}
                    className="rounded-md border border-red-400/40 bg-red-500/10 px-2.5 py-1 text-xs text-red-200 hover:bg-red-500/20 disabled:opacity-50"
                  >
                    Retirer
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}

        {ajout ? (
          <FormulaireAjout
            busy={busy}
            onCancel={() => setAjout(false)}
            onSubmit={ajouter}
          />
        ) : (
          <button
            type="button"
            onClick={() => setAjout(true)}
            className="mt-3 rounded-lg bg-accent px-3 py-1.5 text-xs font-semibold text-black"
          >
            + Ajouter une liste
          </button>
        )}
      </section>

      {/* =========================================================
           CELLES QUE LE CLIENT A AJOUTÉES LUI-MÊME
          =========================================================
           Elles ne sont PAS chez nous : on ne les connaît que par ce
           que son app remonte. D'où un geste différent — un ordre, pas
           une suppression — et une phrase différente à lui dire au
           téléphone. */}
      {locales.length > 0 && (
        <section className="mt-5">
          <h3 className="mb-1 text-sm font-semibold">
            Listes que le client a ajoutées lui-même
          </h3>
          <p className="mb-2 text-[11px] text-ink-tertiary">
            Elles vivent sur {possessif}, pas chez nous. Les retirer
            envoie un <b>ordre</b> : il s’applique à sa prochaine
            synchro, même appareil éteint au moment du clic.
          </p>
          <ul className="space-y-2">
            {locales.map((l, i) => (
              <li
                key={i}
                className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-white/10 bg-obsidian px-3 py-2"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm text-ink-primary">
                    {l.name || l.server || 'Liste du client'}
                    {l.active && (
                      <span className="ml-2 rounded bg-accent/20 px-1.5 py-0.5 text-[10px] text-accent-bright">
                        regardée
                      </span>
                    )}
                  </p>
                  <p className="truncate text-[11px] text-ink-tertiary">
                    {l.type === 'xtream' ? 'Xtream' : 'M3U'}
                    {l.username ? ` · ${l.username}` : ''}
                    {` · ${l.channels} chaînes`}
                  </p>
                </div>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => { void retirerLocale(l); }}
                  className="rounded-md border border-red-400/40 bg-red-500/10 px-2.5 py-1 text-xs text-red-200 hover:bg-red-500/20 disabled:opacity-50"
                >
                  Retirer
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  );
}

// =========================================================
//  Ajouter une liste — Xtream ou M3U
// =========================================================
//  On AJOUTE (`sourcesApi.add`), on ne remplace pas : `setMany`
//  écraserait les listes déjà en place, y compris celle que le client
//  est en train de regarder.
// =========================================================
//  COLLER LE CODE DU FOURNISSEUR — instantané, sans deviner
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026, tard) : « je dois pouvoir
//  copier-coller les codes M3U facilement pour un client, ça doit
//  être fluide, instantané. »
//
//  CE QUE LE SUPPORT REÇOIT VRAIMENT d'un fournisseur, en pratique :
//  rarement un serveur/identifiant/mot de passe déjà séparés en trois
//  champs. Le plus souvent, un SEUL bloc de texte collé depuis
//  WhatsApp : un lien complet, ou un « code » du genre
//  « serveur:port:identifiant:motdepasse ». Lui faire recopier ça à
//  la main dans trois cases, chaque fois, à chaque client, c'est
//  exactement le contraire de « fluide ».
//
//  [analyserCode] lit ce bloc et retrouve le bon découpage — mais ne
//  DEVINE JAMAIS un identifiant ou un mot de passe qui ne serait pas
//  littéralement dans le texte collé. Trois issues, et rien d'autre :
//
//   1. Un lien Xtream (get.php / player_api.php avec `username` et
//      `password` en paramètres, OU la forme courte
//      `serveur/identifiant/motdepasse`) → les trois champs Xtream se
//      remplissent, l'onglet bascule dessus.
//   2. Un « code » `serveur:port:identifiant:motdepasse` (le format
//      que beaucoup de fournisseurs envoient tel quel) → pareil.
//   3. N'importe quel autre lien, ou rien de reconnu → le texte part
//      TEL QUEL dans le champ M3U. On ne perd rien, on ne fabrique
//      rien : c'est exactement ce que le support aurait tapé à la
//      main.
//
//  L'ANALYSE EST INSTANTANÉE PARCE QU'ELLE NE PART NULLE PART. Pas
//  d'appel réseau, pas d'attente : c'est du texte relu localement, au
//  caractère près, pendant que le support tape. Et rien ne part
//  jamais vers l'appareil du client tant qu'il n'a pas cliqué
//  « Ajouter » — coller ne fait que PRÉ-REMPLIR, ça ne soumet rien.
// =========================================================

type ResultatCollage =
  | { ok: true; type: 'xtream'; server_url: string; username: string; password: string; note: string }
  | { ok: true; type: 'm3u'; m3u_url: string; note: string }
  | { ok: false; brut: string };

function analyserCode(brutEntree: string): ResultatCollage | null {
  const brut = brutEntree.trim();
  if (!brut) return null;

  // 1) « serveur:port:identifiant:motdepasse » — le format que
  //    beaucoup de fournisseurs envoient tel quel, sans lien du tout.
  const mColon = brut.match(/^([a-zA-Z0-9_.-]+):(\d{2,5}):([^\s:]+):([^\s:]+)$/);
  if (mColon) {
    const [, host, port, u, p] = mColon;
    return {
      ok: true, type: 'xtream',
      server_url: `http://${host}:${port}`, username: u, password: p,
      note: `Détecté : Xtream — ${host}:${port} · ${u}`,
    };
  }

  // 2) Une URL quelque part dans le texte collé. Le support colle
  //    souvent une phrase entière autour (« voici ton accès :
  //    http://… ») : on ne garde que le lien, pas la phrase.
  const mUrl = brut.match(/https?:\/\/[^\s"'<>]+/i);
  if (!mUrl) {
    // Rien reconnu : ON NE DEVINE PAS PLUS LOIN. Le texte part tel
    // quel vers le champ M3U — l'utilisateur verra que ce n'en est
    // pas un au moment de valider, exactement comme s'il l'avait
    // tapé lui-même.
    return { ok: false, brut };
  }
  let url: URL;
  try {
    url = new URL(mUrl[0]);
  } catch {
    return { ok: false, brut };
  }

  const u = url.searchParams.get('username');
  const p = url.searchParams.get('password');
  if (u && p) {
    return {
      ok: true, type: 'xtream',
      server_url: `${url.protocol}//${url.host}`, username: u, password: p,
      note: `Détecté : Xtream — ${url.host} · ${u}`,
    };
  }

  // 3) La forme courte « serveur/identifiant/motdepasse », sans
  //    get.php ni paramètres — très répandue chez les fournisseurs
  //    qui ne donnent QUE ce lien-là.
  const segments = url.pathname.split('/').filter(Boolean);
  if (segments.length >= 2 && !/get\.php|player_api\.php|xmltv\.php/i.test(url.pathname)) {
    const [seg1, seg2] = segments;
    // Le dernier segment peut porter une extension (.m3u8, .ts…) —
    // elle ne fait pas partie du mot de passe.
    const p2 = seg2.replace(/\.(m3u8?|ts)$/i, '');
    if (seg1 && p2) {
      return {
        ok: true, type: 'xtream',
        server_url: `${url.protocol}//${url.host}`, username: seg1, password: p2,
        note: `Détecté : Xtream (lien court) — ${url.host} · ${seg1}`,
      };
    }
  }

  // 4) Un lien qu'on ne sait pas découper en identifiants : c'est
  //    exactement ce que le champ M3U attend, tel quel.
  return { ok: true, type: 'm3u', m3u_url: url.toString(), note: 'Détecté : lien M3U direct' };
}

function FormulaireAjout({
  busy,
  onCancel,
  onSubmit,
}: {
  busy: boolean;
  onCancel: () => void;
  onSubmit: (src: DeviceSourceInput, active: boolean) => void;
}) {
  const [type, setType] = useState<'xtream' | 'm3u'>('xtream');
  const [label, setLabel] = useState('');
  const [server, setServer] = useState('');
  const [user, setUser] = useState('');
  const [pass, setPass] = useState('');
  const [m3u, setM3u] = useState('');
  const [active, setActive] = useState(true);

  // Le champ « coller le code » : purement une aide au remplissage,
  // il n'est jamais envoyé lui-même — voir analyserCode ci-dessus.
  const [collage, setCollage] = useState('');
  const [detection, setDetection] = useState<string | null>(null);

  function surCollage(texte: string) {
    setCollage(texte);
    const r = analyserCode(texte);
    if (!r) {
      setDetection(null);
      return;
    }
    if (!r.ok) {
      setType('m3u');
      setM3u(r.brut);
      setDetection(
        '⚠ Format non reconnu — le texte a été mis dans le champ M3U '
        + 'ci-dessous, vérifie-le avant d’ajouter.',
      );
      return;
    }
    if (r.type === 'xtream') {
      setType('xtream');
      setServer(r.server_url);
      setUser(r.username);
      setPass(r.password);
    } else {
      setType('m3u');
      setM3u(r.m3u_url);
    }
    setDetection(r.note);
  }

  function envoyer(e: FormEvent) {
    e.preventDefault();
    if (type === 'xtream') {
      if (!server.trim() || !user.trim() || !pass.trim()) {
        toast('Serveur, identifiant et mot de passe sont nécessaires.', 'warning');
        return;
      }
      onSubmit({
        type: 'xtream',
        label: label.trim() || null,
        server_url: server.trim(),
        username: user.trim(),
        password: pass.trim(),
      }, active);
      return;
    }
    if (!m3u.trim()) {
      toast('Colle l’URL du M3U.', 'warning');
      return;
    }
    onSubmit({ type: 'm3u', label: label.trim() || null, m3u_url: m3u.trim() }, active);
  }

  const champ =
    'w-full rounded-lg border border-white/10 bg-obsidian px-3 py-2 text-sm text-ink-primary outline-none focus:border-accent/50';

  return (
    <form
      onSubmit={envoyer}
      className="mt-3 space-y-2 rounded-lg border border-white/10 bg-midnight p-3"
    >
      {/* COLLER LE CODE — voir le pavé plus haut. Une seule case, tout
          ce qui suit se remplit tout seul, instantanément, sans rien
          envoyer nulle part. */}
      <div>
        <label className="mb-1 block text-[11px] font-semibold text-ink-secondary">
          Colle le code du fournisseur (un lien, ou serveur:port:id:mdp)
        </label>
        <textarea
          value={collage}
          onChange={(e) => surCollage(e.target.value)}
          placeholder="http://serveur:port/get.php?username=…&password=…  —  ou serveur:port:identifiant:motdepasse"
          spellCheck={false}
          rows={2}
          className={champ + ' resize-none font-mono text-xs'}
        />
        {detection && (
          <p
            className={
              'mt-1 text-[11px] '
              + (detection.startsWith('⚠') ? 'text-warning' : 'text-success')
            }
          >
            {detection}
          </p>
        )}
      </div>

      <div className="flex gap-2">
        {(['xtream', 'm3u'] as const).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setType(t)}
            className={
              'rounded-md px-2.5 py-1 text-xs font-medium '
              + (type === t
                ? 'bg-accent text-black'
                : 'border border-white/10 text-ink-secondary')
            }
          >
            {t === 'xtream' ? 'Xtream' : 'M3U'}
          </button>
        ))}
      </div>

      <input
        value={label}
        onChange={(e) => setLabel(e.target.value)}
        placeholder="Nom de la liste (facultatif — s’affiche chez le client)"
        className={champ}
      />

      {type === 'xtream' ? (
        <>
          <input
            value={server}
            onChange={(e) => { setServer(e.target.value); setDetection(null); }}
            placeholder="http://serveur:port"
            spellCheck={false}
            className={champ}
          />
          <div className="grid gap-2 sm:grid-cols-2">
            <input
              value={user}
              onChange={(e) => { setUser(e.target.value); setDetection(null); }}
              placeholder="Identifiant"
              spellCheck={false}
              className={champ}
            />
            <input
              value={pass}
              onChange={(e) => { setPass(e.target.value); setDetection(null); }}
              placeholder="Mot de passe"
              spellCheck={false}
              className={champ}
            />
          </div>
        </>
      ) : (
        <input
          value={m3u}
          onChange={(e) => { setM3u(e.target.value); setDetection(null); }}
          placeholder="http://…/get.php?…&type=m3u_plus"
          spellCheck={false}
          className={champ}
        />
      )}

      <label className="flex items-center gap-2 text-xs text-ink-secondary">
        <input
          type="checkbox"
          checked={active}
          onChange={(e) => setActive(e.target.checked)}
          className="h-3.5 w-3.5 accent-accent"
        />
        C’est celle-ci que le client doit regarder tout de suite
      </label>

      <div className="flex gap-2 pt-1">
        <button
          type="submit"
          disabled={busy}
          className="rounded-lg bg-accent px-3 py-1.5 text-xs font-semibold text-black disabled:opacity-50"
        >
          {busy ? 'Envoi…' : 'Ajouter'}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-lg border border-white/10 px-3 py-1.5 text-xs text-ink-secondary"
        >
          Annuler
        </button>
      </div>
    </form>
  );
}
