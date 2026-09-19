// =========================================================
//  DeviceScreenPage — « je mets la MAC, et l'appareil vient »
// =========================================================
//  UN SEUL ÉCRAN, DEUX PORTES : « Téléphone » et « Télévision ».
//
//  Demande du propriétaire, une heure après la première :
//
//    « Comme tu as créé la section Téléphone, il faut créer aussi la
//      section Télévision qui fonctionne la même chose. »
//
//  « La même chose » au sens propre : c'est le MÊME code. Un téléphone
//  et une box lisent la même liste, chez le même fournisseur, par les
//  mêmes routes — seuls le cadre dessiné à l'écran et les mots changent
//  (« son téléphone » / « sa box »).
//
//  DEUX COPIES DE CETTE PAGE AURAIENT DÉRIVÉ, et vite : on corrige un
//  bug de retrait de liste dans l'une, on oublie l'autre, et le support
//  se met à dépendre de la porte par laquelle on est entré. Même raison
//  que ci/build_label.sh et cloudflare/stream_proxy.js — une seule
//  implémentation, autant d'appelants qu'on veut.
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026), mot pour mot :
//
//    « Je veux une option qui s'appelle Téléphone. Je mets l'adresse
//      MAC et le téléphone vient. Je vois les chaînes qu'il a. Et
//      j'efface ou j'ajoute les listes. »
//
//  ---------------------------------------------------------
//  CE QUE CET ÉCRAN EST — ET CE QU'IL N'EST PAS
//  ---------------------------------------------------------
//  Il n'y a PAS de caméra dans le téléphone du client. Personne ne
//  filme son écran, et ce n'est pas une omission : une recopie d'écran
//  demanderait à l'app de diffuser ce qu'elle affiche en permanence —
//  batterie, données, et le droit de regarder par-dessus l'épaule d'un
//  client sans qu'il le sache.
//
//  Ce qu'on fait à la place est plus fiable pour dépanner : on lit LA
//  MÊME SOURCE que son app, chez le même fournisseur, et on la range
//  comme elle la range. Quand il dit « je n'ai pas TF1 », ce panneau
//  répond, avec la liste sous les yeux.
//
//  LÀ OÙ LES DEUX PEUVENT DIFFÉRER, et c'est écrit à l'écran : ses
//  favoris, son historique et ses catégories masquées ne vivent que
//  chez lui. Le panel ne les invente pas.
//
//  ---------------------------------------------------------
//  LES LISTES : DEUX ORIGINES, DEUX GESTES
//  ---------------------------------------------------------
//   • POUSSÉE PAR LE PANEL → elle est en base. On l'ajoute, on la
//     retire, on l'active tout de suite (`sourcesApi.add/removeAt/
//     setActive`).
//   • AJOUTÉE PAR LE CLIENT sur son téléphone → elle n'existe QUE chez
//     lui ; le panel ne la connaît que par ce que le heartbeat remonte.
//     On ne peut donc pas l'effacer en base : on envoie un ORDRE
//     (`sourcesApi.order('source_remove')`), que l'appareil exécute à
//     sa prochaine synchro — même s'il est éteint au moment du clic.
//
//  C'est la distinction la plus importante de cet écran, et elle est
//  dite au client de vive voix : « c'est parti, ça s'appliquera dès
//  qu'il rallume » n'est pas la même promesse que « c'est fait ».
// =========================================================

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AppLayout } from '@/components/AppLayout';
import { ChannelPlayer } from '@/components/ChannelPlayer';
import { PrendreLaMain } from '@/components/PrendreLaMain';
import { toast, rtActionFeedback } from '@/components/Toast';
import { useLiveDevices } from '@/lib/realtime';
import { formatMacInput } from '@/lib/utils';
import {
  devicesApi, sourcesApi, ApiError,
  type DeviceChannels, type DeviceOverview, type DeviceSource,
  type DeviceLocalSource, type DeviceSourceInput,
} from '@/lib/api';

// ---------------------------------------------------------
//  Le nom qu'on affiche pour une liste.
// ---------------------------------------------------------
//  Un M3U sans étiquette donnerait une URL de 200 caractères dans un
//  onglet de 8 cm. On montre le nom s'il existe, sinon l'hôte, sinon
//  « Liste n ». Jamais l'URL brute, et JAMAIS le mot de passe.
function nomListe(s: DeviceSource, i: number): string {
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

/// Ce qui CHANGE entre les deux portes — et rien d'autre. Tout le
/// reste du fichier est commun, volontairement.
type Appareil = 'phone' | 'tv';

const APPARENCE: Record<Appareil, {
  titre: string;
  sousTitre: string;
  ouvrir: string;
  /// « son téléphone » / « sa box » — utilisé dans les phrases.
  possessif: string;
  /// Largeur et arrondi du cadre : un téléphone est étroit et très
  /// arrondi, un téléviseur large et presque carré. C'est décoratif,
  /// mais c'est ce qui fait reconnaître l'écran d'un coup d'œil.
  cadre: string;
  ecran: string;
  /// Combien de tuiles de chaînes par rangée. Une box a de la place.
  colonnes: string;
}> = {
  phone: {
    titre: 'Téléphone',
    sousTitre: 'Colle une MAC : tu vois ses listes et ses chaînes, et tu les changes.',
    ouvrir: 'Ouvrir le téléphone',
    possessif: 'son téléphone',
    cadre: 'mx-auto w-full max-w-[360px]',
    ecran: 'rounded-[2rem] border-4 border-white/10 bg-[#08080A] p-3 shadow-2xl',
    colonnes: 'grid-cols-3',
  },
  tv: {
    titre: 'Télévision',
    sousTitre: 'Colle la MAC d’une box : tu vois ses listes et ses chaînes, et tu les changes.',
    ouvrir: 'Ouvrir la box',
    possessif: 'sa box',
    cadre: 'mx-auto w-full max-w-[560px]',
    ecran: 'rounded-xl border-4 border-white/10 bg-[#08080A] p-3 shadow-2xl',
    colonnes: 'grid-cols-4',
  },
};

/// La porte « Téléphone ».
export function PhonePage({ onLogout }: { onLogout: () => void }) {
  return <DeviceScreenPage onLogout={onLogout} kind="phone" />;
}

/// La porte « Télévision ». MÊME page, même code, même serveur.
export function TvPage({ onLogout }: { onLogout: () => void }) {
  return <DeviceScreenPage onLogout={onLogout} kind="tv" />;
}

function DeviceScreenPage({
  onLogout,
  kind,
}: {
  onLogout: () => void;
  kind: Appareil;
}) {
  const look = APPARENCE[kind];
  const [sp, setSp] = useSearchParams();
  const [mac, setMac] = useState(sp.get('mac') || 'MK:');
  const [busy, setBusy] = useState(false);
  const [charge, setCharge] = useState(false);
  const [ov, setOv] = useState<DeviceOverview | null>(null);
  const [sources, setSources] = useState<DeviceSource[]>([]);
  const [chaines, setChaines] = useState<DeviceChannels | null>(null);
  const [erreurChaines, setErreurChaines] = useState<string | null>(null);
  const [onglet, setOnglet] = useState<number | null>(null);
  const [filtre, setFiltre] = useState('');
  const [categorie, setCategorie] = useState<string | null>(null);
  const [ajout, setAjout] = useState(false);
  /// La chaîne en cours de lecture dans le cadre du téléphone.
  const [joue, setJoue] = useState<{ id: string; name: string } | null>(null);

  const { devices: live, connected: rtOk } = useLiveDevices();
  const macCourante = ov?.mac || '';
  const enLigne = rtOk && live.some((d) => d.mac === macCourante);

  const locales: DeviceLocalSource[] = ov?.localSources ?? [];

  // ---------------------------------------------------------
  //  Charger : la fiche, les listes, les chaînes.
  // ---------------------------------------------------------
  //  Les TROIS en parallèle, et les chaînes ont le droit d'échouer sans
  //  emporter le reste. Un fournisseur injoignable ne doit pas cacher à
  //  Lionel l'abonnement et les listes du client — c'est justement dans
  //  ce cas-là qu'il en a le plus besoin.
  const charger = useCallback(async (cible: string, index?: number) => {
    const clef = cible.trim();
    if (clef.length < 8) {
      toast('Colle d’abord la MAC (MK:…)', 'warning');
      return;
    }
    setCharge(true);
    setErreurChaines(null);
    try {
      const [fiche, listes] = await Promise.all([
        devicesApi.overview(clef).catch(() => null),
        sourcesApi.get(clef).catch(() => null),
      ]);
      if (!fiche) {
        toast(
          'Aucune fiche pour cette MAC. Soit l’app n’a jamais démarré '
          + 'avec ce numéro, soit elle appartient à un autre revendeur.',
          'error',
        );
        setOv(null);
        setSources([]);
        setChaines(null);
        return;
      }
      setOv(fiche);
      setSources(listes?.sources ?? (listes?.source ? [listes.source] : []));
      if (fiche.mac && fiche.mac !== sp.get('mac')) {
        setSp({ mac: fiche.mac }, { replace: true });
      }
      try {
        const c = await devicesApi.channels(clef, index);
        setChaines(c);
        setOnglet(c.index);
        setCategorie(null);
        // On coupe la lecture en cours : elle appartenait à l'ancienne
        // liste. La laisser tourner ferait jouer une chaîne qui n'est
        // plus celle affichée — et continuerait de tirer sur la ligne
        // du client pour rien.
        setJoue(null);
      } catch (e) {
        setChaines(null);
        setErreurChaines(
          e instanceof ApiError ? e.message : 'Lecture des chaînes impossible.',
        );
      }
    } finally {
      setCharge(false);
    }
  }, [sp, setSp]);

  useEffect(() => {
    const depuisUrl = sp.get('mac');
    if (depuisUrl && depuisUrl.length >= 8) {
      setMac(formatMacInput(depuisUrl));
      void charger(depuisUrl);
    }
    // Une seule fois à l'arrivée, pas à chaque frappe.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---------------------------------------------------------
  //  Les chaînes affichées : catégorie choisie + recherche.
  // ---------------------------------------------------------
  const categories = chaines?.categories ?? [];
  const visibles = useMemo(() => {
    const q = filtre.trim().toLowerCase();
    const dans = categorie
      ? categories.filter((c) => c.id === categorie)
      : categories;
    if (!q) return dans;
    return dans
      .map((c) => ({
        ...c,
        channels: c.channels.filter((ch) => ch.name.toLowerCase().includes(q)),
      }))
      .filter((c) => c.channels.length > 0);
  }, [categories, categorie, filtre]);

  const nbVisibles = visibles.reduce((n, c) => n + c.channels.length, 0);

  // ---------------------------------------------------------
  //  Les gestes sur les listes
  // ---------------------------------------------------------
  async function activer(i: number) {
    setBusy(true);
    try {
      const r = await sourcesApi.setActive(macCourante, i);
      void rtActionFeedback(r.rt);
      toast('C’est cette liste que le client regarde maintenant.', 'success');
      await charger(macCourante, i);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec.', 'error');
    } finally {
      setBusy(false);
    }
  }

  async function retirer(i: number, s: DeviceSource) {
    if (!window.confirm(
      `Retirer « ${nomListe(s, i)} » de ${look.possessif} ?\n\n`
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
      const r = await sourcesApi.removeAt(macCourante, i, empreinte || undefined);
      void rtActionFeedback(r.rt);
      toast('Liste retirée.', 'success');
      await charger(macCourante);
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
      + 'Cette liste, c’est le CLIENT qui l’a ajoutée sur son '
      + `${kind === 'tv' ? 'sa box' : 'son téléphone'} : elle n’est pas chez nous. On envoie l’ordre, `
      + 'l’appareil l’exécutera à sa prochaine synchro — même s’il est '
      + 'éteint en ce moment.',
    )) return;
    setBusy(true);
    try {
      const r = await sourcesApi.order(macCourante, 'source_remove', {
        type: l.type,
        name: l.name,
        server: l.server,
        username: l.username,
      });
      void rtActionFeedback(r.rt);
      toast(
        `Ordre envoyé. Il s’appliquera dès que ${look.possessif} se `
        + 'resynchronise.',
        'success',
      );
      await charger(macCourante);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Échec de l’ordre.', 'error');
    } finally {
      setBusy(false);
    }
  }

  async function ajouter(src: DeviceSourceInput, active: boolean) {
    setBusy(true);
    try {
      const r = await sourcesApi.add(macCourante, src, active);
      void rtActionFeedback(r.rt);
      toast(
        enLigne
          ? `Liste ajoutée. ${kind === 'tv' ? 'La box' : 'Le téléphone'} la charge dans la seconde.`
          : `Liste ajoutée. ${kind === 'tv' ? 'La box la prendra' : 'Le téléphone la prendra'} à son prochain `
            + 'démarrage.',
        'success',
      );
      setAjout(false);
      await charger(macCourante, active ? r.index : undefined);
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Ajout impossible.', 'error');
    } finally {
      setBusy(false);
    }
  }

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    void charger(mac);
  }

  return (
    <AppLayout
      onLogout={onLogout}
      title={look.titre}
      subtitle={look.sousTitre}
    >
      {/* ===== La barre de saisie ===== */}
      <form onSubmit={onSubmit} className="mb-6 flex flex-wrap items-center gap-2">
        <input
          value={mac}
          onChange={(e) => setMac(formatMacInput(e.target.value))}
          placeholder="MK:XX:XX:XX:XX:XX"
          spellCheck={false}
          className="w-64 rounded-lg border border-white/10 bg-obsidian px-3 py-2 font-mono text-sm text-ink-primary outline-none focus:border-accent/50"
        />
        <button
          type="submit"
          disabled={charge}
          className="rounded-lg bg-accent px-4 py-2 text-sm font-semibold text-black disabled:opacity-50"
        >
          {charge ? 'Ouverture…' : look.ouvrir}
        </button>
        {ov && (
          <span className="inline-flex items-center gap-2 text-xs text-ink-tertiary">
            <span
              className={
                'h-1.5 w-1.5 rounded-full '
                + (enLigne ? 'animate-pulse bg-success' : 'bg-white/20')
              }
            />
            {enLigne ? 'en ligne maintenant' : 'hors ligne'}
            {ov.device?.device_model ? ` · ${ov.device.device_model}` : ''}
            {ov.device?.app_version ? ` · v${ov.device.app_version}` : ''}
          </span>
        )}
      </form>

      {!ov && !charge && (
        <p className="max-w-2xl text-sm text-ink-tertiary">
          Colle la MAC d’un client et {look.possessif} s’ouvre ici : ses
          listes, et les chaînes qu’il a vraiment.
        </p>
      )}

      {ov && (
        <div className="grid gap-6 lg:grid-cols-[minmax(0,360px)_minmax(0,1fr)]">
          {/* =========================================================
               LE TÉLÉPHONE
              =========================================================
               Un cadre, dans les couleurs de l'app (Maison Noir + ember),
               pour que Lionel reconnaisse d'un coup d'œil ce que son
               client a sous les yeux. Le cadre est décoratif ; ce qui
               compte est dedans. */}
          <div className={look.cadre}>
            <div className={look.ecran}>
              <div className="mb-2 flex items-center justify-between px-2 text-[10px] text-ink-tertiary">
                <span className="font-mono">{ov.mac}</span>
                <span>{enLigne ? '● en ligne' : '○ hors ligne'}</span>
              </div>

              <div className="rounded-2xl bg-[#15151B] p-3">
                <div className="mb-3 flex items-center justify-between">
                  <span className="text-sm font-bold tracking-tight text-[#F0EDE9]">
                    7 MOTION
                  </span>
                  <span className="text-[10px] text-[#7E7872]">
                    {chaines ? `${chaines.total} chaînes` : '—'}
                  </span>
                </div>

                {/* Les onglets de listes, comme dans l'app */}
                {sources.length > 0 && (
                  <div className="mb-3 flex flex-wrap gap-1.5">
                    {sources.map((s, i) => (
                      <button
                        key={i}
                        type="button"
                        disabled={charge}
                        onClick={() => { void charger(macCourante, i); }}
                        className={
                          'rounded-full px-2.5 py-1 text-[11px] font-medium '
                          + (onglet === i
                            ? 'bg-accent text-black'
                            : 'border border-white/10 text-[#B6B0A8]')
                        }
                      >
                        {nomListe(s, i)}
                        {s.active ? ' ●' : ''}
                      </button>
                    ))}
                  </div>
                )}

                <input
                  value={filtre}
                  onChange={(e) => setFiltre(e.target.value)}
                  placeholder="Chercher une chaîne…"
                  className="mb-3 w-full rounded-lg border border-white/10 bg-[#0E0E12] px-2.5 py-1.5 text-xs text-[#F0EDE9] outline-none focus:border-accent/50"
                />

                {erreurChaines && (
                  <SansChaines
                    message={erreurChaines}
                    locales={locales}
                    possessif={look.possessif}
                    enLigne={enLigne}
                  />
                )}

                {/* LE LECTEUR, DANS LE CADRE DU TÉLÉPHONE. Il n'apparaît
                    qu'au clic : ouvrir un flux prend une place de
                    connexion sur la ligne du client, et on ne la prend
                    pas sans raison. */}
                {joue && onglet != null && (
                  <ChannelPlayer
                    mac={macCourante}
                    index={onglet}
                    channel={joue}
                    onClose={() => setJoue(null)}
                  />
                )}

                {chaines && (
                  <>
                    {/* Catégories : « Tout » + celles du fournisseur */}
                    <div className="mb-2 flex flex-wrap gap-1">
                      <button
                        type="button"
                        onClick={() => setCategorie(null)}
                        className={
                          'rounded px-2 py-0.5 text-[10px] '
                          + (categorie === null
                            ? 'bg-white/15 text-[#F0EDE9]'
                            : 'text-[#7E7872] hover:text-[#B6B0A8]')
                        }
                      >
                        Tout
                      </button>
                      {categories.map((c) => (
                        <button
                          key={c.id}
                          type="button"
                          onClick={() => setCategorie(c.id)}
                          className={
                            'rounded px-2 py-0.5 text-[10px] '
                            + (categorie === c.id
                              ? 'bg-white/15 text-[#F0EDE9]'
                              : 'text-[#7E7872] hover:text-[#B6B0A8]')
                          }
                        >
                          {c.name} ({c.channels.length})
                        </button>
                      ))}
                    </div>

                    <div className="max-h-[420px] overflow-y-auto pr-1">
                      {nbVisibles === 0 ? (
                        <p className="px-1 py-6 text-center text-[11px] text-[#7E7872]">
                          {filtre.trim()
                            ? `Aucune chaîne « ${filtre.trim()} » dans cette liste. `
                              + 'C’est ce que le client voit aussi.'
                            : 'Cette liste est vide.'}
                        </p>
                      ) : (
                        visibles.map((c) => (
                          <div key={c.id} className="mb-2">
                            <p className="mb-1 px-1 text-[10px] uppercase tracking-wider text-[#4E4A45]">
                              {c.name}
                            </p>
                            <div className={'grid gap-1.5 ' + look.colonnes}>
                              {c.channels.map((ch) => (
                                <button
                                  key={ch.id}
                                  type="button"
                                  title={`Lire « ${ch.name} »`}
                                  onClick={() => setJoue({ id: ch.id, name: ch.name })}
                                  className={
                                    'flex flex-col items-center gap-1 rounded-lg p-1.5 text-left transition '
                                    + (joue?.id === ch.id
                                      ? 'bg-accent/20 ring-1 ring-accent/50'
                                      : 'bg-[#1D1D25] hover:bg-[#28282F]')
                                  }
                                >
                                  {ch.logo ? (
                                    <img
                                      src={ch.logo}
                                      alt=""
                                      loading="lazy"
                                      className="h-7 w-7 rounded object-contain"
                                      onError={(e) => {
                                        // Un logo mort ne doit pas laisser
                                        // une icône cassée : le client, lui,
                                        // voit une tuile propre.
                                        e.currentTarget.style.display = 'none';
                                      }}
                                    />
                                  ) : (
                                    <div className="flex h-7 w-7 items-center justify-center rounded bg-white/5 text-[9px] text-[#7E7872]">
                                      {ch.name.slice(0, 2).toUpperCase()}
                                    </div>
                                  )}
                                  <span className="line-clamp-2 w-full text-center text-[9px] leading-tight text-[#B6B0A8]">
                                    {ch.name}
                                  </span>
                                </button>
                              ))}
                            </div>
                          </div>
                        ))
                      )}
                    </div>

                    {chaines.truncated && (
                      <p className="mt-2 rounded border border-warning/30 bg-warning/10 px-2 py-1 text-[10px] text-warning">
                        Liste tronquée à {chaines.total} chaînes. Le client en
                        a peut-être davantage — ne conclus pas « il ne l’a
                        pas » à partir de cet écran.
                      </p>
                    )}
                  </>
                )}
              </div>
            </div>

            {/* CE QUI N'EST PAS ICI, DIT FRANCHEMENT. Sans cette ligne,
                Lionel prendrait cet écran pour la copie exacte du
                téléphone et conclurait à tort. */}
            <p className="mt-3 px-2 text-[11px] leading-relaxed text-ink-tertiary">
              Ce n’est pas l’écran du client filmé : c’est <b>sa liste, lue
              chez son fournisseur</b>, rangée comme son app la range. Ses
              favoris, son historique et ses catégories masquées ne vivent
              que sur {look.possessif} — ils n’apparaissent pas ici.
            </p>
          </div>

          {/* =========================================================
               LES LISTES, ET CE QU'ON PEUT EN FAIRE
              ========================================================= */}
          <div className="space-y-6">
            {/* PRENDRE LA MAIN — en premier : quand on ouvre cette page
                avec un client au téléphone, c'est ce qu'on vient faire. */}
            <PrendreLaMain mac={macCourante} enLigne={enLigne} />

            <section>
              <h3 className="mb-2 text-sm font-semibold">
                Listes poussées depuis le panel
              </h3>
              {sources.length === 0 ? (
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
                 Elles ne sont PAS chez nous : on ne les connaît que par
                 ce que son app remonte. D'où un geste différent — un
                 ordre, pas une suppression — et une phrase différente à
                 lui dire au téléphone. */}
            {locales.length > 0 && (
              <section>
                <h3 className="mb-1 text-sm font-semibold">
                  Listes que le client a ajoutées lui-même
                </h3>
                <p className="mb-2 text-[11px] text-ink-tertiary">
                  Elles vivent sur {look.possessif}, pas chez nous. Les
                  retirer envoie un <b>ordre</b> : il s’applique à sa
                  prochaine synchro, même appareil éteint au moment du
                  clic.
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
          </div>
        </div>
      )}
    </AppLayout>
  );
}

// =========================================================
//  QUAND ON N'A AUCUNE CHAÎNE À MONTRER
// =========================================================
//  CE QUE CE COMPOSANT RÉPARE (18/09/2026). Lionel regardait BBC One
//  sur son téléphone pendant que ce panneau lui annonçait :
//
//    « Cet appareil n'a aucune liste poussée depuis le panel. »
//
//  Techniquement exact. Humainement faux, et dangereux : lu vite, ça
//  dit « ce client n'a rien », alors qu'il était en train de regarder
//  la télévision. Un support qui appelle sur cette base se trompe de
//  conversation.
//
//  ---------------------------------------------------------
//  POURQUOI ON NE PEUT PAS MONTRER SES CHAÎNES À LUI
//  ---------------------------------------------------------
//  Quand le CLIENT saisit sa liste lui-même, son mot de passe reste
//  chez lui : l'app remonte le nom, l'origine du serveur, l'identifiant
//  et le NOMBRE de chaînes — jamais le mot de passe, et pour un M3U
//  jamais l'URL complète (elle porte presque toujours les
//  identifiants). C'est une décision de vie privée prise avant ce
//  panneau, et elle est juste : on ne collecte pas les accès de nos
//  clients « au cas où ».
//
//  Sans ces accès, le serveur ne PEUT PAS aller lire son bouquet. Ce
//  n'est pas une limite à corriger, c'est le prix d'un choix qu'on
//  assume. Ce qu'on doit à Lionel, c'est de le dire clairement et de
//  montrer tout ce qu'on sait quand même.
//
//  ---------------------------------------------------------
//  ET SI ON NE VOIT RIEN DU TOUT ?
//  ---------------------------------------------------------
//  Alors on ne conclut PAS « il n'a rien ». L'inventaire n'arrive que
//  par le heartbeat : un appareil hors ligne peut très bien être plein
//  de chaînes sans que le serveur en sache quoi que ce soit. C'est
//  exactement le cas de la capture qui a motivé ce correctif.
function SansChaines({
  message,
  locales,
  possessif,
  enLigne,
}: {
  message: string;
  locales: DeviceLocalSource[];
  possessif: string;
  enLigne: boolean;
}) {
  //  Cas 1 — RIEN de poussé, mais le client a SES listes à lui.
  if (locales.length > 0) {
    const total = locales.reduce((n, l) => n + (l.channels || 0), 0);
    return (
      <div className="rounded-lg border border-warning/40 bg-warning/10 px-2.5 py-2 text-[11px] text-warning">
        <p className="font-semibold">
          Ce client a {locales.length} liste{locales.length > 1 ? 's' : ''} —
          mais {locales.length > 1 ? 'ce sont les siennes' : 'c’est la sienne'}.
        </p>
        <ul className="mt-1.5 space-y-1">
          {locales.map((l, i) => (
            <li key={i} className="flex items-baseline justify-between gap-2">
              <span className="truncate">
                {l.name || l.server || 'Liste du client'}
                {l.active ? ' ●' : ''}
              </span>
              <span className="shrink-0 opacity-80">{l.channels} chaînes</span>
            </li>
          ))}
        </ul>
        <p className="mt-2 opacity-90">
          Il regarde bien la télévision — {total} chaînes au total d’après son
          app. Je ne peux pas te les LISTER ici : quand le client saisit sa
          liste lui-même, son mot de passe reste chez lui et le serveur n’a
          pas de quoi aller lire son bouquet.
        </p>
        <p className="mt-1 opacity-90">
          Pour les voir : pousse-lui la liste depuis le panel (là on a les
          accès), ou demande-lui son mot de passe et ajoute-la ci-contre.
        </p>
      </div>
    );
  }

  //  Cas 2 — on ne voit RIEN, et l'appareil est hors ligne. Ne jamais
  //  en conclure qu'il est vide : l'inventaire ne voyage que par le
  //  heartbeat.
  if (!enLigne) {
    return (
      <div className="rounded-lg border border-white/15 bg-white/5 px-2.5 py-2 text-[11px] text-[#B6B0A8]">
        <p className="font-semibold text-[#F0EDE9]">
          Rien à afficher — et ça ne veut PAS dire qu’il n’a rien.
        </p>
        <p className="mt-1">
          Aucune liste poussée depuis le panel, et {possessif} n’a rien
          remonté non plus. Or son inventaire ne voyage que quand l’app
          tourne : hors ligne, le serveur ne sait tout simplement pas ce
          qu’il a. Il peut très bien être devant sa télé en ce moment.
        </p>
        <p className="mt-1">
          Attends qu’il rouvre l’app, ou pousse-lui une liste ci-contre.
        </p>
      </div>
    );
  }

  //  Cas 3 — en ligne, et vraiment rien : là on peut le dire.
  return (
    <div className="rounded-lg border border-red-500/40 bg-red-500/10 px-2.5 py-2 text-[11px] text-red-200">
      {message}
    </div>
  );
}

// =========================================================
//  Ajouter une liste — Xtream ou M3U
// =========================================================
//  On AJOUTE (`sourcesApi.add`), on ne remplace pas : `setMany`
//  écraserait les listes déjà en place, y compris celle que le client
//  est en train de regarder.
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
            onChange={(e) => setServer(e.target.value)}
            placeholder="http://serveur:port"
            spellCheck={false}
            className={champ}
          />
          <div className="grid gap-2 sm:grid-cols-2">
            <input
              value={user}
              onChange={(e) => setUser(e.target.value)}
              placeholder="Identifiant"
              spellCheck={false}
              className={champ}
            />
            <input
              value={pass}
              onChange={(e) => setPass(e.target.value)}
              placeholder="Mot de passe"
              spellCheck={false}
              className={champ}
            />
          </div>
        </>
      ) : (
        <input
          value={m3u}
          onChange={(e) => setM3u(e.target.value)}
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
