// Le chiffrement RFC 8291 et la signature VAPID sont délégués à une bibliothèque
// WebCrypto maintenue. Le transport reste volontairement borné et n'accepte
// que les services de push des navigateurs pris en charge.
import { buildPushPayload } from '@block65/webcrypto-web-push';

const PUSH_HOSTS = new Set([
  'fcm.googleapis.com',
  'updates.push.services.mozilla.com',
  'web.push.apple.com',
]);
const TYPES = new Set(['new_device', 'activation', 'problem']);
const B64URL = /^[A-Za-z0-9_-]+$/;

function decodeKey(value, length) {
  if (typeof value !== 'string' || !B64URL.test(value) || value.length > 128) return null;
  try {
    const binary = atob(value.replace(/-/g, '+').replace(/_/g, '/'));
    if (binary.length !== length) return null;
    const bytes = Uint8Array.from(binary, (letter) => letter.charCodeAt(0));
    // Une seule représentation évite les variantes ambiguës stockées en base.
    if (btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') !== value) return null;
    return bytes;
  } catch { return null; }
}

export function validPushSubscription(subscription) {
  if (!subscription || typeof subscription.endpoint !== 'string' || subscription.endpoint.length > 2048) return false;
  let endpoint;
  try { endpoint = new URL(subscription.endpoint); } catch { return false; }
  if (endpoint.protocol !== 'https:' || !PUSH_HOSTS.has(endpoint.hostname)
      || endpoint.username || endpoint.password || endpoint.port || endpoint.hash
      || endpoint.pathname.length < 2 || endpoint.href !== subscription.endpoint) return false;
  const publicKey = decodeKey(subscription.keys?.p256dh, 65);
  return !!publicKey && publicKey[0] === 4 && !!decodeKey(subscription.keys?.auth, 16)
    && (subscription.expirationTime == null
      || (Number.isSafeInteger(subscription.expirationTime) && subscription.expirationTime > Date.now()));
}

export function validAlertPayload(payload) {
  if (!payload || payload.v !== 1 || !TYPES.has(payload.type)
      || typeof payload.event_id !== 'string' || !/^[A-Za-z0-9_.:-]{8,128}$/.test(payload.event_id)
      || typeof payload.title !== 'string' || payload.title.length < 1 || payload.title.length > 96
      || typeof payload.message !== 'string' || payload.message.length < 1 || payload.message.length > 240
      || /[\u0000-\u001f\u007f]/.test(payload.title + payload.message)
      || typeof payload.url !== 'string' || payload.url.length > 160) return false;
  const keys = Object.keys(payload).sort().join(',');
  if (keys !== 'event_id,message,title,type,url,v') return false;
  // La notification ne contient qu'une destination interne, jamais un lien
  // fournisseur ni un jeton. La page relira ensuite la fiche sous authentification.
  let url;
  try { url = new URL(payload.url, 'https://panel.invalid'); } catch { return false; }
  if (!payload.url.startsWith('/') || payload.url.startsWith('//')
      || url.origin !== 'https://panel.invalid' || url.hash
      || !['/devices', '/blackbox'].includes(url.pathname)
      || [...url.searchParams.keys()].join(',') !== 'mac') return false;
  return /^(?:MK|[0-9A-F]{2})(?::[0-9A-F]{2}){5}$/.test(url.searchParams.get('mac') || '');
}

export function readVapidConfig(env) {
  const publicBytes = decodeKey(env.PANEL_PUSH_PUBLIC_KEY, 65);
  if (!publicBytes || publicBytes[0] !== 4 || !decodeKey(env.PANEL_PUSH_PRIVATE_KEY, 32)
      || env.PANEL_PUSH_SUBJECT !== 'https://atlas-console-k7q2.vercel.app/') {
    throw new Error('push_configuration_invalid');
  }
  return {
    subject: env.PANEL_PUSH_SUBJECT,
    publicKey: env.PANEL_PUSH_PUBLIC_KEY,
    privateKey: env.PANEL_PUSH_PRIVATE_KEY,
  };
}

export async function verifyVapidConfig(env) {
  const vapid = readVapidConfig(env);
  const raw = decodeKey(vapid.publicKey, 65);
  const encode = (bytes) => btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  try {
    const privateKey = await crypto.subtle.importKey('jwk', {
      kty: 'EC', crv: 'P-256', x: encode(raw.slice(1, 33)),
      y: encode(raw.slice(33, 65)), d: vapid.privateKey,
    }, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
    const publicKey = await crypto.subtle.importKey('raw', raw,
      { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    const probe = new TextEncoder().encode('atlas-panel-push-configuration');
    const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, privateKey, probe);
    if (!await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, signature, probe)) throw new Error();
    return vapid;
  } catch { throw new Error('push_configuration_invalid'); }
}

function retryDelay(header) {
  if (header == null) return null;
  const seconds = /^\d{1,6}$/.test(header) ? Number(header) : (Date.parse(header) - Date.now()) / 1000;
  return Number.isFinite(seconds) && seconds >= 0 ? Math.min(3600, Math.max(60, Math.ceil(seconds))) : null;
}

export async function sendWebPush(subscription, payload, env, fetcher = fetch) {
  if (!validPushSubscription(subscription)) return { state: 'invalid', status: null, error: 'subscription_invalid' };
  if (!validAlertPayload(payload)) throw new Error('push_payload_invalid');
  const vapid = readVapidConfig(env);
  let request;
  try {
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(payload.event_id)));
    const topic = btoa(String.fromCharCode(...digest.slice(0, 18))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    request = await buildPushPayload({ data: payload, options: { ttl: 3600, urgency: 'normal', topic } }, subscription, vapid);
  } catch {
    // Une clé navigateur invalide n'est jamais envoyée. Les valeurs sensibles
    // de l'exception de la bibliothèque ne sont ni journalisées ni retournées.
    return { state: 'invalid', status: null, error: 'subscription_crypto_invalid' };
  }
  const abort = new AbortController();
  const timeout = setTimeout(() => abort.abort(), 8000);
  try {
    // Workers n'implémente pas redirect:error. Le mode manual rend le 3xx
    // au code ci-dessous, qui le refuse sans contacter la nouvelle adresse.
    const response = await fetcher(subscription.endpoint, { ...request, redirect: 'manual', signal: abort.signal });
    const status = response.status;
    const retryAfter = retryDelay(response.headers.get('Retry-After'));
    // Le corps peut contenir des détails du service tiers. Il n'est pas conservé.
    try { await response.body?.cancel(); } catch {}
    if (status >= 200 && status < 300) return { state: 'sent', status, error: null };
    if (status === 404 || status === 410) return { state: 'gone', status, error: 'subscription_expired' };
    if ([408, 425, 429].includes(status) || status >= 500) {
      return { state: 'retry', status, error: 'push_service_temporary', retryAfter };
    }
    return { state: 'failed', status, error: 'push_service_rejected' };
  } catch {
    return { state: 'retry', status: null, error: 'push_network_unavailable', retryAfter: null };
  } finally { clearTimeout(timeout); }
}
