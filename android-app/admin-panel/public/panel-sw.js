/* Worker du panneau : notifications seulement. Aucun gestionnaire fetch,
 * aucun cache de page/API, aucun accès à un jeton ou aux journaux clients. */
'use strict';
const EVENT_TYPES = new Set(['new_device', 'activation', 'problem']);
const SEEN_DB = 'panel-alert-events-v1';
const MAX_SEEN = 512;
const RETENTION_MS = 7 * 86400000;
let consentBlocked = false;

function destination(value) {
  if (typeof value !== 'string' || value.length > 512 || /[\\\u0000-\u0020\u007f]/.test(value)) return null;
  try {
    const url = new URL(value, self.location.origin);
    if (!['https:', 'http:'].includes(url.protocol) || url.origin !== self.location.origin
        || url.username || url.password || url.hash
        || !['/devices', '/blackbox'].includes(url.pathname)) return null;
    const keys = Array.from(url.searchParams.keys());
    if (keys.length !== 1 || keys[0] !== 'mac') return null;
    const mac = (url.searchParams.get('mac') || '').toUpperCase();
    if (!/^(?:MK(?::[0-9A-F]{2}){5}|[0-9A-F]{2}(?::[0-9A-F]{2}){5})$/.test(mac)) return null;
    return url.pathname + '?mac=' + encodeURIComponent(mac);
  } catch (_) { return null; }
}

function safeText(value, maximum, allowEmpty) {
  return typeof value === 'string' && value.length <= maximum && (allowEmpty || value.trim().length > 0)
    && !/[\u0000-\u001f\u007f]/.test(value)
    && !/https?:\/\/|\bBearer\s|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.|\b[a-f0-9]{64}\b/i.test(value)
    && !/(?:password|passwd|username|token|secret|authorization|device[_-]?key)\s*[:=]/i.test(value);
}

function payload(data) {
  if (!data) return null;
  try {
    const raw = data.text();
    if (raw.length > 4096) return null;
    const item = JSON.parse(raw);
    if (!item || Array.isArray(item) || typeof item !== 'object'
        || Object.keys(item).some((key) => !['v', 'event_id', 'type', 'title', 'message', 'url'].includes(key))
        || item.v !== 1 || !EVENT_TYPES.has(item.type)
        || typeof item.event_id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/.test(item.event_id)
        || !safeText(item.title, 96, false) || !safeText(item.message, 240, true)) return null;
    const url = destination(item.url);
    return url ? { ...item, url } : null;
  } catch (_) { return null; }
}

function openSeen() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(SEEN_DB, 2);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains('seen')) request.result.createObjectStore('seen', { keyPath: 'id' });
      if (!request.result.objectStoreNames.contains('control')) request.result.createObjectStore('control', { keyPath: 'id' });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error('storage_unavailable'));
  });
}

async function consent() {
  const db = await openSeen();
  try {
    return await new Promise((resolve, reject) => {
      const request = db.transaction('control').objectStore('control').get('consent');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  } finally { db.close(); }
}
function allowed(value) {
  return !consentBlocked && value && value.enabled === true
    && Number.isSafeInteger(value.expires_at) && value.expires_at > Date.now();
}
async function turnOff(nonce) {
  const db = await openSeen();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction('control', 'readwrite');
      tx.objectStore('control').put({ id: 'consent', nonce, enabled: false, expires_at: 0 });
      tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
    });
  } finally { db.close(); }
}

// La transaction sérialise aussi deux push simultanés. Seuls l'identifiant
// opaque et sa date sont conservés, jamais le texte, la MAC ou l'URL cible.
async function claimEvent(id) {
  const db = await openSeen();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction('seen', 'readwrite');
      const store = tx.objectStore('seen');
      const all = store.getAll();
      let claimed = false;
      all.onsuccess = () => {
        const now = Date.now();
        const records = all.result.filter((row) => row.at > now - RETENTION_MS);
        for (const row of all.result) if (row.at <= now - RETENTION_MS) store.delete(row.id);
        if (records.some((row) => row.id === id)) return;
        records.sort((a, b) => a.at - b.at);
        while (records.length >= MAX_SEEN) store.delete(records.shift().id);
        store.put({ id, at: now });
        claimed = true;
      };
      tx.oncomplete = () => resolve(claimed);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally { db.close(); }
}

async function forgetEvent(id) {
  const db = await openSeen();
  try {
    await new Promise((resolve, reject) => {
      const tx = db.transaction('seen', 'readwrite');
      tx.objectStore('seen').delete(id);
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
  } finally { db.close(); }
}

async function show(data) {
  const item = payload(data);
  if (!item) return;
  try {
    const accepted = await consent();
    if (!allowed(accepted)) return;
    if (!await claimEvent(item.event_id)) return;
    try {
      // Un logout a pu arriver pendant la transaction de déduplication.
      const latest = await consent();
      if (!allowed(latest) || latest.nonce !== accepted.nonce) { await forgetEvent(item.event_id); return; }
      await self.registration.showNotification(item.title, {
        body: item.message, icon: '/icons/panel-192.png', badge: '/icons/panel-badge.png',
        tag: 'panel-' + item.event_id, renotify: false,
        data: { event_id: item.event_id, url: item.url },
      });
      // L'affichage peut terminer après un logout qui a déjà fermé les
      // notifications. Ferme aussi cette arrivée tardive du même événement.
      const afterDisplay = await consent();
      if (!allowed(afterDisplay) || afterDisplay.nonce !== accepted.nonce) {
        const late = await self.registration.getNotifications({ tag: 'panel-' + item.event_id });
        late.forEach((notification) => notification.close());
        await forgetEvent(item.event_id);
      }
    } catch (_) { await forgetEvent(item.event_id); }
  } catch (_) { /* Pas de journal contenant le payload ou les détails clients. */ }
}

self.addEventListener('install', (event) => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));
self.addEventListener('push', (event) => event.waitUntil(show(event.data)));
self.addEventListener('message', (event) => {
  const value = event.data;
  if (!value || typeof value.nonce !== 'string' || !/^[A-Za-z0-9-]{16,80}$/.test(value.nonce)) return;
  if (value.type === 'panel-consent-off') {
    consentBlocked = true;
    event.waitUntil(Promise.all([
      turnOff(value.nonce),
      self.registration.getNotifications().then((items) => items.forEach((item) => item.close())),
    ]).then(() => event.ports[0]?.postMessage({ ok: true })).catch(() => event.ports[0]?.postMessage({ ok: false })));
  } else if (value.type === 'panel-consent-on') {
    event.waitUntil(consent().then((current) => {
      if (current && current.nonce === value.nonce && current.enabled === true && current.expires_at > Date.now()) consentBlocked = false;
      event.ports[0]?.postMessage({ ok: !consentBlocked });
    }).catch(() => event.ports[0]?.postMessage({ ok: false })));
  }
});
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = destination(event.notification.data && event.notification.data.url);
  if (!url) return;
  event.waitUntil((async () => {
    const target = new URL(url, self.location.origin).href;
    const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of clients) {
      try {
        if (new URL(client.url).origin !== self.location.origin || typeof client.navigate !== 'function') continue;
        const opened = await client.navigate(target);
        if (opened) { await opened.focus(); return; }
      } catch (_) { /* Le client a pu se fermer entre la lecture et le clic. */ }
    }
    await self.clients.openWindow(target);
  })());
});
