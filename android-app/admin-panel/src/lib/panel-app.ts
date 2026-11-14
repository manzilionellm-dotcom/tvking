// Installation et capacités du navigateur. Aucune permission n'est demandée
// au démarrage ; les deux demandes explicites sont appelées depuis un clic.
export type PanelPermission = NotificationPermission | 'unsupported';
interface InstallPrompt extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}
export interface PanelAppState {
  installed: boolean;
  appleMobile: boolean;
  canInstall: boolean;
  installPending: boolean;
  installResult: 'accepted' | 'dismissed' | 'failed' | null;
  permission: PanelPermission;
  worker: 'pending' | 'ready' | 'unsupported' | 'failed';
}
export interface PanelAlertsPort {
  // Le port sera fourni par le client serveur des alertes. Un simple accord
  // du navigateur ne rend jamais enabled=true dans ce composant.
  read(registration: ServiceWorkerRegistration, signal: AbortSignal): Promise<PanelAlertsState>;
  enable(registration: ServiceWorkerRegistration): Promise<{ enabled: boolean; expiresAt: number | null }>;
  disable(registration: ServiceWorkerRegistration): Promise<void>;
  savePreferences(enabled: boolean, types: PanelAlertTypes): Promise<void>;
}
export type PanelAlertTypes = { new_device: boolean; activation: boolean; problem: boolean };
export interface PanelAlertsState {
  enabled: boolean; available: boolean; accountEnabled: boolean; types: PanelAlertTypes; expiresAt: number | null;
}

const INITIAL: PanelAppState = { installed: false, appleMobile: false, canInstall: false,
  installPending: false, installResult: null, permission: 'unsupported', worker: 'unsupported' };
let state = INITIAL;
let prompt: InstallPrompt | null = null;
let registration: Promise<ServiceWorkerRegistration | null> | null = null;
let cleanup: (() => void) | null = null;
const listeners = new Set<() => void>();
export const getPanelAppState = () => state;
export const getPanelAppServerState = () => INITIAL;
export function observePanelApp(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
function update(values: Partial<PanelAppState>) {
  state = { ...state, ...values };
  for (const listener of listeners) listener();
}
function readPermission(): PanelPermission {
  return window.isSecureContext && 'serviceWorker' in navigator && 'PushManager' in window
    && 'Notification' in window ? Notification.permission : 'unsupported';
}
export function refreshPanelPermission() { update({ permission: readPermission() }); }

/** Enregistrement du worker fixe de cette origine : aucun cache ni API. */
export function initializePanelApp(): () => void {
  if (cleanup) return cleanup;
  let active = true;
  const standalone = typeof window.matchMedia === 'function' ? window.matchMedia('(display-mode: standalone)') : null;
  const appleMobile = /iPhone|iPad|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const installed = () => !!standalone?.matches || (navigator as Navigator & { standalone?: boolean }).standalone === true;
  const changeDisplay = () => { if (active) update({ installed: installed() }); };
  const beforeInstall = (event: Event) => {
    if (!('prompt' in event) || typeof (event as InstallPrompt).prompt !== 'function') return;
    event.preventDefault();
    prompt = event as InstallPrompt;
    update({ canInstall: true, installResult: null });
  };
  const didInstall = () => { prompt = null; update({ installed: true, canInstall: false, installResult: null }); };
  const refresh = () => { if (document.visibilityState !== 'hidden') refreshPanelPermission(); };
  update({ installed: installed(), appleMobile, permission: readPermission() });
  window.addEventListener('beforeinstallprompt', beforeInstall);
  window.addEventListener('appinstalled', didInstall);
  window.addEventListener('focus', refresh);
  document.addEventListener('visibilitychange', refresh);
  standalone?.addEventListener?.('change', changeDisplay);
  if (window.isSecureContext && 'serviceWorker' in navigator) {
    update({ worker: 'pending' });
    registration = Promise.resolve().then(() => navigator.serviceWorker.register('/panel-sw.js', { scope: '/', updateViaCache: 'none' }))
      .then(() => navigator.serviceWorker.ready)
      .then((value) => { if (active) update({ worker: 'ready' }); return value; })
      .catch(() => { if (active) update({ worker: 'failed' }); return null; });
  } else registration = Promise.resolve(null);
  cleanup = () => {
    active = false;
    window.removeEventListener('beforeinstallprompt', beforeInstall);
    window.removeEventListener('appinstalled', didInstall);
    window.removeEventListener('focus', refresh);
    document.removeEventListener('visibilitychange', refresh);
    standalone?.removeEventListener?.('change', changeDisplay);
    prompt = null;
    cleanup = null;
    registration = null;
    update(INITIAL);
  };
  return cleanup;
}

export function panelWorkerReady(): Promise<ServiceWorkerRegistration | null> {
  return registration || Promise.resolve(null);
}

export async function requestPanelInstallation(): Promise<void> {
  if (!prompt || state.installPending) return;
  const selected = prompt;
  prompt = null;
  update({ installPending: true, canInstall: false, installResult: null });
  try {
    await selected.prompt();
    const choice = await selected.userChoice;
    // « accepted » n'est pas l'événement appinstalled : on n'anticipe pas son succès.
    update({ installResult: state.installed ? null : choice.outcome });
  } catch { update({ installResult: 'failed' }); }
  finally { update({ installPending: false }); }
}

export async function requestPanelPermission(): Promise<PanelPermission> {
  if (readPermission() === 'unsupported') return 'unsupported';
  const permission = await Notification.requestPermission();
  update({ permission });
  return permission;
}
