// Hôte des fiches : charge l'overview existant et n'appelle que les
// routes déjà servies. Le masquage d'une liste ne part jamais.
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { confirmAction } from '@/components/confirm';
import { FLAG_LISTE_MASQUEE } from '@/lib/flags';
import {
  apercuesListes,
  actionsInertes,
  cibleAppareil,
  cibleClient,
  cibleListe,
  cheminFiche,
  joursEssaiValides,
  planHideSource,
  trouverAppareil,
  type FicheCible,
} from '@/lib/fiches';
import { planRemoveSource } from '@/lib/sources';
import {
  activateApi,
  ApiError,
  customersApi,
  devicesApi,
  getCurrentUser,
  isAbortError,
  sourcesApi,
  userCan,
  type Customer,
  type Device,
  type DeviceOverview,
} from '@/lib/api';
import { PANEL_POLL_MS, shouldApplyPollResult } from '@/lib/live-sync';
import { expiryPhrase, readListPage } from '@/lib/robust';
import { formatDateTime } from '@/lib/utils';
import { FicheProvider } from './fiche-context';
import {
  CorpsAppareil,
  CorpsClient,
  CorpsListe,
  FichePanneau,
  type AppareilVue,
  type ClientVue,
} from './FicheUi';
import { usePanelFlag } from './usePanelFlag';

const PLANS: { id: string; label: string }[] = [
  { id: 'monthly', label: '1 mois' },
  { id: 'quarterly', label: '3 mois' },
  { id: 'biannual', label: '6 mois' },
  { id: 'yearly', label: '1 an' },
  { id: 'lifetime', label: 'À vie' },
];

const PLAN_LABELS: Record<string, string> = {
  ...Object.fromEntries(PLANS.map((p) => [p.id, p.label])),
  '1m': '1 mois',
  '3m': '3 mois',
  '6m': '6 mois',
  '1y': '1 an',
};

export function FicheHost({
  children,
  onLogout,
}: {
  children: ReactNode;
  onLogout: () => void;
}) {
  const [pile, setPile] = useState<FicheCible[]>([]);
  const open = useCallback((cible: FicheCible) => {
    setPile((p) => [...p, cible]);
  }, []);
  const close = useCallback(() => setPile([]), []);
  const back = useCallback(() => {
    setPile((p) => (p.length <= 1 ? [] : p.slice(0, -1)));
  }, []);
  const courant = pile.length ? pile[pile.length - 1] : null;

  return (
    <FicheProvider open={open}>
      {children}
      {courant && (
        <FicheLive
          key={cheminFiche(courant)}
          cible={courant}
          onClose={close}
          onBack={pile.length > 1 ? back : undefined}
          onOpen={open}
          onLogout={onLogout}
        />
      )}
    </FicheProvider>
  );
}

async function chargerAppareil(cible: FicheCible): Promise<{ device: Device | null; overview: DeviceOverview | null }> {
  let overview: DeviceOverview | null = null;
  let mac = cible.mac;
  if (cible.deviceId) {
    overview = await devicesApi.overview(cible.deviceId);
    mac = overview.mac || mac;
  }
  let device: Device | null = null;
  if (mac) {
    const page = await devicesApi.list(mac, { limit: 20, offset: 0 });
    device = trouverAppareil(readListPage<Device>(page).items, {
      deviceId: cible.deviceId,
      mac,
    });
  }
  if (!overview && device) overview = await devicesApi.overview(device.id);
  return { device, overview };
}

function FicheLive({
  cible,
  onClose,
  onBack,
  onOpen,
  onLogout,
}: {
  cible: FicheCible;
  onClose: () => void;
  onBack?: () => void;
  onOpen: (cible: FicheCible) => void;
  onLogout: () => void;
}) {
  const navigate = useNavigate();
  const [listeMasquee, setListeMasquee] = usePanelFlag(FLAG_LISTE_MASQUEE);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [reload, setReload] = useState(0);
  const [device, setDevice] = useState<Device | null>(null);
  const [overview, setOverview] = useState<DeviceOverview | null>(null);
  const [customer, setCustomer] = useState<Customer | null>(null);
  const [appareils, setAppareils] = useState<ClientVue['appareils']>([]);
  const [nom, setNom] = useState('');
  const [telephone, setTelephone] = useState('');
  const [notes, setNotes] = useState('');
  const [planOuvert, setPlanOuvert] = useState(false);
  const [plan, setPlan] = useState('yearly');
  const [essaiOuvert, setEssaiOuvert] = useState(false);
  const [jours, setJours] = useState('7');
  const deviceIdRef = useRef<string | null>(cible.deviceId || null);
  const seq = useRef(0);
  const applied = useRef(0);

  useEffect(() => {
    let alive = true;
    seq.current = 0;
    applied.current = 0;
    const pull = (first: boolean) => {
      const my = ++seq.current;
      if (first) setLoading(true);
      const run = async () => {
        if (!first && deviceIdRef.current && cible.kind !== 'client') {
          const ov = await devicesApi.overview(deviceIdRef.current);
          return { kind: 'poll' as const, overview: ov };
        }
        if (cible.kind === 'client') {
          if (!cible.customerId) throw new ApiError(404, 'not_found', 'Client introuvable.');
          const [c, d] = await Promise.all([
            customersApi.get(cible.customerId),
            customersApi.devices(cible.customerId),
          ]);
          return { kind: 'client' as const, customer: c, appareils: d.items || [] };
        }
        const loaded = await chargerAppareil(cible);
        return { kind: 'appareil' as const, ...loaded };
      };
      run()
        .then((r) => {
          if (!alive || !shouldApplyPollResult(my, applied.current)) return;
          applied.current = my;
          if (r.kind === 'poll') {
            setOverview(r.overview);
            setErr(null);
            return;
          }
          if (r.kind === 'client') {
            setCustomer(r.customer);
            setNom(r.customer.name || '');
            setTelephone(r.customer.phone || '');
            setNotes(r.customer.notes || '');
            setAppareils(r.appareils.map((d) => ({
              id: d.id,
              mac: d.mac,
              label: d.label || '',
            })));
            setErr(null);
            return;
          }
          deviceIdRef.current = r.device?.id || cible.deviceId || null;
          setDevice(r.device);
          setOverview(r.overview);
          setErr(null);
        })
        .catch((e: unknown) => {
          if (!alive || isAbortError(e)) return;
          if (!shouldApplyPollResult(my, applied.current)) return;
          if (e instanceof ApiError && e.status === 401) { onLogout(); return; }
          setErr(e instanceof ApiError ? e.message : 'Échec.');
        })
        .finally(() => {
          // Le sondage suivant ne doit pas laisser le premier chargement
          // coincé sur « en cours ».
          if (alive && first) setLoading(false);
        });
    };
    pull(true);
    const timer = cible.kind === 'client' ? null : setInterval(() => pull(false), PANEL_POLL_MS);
    return () => {
      alive = false;
      if (timer) clearInterval(timer);
    };
  }, [cible, onLogout, reload]);

  const user = getCurrentUser();
  const mac = device?.mac || overview?.mac || cible.mac || '';
  const deviceId = device?.id || cible.deviceId || deviceIdRef.current;
  const customerId = cible.kind === 'client' ? cible.customerId || null : device?.customer_id || null;
  const origin = cible.listOrigin === 'locale' ? 'locale' : 'panel';
  const vue = versVue(device, overview, mac);
  const liste = cible.kind !== 'liste'
    ? null
    : (origin === 'locale' ? vue.locales[cible.listIndex ?? 0] : vue.listes[cible.listIndex ?? 0]) ?? null;

  const inertes = actionsInertes({
    deviceId,
    mac,
    customerId,
    blockStatus: device?.block_status,
    canActivate: userCan(user, 'activate'),
    canSources: userCan(user, 'sources'),
    superAdmin: user?.role === 'super_admin',
    listeAbsente: cible.kind === 'liste' && !loading && !liste,
  });

  function titreInerte(id: string): string | undefined {
    if (id === 'prolonger-essai' && user?.role !== 'super_admin') return 'Réservé à l’administrateur.';
    if ((id === 'activer' || id === 'transferer') && !userCan(user, 'activate')) return 'Ton compte ne peut pas activer.';
    if (!userCan(user, 'sources') && (id === 'pousser-liste' || id === 'retirer-listes' || id === 'modifier-liste' || id === 'retirer-liste')) {
      return 'Ton compte ne peut pas modifier les listes.';
    }
    if (id === 'notes-client') return 'Aucun client lié à cette box.';
    if (id === 'geler' || id === 'bannir' || id === 'reactiver') return 'Déjà dans cet état.';
    if (!deviceId) return 'Appareil introuvable.';
    if (id === 'retirer-liste' || id === 'copier-liste') return 'Cette liste n’est pas là.';
    return undefined;
  }

  async function agir(id: string) {
    if (inertes.includes(id) || busy) return;
    setErr(null);
    setInfo(null);
    if (id === 'masquer-liste') {
      const plan = planHideSource(listeMasquee);
      setInfo(plan.reason === 'flag'
        ? 'Interrupteur coupé : la liste n’est pas masquée. Aucun envoi.'
        : 'Bientôt : le serveur ne connaît pas le drapeau hidden. Aucun envoi.');
      return;
    }
    if (id === 'copier-mac') return copier(mac);
    if (id === 'copier-client') return copier(customer?.id || '');
    if (id === 'copier-liste') return copier(liste && liste.identifiant !== '—' ? liste.identifiant : '');
    if (id === 'notes-client' && customerId) {
      const suivant = cibleClient(customerId);
      if (suivant) onOpen(suivant);
      return;
    }
    if (id === 'ouvrir-appareil') {
      const suivant = cibleAppareil({ deviceId, mac });
      if (suivant) onOpen(suivant);
      return;
    }
    if (id === 'pousser-liste' || id === 'modifier-liste') {
      onClose();
      navigate(`/chaines?mac=${encodeURIComponent(mac)}`);
      return;
    }
    if (id === 'transferer') {
      onClose();
      navigate(`/transfer?mac=${encodeURIComponent(mac)}`);
      return;
    }
    if (id === 'activer') { setPlanOuvert(true); return; }
    if (id === 'prolonger-essai') { setEssaiOuvert(true); return; }
    if (id === 'enregistrer-client') return enregistrerClient();
    if (id === 'geler' || id === 'bannir' || id === 'reactiver') return changerBloc(id);
    if (id === 'supprimer') return supprimer();
    if (id === 'retirer-listes') return retirerTout();
    if (id === 'retirer-liste') return retirerUne();
  }

  async function copier(texte: string) {
    if (!texte) { setErr('Rien à copier.'); return; }
    try {
      await navigator.clipboard.writeText(texte);
      setInfo('Identifiant copié.');
    } catch {
      setErr('La copie a échoué.');
    }
  }

  async function enregistrerClient() {
    if (!customer) return;
    setBusy(true);
    try {
      await customersApi.update(customer.id, {
        name: nom.trim() || null,
        phone: telephone.trim() || null,
        notes: notes.trim() || null,
      });
      setInfo('Fiche client enregistrée.');
      setReload((n) => n + 1);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  async function changerBloc(id: string) {
    if (!deviceId) return;
    const status = id === 'geler' ? 'frozen' : id === 'bannir' ? 'banned' : 'active';
    if (status === 'banned') {
      const ok = await confirmAction({
        title: 'Bannir cet appareil ?',
        message: `La MAC ${mac} sera bloquée tant que tu ne la réactives pas.`,
        confirmLabel: 'Bannir',
        danger: true,
      });
      if (!ok) return;
    }
    setBusy(true);
    try {
      await devicesApi.setBlock(deviceId, status);
      setInfo(status === 'active' ? 'Appareil réactivé.' : status === 'frozen' ? 'Appareil gelé.' : 'Appareil banni.');
      setReload((n) => n + 1);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  async function supprimer() {
    if (!deviceId) return;
    const ok = await confirmAction({
      title: 'Supprimer cet appareil ?',
      message: `Supprimer la MAC ${mac} ? Pour stopper un abus, « Bannir » est plus sûr.`,
      confirmLabel: 'Supprimer',
      danger: true,
    });
    if (!ok) return;
    setBusy(true);
    try {
      await devicesApi.remove(deviceId);
      onClose();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
      setBusy(false);
    }
  }

  async function retirerTout() {
    if (!mac) return;
    const ok = await confirmAction({
      title: 'Retirer les listes poussées ?',
      message: 'Elles ne seront plus renvoyées à la box. Les listes ajoutées par le client restent.',
      confirmLabel: 'Retirer',
      danger: true,
    });
    if (!ok) return;
    setBusy(true);
    try {
      await sourcesApi.clear(mac);
      setInfo('Listes poussées retirées.');
      setReload((n) => n + 1);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  async function retirerUne() {
    if (!mac || cible.listIndex == null) return;
    const sources = overview?.sources ?? [];
    const plan = planRemoveSource(sources, cible.listIndex);
    if (plan.kind === 'invalid') return;
    const ok = await confirmAction({
      title: 'Retirer cette liste ?',
      message: 'La box l’enlève toute seule à sa prochaine vérification.',
      confirmLabel: 'Retirer',
      danger: true,
    });
    if (!ok) return;
    setBusy(true);
    try {
      if (plan.kind === 'clear') await sourcesApi.clear(mac);
      else await sourcesApi.setMany(mac, plan.sources);
      setInfo('Liste retirée.');
      setReload((n) => n + 1);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  async function activer() {
    if (!mac) return;
    setBusy(true);
    try {
      await activateApi.activate({ mac, plan });
      setInfo('Activation enregistrée.');
      setPlanOuvert(false);
      setReload((n) => n + 1);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  async function prolonger() {
    if (!mac) return;
    const days = joursEssaiValides(jours);
    if (days == null) { setErr('Indique un nombre entier de jours, de 1 à 365.'); return; }
    setBusy(true);
    try {
      await activateApi.extendTrial(mac, days);
      setInfo('Essai prolongé.');
      setEssaiOuvert(false);
      setReload((n) => n + 1);
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Échec.');
    } finally { setBusy(false); }
  }

  const clientVue: ClientVue | null = customer ? {
    id: customer.id,
    nom: customer.name || '—',
    email: customer.email || '',
    telephone: customer.phone || '',
    notes: customer.notes || '',
    appareils,
  } : null;

  const titre = cible.kind === 'client' ? 'Fiche client' : cible.kind === 'liste' ? 'Fiche liste' : 'Fiche appareil';
  const sousTitre = cible.kind === 'client'
    ? (customer?.name || customer?.email || customer?.id || 'Client')
    : (liste?.label || mac || '—');
  const badge = cible.kind === 'appareil' ? (device?.block_status || 'active') : undefined;

  return (
    <FichePanneau
      testId={`fiche-${cible.kind}`}
      kind={cible.kind}
      origin={origin}
      titre={titre}
      sousTitre={sousTitre}
      badge={badge}
      message={info}
      erreur={err}
      listeMasquee={listeMasquee}
      onToggleMasquee={setListeMasquee}
      inertes={inertes}
      titreInerte={titreInerte}
      busy={busy || loading}
      onAction={(id) => { void agir(id); }}
      onClose={onClose}
      onBack={onBack}
    >
      {loading && <div className="mb-4 h-24 animate-pulse rounded-lg bg-white/5" />}
      {!loading && cible.kind === 'appareil' && (
        <>
          <CorpsAppareil
            vue={vue}
            onClient={customerId ? () => {
              const suivant = cibleClient(customerId);
              if (suivant) onOpen(suivant);
            } : undefined}
            onListe={(index, origine) => {
              const suivant = cibleListe({ deviceId, mac, index, origin: origine });
              if (suivant) onOpen(suivant);
            }}
          />
          {planOuvert && (
            <ChoixPlan plan={plan} onPlan={setPlan} busy={busy} onGo={() => { void activer(); }} onCancel={() => setPlanOuvert(false)} />
          )}
          {essaiOuvert && (
            <ChoixJours jours={jours} onJours={setJours} busy={busy} onGo={() => { void prolonger(); }} onCancel={() => setEssaiOuvert(false)} />
          )}
        </>
      )}
      {!loading && cible.kind === 'client' && clientVue && (
        <CorpsClient
          vue={clientVue}
          nom={nom}
          telephone={telephone}
          notes={notes}
          onNom={setNom}
          onTelephone={setTelephone}
          onNotes={setNotes}
          onAppareil={(id, adresse) => {
            const suivant = cibleAppareil({ deviceId: id, mac: adresse });
            if (suivant) onOpen(suivant);
          }}
        />
      )}
      {!loading && cible.kind === 'liste' && <CorpsListe liste={liste} />}
    </FichePanneau>
  );
}

function versVue(device: Device | null, ov: DeviceOverview | null, mac: string): AppareilVue {
  const license = ov?.license ?? null;
  const phrase = license ? expiryPhrase(license.expires_at) : 'Aucun abonnement';
  const plan = license?.plan ? (PLAN_LABELS[license.plan] || license.plan) : '';
  const abonnement = !license
    ? 'Aucun abonnement'
    : (plan && phrase !== 'À vie' ? `${plan} · ${phrase}` : phrase);
  const presence = ov?.presence ?? null;
  const presenceTexte = !presence
    ? '—'
    : presence.channel
      ? presence.channel
      : `${presence.country ? `${presence.country} ` : ''}${presence.ip || '—'}`.trim();
  return {
    mac: device?.mac || ov?.mac || mac || '—',
    client: device?.customer_name || device?.customer_email || '—',
    customerId: device?.customer_id || null,
    plateforme: device?.platform === 'tv' ? 'TV' : device?.platform === 'mobile' ? 'Mobile' : '—',
    modele: device?.device_model || '—',
    android: device?.android_release ? `Android ${device.android_release}` : '—',
    version: device?.app_build != null ? String(device.app_build) : '—',
    etiquette: device?.label || '—',
    derniereVue: formatDateTime(device?.last_seen_at),
    premiereVue: formatDateTime(device?.first_seen_at),
    acces: device?.access_label || '—',
    blockStatus: device?.block_status || 'active',
    abonnement,
    abonnementOk: !!license && license.status === 'active',
    presence: presenceTexte,
    enLigne: !!presence?.online,
    listes: apercuesListes(
      (ov?.sources ?? []).map((s) => ({ type: s.type, label: s.label, username: s.username })),
      'panel',
    ),
    locales: apercuesListes(
      (ov?.localSources ?? []).map((s) => ({ type: s.type, name: s.name, username: s.username })),
      'locale',
    ),
  };
}

function ChoixPlan({
  plan, onPlan, busy, onGo, onCancel,
}: {
  plan: string;
  onPlan: (id: string) => void;
  busy: boolean;
  onGo: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="mt-3 rounded-lg border border-white/10 bg-obsidian p-3">
      <p className="mb-2 text-sm text-ink-secondary">Durée à ajouter au temps restant.</p>
      <div className="grid grid-cols-2 gap-2">
        {PLANS.map((p) => (
          <button
            key={p.id}
            type="button"
            onClick={() => onPlan(p.id)}
            className={
              'rounded-md border px-3 py-2 text-sm ' +
              (plan === p.id ? 'border-accent bg-accent/10 text-ink-primary' : 'border-white/5 text-ink-secondary')
            }
          >
            {p.label}
          </button>
        ))}
      </div>
      <div className="mt-3 flex justify-end gap-2">
        <button type="button" onClick={onCancel} className="px-3 py-1.5 text-xs text-ink-secondary">Annuler</button>
        <button type="button" disabled={busy} onClick={onGo} className="rounded-md bg-accent px-3 py-1.5 text-xs font-semibold text-black disabled:opacity-50">
          Activer
        </button>
      </div>
    </div>
  );
}

function ChoixJours({
  jours, onJours, busy, onGo, onCancel,
}: {
  jours: string;
  onJours: (v: string) => void;
  busy: boolean;
  onGo: () => void;
  onCancel: () => void;
}) {
  return (
    <div className="mt-3 rounded-lg border border-white/10 bg-obsidian p-3">
      <label htmlFor="fiche-jours" className="mb-1.5 block text-sm text-ink-secondary">
        Jours d’essai à ajouter (1 à 365)
      </label>
      <input
        id="fiche-jours"
        inputMode="numeric"
        value={jours}
        onChange={(e) => onJours(e.target.value)}
        className="w-24 rounded-md border border-white/10 bg-midnight px-3 py-2 text-sm"
      />
      <div className="mt-3 flex justify-end gap-2">
        <button type="button" onClick={onCancel} className="px-3 py-1.5 text-xs text-ink-secondary">Annuler</button>
        <button type="button" disabled={busy} onClick={onGo} className="rounded-md border border-white/15 px-3 py-1.5 text-xs font-semibold disabled:opacity-50">
          Prolonger
        </button>
      </div>
    </div>
  );
}
