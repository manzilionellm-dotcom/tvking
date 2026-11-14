import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { getCurrentUser } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import {
  getPanelAppState, getPanelAppServerState, observePanelApp, panelWorkerReady,
  requestPanelInstallation, requestPanelPermission, type PanelAlertsPort,
  type PanelAlertsState, type PanelAlertTypes,
} from '@/lib/panel-app';

const BUTTON = 'rounded-md border border-white/15 px-3 py-2 text-sm text-ink-secondary hover:border-accent hover:text-ink-primary disabled:cursor-not-allowed disabled:opacity-50';

/** L'installation concerne tous les comptes ; les alertes de cette première
 * version sont strictement réservées au propriétaire super_admin.
 */
export function PanelAppSettings({ alerts = null }: { alerts?: PanelAlertsPort | null }) {
  const app = useSyncExternalStore(observePanelApp, getPanelAppState, getPanelAppServerState);
  return <>
    <section className="rounded-xl border border-white/5 bg-midnight p-5" aria-label="Installer le panneau">
      <h2 className="text-sm font-semibold">Le panneau sur ce téléphone</h2>
      {app.installed ? <p className="mt-2 text-sm text-success" role="status">Le panneau est installé.</p> : <>
        <p className="mt-2 text-sm text-ink-secondary">Ajoute le panneau à l’écran d’accueil pour le retrouver comme une application.</p>
        {app.canInstall && <button type="button" className={`${BUTTON} mt-3`} disabled={app.installPending}
          onClick={() => { void requestPanelInstallation(); }}>Installer le panneau</button>}
        {!app.canInstall && <p className="mt-3 text-xs text-ink-tertiary">
          {app.appleMobile
            ? 'Sur iPhone ou iPad : ouvre ce site dans Safari, touche Partager, puis « Sur l’écran d’accueil ». Ouvre ensuite l’icône ajoutée.'
            : 'Dans le menu du navigateur, choisis « Installer l’application » ou « Ajouter à l’écran d’accueil » si cette option est proposée.'}
        </p>}
        {app.installResult && <p className="mt-2 text-xs text-ink-secondary" role="status">
          {app.installResult === 'accepted' ? 'Installation demandée. Termine les étapes proposées par le navigateur.'
            : app.installResult === 'dismissed' ? 'Installation annulée. Tu peux continuer dans le navigateur.'
              : 'L’installation n’a pas abouti. Réessaie depuis le menu du navigateur.'}
        </p>}
      </>}
    </section>
    {getCurrentUser()?.role === 'super_admin' && <NotificationSettings key={getCurrentUser()?.id} alerts={alerts} />}
  </>;
}

function NotificationSettings({ alerts }: { alerts: PanelAlertsPort | null }) {
  const app = useSyncExternalStore(observePanelApp, getPanelAppState, getPanelAppServerState);
  const [enabled, setEnabled] = useState(false);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [available, setAvailable] = useState(false);
  const [accountEnabled, setAccountEnabled] = useState(false);
  const [types, setTypes] = useState<PanelAlertTypes>({ new_device: true, activation: true, problem: true });
  const [saved, setSaved] = useState('');
  const [expiresAt, setExpiresAt] = useState<number | null>(null);
  const alive = useRef(true);
  const inFlight = useRef(false);
  const sequence = useRef(0);
  const needsInstall = app.appleMobile && !app.installed;
  const dirty = JSON.stringify({ enabled: accountEnabled, types }) !== saved;

  function apply(result: PanelAlertsState) {
    setEnabled(result.enabled === true);
    setAvailable(result.available === true);
    setAccountEnabled(result.accountEnabled);
    setTypes(result.types);
    setSaved(JSON.stringify({ enabled: result.accountEnabled, types: result.types }));
    setLoaded(true);
    setExpiresAt(result.expiresAt);
  }

  useEffect(() => {
    alive.current = true;
    const owner = ++sequence.current;
    const abort = new AbortController();
    setEnabled(false);
    setLoaded(false);
    setError(null);
    if (alerts && app.worker === 'ready') {
      setLoading(true);
      void panelWorkerReady().then(async (registration) => {
        if (!registration) throw new Error();
        return alerts.read(registration, abort.signal);
      }).then((result) => {
        if (alive.current && owner === sequence.current && getCurrentUser()?.role === 'super_admin') apply(result);
      }).catch(() => {
        if (!abort.signal.aborted && alive.current && owner === sequence.current) setError('L’état des alertes n’a pas pu être vérifié.');
      }).finally(() => { if (alive.current && owner === sequence.current) setLoading(false); });
    }
    return () => { alive.current = false; sequence.current++; abort.abort(); };
  }, [alerts, app.worker]);

  useEffect(() => {
    if (!expiresAt) return;
    const timer = window.setTimeout(() => setEnabled(false), Math.max(0, Math.min(2147483647, expiresAt - Date.now())));
    return () => window.clearTimeout(timer);
  }, [expiresAt]);

  async function change(enable: boolean) {
    if (!alerts || inFlight.current || loading || needsInstall || getCurrentUser()?.role !== 'super_admin') return;
    if (enable && (!loaded || !available || !accountEnabled || dirty)) return;
    const owner = ++sequence.current;
    inFlight.current = true;
    setBusy(true);
    setError(null);
    try {
      // Cet appel est effectué directement dans le gestionnaire du clic.
      // Aucune lecture d'état, installation ou ouverture de compte ne le déclenche.
      if (enable && await requestPanelPermission() !== 'granted') return;
      const registration = await panelWorkerReady();
      if (!registration || !alive.current || owner !== sequence.current || getCurrentUser()?.role !== 'super_admin') return;
      if (enable) {
        const result = await alerts.enable(registration);
        if (result.enabled !== true) throw new Error();
        if (alive.current && owner === sequence.current) setExpiresAt(result.expiresAt);
      } else await alerts.disable(registration);
      if (alive.current && owner === sequence.current) setEnabled(enable);
    } catch {
      if (alive.current && owner === sequence.current) {
        if (!enable) setEnabled(false);
        setError('Les alertes n’ont pas pu être configurées. Réessaie.');
      }
    } finally {
      if (alive.current && owner === sequence.current) { inFlight.current = false; setBusy(false); }
    }
  }

  async function save() {
    if (!alerts || !loaded || inFlight.current || getCurrentUser()?.role !== 'super_admin') return;
    const owner = ++sequence.current;
    inFlight.current = true;
    setBusy(true);
    setError(null);
    try {
      await alerts.savePreferences(accountEnabled, types);
      const registration = await panelWorkerReady();
      if (!registration || !alive.current || owner !== sequence.current || getCurrentUser()?.role !== 'super_admin') return;
      const result = await alerts.read(registration, new AbortController().signal);
      if (alive.current && owner === sequence.current) apply(result);
    } catch {
      if (alive.current && owner === sequence.current) {
        if (!accountEnabled) setEnabled(false);
        setError('Les préférences n’ont pas pu être confirmées. Réessaie.');
      }
    } finally {
      if (alive.current && owner === sequence.current) { inFlight.current = false; setBusy(false); }
    }
  }

  return <section className="rounded-xl border border-white/5 bg-midnight p-5" aria-label="Alertes sur ce téléphone">
    <h2 className="text-sm font-semibold">Alertes sur ce téléphone</h2>
    <p className="mt-2 text-sm text-ink-secondary">Nouveaux appareils, activations et problèmes confirmés.</p>
    {loaded && <fieldset className="mt-3 space-y-2 text-xs text-ink-secondary" disabled={busy || loading}>
      <legend className="mb-2 font-semibold">Préférences du compte</legend>
      <label className="flex items-center gap-2"><input type="checkbox" checked={accountEnabled} onChange={(event) => setAccountEnabled(event.target.checked)} />Autoriser les alertes de mon compte</label>
      {([['new_device', 'Nouveaux appareils'], ['activation', 'Activations et renouvellements'], ['problem', 'Problèmes confirmés']] as const).map(([key, label]) =>
        <label key={key} className="flex items-center gap-2"><input type="checkbox" checked={types[key]} onChange={(event) => setTypes((value) => ({ ...value, [key]: event.target.checked }))} />{label}</label>)}
      <p className="text-ink-tertiary">Ces choix s’appliquent aux appareils sur lesquels tu as activé les alertes de ce compte.</p>
      <button type="button" className={BUTTON} disabled={!dirty || busy} onClick={() => { void save(); }}>Enregistrer mes préférences</button>
    </fieldset>}
    <p className="mt-3 text-xs text-ink-secondary" role="status">
      {needsInstall ? 'Sur iPhone ou iPad, ouvre d’abord le panneau depuis l’icône ajoutée à l’écran d’accueil.'
        : app.permission === 'unsupported' ? 'Les notifications ne sont pas disponibles dans ce navigateur.'
          : app.permission === 'denied' ? 'Notifications bloquées dans les réglages du navigateur. Tu peux les y autoriser.'
            : enabled && app.permission === 'granted' ? 'Alertes activées sur ce téléphone.'
              : app.permission === 'granted' ? 'Autorisation du navigateur accordée. Les alertes ne sont pas activées.'
                : 'Les notifications ne sont pas encore autorisées.'}
    </p>
    {!alerts && <p className="mt-2 text-xs text-ink-tertiary">Le service d’alertes n’est pas encore disponible.</p>}
    {expiresAt != null && <p className="mt-2 text-xs text-ink-tertiary">{expiresAt <= Date.now()
      ? 'L’abonnement de ce téléphone a expiré. Reconnecte-toi, puis réactive les alertes.'
      : `Cet abonnement est valable jusqu’au ${formatDateTime(expiresAt)}. Une nouvelle connexion pourra demander sa réactivation.`}</p>}
    {loaded && !available && <p className="mt-2 text-xs text-ink-tertiary">L’envoi de notifications n’est pas encore disponible. Les alertes restent consultables dans le panneau.</p>}
    {loaded && !accountEnabled && <p className="mt-2 text-xs text-ink-tertiary">Autorise les alertes du compte et enregistre tes préférences avant d’activer ce téléphone.</p>}
    {alerts && !needsInstall && app.permission !== 'unsupported' && app.permission !== 'denied' && <button type="button"
      disabled={busy || loading || app.worker !== 'ready' || !loaded || (!enabled && (!available || !accountEnabled || dirty))} className={`${BUTTON} mt-3`} onClick={() => { void change(!enabled); }}>
      {busy ? 'Configuration…' : loading ? 'Vérification…' : enabled ? 'Désactiver sur ce téléphone' : 'Activer sur ce téléphone'}
    </button>}
    {app.worker === 'failed' && <p className="mt-2 text-xs text-ink-tertiary">Le service du navigateur n’a pas pu démarrer. Recharge la page pour réessayer.</p>}
    {error && <p className="mt-3 text-xs text-accent-bright" role="alert">{error}</p>}
  </section>;
}
