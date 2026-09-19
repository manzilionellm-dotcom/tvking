// =========================================================
//  PrendreLaMain — conduire l'app d'un client, sous ses yeux
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Je veux entrer RÉELLEMENT. Un client me dit : sur ma TV je ne
//      trouve pas les favoris. Je lui dis : regarde ta télé. Et
//      j'appuie — chaîne, favoris, tout. Je lui montre tout. »
//
//  PUIS, LE 19/09, APRÈS L'AVOIR ESSAYÉ SUR UNE VRAIE BOX :
//
//    « Je veux que ça soit automatique. »
//    « Et plus, il va y avoir un simulateur de TV ou de téléphone :
//      où je touche, il voit où je touche. »
//
//  ---------------------------------------------------------
//  1) AUTOMATIQUE — IL N'Y A PLUS D'ÉTAPE À NE PAS OUBLIER
//  ---------------------------------------------------------
//  Avant, il fallait cliquer « Demander la main », puis attendre que le
//  client appuie « Oui » SUR SA TÉLÉCOMMANDE. Dans la vraie vie du
//  support, ça ne marche pas : le client est au téléphone, il dit
//  « oui oui vas-y » à l'oreille du support, pas à son écran. Le
//  propriétaire a lu trois « refusé » d'affilée sans comprendre
//  pourquoi — rien n'était cassé, et rien ne marchait.
//
//  Maintenant, CHAQUE BOUTON PORTE LE NOM DU SUPPORT, et le premier
//  geste ouvre la session tout seul. Plus d'étape préalable.
//
//  Ce qui n'a pas changé côté client : un bandeau rouge avec le nom de
//  qui le guide, immédiat, permanent, et un bouton Arrêter dedans.
//
//  ---------------------------------------------------------
//  2) LA MAQUETTE TACTILE — CE QU'ELLE EST, ET CE QU'ELLE N'EST PAS
//  ---------------------------------------------------------
//  ELLE N'EST PAS UNE RECOPIE DE SON ÉCRAN. Personne ne filme sa télé :
//  ni l'app, ni le hub, ni ce panneau ne voient un seul de ses pixels.
//
//  ELLE EST UN PAVÉ TACTILE. Là où le support touche, un halo rouge
//  apparaît AU MÊME ENDROIT, EN PROPORTION, sur l'écran du client. En
//  haut à droite ici = en haut à droite chez lui. C'est exactement le
//  geste qu'on fait avec le doigt en montrant une télé à quelqu'un
//  assis à côté de soi.
//
//  Le dire est important : un support qui croirait voir l'écran du
//  client lui dirait « appuie sur le bouton bleu » alors qu'il n'y a
//  pas de bouton bleu. D'où le rappel écrit, sous la maquette.
//
//  ---------------------------------------------------------
//  CE PANNEAU NE DÉCIDE RIEN
//  ---------------------------------------------------------
//  Il envoie des gestes et affiche les réponses ; il ne « sait » jamais
//  de son côté si la session est ouverte. C'est volontaire : deux
//  endroits qui croiraient connaître l'état finiraient par ne plus être
//  d'accord, et ce jour-là on piloterait l'écran de quelqu'un qui vient
//  de raccrocher.
//
//  D'où la règle d'affichage : ON N'AFFICHE QUE CE QUE L'APPAREIL A
//  RÉPONDU. Un bouton pressé n'est pas un bouton appliqué.
// =========================================================

import {
  useEffect, useRef, useState, type PointerEvent as PointerEvt,
} from 'react';
import { getCurrentUser } from '@/lib/api';
import { onRt, sendCmd, waitForAck } from '@/lib/realtime';
import { toast } from '@/components/Toast';

/// Les écrans que l'app sait ouvrir à distance. Les NOMS sont ceux du
/// code de l'app (`tv_assistance_executeur.dart`) : ce sont des
/// identifiants, pas des libellés — les renommer casserait les boutons.
const ECRANS: { nom: string; libelle: string }[] = [
  { nom: 'chaines', libelle: 'Chaînes' },
  { nom: 'favoris', libelle: 'Favoris' },
  { nom: 'reglages', libelle: 'Réglages' },
  { nom: 'apropos', libelle: 'À propos' },
  { nom: 'diagnostic', libelle: 'Boîte noire' },
];

/// CE QUE L'APPAREIL RÉPOND, EN FRANÇAIS.
///
///  L'app renvoie des identifiants courts et stables (`ecran_inconnu`,
///  `app_en_arriere_plan`…) ; la traduction vit ICI, et seulement ici.
///
///  POURQUOI PAS DE PHRASES CÔTÉ APP : une phrase gravée dans un APK
///  ne se corrige plus. Le jour où on comprend qu'une cause était mal
///  expliquée, on veut pouvoir réécrire la phrase sans attendre que
///  200 box se mettent à jour.
///
///  Un code qu'on ne connaît pas s'affiche TEL QUEL, sans être
///  maquillé : un panel plus ancien que l'app doit dire « je ne sais
///  pas ce que ça veut dire », pas inventer une explication.
const RAISONS: Record<string, string> = {
  sans_nom_de_support:
    'Ton compte n’a ni nom ni e-mail affichable — impossible de guider '
    + 'quelqu’un anonymement.',
  client_a_coupe:
    'Le client vient d’appuyer sur « Arrêter » chez lui. Son refus tient '
    + 'deux minutes — rappelle-le avant de reprendre la main.',
  autre_session_en_cours:
    'Quelqu’un d’autre a déjà la main sur cet appareil. On ne la lui '
    + 'prend pas : le client ne saurait plus qui le guide.',
  plateforme_sans_executeur:
    'Cette application ne sait pas encore ouvrir ses écrans à distance. '
    + 'Le doigt et le message, eux, marchent.',
  ecran_inconnu:
    'Cet écran n’existe pas dans la version installée chez lui.',
  app_en_arriere_plan:
    '7 MOTION n’est pas à l’écran chez lui. Demande-lui de revenir dans '
    + 'l’application, puis réessaie.',
  deja_a_l_accueil:
    'Il est déjà à l’accueil : il n’y avait rien à fermer.',
  pas_encore_branche:
    'Ce geste n’est pas encore branché dans l’app (catégorie, chaîne). '
    + 'Refusé franchement plutôt qu’ouvrir le mauvais dossier chez lui.',
  identifiant_vide: 'Identifiant de chaîne vide.',
  position_invalide: 'Position hors de l’écran — rien n’a été montré.',
  geste_inconnu:
    'Son application est plus ancienne que ce panel : elle ne connaît '
    + 'pas ce bouton. Une mise à jour de son app le rendra disponible.',
  exception:
    'Son application a buté sur une erreur en exécutant le geste. '
    + 'La boîte noire de l’appareil en garde la trace.',
};

type Ligne = { quand: string; quoi: string; ok: boolean | null; pourquoi?: string };
type Forme = 'tv' | 'phone';

export function PrendreLaMain({
  mac,
  enLigne,
  forme = 'tv',
}: {
  mac: string;
  enLigne: boolean;
  /// Donne sa SILHOUETTE à la maquette : 16/9 pour une télé, allongé
  /// pour un téléphone. Purement visuel — ce qui part sur le réseau,
  /// ce sont des fractions, pas des pixels.
  forme?: Forme;
}) {
  const [journal, setJournal] = useState<Ligne[]>([]);
  const [busy, setBusy] = useState(false);

  const moi = getCurrentUser();
  //  QUI GUIDE — le client le lira en toutes lettres dans son bandeau.
  //  Un geste anonyme est refusé par l'app, et c'est bien : un bandeau
  //  qui dirait « quelqu'un vous aide » serait plus inquiétant qu'utile.
  const nomSupport = (moi?.name || moi?.email || '').toString().trim();

  //  [bloquant] grise les boutons le temps de l'accusé de réception.
  //  C'est bon pour « ouvrir Réglages » : deux clics coup sur coup
  //  ouvriraient deux fois l'écran chez le client.
  //
  //  C'est MAUVAIS pour le doigt. Montrer quelque chose, c'est bouger
  //  le doigt : si chaque appui gelait la maquette jusqu'à la réponse
  //  de la box (jusqu'à 8 secondes), on ne pourrait plus rien montrer
  //  du tout. Le pointeur passe donc en non bloquant — au pire deux
  //  halos se suivent, et c'est exactement ce qu'on veut.
  async function envoyer(
    quoi: string,
    payload: Record<string, unknown>,
    opts: { bloquant?: boolean } = {},
  ) {
    if (!enLigne) {
      toast(
        'Cet appareil est hors ligne. Prendre la main suppose que son '
        + 'app est ouverte — demande-lui de la lancer.',
        'warning',
      );
      return;
    }
    const bloquant = opts.bloquant !== false;
    if (bloquant) setBusy(true);
    const t = new Date().toLocaleTimeString();
    try {
      //  LE NOM PART AVEC CHAQUE GESTE, pas seulement avec le bouton
      //  « Prendre la main ». C'est ce qui rend la prise automatique
      //  possible : le premier geste ouvre la session au nom de
      //  celui-là, et le bandeau apparaît chez le client dans la même
      //  seconde.
      const id = sendCmd(mac, 'assist', { support: nomSupport, ...payload });
      const ack = await waitForAck(id, 8000);
      //  ON AFFICHE CE QUE L'APPAREIL A RÉPONDU, PAS CE QU'ON ESPÈRE.
      //  `null` = pas de réponse dans les temps : on ne conclut ni
      //  réussite ni échec, on le dit tel quel.
      const ok = ack ? !!ack.ok : null;
      setJournal((j) => [
        { quand: t, quoi, ok, pourquoi: ack?.error },
        ...j,
      ].slice(0, 12));
      if (ok === false) {
        const code = ack?.error || '';
        toast(
          RAISONS[code]
            || `L’appareil a refusé${code ? ` : ${code}` : ''}.`,
          'warning',
        );
      }
    } catch {
      setJournal((j) => [{ quand: t, quoi, ok: null }, ...j].slice(0, 12));
    } finally {
      if (bloquant) setBusy(false);
    }
  }

  const btn =
    'rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30 disabled:opacity-50';

  return (
    <section className="rounded-xl border border-white/10 bg-obsidian p-3">
      <h3 className="text-sm font-semibold">Prendre la main</h3>
      <p className="mt-1 text-[11px] leading-relaxed text-ink-tertiary">
        Appuie directement sur ce que tu veux : <b>la session s’ouvre
        toute seule</b> au premier geste. Chez lui, un bandeau rouge
        apparaît aussitôt avec ton nom et un bouton <b>Arrêter</b> — il
        voit donc toujours que tu es là, et il peut couper à la seconde.
        Ça se termine tout seul au bout de 30 minutes.
      </p>

      {/* LE NOM MANQUANT, DIT AVANT LE PREMIER CLIC. Sans nom, l'app
          refuse tout — autant le savoir maintenant qu'après trois
          boutons rouges. */}
      {!nomSupport && (
        <p className="mt-2 rounded-lg border border-warning/40 bg-warning/10 px-2 py-1.5 text-[11px] text-warning">
          Ton compte n’a ni nom ni e-mail affichable. L’app refusera
          tous les gestes : on ne guide pas quelqu’un anonymement.
        </p>
      )}

      <div className="mt-3 flex flex-wrap gap-1.5">
        <button
          type="button"
          disabled={busy}
          onClick={() => {
            void envoyer('Prendre la main', { geste: 'prendre' });
          }}
          className="rounded-md bg-accent px-3 py-1 text-xs font-semibold text-black disabled:opacity-50"
        >
          Prendre la main
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => { void envoyer('Rendre la main', { geste: 'fin' }); }}
          className={btn}
        >
          Rendre la main
        </button>
      </div>

      <EcranTactile busy={busy} forme={forme} mac={mac} onEnvoyer={envoyer} />

      <p className="mt-3 text-[11px] font-semibold text-ink-secondary">
        Ouvrir un écran chez lui
      </p>
      <div className="mt-1.5 flex flex-wrap gap-1.5">
        {ECRANS.map((e) => (
          <button
            key={e.nom}
            type="button"
            disabled={busy}
            onClick={() => {
              void envoyer(`Ouvrir « ${e.libelle} »`, {
                geste: 'ouvrir',
                nom: e.nom,
              });
            }}
            className={btn}
          >
            {e.libelle}
          </button>
        ))}
        <button
          type="button"
          disabled={busy}
          onClick={() => { void envoyer('Retour', { geste: 'retour' }); }}
          className={btn}
        >
          ← Retour
        </button>
      </div>

      <p className="mt-3 text-[11px] font-semibold text-ink-secondary">
        Mettre / retirer un favori
      </p>
      <FavoriRapide busy={busy} onEnvoyer={envoyer} />

      {/* LE JOURNAL — ce que l'APPAREIL a répondu, pas ce qu'on a
          cliqué. C'est la différence entre « envoyé » et « fait », et
          elle a déjà coûté une journée sur ce projet. */}
      {journal.length > 0 && (
        <div className="mt-4 rounded-lg border border-white/10 bg-midnight p-2">
          <p className="mb-1 text-[10px] uppercase tracking-wider text-ink-tertiary">
            Ce que l’appareil a répondu
          </p>
          <ul className="space-y-1 text-[11px]">
            {journal.map((l, i) => (
              <li key={i}>
                <div className="flex items-baseline gap-2">
                  <span className="text-ink-tertiary">{l.quand}</span>
                  <span className="flex-1 truncate">{l.quoi}</span>
                  <span
                    className={
                      l.ok === true
                        ? 'text-success'
                        : l.ok === false
                          ? 'text-red-300'
                          : 'text-warning'
                    }
                  >
                    {l.ok === true
                      ? 'fait'
                      : l.ok === false
                        ? 'refusé'
                        : 'pas de réponse'}
                  </span>
                </div>
                {/* LA CAUSE EN CLAIR, SOUS LA LIGNE. Avant le 19/09 on
                    affichait le code brut entre parenthèses
                    (« refuse_ou_echoue ») : exact, illisible, et sans
                    rien à faire ensuite. */}
                {l.ok === false && l.pourquoi && (
                  <p className="pl-1 text-[10px] leading-snug text-ink-tertiary">
                    {RAISONS[l.pourquoi] || l.pourquoi}
                  </p>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      <p className="mt-3 text-[11px] leading-relaxed text-ink-tertiary">
        Tu conduis <b>son application</b>, pas son téléphone : il faut
        qu’il ait 7 MOTION ouvert. Il voit un bandeau rouge avec ton nom
        pendant toute la session, et il y lit que tu vois son écran. Tu
        ne peux ni payer, ni toucher à son mot de passe ou à son code
        parental.
      </p>
    </section>
  );
}

/// LA MAQUETTE TACTILE — « où je touche, il voit où je touche ».
///
///  Le support touche ici ; un halo rouge se pose au même endroit, EN
///  PROPORTION, sur l'écran du client. Ce cadre n'affiche donc rien de
///  ce que le client regarde : c'est un pavé tactile, pas une recopie
///  d'écran, et le texte sous le cadre le dit franchement.
///
///  Le point qu'on voit ici est LOCAL : il montre au support où il
///  vient de toucher. Ce qui compte vraiment — le halo chez le client —
///  est confirmé par le journal, comme tous les autres gestes.
function EcranTactile({
  busy,
  forme,
  mac,
  onEnvoyer,
}: {
  busy: boolean;
  forme: Forme;
  mac: string;
  onEnvoyer: (
    quoi: string,
    payload: Record<string, unknown>,
    opts?: { bloquant?: boolean },
  ) => Promise<void>;
}) {
  const [silhouette, setSilhouette] = useState<Forme>(forme);
  const [point, setPoint] = useState<{ x: number; y: number } | null>(null);
  const [phrase, setPhrase] = useState('C’est ici');
  const cadre = useRef<HTMLDivElement | null>(null);

  //  L'ÉCRAN DU CLIENT, EN VRAI. L'app en envoie une image toutes les
  //  deux secondes pendant la session, et seulement pendant.
  //
  //  ON N'AFFICHE QUE CE QU'ON A REÇU. Pas d'image, pas de cadre
  //  inventé : le quadrillage reste, avec la phrase qui explique
  //  pourquoi il n'y a rien. Dessiner une maquette approximative de
  //  son écran serait pire que le vide — le support montrerait du
  //  doigt un bouton qui n'est pas là.
  const [vue, setVue] = useState<{ png: string; at: number } | null>(null);

  useEffect(() => {
    if (!mac) return undefined;
    return onRt('screen', (e: { mac?: string; png?: string }) => {
      // Le hub diffuse à TOUS les panels connectés : on ne garde que
      // l'appareil ouvert ici. Sans ce filtre, ouvrir deux fiches
      // ferait clignoter l'une avec l'écran de l'autre.
      if (e?.mac !== mac || !e?.png) return;
      setVue({ png: e.png, at: Date.now() });
    });
  }, [mac]);

  //  UNE IMAGE VIEILLE N'EST PLUS UNE IMAGE. Passé 10 s sans rien
  //  recevoir (session finie, app partie en arrière-plan, réseau
  //  coupé), on l'efface. La garder afficherait un écran figé que le
  //  support croirait actuel — il dirait « tu es toujours sur les
  //  réglages ? » alors que le client est ailleurs depuis longtemps.
  useEffect(() => {
    if (!vue) return undefined;
    const t = setTimeout(() => setVue(null), 10000);
    return () => clearTimeout(t);
  }, [vue]);

  function toucher(e: PointerEvt<HTMLDivElement>) {
    const el = cadre.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return;
    //  DES FRACTIONS, JAMAIS DES PIXELS. Cette maquette fait quelques
    //  centaines de points ; sa télé en fait quelques milliers, et la
    //  session suivante sera peut-être sur un téléphone. Des pixels
    //  pointeraient à côté — l'app refuserait, ou pire, montrerait un
    //  coin que personne n'a désigné.
    const x = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    const y = Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
    setPoint({ x, y });
    void onEnvoyer(
      `Doigt en ${Math.round(x * 100)} % / ${Math.round(y * 100)} %`,
      { geste: 'pointeur', x, y, phrase: phrase.trim() },
      { bloquant: false },
    );
  }

  return (
    <>
      <div className="mt-3 flex items-baseline justify-between gap-2">
        <p className="text-[11px] font-semibold text-ink-secondary">
          Lui montrer où appuyer
        </p>
        <div className="flex gap-1">
          {(['tv', 'phone'] as Forme[]).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setSilhouette(f)}
              className={
                'rounded px-2 py-0.5 text-[10px] '
                + (silhouette === f
                  ? 'bg-accent text-black'
                  : 'border border-white/10 text-ink-tertiary hover:border-white/30')
              }
            >
              {f === 'tv' ? 'Télé' : 'Téléphone'}
            </button>
          ))}
        </div>
      </div>

      <div
        ref={cadre}
        onPointerDown={toucher}
        className={
          'relative mt-1.5 w-full cursor-crosshair select-none touch-none '
          + 'overflow-hidden rounded-lg border border-white/15 bg-midnight '
          + (silhouette === 'tv' ? 'aspect-video max-w-md' : 'max-w-[190px]')
        }
        style={silhouette === 'phone' ? { aspectRatio: '9 / 19.5' } : undefined}
      >
        {/* SON ÉCRAN, s'il en arrive une image. */}
        {vue && (
          <img
            src={`data:image/png;base64,${vue.png}`}
            alt="Écran du client"
            draggable={false}
            className="pointer-events-none absolute inset-0 h-full w-full object-contain"
          />
        )}

        {/* Des repères aux tiers, utiles TANT QU'ON NE VOIT RIEN :
            sans eux, « un peu à droite » ne veut rien dire quand on
            vise à l'aveugle. Dès que l'image arrive, ils s'effacent —
            un quadrillage par-dessus son écran gênerait la lecture. */}
        {!vue && (
          <div className="pointer-events-none absolute inset-0">
            <div className="absolute left-1/3 top-0 h-full w-px bg-white/5" />
            <div className="absolute left-2/3 top-0 h-full w-px bg-white/5" />
            <div className="absolute left-0 top-1/3 h-px w-full bg-white/5" />
            <div className="absolute left-0 top-2/3 h-px w-full bg-white/5" />
          </div>
        )}

        {point && (
          <div
            className="pointer-events-none absolute -ml-3 -mt-3 h-6 w-6 rounded-full border-2 border-accent bg-accent/30"
            style={{ left: `${point.x * 100}%`, top: `${point.y * 100}%` }}
          />
        )}

        {!vue && !point && (
          <p className="pointer-events-none absolute inset-0 flex items-center justify-center px-4 text-center text-[10px] leading-snug text-ink-tertiary">
            Touche ici : le même endroit s’allume sur son écran.
          </p>
        )}

        {/* LE VOYANT « EN DIRECT » — il ne s'allume QUE si une image
            est arrivée dans les 10 dernières secondes. Un voyant qui
            resterait vert sur une image figée est exactement le genre
            de mensonge qui coûte une journée. */}
        {vue && (
          <span className="pointer-events-none absolute right-1.5 top-1.5 inline-flex items-center gap-1 rounded bg-black/60 px-1.5 py-0.5 text-[9px] text-success">
            <span className="h-1 w-1 animate-pulse rounded-full bg-success" />
            en direct
          </span>
        )}
      </div>

      <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
        <input
          value={phrase}
          onChange={(e) => setPhrase(e.target.value)}
          placeholder="Ce qu’il doit lire (facultatif)"
          className="w-56 rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs outline-none focus:border-accent/50"
        />
        <button
          type="button"
          disabled={busy || !phrase.trim()}
          onClick={() => {
            void onEnvoyer(`Message « ${phrase.trim()} »`, {
              geste: 'designer',
              cible: '',
              phrase: phrase.trim(),
            });
          }}
          className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30 disabled:opacity-50"
        >
          Afficher seulement
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => {
            setPoint(null);
            void onEnvoyer('Effacer', { geste: 'effacer' });
          }}
          className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30 disabled:opacity-50"
        >
          Effacer
        </button>
      </div>

      {/* LA SEULE LIMITE QUI PEUT TROMPER LE SUPPORT, DITE EN CLAIR.
          Un support qui verrait du noir et croirait la chaîne plantée
          raccrocherait après avoir « diagnostiqué » une panne qui
          n'existe pas. */}
      <p className="mt-1.5 text-[10px] leading-snug text-ink-tertiary">
        {vue ? (
          <>
            Tu vois <b>ses menus</b>, rafraîchis toutes les 2 secondes.
            La <b>vidéo sort noire</b> — Android la dessine hors de
            l’application, on ne peut pas la capturer. Un rectangle noir
            ne veut donc <b>pas</b> dire que sa chaîne est plantée.
          </>
        ) : (
          <>
            Pas encore d’image : elle n’arrive que pendant une session,
            et seulement depuis une app en <b>198883 ou plus</b>. En
            attendant, le cadre reste un pavé tactile — en haut à droite
            ici = en haut à droite chez lui.
          </>
        )}{' '}
        Le doigt s’efface tout seul au bout de 12 secondes.
      </p>
    </>
  );
}

/// Un identifiant de chaîne + le bouton qui bascule son favori. C'est
/// le geste exact de l'exemple du propriétaire.
function FavoriRapide({
  busy,
  onEnvoyer,
}: {
  busy: boolean;
  onEnvoyer: (quoi: string, payload: Record<string, unknown>) => Promise<void>;
}) {
  const [id, setId] = useState('');
  return (
    <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
      <input
        value={id}
        onChange={(e) => setId(e.target.value)}
        placeholder="Identifiant de la chaîne"
        className="w-52 rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs outline-none focus:border-accent/50"
      />
      <button
        type="button"
        disabled={busy || !id.trim()}
        onClick={() => {
          void onEnvoyer(`Favori « ${id.trim()} »`, {
            geste: 'favori',
            id_cible: id.trim(),
          });
        }}
        className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30 disabled:opacity-50"
      >
        ♥ Basculer
      </button>
    </div>
  );
}
