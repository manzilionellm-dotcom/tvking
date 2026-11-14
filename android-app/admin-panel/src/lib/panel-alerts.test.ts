// @vitest-environment jsdom
import { webcrypto } from 'node:crypto';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
const api = vi.hoisted(() => ({ preferences: vi.fn(), subscriptions: vi.fn(), subscribe: vi.fn(), unsubscribe: vi.fn(), savePreferences: vi.fn() }));
const consent = vi.hoisted(() => ({ beginPanelConsent: vi.fn(), confirmPanelConsent: vi.fn(), disablePanelConsent: vi.fn(), hasPanelConsent: vi.fn() }));
vi.mock('./api', async (original) => ({ ...await original<typeof import('./api')>(), panelAlertsApi: api }));
vi.mock('./panel-push-consent', () => consent);
import { setCurrentUser } from './api';
import { panelAlertsPort, vapidKey } from './panel-alerts';

const key = Buffer.from([4, ...Array(64).fill(1)]).toString('base64url');
const prefs = { ok: true, enabled: true, types: { new_device: true, activation: true, problem: true }, push_available: true, public_key: key };
const sub = { endpoint: 'https://push.example.invalid/fixture', toJSON: () => ({ endpoint: 'https://push.example.invalid/fixture', keys: { p256dh: 'fixture-public-key', auth: 'fixture-auth' }, expirationTime: null }), unsubscribe: vi.fn() };
const push = { getSubscription: vi.fn(), subscribe: vi.fn() };
const registration = { pushManager: push } as unknown as ServiceWorkerRegistration;
beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal('crypto', webcrypto);
  vi.stubGlobal('Notification', { permission: 'granted' });
  setCurrentUser({ id: 'owner-fixture', email: 'fixture@example.invalid', name: null, role: 'super_admin' });
  api.preferences.mockReset().mockResolvedValue(prefs);
  api.subscriptions.mockReset().mockResolvedValue({ ok: true, items: [] });
  api.subscribe.mockReset().mockResolvedValue({ ok: true, id: 'subscription_fixture', enabled: true, delivery_confirmed: false, consented_at: Date.now(), expires_at: Date.now() + 600_000 });
  api.unsubscribe.mockReset().mockResolvedValue({ ok: true });
  api.savePreferences.mockReset().mockResolvedValue(prefs);
  consent.beginPanelConsent.mockReset().mockResolvedValue('fixture-attempt');
  consent.confirmPanelConsent.mockReset().mockResolvedValue(true);
  consent.disablePanelConsent.mockReset().mockResolvedValue(undefined);
  consent.hasPanelConsent.mockReset().mockResolvedValue(true);
  push.getSubscription.mockReset().mockResolvedValue(null);
  push.subscribe.mockReset().mockResolvedValue(sub);
  sub.unsubscribe.mockReset().mockResolvedValue(true);
});
afterEach(() => { localStorage.clear(); setCurrentUser(null); vi.unstubAllGlobals(); });

it('lit l’état sans créer de souscription ni demander de permission', async () => {
  expect((await panelAlertsPort.read(registration, new AbortController().signal)).enabled).toBe(false);
  expect(push.subscribe).not.toHaveBeenCalled();
  expect(api.subscribe).not.toHaveBeenCalled();
});
it('exige rôle, consentement navigateur et configuration serveur valides', async () => {
  vi.stubGlobal('Notification', { permission: 'denied' });
  await expect(panelAlertsPort.enable(registration)).rejects.toThrow('permission_required');
  vi.stubGlobal('Notification', { permission: 'granted' });
  api.preferences.mockResolvedValue({ ...prefs, push_available: false });
  await expect(panelAlertsPort.enable(registration)).rejects.toThrow('push_unavailable');
  setCurrentUser({ id: 'support-fixture', email: 'fixture@example.invalid', name: null, role: 'support' });
  await expect(panelAlertsPort.enable(registration)).rejects.toThrow('owner_required');
  expect(push.subscribe).not.toHaveBeenCalled();
});
it('un abonnement navigateur sans confirmation serveur reste une erreur', async () => {
  api.subscribe.mockRejectedValue(new Error('fixture_unavailable'));
  await expect(panelAlertsPort.enable(registration)).rejects.toThrow('fixture_unavailable');
  expect(localStorage.getItem('panel_push_binding_v1')).toBeNull();
  push.getSubscription.mockResolvedValue(sub);
  expect((await panelAlertsPort.read(registration, new AbortController().signal)).enabled).toBe(false);
});
it('ne conserve que la référence opaque et l’empreinte après confirmation', async () => {
  const result = await panelAlertsPort.enable(registration);
  expect(result.enabled).toBe(true);
  expect(result.expiresAt).toBeGreaterThan(Date.now());
  const value = JSON.parse(localStorage.getItem('panel_push_binding_v1')!);
  expect(Object.keys(value).sort()).toEqual(['fingerprint', 'subscription_id', 'user_id']);
  expect(value.fingerprint).toMatch(/^[a-f0-9]{64}$/);
  expect(JSON.stringify(value)).not.toContain('push.example.invalid');
  expect(JSON.stringify(value)).not.toContain('fixture-auth');
});
it('retire l’abonnement navigateur avant la révocation authentifiée', async () => {
  await panelAlertsPort.enable(registration);
  push.getSubscription.mockResolvedValue(sub);
  const order: string[] = [];
  sub.unsubscribe.mockImplementation(async () => { order.push('browser'); return true; });
  api.unsubscribe.mockImplementation(async () => { order.push('server'); return { ok: true }; });
  await panelAlertsPort.disable(registration);
  expect(order).toEqual(['browser', 'server']);
  expect(localStorage.getItem('panel_push_binding_v1')).toBeNull();
});
it('refuse la clé VAPID malformée et une souscription déjà expirée', async () => {
  expect(vapidKey(key)?.length).toBe(65);
  for (const value of ['', 'private', key.slice(1), null]) expect(vapidKey(value)).toBeNull();
  api.subscribe.mockResolvedValue({ ok: true, id: 'subscription_fixture', enabled: true, delivery_confirmed: false, consented_at: 1, expires_at: 2 });
  await expect(panelAlertsPort.enable(registration)).rejects.toThrow('subscription_unconfirmed');
});
it('une approbation tardive ne réactive pas le consentement coupé entre-temps', async () => {
  consent.confirmPanelConsent.mockResolvedValue(false);
  await expect(panelAlertsPort.enable(registration)).rejects.toThrow('subscription_obsolete');
  expect(localStorage.getItem('panel_push_binding_v1')).toBeNull();
});
it('coupe aussi le téléphone avant une désactivation du compte hors réseau', async () => {
  const order: string[] = [];
  consent.disablePanelConsent.mockImplementation(async () => { order.push('local'); });
  api.savePreferences.mockImplementation(async () => { order.push('server'); throw new Error('fixture_offline'); });
  await expect(panelAlertsPort.savePreferences(false, prefs.types)).rejects.toThrow('fixture_offline');
  expect(order).toEqual(['local', 'server']);
});
