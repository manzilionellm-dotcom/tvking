import { getCurrentUser, getToken, panelAlertsApi, type PanelAlertPreferences } from './api';
import { panelWorkerReady, type PanelAlertsPort } from './panel-app';
import { beginPanelConsent, confirmPanelConsent, disablePanelConsent, hasPanelConsent } from './panel-push-consent';

const BINDING = 'panel_push_binding_v1';
interface Binding { user_id: string; subscription_id: string; fingerprint: string }
function owner(): string {
  const user = getCurrentUser();
  if (user?.role !== 'super_admin' || !user.id) throw new Error('owner_required');
  return user.id;
}
function current(id: string) { if (owner() !== id) throw new Error('session_changed'); }
function binding(id: string): Binding | null {
  try {
    const value = JSON.parse(localStorage.getItem(BINDING) || 'null');
    return value?.user_id === id && typeof value.subscription_id === 'string'
      && /^[a-f0-9]{64}$/.test(value.fingerprint) ? value : null;
  } catch { return null; }
}
function forget(value: Binding | null) {
  if (value && binding(value.user_id)?.subscription_id === value.subscription_id) localStorage.removeItem(BINDING);
}
async function fingerprint(endpoint: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(endpoint)));
  return Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
}
export function vapidKey(value: unknown): Uint8Array | null {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{87}=?$/.test(value)) return null;
  try {
    const binary = atob(value.replace(/-/g, '+').replace(/_/g, '/'));
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    return bytes.length === 65 && bytes[0] === 4 ? bytes : null;
  } catch { return null; }
}
function preferences(value: PanelAlertPreferences) {
  if (value?.ok !== true || typeof value.enabled !== 'boolean' || typeof value.push_available !== 'boolean'
      || !value.types || ['new_device', 'activation', 'problem'].some((key) => typeof value.types[key as keyof typeof value.types] !== 'boolean')) {
    throw new Error('invalid_preferences');
  }
  return value;
}

/** Le navigateur garde ses clés Push. Notre seule mémoire locale est une
 * référence opaque, liée au compte, et l'empreinte de son endpoint. */
export const panelAlertsPort: PanelAlertsPort = {
  async read(registration, signal) {
    const id = owner();
    const [prefs, list, sub, localConsent] = await Promise.all([
      panelAlertsApi.preferences(signal), panelAlertsApi.subscriptions(signal), registration.pushManager.getSubscription(),
      hasPanelConsent(),
    ]);
    current(id);
    const verified = preferences(prefs);
    if (list?.ok !== true || !Array.isArray(list.items)) throw new Error('invalid_subscriptions');
    const remembered = binding(id);
    const row = remembered && list.items.find((item) => item.id === remembered.subscription_id);
    const matches = !!sub && !!remembered && await fingerprint(sub.endpoint) === remembered.fingerprint;
    current(id);
    return { enabled: localConsent && verified.enabled && matches && row?.enabled === true && row.current_session === true
      && row.revoked_at == null && (row.expires_at == null || row.expires_at > Date.now()),
      available: verified.push_available && !!vapidKey(verified.public_key),
      accountEnabled: verified.enabled, types: verified.types,
      expiresAt: row && Number.isSafeInteger(row.expires_at) ? row.expires_at : null };
  },
  async savePreferences(enabled, types) {
    const id = owner();
    if (!enabled) await disablePanelConsent();
    current(id);
    const result = await panelAlertsApi.savePreferences(enabled, types);
    current(id);
    if (result?.ok !== true) throw new Error('preferences_unconfirmed');
  },
  async enable(registration) {
    const id = owner();
    if (Notification.permission !== 'granted') throw new Error('permission_required');
    const attempt = await beginPanelConsent();
    const prefs = preferences(await panelAlertsApi.preferences());
    current(id);
    const key = vapidKey(prefs.public_key);
    if (!prefs.enabled || !prefs.push_available || !key) throw new Error('push_unavailable');
    let sub = await registration.pushManager.getSubscription();
    current(id);
    if (!sub) sub = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: new Uint8Array(key).buffer });
    current(id);
    const result = await panelAlertsApi.subscribe(sub.toJSON(), 'Panneau sur ce navigateur');
    current(id);
    if (result?.ok !== true || result.enabled !== true || typeof result.id !== 'string'
        || !/^[A-Za-z0-9_-]{8,128}$/.test(result.id) || result.delivery_confirmed !== false
        || !Number.isSafeInteger(result.expires_at) || result.expires_at <= Date.now()
        || !Number.isSafeInteger(result.consented_at) || result.consented_at <= 0
        || result.consented_at >= result.expires_at) throw new Error('subscription_unconfirmed');
    const value = { user_id: id, subscription_id: result.id, fingerprint: await fingerprint(sub.endpoint) };
    current(id);
    if (!await confirmPanelConsent(attempt, result.expires_at, registration)) throw new Error('subscription_obsolete');
    try { localStorage.setItem(BINDING, JSON.stringify(value)); }
    catch {
      // Sans cette référence, le téléphone ne pourrait plus gérer sa liaison.
      // On annule ce qui vient d'être créé et on garde une erreur visible.
      await Promise.allSettled([disablePanelConsent(registration), sub.unsubscribe(), panelAlertsApi.unsubscribe(result.id)]);
      throw new Error('binding_unavailable');
    }
    return { enabled: true, expiresAt: Number.isSafeInteger(result.expires_at) ? result.expires_at : null };
  },
  async disable(registration) {
    const id = owner();
    await disablePanelConsent(registration);
    const value = binding(id);
    const sub = await registration.pushManager.getSubscription();
    if (sub && !await sub.unsubscribe()) throw new Error('unsubscribe_unconfirmed');
    current(id);
    if (value) {
      const result = await panelAlertsApi.unsubscribe(value.subscription_id);
      if (result?.ok !== true) throw new Error('revocation_unconfirmed');
      forget(value);
    }
  },
};

// Appelle ceci avant d'effacer le JWT. Le timeout du caller permet quand même
// de se déconnecter hors réseau ; aucun ancien jeton n'est confié au worker.
export async function revokePanelPushForLogout(signal?: AbortSignal): Promise<void> {
  const user = getCurrentUser();
  const token = getToken();
  // La coupure locale précède la moindre attente réseau et ne dépend pas du JWT.
  await disablePanelConsent();
  if (!user || signal?.aborted || getCurrentUser()?.id !== user.id || getToken() !== token) return;
  const value = binding(user.id);
  const registration = await panelWorkerReady();
  if (signal?.aborted || getToken() !== token) return;
  const sub = await registration?.pushManager.getSubscription();
  if (signal?.aborted || getToken() !== token) return;
  if (sub) await sub.unsubscribe();
  if (signal?.aborted || getCurrentUser()?.id !== user.id || getToken() !== token) return;
  if (value) {
    await panelAlertsApi.unsubscribe(value.subscription_id, signal);
    forget(value);
  }
}
