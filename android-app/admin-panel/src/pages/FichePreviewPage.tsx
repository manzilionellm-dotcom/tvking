// Aperçu local des fiches, avec des données clairement fictives.
// Aucun appel réseau. L'interrupteur de production n'est pas modifié :
// le masquage reste un état local à cette page, coupé au départ.
import { useState } from 'react';
import {
  actionsInertes,
  actionsPour,
  apercuesListes,
  cibleAppareil,
  cibleClient,
  cibleListe,
  etatAction,
  type FicheCible,
} from '@/lib/fiches';
import {
  CorpsAppareil,
  CorpsClient,
  CorpsListe,
  FichePanneau,
  type AppareilVue,
  type ClientVue,
} from '@/components/fiches/FicheUi';

const APPAREIL: AppareilVue = {
  mac: 'MK:AA:BB:CC:DD:01',
  client: 'Client Exemple',
  customerId: 'cus_exemple',
  plateforme: 'TV',
  modele: 'Box démo',
  android: 'Android 11',
  version: '100',
  etiquette: 'Salon',
  derniereVue: 'à l’instant',
  premiereVue: '01/01/2026',
  acces: 'Essai',
  blockStatus: 'active',
  abonnement: 'Aucun abonnement',
  abonnementOk: false,
  presence: 'Hors ligne',
  enLigne: false,
  listes: apercuesListes([
    { type: 'm3u', label: 'Liste exemple' },
    { type: 'xtream', label: 'Second exemple', username: 'abonne-exemple' },
  ], 'panel'),
  locales: apercuesListes([
    { type: 'm3u', name: 'Liste sur la box' },
  ], 'locale'),
};

const CLIENT: ClientVue = {
  id: 'cus_exemple',
  nom: 'Client Exemple',
  email: 'client@example.invalid',
  telephone: '0600000000',
  notes: 'Note fictive, pour l’aperçu.',
  appareils: [{ id: 'dev_exemple', mac: APPAREIL.mac, label: 'Salon' }],
};

export function FichePreviewPage() {
  const [pile, setPile] = useState<FicheCible[]>([]);
  const [listeMasquee, setListeMasquee] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [nom, setNom] = useState(CLIENT.nom);
  const [telephone, setTelephone] = useState(CLIENT.telephone);
  const [notes, setNotes] = useState(CLIENT.notes);
  const courant = pile.length ? pile[pile.length - 1] : null;

  function open(cible: FicheCible) {
    setMessage(null);
    setPile((p) => [...p, cible]);
  }

  function onAction(id: string) {
    if (!courant) return;
    const origin = courant.listOrigin === 'locale' ? 'locale' : 'panel';
    const action = actionsPour(courant.kind, origin).find((a) => a.id === id);
    if (!action) return;
    const etat = etatAction(action, { listeMasquee });
    if (etat !== 'prete') return;
    if (id === 'notes-client') {
      const cible = cibleClient(CLIENT.id);
      if (cible) open(cible);
      return;
    }
    if (id === 'ouvrir-appareil') {
      const cible = cibleAppareil({ deviceId: 'dev_exemple', mac: APPAREIL.mac });
      if (cible) open(cible);
      return;
    }
    if (id === 'copier-mac' || id === 'copier-client' || id === 'copier-liste') {
      setMessage('Identifiant copié dans cet aperçu. Aucun serveur contacté.');
      return;
    }
    setMessage(`Aperçu : « ${action.label} » appellerait ${action.route}. Rien n’a été envoyé.`);
  }

  const origin = courant?.listOrigin === 'locale' ? 'locale' : 'panel';
  const liste = !courant || courant.kind !== 'liste'
    ? null
    : (origin === 'locale' ? APPAREIL.locales[courant.listIndex ?? 0] : APPAREIL.listes[courant.listIndex ?? 0]) ?? null;
  const inertes = actionsInertes({
    deviceId: 'dev_exemple',
    mac: APPAREIL.mac,
    customerId: CLIENT.id,
    blockStatus: 'active',
    canActivate: true,
    canSources: true,
    superAdmin: true,
    listeAbsente: courant?.kind === 'liste' && !liste,
  });

  return (
    <div className="min-h-screen bg-obsidian p-6 text-ink-primary">
      <h1 className="text-xl font-semibold">Aperçu des fiches — données fictives</h1>
      <p className="mt-2 max-w-2xl text-sm text-ink-secondary">
        Ces adresses n’existent pas. Aucun appel n’est envoyé.
        Dans le panel réel, l’interrupteur « fiches cliquables » est coupé par défaut
        (Mon compte). Ici il est allumé seulement pour montrer les fiches.
      </p>

      <table className="mt-6 w-full max-w-3xl text-sm">
        <thead className="text-left text-[10px] uppercase tracking-widest text-ink-tertiary">
          <tr>
            <th className="px-3 py-2">Élément</th>
            <th className="px-3 py-2">Adresse</th>
          </tr>
        </thead>
        <tbody>
          <tr className="border-t border-white/10">
            <td className="px-3 py-3">Appareil</td>
            <td className="px-3 py-3">
              <button
                type="button"
                data-testid="apercu-appareil"
                className="font-mono text-xs text-accent underline-offset-2 hover:underline"
                onClick={() => {
                  const c = cibleAppareil({ deviceId: 'dev_exemple', mac: APPAREIL.mac });
                  if (c) open(c);
                }}
              >
                {APPAREIL.mac}
              </button>
            </td>
          </tr>
          <tr className="border-t border-white/10">
            <td className="px-3 py-3">Client</td>
            <td className="px-3 py-3">
              <button
                type="button"
                data-testid="apercu-client"
                className="underline-offset-2 hover:underline"
                onClick={() => {
                  const c = cibleClient(CLIENT.id);
                  if (c) open(c);
                }}
              >
                {CLIENT.nom}
              </button>
            </td>
          </tr>
          <tr className="border-t border-white/10">
            <td className="px-3 py-3">Liste</td>
            <td className="px-3 py-3">
              <button
                type="button"
                data-testid="apercu-liste"
                className="underline-offset-2 hover:underline"
                onClick={() => {
                  const c = cibleListe({ deviceId: 'dev_exemple', mac: APPAREIL.mac, index: 0 });
                  if (c) open(c);
                }}
              >
                Liste exemple
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      {courant && (
        <FichePanneau
          testId={`fiche-${courant.kind}`}
          kind={courant.kind}
          origin={origin}
          titre={courant.kind === 'client' ? 'Fiche client' : courant.kind === 'liste' ? 'Fiche liste' : 'Fiche appareil'}
          sousTitre={courant.kind === 'client' ? CLIENT.nom : (liste?.label || APPAREIL.mac)}
          badge={courant.kind === 'appareil' ? 'active' : undefined}
          message={message}
          listeMasquee={listeMasquee}
          onToggleMasquee={setListeMasquee}
          inertes={inertes}
          titreInerte={(id) => (id === 'reactiver' ? 'Déjà dans cet état.' : undefined)}
          onAction={onAction}
          onClose={() => { setPile([]); setMessage(null); }}
          onBack={pile.length > 1 ? () => { setPile((p) => p.slice(0, -1)); setMessage(null); } : undefined}
        >
          {courant.kind === 'appareil' && (
            <CorpsAppareil
              vue={APPAREIL}
              onClient={() => {
                const c = cibleClient(CLIENT.id);
                if (c) open(c);
              }}
              onListe={(index, origine) => {
                const c = cibleListe({ deviceId: 'dev_exemple', mac: APPAREIL.mac, index, origin: origine });
                if (c) open(c);
              }}
            />
          )}
          {courant.kind === 'client' && (
            <CorpsClient
              vue={CLIENT}
              nom={nom}
              telephone={telephone}
              notes={notes}
              onNom={setNom}
              onTelephone={setTelephone}
              onNotes={setNotes}
              onAppareil={() => {
                const c = cibleAppareil({ deviceId: 'dev_exemple', mac: APPAREIL.mac });
                if (c) open(c);
              }}
            />
          )}
          {courant.kind === 'liste' && <CorpsListe liste={liste} />}
        </FichePanneau>
      )}
    </div>
  );
}
