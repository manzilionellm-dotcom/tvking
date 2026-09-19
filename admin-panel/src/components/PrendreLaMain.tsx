// =========================================================
//  PrendreLaMain — conduire l'app d'un client, s'il l'autorise
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) :
//
//    « Je veux entrer RÉELLEMENT. Un client me dit : sur ma TV je ne
//      trouve pas les favoris. Je lui dis : regarde ta télé. Et
//      j'appuie — chaîne, favoris, tout. Je lui montre tout. »
//
//  ---------------------------------------------------------
//  COMMENT ÇA MARCHE, EN UNE PHRASE
//  ---------------------------------------------------------
//  On demande. Le client voit une question sur SA télé, avec le nom de
//  qui demande. S'il accepte, un bandeau rouge s'installe chez lui
//  pendant toute la session, avec un bouton « Arrêter » — et chaque
//  bouton d'ici fait bouger son écran pour de vrai.
//
//  ---------------------------------------------------------
//  CE PANNEAU NE DÉCIDE RIEN
//  ---------------------------------------------------------
//  Le consentement vit DANS L'APP du client. Ce panneau envoie des
//  demandes et affiche les réponses ; il ne « sait » jamais de son
//  côté si la session est ouverte. C'est volontaire : deux endroits
//  qui croiraient connaître l'état finiraient par ne plus être
//  d'accord, et ce jour-là on piloterait l'écran de quelqu'un qui
//  vient de raccrocher.
//
//  D'où la règle d'affichage : ON N'AFFICHE QUE CE QUE L'APPAREIL A
//  RÉPONDU. Un bouton pressé n'est pas un bouton appliqué — c'est
//  l'accusé de réception qui le dit, et rien d'autre.
// =========================================================

import { useState } from 'react';
import { getCurrentUser } from '@/lib/api';
import { sendCmd, waitForAck } from '@/lib/realtime';
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

type Ligne = { quand: string; quoi: string; ok: boolean | null; pourquoi?: string };

export function PrendreLaMain({ mac, enLigne }: { mac: string; enLigne: boolean }) {
  const [journal, setJournal] = useState<Ligne[]>([]);
  const [busy, setBusy] = useState(false);

  const moi = getCurrentUser();
  //  QUI DEMANDE — le client le verra en toutes lettres. Une demande
  //  anonyme est refusée par l'app, et c'est bien : « quelqu'un veut
  //  prendre la main » n'est pas une question à laquelle on peut
  //  répondre.
  const nomSupport = (moi?.name || moi?.email || 'Le support').toString();

  async function envoyer(quoi: string, payload: Record<string, unknown>) {
    if (!enLigne) {
      toast(
        'Cet appareil est hors ligne. Prendre la main suppose que son '
        + 'app est ouverte — demande-lui de la lancer.',
        'warning',
      );
      return;
    }
    setBusy(true);
    const t = new Date().toLocaleTimeString();
    try {
      const id = sendCmd(mac, 'assist', payload);
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
        toast(
          ack?.error === 'demande_refusee'
            ? 'Une demande ou une session est déjà en cours sur cet appareil.'
            : 'L’appareil a REFUSÉ. Le plus souvent : le client n’a pas '
              + '(encore) accepté, ou la session s’est terminée.',
          'warning',
        );
      }
    } catch {
      setJournal((j) => [{ quand: t, quoi, ok: null }, ...j].slice(0, 12));
    } finally {
      setBusy(false);
    }
  }

  const btn =
    'rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30 disabled:opacity-50';

  return (
    <section className="rounded-xl border border-white/10 bg-obsidian p-3">
      <h3 className="text-sm font-semibold">Prendre la main</h3>
      <p className="mt-1 text-[11px] leading-relaxed text-ink-tertiary">
        Le client voit une question sur son écran, avec ton nom. S’il
        accepte, un bandeau rouge reste affiché chez lui pendant toute la
        session, avec un bouton <b>Arrêter</b> — et ce que tu appuies ici
        bouge vraiment sur sa télé. Ça se coupe tout seul au bout de
        30 minutes.
      </p>

      <div className="mt-3 flex flex-wrap gap-1.5">
        <button
          type="button"
          disabled={busy}
          onClick={() => {
            void envoyer('Demande d’assistance', {
              geste: 'demander',
              support: nomSupport,
            });
          }}
          className="rounded-md bg-accent px-3 py-1 text-xs font-semibold text-black disabled:opacity-50"
        >
          Demander la main
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => { void envoyer('Fin de session', { geste: 'fin' }); }}
          className={btn}
        >
          Rendre la main
        </button>
      </div>

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

      <p className="mt-3 text-[11px] font-semibold text-ink-secondary">
        Lui montrer où appuyer
      </p>
      <DesignerRapide busy={busy} onEnvoyer={envoyer} />

      {/* LE JOURNAL — ce que l'APPAREIL a répondu, pas ce qu'on a
          cliqué. C'est la différence entre « envoyé » et « fait », et
          elle a déjà coûté une journée sur ce projet. */}
      {journal.length > 0 && (
        <div className="mt-4 rounded-lg border border-white/10 bg-midnight p-2">
          <p className="mb-1 text-[10px] uppercase tracking-wider text-ink-tertiary">
            Ce que l’appareil a répondu
          </p>
          <ul className="space-y-0.5 text-[11px]">
            {journal.map((l, i) => (
              <li key={i} className="flex items-baseline gap-2">
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
                      ? `refusé${l.pourquoi ? ` (${l.pourquoi})` : ''}`
                      : 'pas de réponse'}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <p className="mt-3 text-[11px] leading-relaxed text-ink-tertiary">
        Tu conduis <b>son application</b>, pas son téléphone : il faut
        qu’il ait 7 MOTION ouvert. Tu ne vois pas son écran — tu vois ce
        que l’appareil répond à chaque bouton. Et tu ne peux ni payer, ni
        toucher à son mot de passe ou à son code parental.
      </p>
    </section>
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

/// Éclairer un élément chez lui avec une phrase. À utiliser APRÈS
/// avoir montré : il refait tout seul, et il retient.
function DesignerRapide({
  busy,
  onEnvoyer,
}: {
  busy: boolean;
  onEnvoyer: (quoi: string, payload: Record<string, unknown>) => Promise<void>;
}) {
  const [phrase, setPhrase] = useState('C’est ici');
  return (
    <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
      <input
        value={phrase}
        onChange={(e) => setPhrase(e.target.value)}
        placeholder="Ce qu’il doit lire"
        className="w-64 rounded-md border border-white/10 bg-obsidian px-2 py-1 text-xs outline-none focus:border-accent/50"
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
        Afficher
      </button>
      <button
        type="button"
        disabled={busy}
        onClick={() => { void onEnvoyer('Effacer le message', { geste: 'effacer' }); }}
        className="rounded-md border border-white/10 px-2.5 py-1 text-xs hover:border-white/30 disabled:opacity-50"
      >
        Effacer
      </button>
    </div>
  );
}
